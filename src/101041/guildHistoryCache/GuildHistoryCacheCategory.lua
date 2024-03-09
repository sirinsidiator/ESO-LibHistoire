-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local MISSING_EVENT_COUNT_THRESHOLD = 2000
local NO_LISTENER_THRESHOLD = 3 * 24 * 3600 -- 3 days

local GuildHistoryCacheCategory = ZO_InitializingObject:Subclass()
internal.class.GuildHistoryCacheCategory = GuildHistoryCacheCategory

function GuildHistoryCacheCategory:Initialize(adapter, saveData, categoryData)
    self.adapter = adapter
    self.categoryData = categoryData
    self.guildId = categoryData:GetGuildData():GetId()
    self.category = categoryData:GetEventCategory()
    self.key = string.format("%s/%d/%d", internal.WORLD_NAME, self.guildId, self.category)
    self.saveData = saveData[self.key] or {}
    saveData[self.key] = self.saveData
    self.performanceTracker = internal.class.PerformanceTracker:New()
    self.unprocessedEventsStartTime = self.saveData.newestLinkedEventTime
    self.rangeInfo = {}
    self.rangeInfoDirty = true
    self.progressDirty = true
    self.processingQueue = {}
    self.listeners = {}
    self:RefreshLinkedEventInfo()
end

function GuildHistoryCacheCategory:RefreshLinkedEventInfo()
    local oldestLinkedEventId = self:GetOldestLinkedEventInfo()
    local newestLinkedEventId = self:GetNewestLinkedEventInfo()
    if not oldestLinkedEventId or not newestLinkedEventId then return end

    local guildId, category = self.guildId, self.category
    local oldestIndex = GetNumGuildHistoryEvents(guildId, category)
    if oldestIndex <= 0 then
        logger:Warn("No events cached for guild %d category %d", guildId, category)
        self:Reset()
        return
    end

    local oldestCachedEventId = GetGuildHistoryEventId(guildId, category, oldestIndex)
    if newestLinkedEventId < oldestCachedEventId then
        logger:Warn("Linked range is outside cached range for guild %d category %d", guildId, category)
        self:Reset()
        return
    end

    local rangeIndex = self:FindRangeIndexForEventId(oldestLinkedEventId)
    if not rangeIndex then
        logger:Warn("Could not find linked range for guild %d category %d", guildId, category)
        self:Reset()
        return
    end

    if oldestCachedEventId ~= oldestLinkedEventId then
        local oldestCachedEventTimestamp = GetGuildHistoryEventTimestamp(guildId, category, oldestIndex)
        logger:Info("Data was removed from linked range for guild %d category %d", guildId, category)
        self:SetOldestLinkedEventInfo(oldestCachedEventId, oldestCachedEventTimestamp)
    end
end

function GuildHistoryCacheCategory:RegisterListener(listener)
    self.saveData.lastListenerRegisteredTime = GetTimeStamp()
    self.listeners[listener] = true
end

function GuildHistoryCacheCategory:UnregisterListener(listener)
    self.listeners[listener] = nil
end

function GuildHistoryCacheCategory:GetListenerInfo()
    local names = {}
    local legacyCount = 0
    for listener in pairs(self.listeners) do
        if listener.GetAddonName then
            names[#names + 1] = listener:GetAddonName()
        else
            legacyCount = legacyCount + 1
        end
    end
    return names, legacyCount, self.saveData.lastListenerRegisteredTime
end

function GuildHistoryCacheCategory:RequestMissingData()
    local guildId, category = self.guildId, self.category
    logger:Debug("Request missing data for guild %d category %d", guildId, category)
    if not self:IsAutoRequesting() then
        logger:Debug("Not automatically requesting more")
        return
    end

    if self:ContinueExistingRequest() then return end

    local oldestLinkedEventId, oldestLinkedEventTime = self:GetOldestLinkedEventInfo()
    local newestLinkedEventId, newestLinkedEventTime = self:GetNewestLinkedEventInfo()
    local oldestGaplessEvent = self.categoryData:GetOldestEventForUpToDateEventsWithoutGaps()
    if not oldestLinkedEventId or not newestLinkedEventId or not oldestGaplessEvent then
        if oldestGaplessEvent then
            self:OnCategoryUpdated()
        else
            self.initialRequest = true
            self:CreateRequest()
            self:QueueRequest()
        end
        return
    end

    local requestNewestTime, requestOldestTime = self:OptimizeRequestTimeRange(oldestLinkedEventTime,
        newestLinkedEventTime, oldestGaplessEvent)
    self:CreateRequest(requestNewestTime, requestOldestTime)
    self:QueueRequest()
end

function GuildHistoryCacheCategory:ContinueExistingRequest()
    local request = self.request
    if request then
        if not request:IsValid() or request:IsComplete() or self.initialRequest then
            self:DestroyRequest()
        else
            return self:QueueRequest()
        end
    end
    return false
end

function GuildHistoryCacheCategory:HasPendingRequest()
    return self.request ~= nil
end

function GuildHistoryCacheCategory:VerifyRequest()
    local request = self.request
    if request then
        if request:IsComplete() then
            logger:Warn("Request is complete but was not destroyed")
            self:DestroyRequest()
        elseif not request:IsValid() then
            logger:Warn("Request is invalid but was not destroyed")
            self:DestroyRequest()
        elseif not request:IsRequestQueued() then
            logger:Warn("Request is not queued")
            self:QueueRequest()
        end
    end
end

function GuildHistoryCacheCategory:CreateRequest(newestTime, oldestTime)
    local guildId, category = self.guildId, self.category
    logger:Debug("Create data request for guild %d category %d", guildId, category)
    self.request = ZO_GuildHistoryRequest:New(guildId, category, newestTime, oldestTime)
    internal:FireCallbacks(internal.callback.REQUEST_CREATED, self.request)
end

function GuildHistoryCacheCategory:QueueRequest()
    local request = self.request
    logger:Debug("Queue server request for guild %d category %d", self.guildId, self.category)
    if request:IsComplete() then
        logger:Warn("Tried to queue already completed request")
        self:DestroyRequest()
        return false
    end
    if request:RequestMoreEvents(true) == GUILD_HISTORY_DATA_READY_STATE_INVALID_REQUEST then
        self:DestroyRequest()
        return false
    end
    if request:IsComplete() then
        logger:Warn("Request is complete right after queuing it")
        self:DestroyRequest()
        return false
    end
    return true
end

function GuildHistoryCacheCategory:DestroyRequest()
    local request = self.request
    self.request = nil
    self.initialRequest = false
    DestroyGuildHistoryRequest(request:GetRequestId())
    internal:FireCallbacks(internal.callback.REQUEST_DESTROYED, request)
end

function GuildHistoryCacheCategory:OptimizeRequestTimeRange(oldestLinkedEventTime, newestLinkedEventTime,
                                                            oldestGaplessEvent)
    local requestOldestTime = oldestLinkedEventTime
    local requestNewestTime = oldestGaplessEvent:GetEventTimestampS()
    local guildId, category = self.guildId, self.category
    logger:Debug("Optimize request time range for guild %d category %d", guildId, category)

    local newestIndex, oldestIndex = self.adapter:GetGuildHistoryEventIndicesForTimeRange(guildId, category,
        newestLinkedEventTime, oldestLinkedEventTime)
    if not newestIndex or not oldestIndex then
        logger:Warn("Could not find events in linked range for guild %d category %d", guildId, category)
        return requestNewestTime, requestOldestTime
    end

    local numEvents = oldestIndex - newestIndex + 1
    local linkedRangeSeconds = newestLinkedEventTime - oldestLinkedEventTime
    local requestRangeSeconds = (requestNewestTime or GetTimeStamp()) - requestOldestTime
    local estimatedMissingEvents = numEvents * (requestRangeSeconds / linkedRangeSeconds)
    if estimatedMissingEvents > MISSING_EVENT_COUNT_THRESHOLD then
        logger:Debug("Limit request time range")
        requestNewestTime = requestOldestTime + (linkedRangeSeconds / numEvents) * MISSING_EVENT_COUNT_THRESHOLD / 2
    end

    if requestNewestTime <= requestOldestTime then
        logger:Debug("Request time range is invalid - request from oldest time up to latest")
        requestNewestTime = nil
    end
    return requestNewestTime, requestOldestTime
end

function GuildHistoryCacheCategory:IsAutoRequesting()
    local mode = self:GetRequestMode()
    if mode == internal.REQUEST_MODE_ON then
        return true
    elseif mode == internal.REQUEST_MODE_OFF then
        return false
    else
        local lastListenerTime = self.saveData.lastListenerRegisteredTime or 0
        return GetTimeStamp() - lastListenerTime < NO_LISTENER_THRESHOLD
    end
end

function GuildHistoryCacheCategory:GetRequestMode()
    return self.saveData.requestMode or internal.REQUEST_MODE_AUTO
end

function GuildHistoryCacheCategory:SetRequestMode(mode)
    logger:Info("Set request mode for guild %d category %d to %s", self.guildId, self.category, mode)
    self.saveData.requestMode = mode
    internal:FireCallbacks(internal.callback.REQUEST_MODE_CHANGED, self.guildId, self.category, mode)
end

function GuildHistoryCacheCategory:SetNewestLinkedEventInfo(eventId, eventTime)
    if eventId ~= 0 then
        self.saveData.newestLinkedEventId = eventId
        self.saveData.newestLinkedEventTime = eventTime
    else
        self.saveData.newestLinkedEventId = nil
        self.saveData.newestLinkedEventTime = nil
    end
    self.progressDirty = true
end

function GuildHistoryCacheCategory:SetOldestLinkedEventInfo(eventId, eventTime)
    if eventId ~= 0 then
        self.saveData.oldestLinkedEventId = eventId
        self.saveData.oldestLinkedEventTime = eventTime
    else
        self.saveData.oldestLinkedEventId = nil
        self.saveData.oldestLinkedEventTime = nil
        internal:FireCallbacks(internal.callback.LINKED_RANGE_LOST, self.guildId, self.category)
    end
end

function GuildHistoryCacheCategory:GetNewestLinkedEventInfo()
    local eventId = self.saveData.newestLinkedEventId
    local eventTime = self.saveData.newestLinkedEventTime
    if eventId ~= 0 then
        return eventId, eventTime
    end
end

function GuildHistoryCacheCategory:GetOldestLinkedEventInfo()
    local eventId = self.saveData.oldestLinkedEventId
    local eventTime = self.saveData.oldestLinkedEventTime
    if eventId ~= 0 then
        return eventId, eventTime
    end
end

function GuildHistoryCacheCategory:OnCategoryUpdated(flags)
    self.rangeInfoDirty = true

    internal:FireCallbacks(internal.callback.CATEGORY_DATA_UPDATED, self, flags)
    self:RestartProcessingTask()
    if self:ContinueExistingRequest() then return end

    self.progressDirty = true
    local guildId, category = self.guildId, self.category
    local oldestLinkedEventId = self:GetOldestLinkedEventInfo()
    local newestLinkedEventId = self:GetNewestLinkedEventInfo()

    if not oldestLinkedEventId or not newestLinkedEventId then
        if oldestLinkedEventId ~= newestLinkedEventId then
            logger:Warn("Invalid save data state for guild %d category %d", guildId, category)
            self:Reset()
        else
            logger:Info("No linked range stored for guild %d category %d", guildId, category)
        end

        newestLinkedEventId = self:SetupFirstLinkedEventId()
        oldestLinkedEventId = newestLinkedEventId
    end

    self:ProcessNextRequest()
    if newestLinkedEventId and oldestLinkedEventId then
        self:StartProcessingEvents(newestLinkedEventId, oldestLinkedEventId)
    end
end

function GuildHistoryCacheCategory:Reset()
    logger:Info("Resetting cache for guild %d category %d", self.guildId, self.category)
    if self.request then
        self:DestroyRequest()
    end

    if self.processingTask then
        self.processingTask:Cancel()
        self.processingTask = nil
    end

    if self.processingRequest then
        self.processingRequest:StopProcessing()
        self.processingRequest = nil
    end

    for listener in pairs(self.listeners) do
        listener:Stop()
    end

    self:SetNewestLinkedEventInfo()
    self:SetOldestLinkedEventInfo()
end

function GuildHistoryCacheCategory:SetupFirstLinkedEventId()
    logger:Info("Setting up first linked event for guild %d category %d", self.guildId, self.category)
    local event = self.categoryData:GetOldestEventForUpToDateEventsWithoutGaps()
    if not event then
        logger:Warn("Could not find any events for guild %d category %d", self.guildId, self.category)
        return
    end
    local eventId = event:GetEventId()
    local eventTime = event:GetEventTimestampS()
    logger:Debug("Send first event %d to listeners", eventId)
    internal:FireCallbacks(internal.callback.PROCESS_LINKED_EVENT, self.guildId, self.category, event)
    self:SetOldestLinkedEventInfo(eventId, eventTime)
    self:SetNewestLinkedEventInfo(eventId, eventTime)
    internal:FireCallbacks(internal.callback.LINKED_RANGE_FOUND, self.guildId, self.category)
    return eventId
end

function GuildHistoryCacheCategory:QueueProcessingRequest(request)
    self.processingQueue[#self.processingQueue + 1] = request
    self:ProcessNextRequest()
end

function GuildHistoryCacheCategory:RemoveProcessingRequest(request)
    if self.processingRequest == request then
        self.processingRequest:StopProcessing()
        self.processingRequest = nil
    end

    for i = 1, #self.processingQueue do
        if self.processingQueue[i] == request then
            table.remove(self.processingQueue, i)
            self:ProcessNextRequest()
            return
        end
    end
end

function GuildHistoryCacheCategory:ProcessNextRequest()
    if self:IsProcessing() then return end
    local request = self.processingQueue[1]
    if request then
        request:StartProcessing()
    end
end

function GuildHistoryCacheCategory:StartProcessingEvents(newestLinkedEventId, oldestLinkedEventId)
    if self:IsProcessing() then return end

    local guildId, category = self.guildId, self.category
    logger:Info("Start processing events for guild %d category %d", guildId, category)
    local rangeIndex = self:FindRangeIndexForEventId(newestLinkedEventId)
    if not rangeIndex then
        logger:Warn("Could not find linked range for guild %d category %d", guildId, category)
        self:RequestMissingData()
        return
    end

    local newestTime, oldestTime, newestEventId, oldestEventId = self:GetRangeInfo(rangeIndex)
    local unlinkedEvents, missedEvents = {}, {}
    local categoryData = self.categoryData

    if newestLinkedEventId < newestEventId then
        local _, newestLinkedEventTime = self:GetNewestLinkedEventInfo()
        logger:Debug("Found events newer than the linked range for guild %d category %d", guildId, category)
        unlinkedEvents = categoryData:GetEventsInTimeRange(newestTime, newestLinkedEventTime)
    end

    if oldestLinkedEventId > oldestEventId then
        local _, oldestLinkedEventTime = self:GetOldestLinkedEventInfo()
        logger:Debug("Found events older than the linked range for guild %d category %d", guildId, category)
        missedEvents = categoryData:GetEventsInTimeRange(oldestLinkedEventTime, oldestTime)
    end

    local numUnlinkedEvents = #unlinkedEvents
    local numMissedEvents = #missedEvents
    logger:Info("Found %d unlinked events and %d missed events for guild %d category %d", numUnlinkedEvents,
        numMissedEvents, guildId, category)

    if numUnlinkedEvents > 0 or numMissedEvents > 0 then
        local task = internal:CreateAsyncTask()
        self.processingTask = task

        self:InitializePendingEventMetrics(numUnlinkedEvents + numMissedEvents)
        if numUnlinkedEvents > 0 then
            self.processingStartTime = unlinkedEvents[numUnlinkedEvents]:GetEventTimestampS()
            self.processingEndTime = unlinkedEvents[1]:GetEventTimestampS()
            logger:Info("set processing time range", guildId, category, self
                .processingStartTime, self.processingEndTime)
            internal:FireCallbacks(internal.callback.PROCESS_LINKED_EVENTS_STARTED, guildId, category, numUnlinkedEvents)
        end

        task:For(numUnlinkedEvents, 1, -1):Do(function(i)
            self.progressDirty = true
            self:IncrementPendingEventMetrics()
            local event = unlinkedEvents[i]
            local eventId = event:GetEventId()
            if eventId <= newestLinkedEventId then
                logger:Warn("skip already linked event")
            else
                local eventTime = event:GetEventTimestampS()
                self:SetNewestLinkedEventInfo(eventId, eventTime)
                logger:Verbose("Send unlinked event to listeners", guildId, category, eventId)
                internal:FireCallbacks(internal.callback.PROCESS_LINKED_EVENT, guildId, category, event)
                self.processingCurrentTime = eventTime
            end
        end):Then(function()
            self.progressDirty = true
            logger:Debug("Finished processing unlinked events", guildId, category)
            internal:FireCallbacks(internal.callback.PROCESS_LINKED_EVENTS_FINISHED, guildId, category)
            self.processingCurrentTime = nil
            if numMissedEvents > 0 then
                self.processingStartTime = missedEvents[numMissedEvents]:GetEventTimestampS()
                self.processingEndTime = missedEvents[1]:GetEventTimestampS()
                logger:Info("set processing time range", guildId, category, self.processingStartTime,
                    self.processingEndTime)
                internal:FireCallbacks(internal.callback.PROCESS_MISSED_EVENTS_STARTED, guildId, category,
                    numMissedEvents)
            else
                self.processingStartTime = nil
                self.processingEndTime = nil
            end
        end):For(1, numMissedEvents):Do(function(i)
            self.progressDirty = true
            self:IncrementPendingEventMetrics()
            local event = missedEvents[i]
            local eventId = event:GetEventId()
            if eventId >= oldestLinkedEventId then
                logger:Warn("skip already linked event")
            else
                local eventTime = event:GetEventTimestampS()
                self:SetOldestLinkedEventInfo(eventId, eventTime)
                logger:Verbose("Send missed event to listeners", guildId, category, eventId)
                internal:FireCallbacks(internal.callback.PROCESS_MISSED_EVENT, guildId, category, event)
                self.processingCurrentTime = eventTime
            end
        end):Then(function()
            self.progressDirty = true
            self:ResetPendingEventMetrics()
            self.processingTask = nil
            self.processingStartTime = nil
            self.processingEndTime = nil
            self.processingCurrentTime = nil
            logger:Info("Finished processing missed events", guildId, category)
            internal:FireCallbacks(internal.callback.PROCESS_MISSED_EVENTS_FINISHED, guildId, category)
            self:ProcessNextRequest()
        end)
    end
end

function GuildHistoryCacheCategory:RestartProcessingTask()
    if self.processingTask then
        logger:Info("Restart processing events for guild %d category %d", self.guildId, self.category)
        self.processingTask:Cancel()
        self.processingTask = nil
        local newestLinkedEventId = self:GetNewestLinkedEventInfo()
        local oldestLinkedEventId = self:GetOldestLinkedEventInfo()
        self:StartProcessingEvents(newestLinkedEventId, oldestLinkedEventId)
    end
end

function GuildHistoryCacheCategory:GetKey()
    return self.key
end

function GuildHistoryCacheCategory:GetGuildId()
    return self.guildId
end

function GuildHistoryCacheCategory:GetCategory()
    return self.category
end

function GuildHistoryCacheCategory:HasLinked()
    if self.processingTask then return false end

    local event = self.categoryData:GetOldestEventForUpToDateEventsWithoutGaps()
    if not event then
        return true
    end

    local newestLinkedEventId = self:GetNewestLinkedEventInfo()
    if newestLinkedEventId then
        return event:GetEventId() <= newestLinkedEventId
    end

    return false
end

function GuildHistoryCacheCategory:IsFor(guildId, category)
    return self.guildId == guildId and self.category == category
end

function GuildHistoryCacheCategory:IsProcessing()
    return self.processingTask ~= nil or self.processingRequest ~= nil
end

function GuildHistoryCacheCategory:GetNumLinkedEvents()
    local _, oldestEventTime = self:GetOldestLinkedEventInfo()
    local _, newestEventTime = self:GetNewestLinkedEventInfo()
    if not oldestEventTime or not newestEventTime then return 0 end
    local newestIndex, oldestIndex = self.adapter:GetGuildHistoryEventIndicesForTimeRange(
        self.guildId, self.category, newestEventTime, oldestEventTime)
    if not newestIndex or not oldestIndex then return 0 end
    return oldestIndex - newestIndex + 1
end

function GuildHistoryCacheCategory:GetNumUnlinkedEvents()
    local _, newestEventTime = self:GetNewestLinkedEventInfo()
    if not newestEventTime then return 0 end
    local now = GetTimeStamp()
    local newestIndex, oldestIndex = self.adapter:GetGuildHistoryEventIndicesForTimeRange(
        self.guildId, self.category, now, newestEventTime + 1)
    if not newestIndex or not oldestIndex then return 0 end
end

function GuildHistoryCacheCategory:HasCachedEvents()
    return self.categoryData:GetNumEvents() > 0
end

function GuildHistoryCacheCategory:GetEvent(i)
    return self.categoryData:GetEvent(i)
end

function GuildHistoryCacheCategory:GetEventById(eventId)
    if not eventId then return end
    local index = GetGuildHistoryEventIndex(self.guildId, self.category, eventId)
    if not index then return end
    return self.categoryData:GetEvent(index)
end

function GuildHistoryCacheCategory:GetOldestLinkedEvent()
    local eventId = self:GetOldestLinkedEventInfo()
    if not eventId then return end
    return self:GetEventById(eventId)
end

function GuildHistoryCacheCategory:GetNewestLinkedEvent()
    local eventId = self:GetNewestLinkedEventInfo()
    if not eventId then return end
    return self:GetEventById(eventId)
end

function GuildHistoryCacheCategory:GetOldestCachedEvent()
    local numEvents = self.categoryData:GetNumEvents()
    if numEvents == 0 then return end
    return self.categoryData:GetEvent(numEvents)
end

function GuildHistoryCacheCategory:GetLocalCacheTimeLimit()
    local cacheLimit = self.adapter:GetGuildHistoryCacheMaxTime(self.category)
    return internal.UI_LOAD_TIME - cacheLimit
end

function GuildHistoryCacheCategory:GetCacheStartTime()
    local startTime

    local numEvents = self.categoryData:GetNumEvents()
    if numEvents > 0 then
        local oldestEvent = self.categoryData:GetEvent(numEvents)
        if oldestEvent then
            startTime = oldestEvent:GetEventTimestampS()
        end
    end

    local serverTimeLimit = GetTimeStamp() - self.adapter:GetGuildHistoryServerMaxTime(self.category)
    if not startTime or serverTimeLimit < startTime then
        startTime = serverTimeLimit
    end

    local localLimitTime = self:GetLocalCacheTimeLimit()
    if localLimitTime < startTime then
        startTime = localLimitTime
    end

    return startTime
end

function GuildHistoryCacheCategory:GetUnprocessedEventsStartTime()
    return self.unprocessedEventsStartTime
end

function GuildHistoryCacheCategory:GetGaplessRangeStartTime()
    local event = self.categoryData:GetOldestEventForUpToDateEventsWithoutGaps()
    if event then
        return event:GetEventTimestampS()
    end
end

function GuildHistoryCacheCategory:GetRequestTimeRange()
    local request = self.request
    if request then
        return request.oldestTimeS or 0, request.newestTimeS or GetTimeStamp()
    end
end

function GuildHistoryCacheCategory:GetProcessingTimeRange()
    return self.processingStartTime, self.processingEndTime, self.processingCurrentTime
end

function GuildHistoryCacheCategory:UpdateRangeInfo()
    if self.rangeInfoDirty then
        self.rangeInfoDirty = false

        local guildId, category = self.guildId, self.category
        local ranges = {}
        for i = 1, GetNumGuildHistoryEventRanges(guildId, category) do
            local newestTimeS, oldestTimeS = GetGuildHistoryEventRangeInfo(guildId, category, i)
            -- range info includes events that are hidden due to permissions, so we check for actually visible events here
            local newestIndex, oldestIndex = self.adapter:GetGuildHistoryEventIndicesForTimeRange(
                guildId, category, newestTimeS, oldestTimeS)
            if newestIndex then
                local newestEventId, newestTimeS = GetGuildHistoryEventBasicInfo(guildId, category, newestIndex)
                local oldestEventId, oldestTimeS = GetGuildHistoryEventBasicInfo(guildId, category, oldestIndex)
                ranges[#ranges + 1] = { newestTimeS, oldestTimeS, newestEventId, oldestEventId }
            end
        end

        table.sort(ranges, function(a, b)
            return a[1] < b[1]
        end)
        self.rangeInfo = ranges
    end
end

function GuildHistoryCacheCategory:GetNumRanges()
    self:UpdateRangeInfo()
    return #self.rangeInfo
end

function GuildHistoryCacheCategory:GetRangeInfo(index)
    self:UpdateRangeInfo()
    local range = self.rangeInfo[index]
    if not range then return end
    return unpack(range)
end

function GuildHistoryCacheCategory:FindRangeIndexForEventId(eventId)
    for i = 1, self:GetNumRanges() do
        local _, _, newestEventId, oldestEventId = self:GetRangeInfo(i)
        if eventId >= oldestEventId and eventId <= newestEventId then
            return i
        end
    end
end

function GuildHistoryCacheCategory:GetIndexRangeForEventIdRange(startId, endId)
    local startIndex = GetGuildHistoryEventIndex(self.guildId, self.category, startId)
    local endIndex = GetGuildHistoryEventIndex(self.guildId, self.category, endId)
    return startIndex, endIndex
end

function GuildHistoryCacheCategory:FindFirstAvailableEventIdForEventId(eventId)
    local oldestLinkedEventId = self:GetOldestLinkedEventInfo()
    if not oldestLinkedEventId then
        return nil
    elseif eventId <= oldestLinkedEventId then
        return oldestLinkedEventId
    end

    local newestLinkedEventId = self:GetNewestLinkedEventInfo()
    if not newestLinkedEventId or eventId > newestLinkedEventId then
        return nil
    elseif eventId == newestLinkedEventId then
        return newestLinkedEventId
    end

    local newestIndex, oldestIndex = self:GetLinkedRangeIndices()
    if not newestIndex or not oldestIndex then return nil end

    local eventId = self:SearchEventIdInInterval(eventId, newestIndex, oldestIndex)
    return eventId
end

function GuildHistoryCacheCategory:GetLinkedRangeIndices()
    local oldestLinkedEventId = self:GetOldestLinkedEventInfo()
    if not oldestLinkedEventId then return end

    local guildId, category = self.guildId, self.category
    local rangeIndex = self:FindRangeIndexForEventId(oldestLinkedEventId)
    if not rangeIndex then return end

    local newestTime, oldestTime = self:GetRangeInfo(rangeIndex)
    local newestIndex, oldestIndex = self.adapter:GetGuildHistoryEventIndicesForTimeRange(
        guildId, category, newestTime, oldestTime)
    return newestIndex, oldestIndex
end

function GuildHistoryCacheCategory:SearchEventIdInInterval(eventId, firstIndex, lastIndex)
    if lastIndex - firstIndex < 2 then return nil, nil end

    local firstEventId = self:GetEvent(firstIndex):GetEventId()
    local lastEventId = self:GetEvent(lastIndex):GetEventId()
    if eventId < firstEventId or eventId > lastEventId then
        logger:Warn("Abort SearchEventIdInInterval", eventId < firstEventId, eventId > lastEventId)
        return nil, nil
    end

    local distanceFromFirst = (eventId - firstEventId) / (lastEventId - firstEventId)
    local index = firstIndex + math.floor(distanceFromFirst * (lastIndex - firstIndex))
    if index == firstIndex or index == lastIndex then
        -- our approximation is likely incorrect, so we just do a regular binary search
        index = firstIndex + math.floor(0.5 * (lastIndex - firstIndex))
    end

    local event = self:GetEvent(index)
    local foundEventId = event:GetEventId()

    if eventId > foundEventId then
        return self:SearchEventIdInInterval(eventId, index, lastIndex)
    elseif eventId < foundEventId then
        return self:SearchEventIdInInterval(eventId, firstIndex, index)
    end

    return event, index
end

function GuildHistoryCacheCategory:FindLastAvailableEventIdForEventId(eventId)
    local oldestLinkedEventId = self:GetOldestLinkedEventInfo()
    if not oldestLinkedEventId or eventId < oldestLinkedEventId then
        return nil
    elseif eventId == oldestLinkedEventId then
        return oldestLinkedEventId
    end

    local newestLinkedEventId = self:GetNewestLinkedEventInfo()
    if not newestLinkedEventId then
        return nil
    elseif eventId > newestLinkedEventId then
        return newestLinkedEventId
    end

    local newestIndex, oldestIndex = self:GetLinkedRangeIndices()
    if not newestIndex or not oldestIndex then return nil end

    local eventId = self:SearchEventIdInInterval(eventId, newestIndex, oldestIndex)
    return eventId
end

function GuildHistoryCacheCategory:FindFirstAvailableEventIdForEventTime(eventTime)
    local oldestId, oldestTime = self:GetOldestLinkedEventInfo()
    if not oldestId then
        return nil
    elseif eventTime <= oldestTime then
        return oldestId
    end

    local newestId, newestTime = self:GetNewestLinkedEventInfo()
    if not newestId then
        return nil
    end

    local guildId, category = self.guildId, self.category
    local _, oldestIndex = self.adapter:GetGuildHistoryEventIndicesForTimeRange(
        guildId, category, newestTime, eventTime)
    if oldestIndex then
        return GetGuildHistoryEventId(guildId, category, oldestIndex)
    end

    return nil
end

function GuildHistoryCacheCategory:FindLastAvailableEventIdForEventTime(eventTime)
    local newestId, newestTime = self:GetNewestLinkedEventInfo()
    if not newestId then
        return nil
    elseif eventTime > newestTime then
        return newestId
    end

    local oldestId, oldestTime = self:GetOldestLinkedEventInfo()
    if not oldestId then
        return nil
    end

    local guildId, category = self.guildId, self.category
    local newestIndex = self.adapter:GetGuildHistoryEventIndicesForTimeRange(
        guildId, category, eventTime, oldestTime)
    if newestIndex then
        return GetGuildHistoryEventId(guildId, category, newestIndex)
    end

    return nil
end

function GuildHistoryCacheCategory:Clear()
    logger:Warn("Clearing cache for guild %d category %d", self.guildId, self.category)
    local result = ClearGuildHistoryCache(self.guildId, self.category)
    logger:Info("Cache clear result:", result)
    return result
end

function GuildHistoryCacheCategory:InitializePendingEventMetrics(numPendingEvents)
    self.numPendingEvents = numPendingEvents
    self.performanceTracker:Reset()
end

function GuildHistoryCacheCategory:ResetPendingEventMetrics()
    self.numPendingEvents = nil
    self.performanceTracker:Reset()
end

function GuildHistoryCacheCategory:IncrementPendingEventMetrics()
    self.numPendingEvents = self.numPendingEvents - 1
    self.performanceTracker:Increment()
end

function GuildHistoryCacheCategory:GetPendingEventMetrics()
    if not self.numPendingEvents or not self:IsProcessing() then return 0, -1, -1 end

    local count = self.numPendingEvents
    local speed, timeLeft = self.performanceTracker:GetProcessingSpeedAndEstimatedTimeLeft(count)
    return count, speed, timeLeft
end

function GuildHistoryCacheCategory:UpdateProgressBar(bar)
    bar:Update(self)
end

function GuildHistoryCacheCategory:GetProgress()
    if self.progressDirty then
        if self:HasLinked() then
            self.progress = 1
            self.missingTime = 0
        else
            local _, newestEventTime = self:GetNewestLinkedEventInfo()
            if newestEventTime then
                local now = GetTimeStamp()
                local events = self.categoryData:GetEventsInTimeRange(newestEventTime + 1, now) -- TODO optimize by getting the time directly
                if #events > 0 then
                    self.missingTime = events[1]:GetEventTimestampS() - newestEventTime
                    self.progress = 1 - self.missingTime / (now - newestEventTime)
                else
                    self.progress = 0
                    self.missingTime = -1
                end
            else
                self.progress = 0
                self.missingTime = -1
            end
        end
        self.progressDirty = false
    end
    return self.progress, self.missingTime
end

function GuildHistoryCacheCategory:IsAggregated()
    return false
end

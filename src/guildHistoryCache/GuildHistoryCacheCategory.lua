-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local MISSING_EVENT_COUNT_THRESHOLD = 2000
local NO_LISTENER_THRESHOLD = 3 * 24 * 3600            -- 3 days
local INITIAL_REQUEST_RESEND_THRESHOLD = 7 * 24 * 3600 -- 7 days
local BASE_PRIORITY = {
    [GUILD_HISTORY_EVENT_CATEGORY_TRADER] = 40,
    [GUILD_HISTORY_EVENT_CATEGORY_BANKED_CURRENCY] = 30,
    [GUILD_HISTORY_EVENT_CATEGORY_BANKED_ITEM] = 20,
    [GUILD_HISTORY_EVENT_CATEGORY_ROSTER] = 10,
    [GUILD_HISTORY_EVENT_CATEGORY_ACTIVITY] = 0,
    [GUILD_HISTORY_EVENT_CATEGORY_AVA_ACTIVITY] = 0,
    [GUILD_HISTORY_EVENT_CATEGORY_MILESTONE] = 0,
}
local LISTENER_PRIORITY_BONUS = 6

local GuildHistoryCacheCategory = ZO_InitializingObject:Subclass()
internal.class.GuildHistoryCacheCategory = GuildHistoryCacheCategory

function GuildHistoryCacheCategory:Initialize(adapter, requestManager, categoryData)
    self.adapter = adapter
    self.requestManager = requestManager
    self.categoryData = categoryData
    self.guildId = categoryData:GetGuildData():GetId()
    self.category = categoryData:GetEventCategory()
    self.key = string.format("%s/%d/%d", internal.WORLD_NAME, self.guildId, self.category)
    self.saveData = adapter:GetOrCreateCacheSaveData(self.key)
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
    local oldestLinkedEventId, oldestLinkedEventTime = self:GetOldestLinkedEventInfo()
    local newestLinkedEventId, newestLinkedEventTime = self:GetNewestLinkedEventInfo()
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

    if oldestCachedEventId ~= oldestLinkedEventId then
        oldestLinkedEventId, oldestLinkedEventTime = GetGuildHistoryEventBasicInfo(guildId, category, oldestIndex)
        logger:Info("Data was removed from linked range for guild %d category %d", guildId, category)
        self:SetOldestLinkedEventInfo(oldestLinkedEventId, oldestLinkedEventTime)
    end

    local rangeIndex = self:FindRangeIndexForEventId(oldestCachedEventId)
    if not rangeIndex then
        logger:Warn("Could not find linked range for guild %d category %d", guildId, category)
        self:Reset()
        return
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

function GuildHistoryCacheCategory:GetRequestPriority()
    local priority = BASE_PRIORITY[self.category] or 0
    local listenerPriority = LISTENER_PRIORITY_BONUS * NonContiguousCount(self.listeners)
    return priority + listenerPriority
end

function GuildHistoryCacheCategory:ShouldSendInitialRequest(oldestLinkedEventId)
    local timeSinceLastInitialRequest = GetTimeStamp() - (self.saveData.initialRequestTime or 0)
    if not oldestLinkedEventId and timeSinceLastInitialRequest < INITIAL_REQUEST_RESEND_THRESHOLD then
        logger:Debug("Initial request on cooldown")
        return false
    end

    local shouldSend = true
    if self.category == GUILD_HISTORY_EVENT_CATEGORY_TRADER then
        shouldSend = DoesGuildHavePrivilege(self.guildId, GUILD_PRIVILEGE_TRADING_HOUSE)
    elseif self.category == GUILD_HISTORY_EVENT_CATEGORY_BANKED_CURRENCY or self.category == GUILD_HISTORY_EVENT_CATEGORY_BANKED_ITEM then
        shouldSend = DoesGuildHavePrivilege(self.guildId, GUILD_PRIVILEGE_BANK_DEPOSIT)
    end
    logger:Debug("Should send initial request", shouldSend)
    return shouldSend
end

function GuildHistoryCacheCategory:RequestMissingData()
    logger:Debug("Request missing data for", self.key)
    if self:ContinueExistingRequest() or not self:IsAutoRequesting() then return end

    local oldestLinkedEventId, oldestLinkedEventTime = self:GetOldestLinkedEventInfo()
    local newestLinkedEventId, newestLinkedEventTime = self:GetNewestLinkedEventInfo()
    local oldestGaplessEventIndex = GetOldestGuildHistoryEventIndexForUpToDateEventsWithoutGaps(self.guild, self
        .category)
    if not oldestLinkedEventId or not newestLinkedEventId then
        if oldestGaplessEventIndex then
            self:OnCategoryUpdated()
        elseif self:ShouldSendInitialRequest(oldestLinkedEventId) then
            self.requestManager:QueueRequest(self:CreateRequest())
        end
        return
    end

    local oldestGaplessEventTime
    if oldestGaplessEventIndex then
        local oldestGaplessEventId
        oldestGaplessEventId, oldestGaplessEventTime = GetGuildHistoryEventBasicInfo(self.guild, self.category,
            oldestGaplessEventIndex)
        if oldestLinkedEventId == oldestGaplessEventId then
            logger:Debug("No missing data for", self.key)
            self:OnCategoryUpdated()
            return
        end
    else
        oldestGaplessEventTime = GetTimeStamp()
    end

    local requestNewestTime, requestOldestTime = self:OptimizeRequestTimeRange(oldestLinkedEventTime,
        newestLinkedEventTime, oldestGaplessEventTime)
    if requestNewestTime and requestOldestTime then
        self.requestManager:QueueRequest(self:CreateRequest(requestNewestTime, requestOldestTime))
    end
end

function GuildHistoryCacheCategory:ContinueExistingRequest()
    local request = self.request
    if request then
        if request:IsInitialRequest() then
            self.saveData.initialRequestTime = GetTimeStamp()
        end

        if request:ShouldContinue() then
            logger:Debug("Queue existing request", self.key)
            self.requestManager:QueueRequest(request)
            return true
        else
            logger:Debug("Destroy existing request", self.key)
            self:DestroyRequest()
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
            logger:Warn("Request is complete but was not destroyed", self.key)
            self:DestroyRequest()
        elseif not request:IsValid() then
            logger:Warn("Request is invalid but was not destroyed", self.key)
            self:DestroyRequest()
        elseif not request:IsRequestQueued() then
            logger:Warn("Request is not queued", self.key)
            self.requestManager:QueueRequest(request)
        else
            logger:Debug("Request is valid and queued", self.key)
        end
    elseif not self:HasLinked() then
        logger:Debug("No request and not linked", self.key)
        self:RequestMissingData()
    end
end

function GuildHistoryCacheCategory:CreateRequest(newestTime, oldestTime)
    logger:Debug("Create server request", self.key)
    self.request = internal.class.GuildHistoryServerRequest:New(self, newestTime, oldestTime)
    internal:FireCallbacks(internal.callback.REQUEST_CREATED, self.request)
    return self.request
end

function GuildHistoryCacheCategory:DestroyRequest(request)
    if not self.request or (request and self.request ~= request) then return end
    logger:Debug("destroy server request", self.key)
    local request = self.request
    self.request = nil
    if not request:Destroy() then return end
    if request:IsRequestQueued() then
        self.requestManager:RemoveRequest(request)
    end
    internal:FireCallbacks(internal.callback.REQUEST_DESTROYED, request)
end

function GuildHistoryCacheCategory:OptimizeRequestTimeRange(oldestLinkedEventTime, newestLinkedEventTime,
                                                            oldestGaplessEventTime)
    if oldestGaplessEventTime <= newestLinkedEventTime then
        logger:Warn("Time range optimization failed - Invalid time range")
        return nil, nil
    end

    local requestOldestTime = newestLinkedEventTime - 1
    local requestNewestTime = oldestGaplessEventTime + 1
    local guildId, category = self.guildId, self.category
    logger:Debug("Optimize request time range for", self.key)

    local newestIndex, oldestIndex = self.adapter:GetGuildHistoryEventIndicesForTimeRange(guildId, category,
        newestLinkedEventTime, oldestLinkedEventTime)
    if not newestIndex or not oldestIndex then
        logger:Warn("Time range optimization failed - could not find events in linked range")
        return requestNewestTime, requestOldestTime
    end

    local numEvents = oldestIndex - newestIndex + 1
    local linkedRangeSeconds = newestLinkedEventTime - oldestLinkedEventTime
    local requestRangeSeconds = requestNewestTime - requestOldestTime

    local estimatedMissingEvents = numEvents * requestRangeSeconds / linkedRangeSeconds
    logger:Verbose("estimatedMissingEvents", estimatedMissingEvents, numEvents, requestRangeSeconds, linkedRangeSeconds)
    if estimatedMissingEvents > MISSING_EVENT_COUNT_THRESHOLD then
        logger:Debug("Limit request time range")
        requestNewestTime = requestOldestTime + 1 + (linkedRangeSeconds / numEvents) * MISSING_EVENT_COUNT_THRESHOLD / 2
    end

    if requestNewestTime <= requestOldestTime then
        logger:Warn("Time range optimization failed - request range is invalid")
        requestNewestTime = oldestGaplessEventTime + 1
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
    if not self:IsAutoRequesting() then
        logger:Debug("Skip processing for inactive category", self.key)
        return
    end

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
    self.saveData.initialRequestTime = nil

    self.rangeInfoDirty = true
    self.progressDirty = true

    zo_callLater(function() self:OnCategoryUpdated() end, 0)
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
    if not request then return end

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
    if self:IsProcessing() or not self:IsAutoRequesting() then return end

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
                logger:Warn("skip already linked event", guildId, category, eventId, newestLinkedEventId)
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
                self.processingCurrentTime = -eventTime
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
    local event = self.categoryData:GetOldestEventForUpToDateEventsWithoutGaps()
    if not event then
        return not self:HasCachedEvents()
    end

    local newestLinkedEventId = self:GetNewestLinkedEventInfo()
    if newestLinkedEventId then
        local index = GetGuildHistoryEventIndex(self.guildId, self.category, newestLinkedEventId)
        return index == 1
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
    return self:GetOldestUnlinkedEventIndex() or 0
end

function GuildHistoryCacheCategory:GetOldestUnlinkedEventTime()
    local index = self:GetOldestUnlinkedEventIndex()
    if not index then return end
    return GetGuildHistoryEventTimestamp(self.guildId, self.category, index)
end

function GuildHistoryCacheCategory:GetOldestUnlinkedEventIndex()
    local newestLinkedEventId = self:GetNewestLinkedEventInfo()
    if not newestLinkedEventId then return end
    local index = GetGuildHistoryEventIndex(self.guildId, self.category, newestLinkedEventId)
    if not index or index == 1 then return end
    return index - 1
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
        return request.oldestTime, request.newestTime
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
            if newestIndex and oldestIndex then
                local newestEventId, newestTimeS = GetGuildHistoryEventBasicInfo(guildId, category, newestIndex)
                local oldestEventId, oldestTimeS = GetGuildHistoryEventBasicInfo(guildId, category, oldestIndex)
                if newestEventId and oldestEventId then
                    ranges[#ranges + 1] = { newestTimeS, oldestTimeS, newestEventId, oldestEventId }
                else
                    logger:Warn("Could not get event info for range")
                end
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
        logger:Verbose("No oldestLinkedEventId found")
        return nil
    elseif eventId <= oldestLinkedEventId then
        logger:Verbose("Event is older than oldestLinkedEventId")
        return oldestLinkedEventId
    end

    local newestLinkedEventId = self:GetNewestLinkedEventInfo()
    if not newestLinkedEventId or eventId > newestLinkedEventId then
        logger:Verbose("No newestLinkedEventId found or event is newer than newestLinkedEventId")
        return nil
    elseif eventId == newestLinkedEventId then
        logger:Verbose("Event is newestLinkedEventId")
        return newestLinkedEventId
    end

    local newestIndex, oldestIndex = self:GetLinkedRangeIndices()
    if not newestIndex or not oldestIndex then
        logger:Verbose("No linked range found")
        return nil
    end

    local eventId = self:SearchEventIdInInterval(eventId, newestIndex, oldestIndex)
    return eventId
end

function GuildHistoryCacheCategory:GetLinkedRangeIndices()
    local oldestLinkedEventId = self:GetOldestLinkedEventInfo()
    if not oldestLinkedEventId then
        logger:Verbose("No oldestLinkedEventId found")
        return
    end

    local guildId, category = self.guildId, self.category
    local rangeIndex = self:FindRangeIndexForEventId(oldestLinkedEventId)
    if not rangeIndex then
        logger:Verbose("No rangeIndex found for oldestLinkedEventId", oldestLinkedEventId)
        return
    end

    local newestTime, oldestTime = self:GetRangeInfo(rangeIndex)
    local newestIndex, oldestIndex = self.adapter:GetGuildHistoryEventIndicesForTimeRange(
        guildId, category, newestTime, oldestTime)
    return newestIndex, oldestIndex
end

function GuildHistoryCacheCategory:SearchEventIdInInterval(eventId, firstIndex, lastIndex)
    if firstIndex > lastIndex then
        logger:Warn("SearchEventIdInInterval - firstIndex is greater than lastIndex", firstIndex, lastIndex)
        local temp = firstIndex
        firstIndex = lastIndex
        lastIndex = temp
    end

    if lastIndex - firstIndex < 2 then
        logger:Verbose("Abort SearchEventIdInInterval - not enough events")
        return nil, nil
    end

    local firstEventId = self:GetEvent(firstIndex):GetEventId()
    local lastEventId = self:GetEvent(lastIndex):GetEventId()
    if eventId < firstEventId or eventId > lastEventId then
        logger:Warn("Abort SearchEventIdInInterval - eventId is outside current range", eventId < firstEventId,
            eventId > lastEventId)
        return nil, nil
    end

    local distanceFromFirst = (eventId - firstEventId) / (lastEventId - firstEventId)
    local index = firstIndex + math.floor(distanceFromFirst * (lastIndex - firstIndex))
    if index == firstIndex or index == lastIndex then
        -- our approximation is likely incorrect, so we just do a regular binary search
        index = firstIndex + math.floor(0.5 * (lastIndex - firstIndex))
        logger:Verbose("Use regular index", index)
    else
        logger:Verbose("Use approximated index", index)
    end

    local event = self:GetEvent(index)
    local foundEventId = event:GetEventId()

    if eventId > foundEventId then
        logger:Verbose("SearchEventIdInInterval - eventId is greater than foundEventId")
        return self:SearchEventIdInInterval(eventId, index, lastIndex)
    elseif eventId < foundEventId then
        logger:Verbose("SearchEventIdInInterval - eventId is smaller than foundEventId")
        return self:SearchEventIdInInterval(eventId, firstIndex, index)
    end

    logger:Verbose("SearchEventIdInInterval - eventId found")
    return foundEventId, index
end

function GuildHistoryCacheCategory:FindLastAvailableEventIdForEventId(eventId)
    local oldestLinkedEventId = self:GetOldestLinkedEventInfo()
    if not oldestLinkedEventId or eventId < oldestLinkedEventId then
        logger:Verbose("No oldestLinkedEventId found or event is older than oldestLinkedEventId")
        return nil
    elseif eventId == oldestLinkedEventId then
        logger:Verbose("Event is oldestLinkedEventId")
        return oldestLinkedEventId
    end

    local newestLinkedEventId = self:GetNewestLinkedEventInfo()
    if not newestLinkedEventId then
        logger:Verbose("No newestLinkedEventId found")
        return nil
    elseif eventId > newestLinkedEventId then
        logger:Verbose("Event is newer than newestLinkedEventId")
        return newestLinkedEventId
    end

    local newestIndex, oldestIndex = self:GetLinkedRangeIndices()
    if not newestIndex or not oldestIndex then
        logger:Verbose("No linked range found")
        return nil
    end

    local eventId = self:SearchEventIdInInterval(eventId, newestIndex, oldestIndex)
    return eventId
end

function GuildHistoryCacheCategory:FindFirstAvailableEventIdForEventTime(eventTime)
    local oldestId, oldestTime = self:GetOldestLinkedEventInfo()
    if not oldestId then
        logger:Verbose("No oldestId found")
        return nil
    elseif eventTime <= oldestTime then
        logger:Verbose("Event is older than oldestTime")
        return oldestId
    end

    local newestId, newestTime = self:GetNewestLinkedEventInfo()
    if not newestId then
        logger:Verbose("No newestId found")
        return nil
    elseif eventTime > newestTime then
        logger:Verbose("Event is newer than newestTime")
        return newestId
    end

    local guildId, category = self.guildId, self.category
    local _, oldestIndex = self.adapter:GetGuildHistoryEventIndicesForTimeRange(
        guildId, category, newestTime, eventTime)
    if oldestIndex then
        logger:Verbose("Found oldestIndex", oldestIndex, GetGuildHistoryEventBasicInfo(guildId, category, oldestIndex))
        return GetGuildHistoryEventId(guildId, category, oldestIndex)
    end

    logger:Verbose("No oldestIndex found")
    return nil
end

function GuildHistoryCacheCategory:FindLastAvailableEventIdForEventTime(eventTime)
    local newestId, newestTime = self:GetNewestLinkedEventInfo()
    if not newestId then
        logger:Verbose("No newestId found")
        return nil
    elseif eventTime > newestTime then
        logger:Verbose("Event is newer than newestTime")
        return newestId
    end

    local oldestId, oldestTime = self:GetOldestLinkedEventInfo()
    if not oldestId then
        logger:Verbose("No oldestId found")
        return nil
    elseif eventTime <= oldestTime then
        logger:Verbose("Event is older than oldestTime")
        return oldestId
    end

    local guildId, category = self.guildId, self.category
    local newestIndex = self.adapter:GetGuildHistoryEventIndicesForTimeRange(
        guildId, category, eventTime, oldestTime)
    if newestIndex then
        logger:Verbose("Found newestIndex", newestIndex, GetGuildHistoryEventBasicInfo(guildId, category, newestIndex))
        return GetGuildHistoryEventId(guildId, category, newestIndex)
    end

    logger:Verbose("No newestIndex found")
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
        if self:HasLinked() and not self:IsProcessing() and not self:HasPendingRequest() then
            self.progress = 1
            self.missingTime = 0
        else
            local _, newestEventTime = self:GetNewestLinkedEventInfo()
            if newestEventTime then
                local now = GetTimeStamp()
                local events = self.categoryData:GetEventsInTimeRange(now, newestEventTime + 1) -- TODO optimize by getting the time directly
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

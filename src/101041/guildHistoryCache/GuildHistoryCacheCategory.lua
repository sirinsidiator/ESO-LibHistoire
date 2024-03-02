-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local MAX_NUMBER_OF_DAYS_CVAR_SUFFIX = {
    [GUILD_HISTORY_EVENT_CATEGORY_ACTIVITY] = "activity",
    [GUILD_HISTORY_EVENT_CATEGORY_AVA_ACTIVITY] = "ava_activity",
    [GUILD_HISTORY_EVENT_CATEGORY_BANKED_CURRENCY] = "banked_currency",
    [GUILD_HISTORY_EVENT_CATEGORY_BANKED_ITEM] = "banked_item",
    [GUILD_HISTORY_EVENT_CATEGORY_MILESTONE] = "milestone",
    [GUILD_HISTORY_EVENT_CATEGORY_ROSTER] = "roster",
    [GUILD_HISTORY_EVENT_CATEGORY_TRADER] = "trader"
}

local SECONDS_PER_DAY = 60 * 60 * 24
local DEFAULT_MAX_CACHE_TIMERANGE = 30 * SECONDS_PER_DAY
local MISSING_EVENT_COUNT_THRESHOLD = 2000
local MAX_SERVER_TIMERANGE_FOR_CATEGORY = {}
for eventCategory = GUILD_HISTORY_EVENT_CATEGORY_ITERATION_BEGIN, GUILD_HISTORY_EVENT_CATEGORY_ITERATION_END do
    MAX_SERVER_TIMERANGE_FOR_CATEGORY[eventCategory] = DEFAULT_MAX_CACHE_TIMERANGE
end
MAX_SERVER_TIMERANGE_FOR_CATEGORY[GUILD_HISTORY_EVENT_CATEGORY_MILESTONE] = 180 * SECONDS_PER_DAY
MAX_SERVER_TIMERANGE_FOR_CATEGORY[GUILD_HISTORY_EVENT_CATEGORY_ROSTER] = 180 * SECONDS_PER_DAY

local GuildHistoryCacheCategory = ZO_InitializingObject:Subclass()
internal.class.GuildHistoryCacheCategory = GuildHistoryCacheCategory

function GuildHistoryCacheCategory:Initialize(saveData, categoryData)
    self.categoryData = categoryData
    self.guildId = categoryData:GetGuildData():GetId()
    self.category = categoryData:GetEventCategory()
    self.key = string.format("%s/%d/%d", internal.WORLD_NAME, self.guildId, self.category)
    self.saveData = saveData[self.key] or {}
    saveData[self.key] = self.saveData
    self.performanceTracker = internal.class.PerformanceTracker:New()
    self.unprocessedEventsStartTime = self.saveData.newestLinkedEventTime
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
    if oldestIndex <= 0 then return end

    local oldestCachedEventId = GetGuildHistoryEventId(guildId, category, oldestIndex)
    if newestLinkedEventId < oldestCachedEventId then
        logger:Warn("Linked range is outside cached range for guild %d category %d", guildId, category)
        self:Reset()
    elseif oldestCachedEventId ~= oldestLinkedEventId then
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

function GuildHistoryCacheCategory:GetListenerNames()
    local names = {}
    local legacyCount = 0
    for listener in pairs(self.listeners) do
        if listener.GetAddonName then
            names[#names + 1] = listener:GetAddonName()
        else
            legacyCount = legacyCount + 1
        end
    end
    return names, legacyCount
end

function GuildHistoryCacheCategory:RequestMissingData()
    local guildId, category = self.guildId, self.category
    logger:Debug("Request missing data for guild %d category %d", guildId, category)
    if not self:IsWatching() then
        logger:Debug("Not actively watching")
        return
    end

    local request = self.request
    if request then
        logger:Debug("Request already exists")
        if not request:IsValid() or request:IsComplete() or self.initialRequest then
            logger:Warn("Request is invalid, complete or initial - destroy")
            self.initialRequest = false
            DestroyGuildHistoryRequest(request:GetRequestId())
            self.request = nil
        else
            logger:Debug("Request is still valid - reuse")
            request:RequestMoreEvents(true)
            return
        end
    end

    local _, requestOldestTime = self:GetNewestLinkedEventInfo()
    local oldestGaplessEvent = self.categoryData:GetOldestEventForUpToDateEventsWithoutGaps()
    if not requestOldestTime and not oldestGaplessEvent then
        self.initialRequest = true
        return self:SendRequest()
    elseif not requestOldestTime then
        self:OnCategoryUpdated()
        return
    end

    local requestNewestTime = oldestGaplessEvent and oldestGaplessEvent:GetEventTimestampS() or GetTimeStamp()
    local endTime = self:EstimateOptimalRequestRangeEndTime(requestOldestTime, requestNewestTime)
    if endTime then
        logger:Debug("Estimated optimal request range end time for guild %d category %d", guildId, category)
        requestNewestTime = endTime
    end

    self:SendRequest(requestNewestTime, requestOldestTime)
end

function GuildHistoryCacheCategory:SendRequest(newestTime, oldestTime)
    local guildId, category = self.guildId, self.category
    logger:Debug("Send data request for guild %d category %d", guildId, category)
    self.request = ZO_GuildHistoryRequest:New(guildId, category, newestTime, oldestTime)
    self.request:RequestMoreEvents(true)
end

function GuildHistoryCacheCategory:EstimateOptimalRequestRangeEndTime(requestOldestTime, requestNewestTime)
    local guildId, category = self.guildId, self.category
    logger:Debug("Estimate missing events for guild %d category %d", guildId, category)
    local newestLinkedEventId = self:GetNewestLinkedEventInfo()
    if not newestLinkedEventId then
        logger:Debug("No linked range stored for guild %d category %d", guildId, category)
        return
    end

    local rangeIndex = GetGuildHistoryEventRangeIndexForEventId(guildId, category, newestLinkedEventId)
    if not rangeIndex then
        logger:Warn("Could not find linked range for guild %d category %d", guildId, category)
        return
    end

    local oldestTime, newestTime = GetGuildHistoryEventRangeInfo(guildId, category, rangeIndex)
    local newestIndex, oldestIndex = GetGuildHistoryEventIndicesForTimeRange(guildId, category, oldestTime, newestTime)
    local numEvents = oldestIndex - newestIndex + 1
    local linkedRangeSeconds = newestTime - oldestTime
    local requestRangeSeconds = requestNewestTime - requestOldestTime
    local estimatedMissingEvents = numEvents * (requestRangeSeconds / linkedRangeSeconds)
    if estimatedMissingEvents > MISSING_EVENT_COUNT_THRESHOLD then
        return requestOldestTime + (linkedRangeSeconds / numEvents) * MISSING_EVENT_COUNT_THRESHOLD / 2
    end
end

function GuildHistoryCacheCategory:IsWatching()
    local mode = self:GetWatchMode()
    if mode == internal.WATCH_MODE_ON then
        return true
    elseif mode == internal.WATCH_MODE_OFF then
        return false
    else
        local lastListenerTime = self.saveData.lastListenerRegisteredTime or 0
        return GetTimeStamp() - lastListenerTime < 3 * SECONDS_PER_DAY
    end
end

function GuildHistoryCacheCategory:GetWatchMode()
    return self.saveData.watching or internal.WATCH_MODE_AUTO
end

function GuildHistoryCacheCategory:SetWatchMode(mode)
    logger:Info("Set watch mode for guild %d category %d to %s", self.guildId, self.category, mode)
    self.saveData.watching = mode
    internal.FireCallbacks(internal.callback.WATCH_MODE_CHANGED, self.guildId, self.category, mode)
end

function GuildHistoryCacheCategory:SetNewestLinkedEventInfo(eventId, eventTime)
    if eventId ~= 0 then
        self.saveData.newestLinkedEventId = eventId
        self.saveData.newestLinkedEventTime = eventTime
    else
        self.saveData.newestLinkedEventId = nil
        self.saveData.newestLinkedEventTime = nil
    end
end

function GuildHistoryCacheCategory:SetOldestLinkedEventInfo(eventId, eventTime)
    if eventId ~= 0 then
        self.saveData.oldestLinkedEventId = eventId
        self.saveData.oldestLinkedEventTime = eventTime
    else
        self.saveData.oldestLinkedEventId = nil
        self.saveData.oldestLinkedEventTime = nil
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
    internal:FireCallbacks(internal.callback.CATEGORY_DATA_UPDATED, self, flags)
    self:StopProcessingEvents()
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
    self:SetOldestLinkedEventInfo()
    self:SetNewestLinkedEventInfo()
    -- TODO inform listeners that a reset happened?
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
    logger:Info("Start processing events for guild %d category %d", self.guildId, self.category)

    local guildId, category = self.guildId, self.category
    logger:Debug("Find linked range for guild %d category %d", guildId, category)
    local rangeIndex = GetGuildHistoryEventRangeIndexForEventId(guildId, category, newestLinkedEventId)
    if not rangeIndex then
        logger:Warn("Could not find linked range for guild %d category %d", guildId, category)
        self:RequestMissingData()
        return
    end

    local oldestTime, newestTime, newestEventId, oldestEventId = GetGuildHistoryEventRangeInfo(guildId,
        category, rangeIndex)

    local categoryData = self.categoryData

    local unlinkedEvents, missedEvents = {}, {}

    if newestLinkedEventId < newestEventId then
        logger:Info("Found events newer than the linked range for guild %d category %d", guildId, category)
        local _, newestLinkedEventTime = self:GetNewestLinkedEventInfo()
        unlinkedEvents = categoryData:GetEventsInTimeRange(newestLinkedEventTime, newestTime)
    end

    if oldestLinkedEventId > oldestEventId then
        logger:Info("Found events older than the linked range for guild %d category %d", guildId, category)
        local _, oldestLinkedEventTime = self:GetOldestLinkedEventInfo()
        missedEvents = categoryData:GetEventsInTimeRange(oldestTime, oldestLinkedEventTime)
    end

    logger:Debug("Found %d unlinked events and %d missed events for guild %d category %d", #unlinkedEvents,
        #missedEvents, guildId, category)

    if #unlinkedEvents > 0 or #missedEvents > 0 then
        local task = internal:CreateAsyncTask()
        self.processingTask = task
        self:InitializePendingEventMetrics(#unlinkedEvents + #missedEvents)
        internal.FireCallbacks(internal.callback.PROCESSING_STARTED, guildId, category, #unlinkedEvents, #missedEvents)
        task:For(1, #unlinkedEvents):Do(function(i)
            self:IncrementPendingEventMetrics()
            local event = unlinkedEvents[i]
            if not self.processingStartTime then
                self.processingStartTime = event:GetEventTimestampS()
            end
            self.processingEndTime = event:GetEventTimestampS()

            local eventId = event:GetEventId()
            logger:Debug("Send unlinked event %d to listeners", eventId)
            internal:FireCallbacks(internal.callback.PROCESS_LINKED_EVENT, guildId, category, event)
            self:SetNewestLinkedEventInfo(eventId, event:GetEventTimestampS())
        end):Then(function()
            logger:Debug("Finished processing unlinked events for guild %d category %d", guildId, category)
            internal.FireCallbacks(internal.callback.PROCESSING_LINKED_EVENTS_FINISHED, guildId, category)
            self.processingStartTime = nil
            self.processingEndTime = nil
        end):For(#missedEvents, 1, -1):Do(function(i)
            self:IncrementPendingEventMetrics()
            local event = missedEvents[i]
            if not self.processingEndTime then
                self.processingEndTime = event:GetEventTimestampS()
            end
            self.processingStartTime = event:GetEventTimestampS()

            local eventId = event:GetEventId()
            logger:Debug("Send missed event %d to listeners", eventId)
            internal:FireCallbacks(internal.callback.PROCESS_MISSED_EVENT, guildId, category, event)
            self:SetOldestLinkedEventInfo(eventId, event:GetEventTimestampS())
        end):Then(function()
            self:ResetPendingEventMetrics()
            self.processingTask = nil
            self.processingStartTime = nil
            self.processingEndTime = nil
            logger:Debug("Finished processing missed events for guild %d category %d", guildId, category)
            internal.FireCallbacks(internal.callback.PROCESSING_FINISHED, guildId, category)
            self:ProcessNextRequest()
        end)
    end
end

function GuildHistoryCacheCategory:StopProcessingEvents()
    if self.processingTask then
        logger:Info("Stop processing events for guild %d category %d", self.guildId, self.category)
        self.processingTask:Cancel()
        self.processingTask = nil
        self.processingStartTime = nil
        self.processingEndTime = nil
        self:ResetPendingEventMetrics()
        internal.FireCallbacks(internal.callback.PROCESSING_STOPPED, self.guildId, self.category)
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
    if event then
        local newestLinkedEventId = self:GetNewestLinkedEventInfo()
        if newestLinkedEventId then
            return event:GetEventId() <= newestLinkedEventId
        end
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
    local events = self.categoryData:GetEventsInTimeRange(oldestEventTime, newestEventTime)
    return #events
end

function GuildHistoryCacheCategory:GetNumUnlinkedEvents()
    local _, newestEventTime = self:GetNewestLinkedEventInfo()
    if not newestEventTime then return 0 end
    local now = GetTimeStamp()
    local events = self.categoryData:GetEventsInTimeRange(newestEventTime + 1, now)
    return #events
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
    local days = GetCVar("GuildHistoryCacheMaxNumberOfDays_" .. MAX_NUMBER_OF_DAYS_CVAR_SUFFIX[self.category])
    local seconds = days and (tonumber(days) * SECONDS_PER_DAY) or DEFAULT_MAX_CACHE_TIMERANGE
    return internal.UI_LOAD_TIME - seconds
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

    local serverTimeLimit = GetTimeStamp() - MAX_SERVER_TIMERANGE_FOR_CATEGORY[self.category]
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
    if request and not self.initialRequest then
        return request.oldestTimeS, request.newestTimeS
    end
end

function GuildHistoryCacheCategory:GetProcessingTimeRange()
    return self.processingStartTime, self.processingEndTime
end

function GuildHistoryCacheCategory:GetNumRanges()
    return GetNumGuildHistoryEventRanges(self.guildId, self.category)
end

function GuildHistoryCacheCategory:GetRangeInfo(index)
    return GetGuildHistoryEventRangeInfo(self.guildId, self.category, index)
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
    local rangeIndex = GetGuildHistoryEventRangeIndexForEventId(guildId, category, oldestLinkedEventId)
    if not rangeIndex then return end

    local oldestTime, newestTime = GetGuildHistoryEventRangeInfo(guildId, category, rangeIndex)
    local newestIndex, oldestIndex = GetGuildHistoryEventIndicesForTimeRange(guildId, category, newestTime, oldestTime)
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
    local _, oldestIndex = GetGuildHistoryEventIndicesForTimeRange(guildId, category, newestTime, eventTime)
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
    local newestIndex = GetGuildHistoryEventIndicesForTimeRange(guildId, category, eventTime, oldestTime)
    if newestIndex then
        return GetGuildHistoryEventId(guildId, category, newestIndex)
    end

    return nil
end

function GuildHistoryCacheCategory:Clear()
    logger:Warn("Clearing cache for guild %d category %d", self.guildId, self.category)
    local result = ClearGuildHistoryCache(self.guildId, self.category)
    logger:Info("Cache clear result:", result)
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

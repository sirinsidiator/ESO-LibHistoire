-- SPDX-FileCopyrightText: 2025 sirinsidiator
--
-- SPDX-License-Identifier: Artistic-2.0

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local MISSING_EVENT_COUNT_THRESHOLD = 4000
local NO_PROCESSOR_THRESHOLD = 3 * 24 * 3600           -- 3 days
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
local PROCESSOR_PRIORITY_BONUS = 6

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
    self.unprocessedEventsStartTime = self.saveData.newestManagedEventTime
    self.rangeInfo = {}
    self.rangeInfoDirty = true
    self.progressDirty = true
    self.wasLinked = false
    self.processingQueue = {}
    self.processors = {}
    self:RefreshManagedRangeInfo()
end

function GuildHistoryCacheCategory:RefreshManagedRangeInfo()
    local oldestManagedEventId, oldestManagedEventTime = self:GetOldestManagedEventInfo()
    local newestManagedEventId, newestManagedEventTime = self:GetNewestManagedEventInfo()
    if not oldestManagedEventId or not newestManagedEventId then return end

    local guildId, category = self.guildId, self.category
    local oldestIndex = GetNumGuildHistoryEvents(guildId, category)
    if oldestIndex <= 0 then
        logger:Warn("No events cached for guild %d category %d", guildId, category)
        self:Reset()
        return
    end

    local oldestCachedEventId = GetGuildHistoryEventId(guildId, category, oldestIndex)
    if newestManagedEventId < oldestCachedEventId then
        logger:Warn("Managed range is outside cached range for guild %d category %d", guildId, category)
        self:Reset()
        return
    end

    if oldestCachedEventId ~= oldestManagedEventId then
        oldestManagedEventId, oldestManagedEventTime = GetGuildHistoryEventBasicInfo(guildId, category, oldestIndex)
        logger:Info("Data was removed from managed range for guild %d category %d", guildId, category)
        self:SetOldestManagedEventInfo(oldestManagedEventId, oldestManagedEventTime)
    end

    local oldestRangeIndex = self:FindRangeIndexForEventId(oldestCachedEventId)
    local newestRangeIndex = self:FindRangeIndexForEventId(newestManagedEventId)
    if not oldestRangeIndex or not newestRangeIndex or oldestRangeIndex ~= newestRangeIndex then
        logger:Warn("Could not find managed range for guild %d category %d", guildId, category)
        self:Reset()
        return
    end

    self:CheckHasLinked()
end

function GuildHistoryCacheCategory:RegisterProcessor(processor)
    self.saveData.lastProcessorRegisteredTime = GetTimeStamp()
    self.processors[processor] = true
end

function GuildHistoryCacheCategory:UnregisterProcessor(processor)
    self.processors[processor] = nil
end

function GuildHistoryCacheCategory:GetProcessorInfo()
    local names = {}
    local legacyCount = 0
    for processor in pairs(self.processors) do
        if processor.GetAddonName then
            names[#names + 1] = processor:GetAddonName()
        else
            legacyCount = legacyCount + 1
        end
    end
    return names, legacyCount, self.saveData.lastProcessorRegisteredTime
end

function GuildHistoryCacheCategory:GetRequestPriority()
    local priority = BASE_PRIORITY[self.category] or 0
    local processorBonus = PROCESSOR_PRIORITY_BONUS * NonContiguousCount(self.processors)
    return priority + processorBonus
end

function GuildHistoryCacheCategory:ShouldSendInitialRequest(oldestManagedEventId)
    local timeSinceLastInitialRequest = GetTimeStamp() - (self.saveData.initialRequestTime or 0)
    if not oldestManagedEventId and timeSinceLastInitialRequest < INITIAL_REQUEST_RESEND_THRESHOLD then
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
    if self:ContinueExistingRequest() or not self:IsAutoRequesting() then return end
    logger:Debug("Request missing data for", self.key)

    if self:IsManagedRangeConnectedToPresent() then
        logger:Debug("Already connected to present", self.key)
        self:OnCategoryUpdated()
        return
    end

    local oldestManagedEventId, oldestManagedEventTime = self:GetOldestManagedEventInfo()
    local newestManagedEventId, newestManagedEventTime = self:GetNewestManagedEventInfo()
    local oldestGaplessEventIndex = GetOldestGuildHistoryEventIndexForUpToDateEventsWithoutGaps(self.guild, self
        .category)
    if not oldestManagedEventId or not newestManagedEventId then
        if oldestGaplessEventIndex then
            self:OnCategoryUpdated()
        elseif self:ShouldSendInitialRequest(oldestManagedEventId) then
            self:QueueInitialRequest()
        end
        return
    end

    local oldestGaplessEventTime
    if oldestGaplessEventIndex then
        local oldestGaplessEventId
        oldestGaplessEventId, oldestGaplessEventTime = GetGuildHistoryEventBasicInfo(self.guild, self.category,
            oldestGaplessEventIndex)
        logger:Verbose("oldestGaplessEventId", oldestGaplessEventId, "oldestManagedEventId", oldestManagedEventId)
        if oldestManagedEventId == oldestGaplessEventId then
            logger:Debug("No missing data for", self.key)
            self:OnCategoryUpdated()
            return
        end
    else
        logger:Verbose("no oldestGaplessEventIndex")
    end

    local requestNewestTime, requestOldestTime = self:OptimizeRequestTimeRange(oldestManagedEventTime,
        newestManagedEventTime, oldestGaplessEventTime)
    if requestOldestTime then
        self.requestManager:QueueRequest(self:CreateRequest(requestNewestTime, requestOldestTime))
    end
end

function GuildHistoryCacheCategory:QueueInitialRequest()
    if self.request then
        self:DestroyRequest()
    end
    self.requestManager:QueueRequest(self:CreateRequest())
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

function GuildHistoryCacheCategory:OptimizeRequestTimeRange(oldestManagedEventTime, newestManagedEventTime,
                                                            oldestGaplessEventTime)
    if oldestGaplessEventTime and oldestGaplessEventTime <= newestManagedEventTime then
        logger:Warn("Time range optimization failed - Invalid time range")
        return nil, nil
    end

    local requestOldestTime = newestManagedEventTime - 1
    local requestNewestTime = nil
    if oldestGaplessEventTime then
        requestNewestTime = oldestGaplessEventTime + 1
        logger:Verbose("Has gapless event time")
    end
    local guildId, category = self.guildId, self.category
    logger:Debug("Optimize request time range for", self.key)

    local newestIndex, oldestIndex = self.adapter:GetGuildHistoryEventIndicesForTimeRange(guildId, category,
        newestManagedEventTime, oldestManagedEventTime)
    if not newestIndex or not oldestIndex then
        logger:Warn("Time range optimization failed - could not find events in managed range")
        return requestNewestTime, requestOldestTime
    end

    local numEvents = oldestIndex - newestIndex + 1
    local managedRangeSeconds = newestManagedEventTime - oldestManagedEventTime
    local requestRangeSeconds = (requestNewestTime or GetTimeStamp()) - requestOldestTime

    local estimatedMissingEvents = numEvents * requestRangeSeconds / managedRangeSeconds
    logger:Verbose("estimatedMissingEvents", estimatedMissingEvents, numEvents, requestRangeSeconds, managedRangeSeconds)
    if estimatedMissingEvents > MISSING_EVENT_COUNT_THRESHOLD then
        logger:Debug("Limit request time range")
        local optimizedRequestNewestTime = newestManagedEventTime +
            (managedRangeSeconds / numEvents) * MISSING_EVENT_COUNT_THRESHOLD / 2
        if optimizedRequestNewestTime > requestOldestTime then
            requestNewestTime = optimizedRequestNewestTime
        else
            logger:Warn("Time range optimization failed - request range is invalid")
        end
    end

    logger:Verbose("Optimized request time range", requestNewestTime, requestOldestTime)
    return requestNewestTime, requestOldestTime
end

function GuildHistoryCacheCategory:IsAutoRequesting()
    local mode = self:GetRequestMode()
    if mode == internal.REQUEST_MODE_ON then
        return true
    elseif mode == internal.REQUEST_MODE_OFF then
        return false
    else
        local lastProcessorTime = self.saveData.lastProcessorRegisteredTime or 0
        return GetTimeStamp() - lastProcessorTime < NO_PROCESSOR_THRESHOLD
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

function GuildHistoryCacheCategory:SetNewestManagedEventInfo(eventId, eventTime)
    if eventId ~= 0 then
        self.saveData.newestManagedEventId = eventId
        self.saveData.newestManagedEventTime = eventTime
    else
        self.saveData.newestManagedEventId = nil
        self.saveData.newestManagedEventTime = nil
    end
    self.progressDirty = true
end

function GuildHistoryCacheCategory:SetOldestManagedEventInfo(eventId, eventTime)
    if eventId ~= 0 then
        self.saveData.oldestManagedEventId = eventId
        self.saveData.oldestManagedEventTime = eventTime
    else
        self.saveData.oldestManagedEventId = nil
        self.saveData.oldestManagedEventTime = nil
        internal:FireCallbacks(internal.callback.MANAGED_RANGE_LOST, self.guildId, self.category)
    end
end

function GuildHistoryCacheCategory:GetNewestManagedEventInfo()
    local eventId = self.saveData.newestManagedEventId
    local eventTime = self.saveData.newestManagedEventTime
    if eventId ~= 0 then
        return eventId, eventTime
    end
end

function GuildHistoryCacheCategory:GetOldestManagedEventInfo()
    local eventId = self.saveData.oldestManagedEventId
    local eventTime = self.saveData.oldestManagedEventTime
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
    local isNewManagedRange = false
    local guildId, category = self.guildId, self.category
    local oldestManagedEventId = self:GetOldestManagedEventInfo()
    local newestManagedEventId = self:GetNewestManagedEventInfo()

    if not oldestManagedEventId or not newestManagedEventId then
        if oldestManagedEventId ~= newestManagedEventId then
            logger:Warn("Invalid save data state for guild %d category %d", guildId, category)
            self:Reset()
        else
            logger:Info("No managed range stored for guild %d category %d", guildId, category)
        end

        local index = GetOldestGuildHistoryEventIndexForUpToDateEventsWithoutGaps(guildId, category)
        if index then
            local eventId = GetGuildHistoryEventId(guildId, category, index)
            newestManagedEventId = eventId
            oldestManagedEventId = eventId
            isNewManagedRange = true
        else
            logger:Warn("Could not find any unlinked events for", self.key)
        end
    end

    self:ProcessNextRequest()
    if newestManagedEventId and oldestManagedEventId then
        self:StartProcessingEvents(newestManagedEventId, oldestManagedEventId, isNewManagedRange)
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

    self.saveData.initialRequestTime = nil
    self.saveData.lastLinkedTime = nil

    self.rangeInfoDirty = true
    self.progressDirty = true
    self.wasLinked = false

    self:SetNewestManagedEventInfo()
    self:SetOldestManagedEventInfo()

    for processor in pairs(self.processors) do
        processor:StopInternal(internal.STOP_REASON_MANAGED_RANGE_LOST)
    end

    zo_callLater(function() self:OnCategoryUpdated() end, 0)
end

function GuildHistoryCacheCategory:QueueProcessingRequest(request)
    self.processingQueue[#self.processingQueue + 1] = request
    zo_callLater(function() self:ProcessNextRequest() end, 0)
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
        self.processingRequest = request
        request:StartProcessing()
    end
end

function GuildHistoryCacheCategory:StartProcessingEvents(newestManagedEventId, oldestManagedEventId, isNewManagedRange)
    if self:IsProcessing() or not self:IsAutoRequesting() then return end

    local guildId, category = self.guildId, self.category
    logger:Info("Start processing events for guild %d category %d", guildId, category)
    local rangeIndex = self:FindRangeIndexForEventId(newestManagedEventId)
    if not rangeIndex or not oldestManagedEventId then
        logger:Warn("Could not find managed range for guild %d category %d", guildId, category)
        self:RequestMissingData()
        return
    end

    local newestTime, oldestTime, newestEventId, oldestEventId = self:GetRangeInfo(rangeIndex)
    local unlinkedEvents, missedEvents = {}, {}
    local categoryData = self.categoryData

    if isNewManagedRange or newestManagedEventId < newestEventId then
        local _, newestManagedEventTime
        if isNewManagedRange then
            local index = GetGuildHistoryEventIndex(guildId, category, newestManagedEventId)
            newestManagedEventTime = GetGuildHistoryEventTimestamp(guildId, category, index)
        else
            _, newestManagedEventTime = self:GetNewestManagedEventInfo()
        end
        logger:Debug("Found events newer than the managed range", self.key)
        unlinkedEvents = categoryData:GetEventsInTimeRange(newestTime, newestManagedEventTime)
    end

    if oldestManagedEventId > oldestEventId then
        local _, oldestManagedEventTime = self:GetOldestManagedEventInfo()
        logger:Debug("Found events older than the managed range", self.key)
        missedEvents = categoryData:GetEventsInTimeRange(oldestManagedEventTime, oldestTime)
    end

    local numUnlinkedEvents = #unlinkedEvents
    local numMissedEvents = #missedEvents
    logger:Info("Found %d unlinked events and %d missed events for %s", numUnlinkedEvents, numMissedEvents, self.key)

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

        local previousTime = 0
        local shouldSetOldestEventInfo = isNewManagedRange
        task:For(numUnlinkedEvents, 1, -1):Do(function(i)
            self.progressDirty = true
            self:IncrementPendingEventMetrics()
            local event = unlinkedEvents[i]
            local eventId = event:GetEventId()
            if (isNewManagedRange and eventId < newestManagedEventId) or (not isNewManagedRange and eventId <= newestManagedEventId) then
                logger:Debug("skip already processed event", guildId, category, eventId, newestManagedEventId)
            else
                local eventTime = event:GetEventTimestampS()
                assert(eventTime >= oldestTime and eventTime >= previousTime, "Received event with invalid timestamp")
                if shouldSetOldestEventInfo then
                    self:SetOldestManagedEventInfo(eventId, eventTime)
                    shouldSetOldestEventInfo = false
                end
                self:SetNewestManagedEventInfo(eventId, eventTime)
                internal:FireCallbacks(internal.callback.PROCESS_LINKED_EVENT, guildId, category, event)
                self.processingCurrentTime = eventTime
                previousTime = eventTime
            end
        end):Then(function()
            self.progressDirty = true
            logger:Debug("Finished processing unlinked events", guildId, category)
            if isNewManagedRange then
                internal:FireCallbacks(internal.callback.MANAGED_RANGE_FOUND, guildId, category)
            end
            self:CheckHasLinked()
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
            previousTime = newestTime
        end):For(1, numMissedEvents):Do(function(i)
            self.progressDirty = true
            self:IncrementPendingEventMetrics()
            local event = missedEvents[i]
            local eventId = event:GetEventId()
            if eventId >= oldestManagedEventId then
                logger:Debug("skip already processed event")
            else
                local eventTime = event:GetEventTimestampS()
                assert(eventTime >= oldestTime and eventTime <= previousTime, "Received event with invalid timestamp")
                self:SetOldestManagedEventInfo(eventId, eventTime)
                internal:FireCallbacks(internal.callback.PROCESS_MISSED_EVENT, guildId, category, event)
                self.processingCurrentTime = -eventTime
                previousTime = eventTime
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
    else
        self:CheckHasLinked()
    end
end

function GuildHistoryCacheCategory:RestartProcessingTask()
    if self.processingTask then
        logger:Info("Restart processing events for guild %d category %d", self.guildId, self.category)
        self.processingTask:Cancel()
        self.processingTask = nil
        local newestManagedEventId = self:GetNewestManagedEventInfo()
        local oldestManagedEventId = self:GetOldestManagedEventInfo()
        self:StartProcessingEvents(newestManagedEventId, oldestManagedEventId)
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
    local guildId, category = self.guildId, self.category
    local gaplessIndex = GetOldestGuildHistoryEventIndexForUpToDateEventsWithoutGaps(guildId, category)
    if not gaplessIndex then
        return GetNumGuildHistoryEvents(guildId, category) == 0
    end

    local newestManagedEventId = self:GetNewestManagedEventInfo()
    if newestManagedEventId then
        local index = GetGuildHistoryEventIndex(guildId, category, newestManagedEventId)
        return index == 1
    end

    return false
end

function GuildHistoryCacheCategory:CheckHasLinked()
    if self:HasLinked() then
        logger:Debug("Category is linked", self.key)
        self.saveData.lastLinkedTime = GetTimeStamp()
        if not self.wasLinked then
            self.wasLinked = true
            internal:FireCallbacks(internal.callback.CATEGORY_LINKED, self.guildId, self.category)
        end
    end
end

function GuildHistoryCacheCategory:GetLastLinkedTime()
    return self.saveData.lastLinkedTime or 0
end

function GuildHistoryCacheCategory:IsManagedRangeConnectedToPresent()
    local guildId, category = self.guildId, self.category
    local gaplessIndex = GetOldestGuildHistoryEventIndexForUpToDateEventsWithoutGaps(guildId, category)
    local newestManagedEventId = self:GetNewestManagedEventInfo()
    if gaplessIndex and newestManagedEventId then
        local index = GetGuildHistoryEventIndex(guildId, category, newestManagedEventId)
        return index and index <= gaplessIndex
    end
    return false
end

function GuildHistoryCacheCategory:IsFor(guildId, category)
    return self.guildId == guildId and self.category == category
end

function GuildHistoryCacheCategory:IsProcessing()
    return self.processingTask ~= nil or self.processingRequest ~= nil
end

function GuildHistoryCacheCategory:GetNumLoadedManagedEvents()
    local _, oldestEventTime = self:GetOldestManagedEventInfo()
    local _, newestEventTime = self:GetNewestManagedEventInfo()
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
    local newestManagedEventId = self:GetNewestManagedEventInfo()
    if not newestManagedEventId then return end
    local index = GetGuildHistoryEventIndex(self.guildId, self.category, newestManagedEventId)
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
        return request:GetOldestTime(), request:GetNewestTime()
    end
end

function GuildHistoryCacheCategory:GetProcessingTimeRange()
    return self.processingStartTime, self.processingEndTime, self.processingCurrentTime
end

local function FindAndFilterNextOverlappingRange(ranges, guildId, category)
    for indexA = 1, #ranges do
        local _, _, newestIdA, oldestIdA = unpack(ranges[indexA])
        for indexB = indexA + 1, #ranges do
            local _, _, newestIdB, oldestIdB = unpack(ranges[indexB])
            if not (newestIdA < oldestIdB or oldestIdA > newestIdB) then
                logger:Warn("Found overlapping ranges in guild %d category %d", guildId, category)
                if newestIdA > newestIdB then
                    table.remove(ranges, indexB)
                else
                    table.remove(ranges, indexA)
                end
                return true
            end
        end
    end
    return false
end

function GuildHistoryCacheCategory:UpdateRangeInfo()
    if self.rangeInfoDirty then
        self.rangeInfoDirty = false

        local guildId, category = self.guildId, self.category
        local ranges = {}
        local previousNewestTimeS = GetTimeStamp() + 100
        for i = 1, GetNumGuildHistoryEventRanges(guildId, category) do
            local newestTimeS, oldestTimeS = GetGuildHistoryEventRangeInfo(guildId, category, i)
            -- verify that each range is older than the previous one
            if newestTimeS > previousNewestTimeS then
                logger:Warn("Out of order range detected for guild %d category %d", guildId, category)
            end
            previousNewestTimeS = newestTimeS

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

        -- sometimes the game fails to remove ranges after merging, so we remove overlapping ones to avoid issues when detecting the linked state
        while FindAndFilterNextOverlappingRange(ranges, guildId, category) do end

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
    if not eventId then return end
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
    local oldestManagedEventId = self:GetOldestManagedEventInfo()
    if not oldestManagedEventId then
        logger:Verbose("No oldestManagedEventId found")
        return nil
    elseif eventId <= oldestManagedEventId then
        logger:Verbose("Event is older than oldestManagedEventId")
        return oldestManagedEventId
    end

    local newestManagedEventId = self:GetNewestManagedEventInfo()
    if not newestManagedEventId or eventId > newestManagedEventId then
        logger:Verbose("No newestManagedEventId found or event is newer than newestManagedEventId")
        return nil
    elseif eventId == newestManagedEventId then
        logger:Verbose("Event is newestManagedEventId")
        return newestManagedEventId
    end

    local newestIndex, oldestIndex = self:GetManagedRangeIndices()
    if not newestIndex or not oldestIndex then
        logger:Verbose("No managed range found")
        return nil
    end

    local eventId = self:SearchEventIdInInterval(eventId, newestIndex, oldestIndex)
    return eventId
end

function GuildHistoryCacheCategory:GetManagedRangeIndices()
    local oldestManagedEventId = self:GetOldestManagedEventInfo()
    if not oldestManagedEventId then
        logger:Verbose("No oldestManagedEventId found")
        return
    end

    local guildId, category = self.guildId, self.category
    local rangeIndex = self:FindRangeIndexForEventId(oldestManagedEventId)
    if not rangeIndex then
        logger:Verbose("No rangeIndex found for oldestManagedEventId", oldestManagedEventId)
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
    local oldestManagedEventId = self:GetOldestManagedEventInfo()
    if not oldestManagedEventId or eventId < oldestManagedEventId then
        logger:Verbose("No oldestManagedEventId found or event is older than oldestManagedEventId")
        return nil
    elseif eventId == oldestManagedEventId then
        logger:Verbose("Event is oldestManagedEventId")
        return oldestManagedEventId
    end

    local newestManagedEventId = self:GetNewestManagedEventInfo()
    if not newestManagedEventId then
        logger:Verbose("No newestManagedEventId found")
        return nil
    elseif eventId > newestManagedEventId then
        logger:Verbose("Event is newer than newestManagedEventId")
        return newestManagedEventId
    end

    local newestIndex, oldestIndex = self:GetManagedRangeIndices()
    if not newestIndex or not oldestIndex then
        logger:Verbose("No managed range found")
        return nil
    end

    local eventId = self:SearchEventIdInInterval(eventId, newestIndex, oldestIndex)
    return eventId
end

function GuildHistoryCacheCategory:FindFirstAvailableEventIdForEventTime(eventTime)
    local oldestId, oldestTime = self:GetOldestManagedEventInfo()
    if not oldestId then
        logger:Verbose("No oldestId found")
        return nil
    elseif eventTime <= oldestTime then
        logger:Verbose("Event is older than oldestTime")
        return oldestId
    end

    local newestId, newestTime = self:GetNewestManagedEventInfo()
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
    local newestId, newestTime = self:GetNewestManagedEventInfo()
    if not newestId then
        logger:Verbose("No newestId found")
        return nil
    elseif eventTime > newestTime then
        logger:Verbose("Event is newer than newestTime")
        return newestId
    end

    local oldestId, oldestTime = self:GetOldestManagedEventInfo()
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
            local _, newestEventTime = self:GetNewestManagedEventInfo()
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

function GuildHistoryCacheCategory:GetDebugInfo()
    local guildId, category = self.guildId, self.category
    local debugInfo = {}
    debugInfo.key = self.key

    debugInfo.saveData = self.saveData
    debugInfo.requestMode = self:GetRequestMode()
    debugInfo.isAutoRequesting = self:IsAutoRequesting()
    debugInfo.hasLinked = self:HasLinked()
    debugInfo.isManagedRangeConnectedToPresent = self:IsManagedRangeConnectedToPresent()
    debugInfo.isProcessing = self:IsProcessing()
    debugInfo.unprocessedEventsStartTime = self:GetUnprocessedEventsStartTime()
    debugInfo.numCachedEvents = self.categoryData:GetNumEvents()
    debugInfo.numLoadedManagedEvents = self:GetNumLoadedManagedEvents()
    debugInfo.numUnlinkedEvents = self:GetNumUnlinkedEvents()

    local oldestManagedEventId, oldestManagedEventTime = self:GetOldestManagedEventInfo()
    local oldestManagedEventIndex = GetGuildHistoryEventIndex(guildId, category, oldestManagedEventId)
    debugInfo.oldestManagedEvent = {
        id = oldestManagedEventId,
        time = oldestManagedEventTime,
        index = oldestManagedEventIndex
    }

    local newestManagedEventId, newestManagedEventTime = self:GetNewestManagedEventInfo()
    local newestManagedEventIndex = GetGuildHistoryEventIndex(guildId, category, newestManagedEventId)
    debugInfo.newestManagedEvent = {
        id = newestManagedEventId,
        time = newestManagedEventTime,
        index = newestManagedEventIndex
    }

    local oldestGaplessEventIndex = GetOldestGuildHistoryEventIndexForUpToDateEventsWithoutGaps(guildId, category)
    if oldestGaplessEventIndex then
        local oldestGaplessEventTime, oldestGaplessEventId = GetGuildHistoryEventBasicInfo(guildId, category,
            oldestGaplessEventIndex)
        debugInfo.oldestGaplessEvent = {
            id = oldestGaplessEventId,
            time = oldestGaplessEventTime,
            index = oldestGaplessEventIndex
        }
    else
        debugInfo.oldestGaplessEvent = false
    end

    debugInfo.numRanges = self:GetNumRanges()
    debugInfo.ranges = {}
    for i = 1, debugInfo.numRanges do
        local newestTime, oldestTime, newestEventId, oldestEventId = self:GetRangeInfo(i)
        local newestIndex = GetGuildHistoryEventIndex(guildId, category, newestEventId)
        local oldestIndex = GetGuildHistoryEventIndex(guildId, category, oldestEventId)
        debugInfo.ranges[i] = {
            numEvents = oldestIndex - newestIndex + 1,
            oldestEvent = {
                id = oldestEventId,
                time = oldestTime,
                index = oldestIndex
            },
            newestEvent = {
                id = newestEventId,
                time = newestTime,
                index = newestIndex
            }
        }
    end

    debugInfo.numRawRanges = GetNumGuildHistoryEventRanges(guildId, category)
    debugInfo.rawRanges = {}
    for i = 1, debugInfo.numRawRanges do
        local newestTime, oldestTime, newestEventId, oldestEventId = GetGuildHistoryEventRangeInfo(guildId, category, i)
        local newestIndex = GetGuildHistoryEventIndex(guildId, category, newestEventId)
        local oldestIndex = GetGuildHistoryEventIndex(guildId, category, oldestEventId)

        debugInfo.rawRanges[i] = {
            numEvents = oldestIndex and newestIndex and oldestIndex - newestIndex + 1 or -1,
            oldestEvent = {
                id = oldestEventId,
                time = oldestTime,
                index = oldestIndex
            },
            newestEvent = {
                id = newestEventId,
                time = newestTime,
                index = newestIndex
            }
        }
    end

    if self.request then
        debugInfo.request = self.request:GetDebugInfo()
    end

    local processingStartTime, processingEndTime, processingCurrentTime = self:GetProcessingTimeRange()
    debugInfo.processing = {
        isProcessing = self:IsProcessing(),
        startTime = processingStartTime,
        currentTime = processingCurrentTime,
        endTime = processingEndTime,
        -- task = self.processingTask and self.processingTask:GetDebugInfo() TODO comes from LibAsync, so no GetDebugInfo function -> any info we want to add?
    }

    debugInfo.processingQueue = {}
    for i = 1, #self.processingQueue do
        debugInfo.processingQueue[i] = self.processingQueue[i]:GetDebugInfo()
    end

    return debugInfo
end

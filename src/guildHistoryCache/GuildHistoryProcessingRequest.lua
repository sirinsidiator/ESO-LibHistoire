-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local GuildHistoryProcessingRequest = ZO_InitializingObject:Subclass()
internal.class.GuildHistoryProcessingRequest = GuildHistoryProcessingRequest

function GuildHistoryProcessingRequest:Initialize(processor, onEvent, onCompleted)
    self.processor = processor
    self.onEvent = onEvent
    self.onCompleted = onCompleted
    self.performanceTracker = internal.class.PerformanceTracker:New()
end

function GuildHistoryProcessingRequest:StartProcessing(endId)
    logger:Debug("start processing", self.processor:GetKey())
    assert(self.processor:IsRunning(),
        string.format("Processor %s should be running (%s)", self.processor:GetKey(), self.processor.addonName or "-"))
    self:StopProcessing()

    local hasProcessedEvents = false
    local processor = self.processor
    local startId = processor.currentEventId
    if not startId then
        logger:Debug("no startId - find one")
        startId = self:FindStartId()
    end

    if not startId then
        logger:Debug("still no startId - are we done?")
        self:EnsureIterationIsComplete(hasProcessedEvents)
        return
    end

    endId = endId or self:FindEndId()

    if not endId or startId > endId then
        logger:Debug("startId is greater than endId - are we done?")
        self:EnsureIterationIsComplete(hasProcessedEvents)
        return
    end

    local startIndex, endIndex = processor.categoryCache:GetIndexRangeForEventIdRange(startId, endId)
    self.currentIndex = startIndex
    self.endIndex = endIndex
    self.performanceTracker:Reset()
    self.task = internal:CreateAsyncTask()
    logger:Debug("run processing task", startIndex, endIndex)
    self.task:For(startIndex, endIndex, -1):Do(function(i)
        self.currentIndex = i
        self.performanceTracker:Increment()
        local event = processor.categoryCache:GetEvent(i)
        local eventId = event:GetEventId()
        if eventId < startId or eventId > endId then
            logger:Debug("event out of range", eventId, startId, endId)
            return
        end
        self.onEvent(processor, event)
        hasProcessedEvents = true
    end):Then(function()
        logger:Debug("processing complete", processor:GetKey(), self.currentIndex, startIndex, endIndex)
        self.task = nil
        self:EnsureIterationIsComplete(hasProcessedEvents)
    end)
end

function GuildHistoryProcessingRequest:StopProcessing()
    if self.task then
        logger:Debug("stop processing")
        self.performanceTracker:Reset()
        self.task:Cancel()
        self.task = nil
        self.currentIndex = nil
        self.endIndex = nil
    end
end

function GuildHistoryProcessingRequest:FindStartId()
    local startId
    local processor = self.processor
    if processor.afterEventId then
        startId = processor.categoryCache:FindFirstAvailableEventIdForEventId(processor.afterEventId)
        logger:Debug("afterEventId", processor.afterEventId, startId)
    elseif processor.afterEventTime then
        startId = processor.categoryCache:FindFirstAvailableEventIdForEventTime(processor.afterEventTime)
        logger:Debug("afterEventTime", processor.afterEventTime, startId)
    end
    if not startId then
        startId = processor.categoryCache:GetOldestManagedEventInfo()
        logger:Debug("no startId - use oldest", startId)
    end
    return startId
end

function GuildHistoryProcessingRequest:FindEndId()
    local endId
    local processor = self.processor
    if processor.beforeEventId then
        endId = processor.categoryCache:FindLastAvailableEventIdForEventId(processor.beforeEventId)
        logger:Debug("beforeEventId", processor.beforeEventId, endId)
    elseif processor.beforeEventTime then
        endId = processor.categoryCache:FindLastAvailableEventIdForEventTime(processor.beforeEventTime)
        logger:Debug("beforeEventTime", processor.beforeEventTime, endId)
    end
    if not endId then
        endId = processor.categoryCache:GetNewestManagedEventInfo()
        logger:Debug("no endId - use newest", endId)
    end
    return endId
end

function GuildHistoryProcessingRequest:EnsureIterationIsComplete(hasProcessedEvents)
    local endId = self:FindEndId()
    local processor = self.processor
    if not processor.currentEventId or processor.currentEventId == endId then
        logger:Debug("iterated all stored events - register for callback")
        self.onCompleted(processor)
    elseif hasProcessedEvents then
        logger:Debug("has not reached the end yet - go for another round")
        self:StartProcessing(endId)
    else
        error("no events processed and not at the end - something went wrong")
    end
end

function GuildHistoryProcessingRequest:GetPendingEventMetrics()
    if not self.task then return 0, -1, -1 end
    local count = self.currentIndex - self.endIndex
    local speed, timeLeft = self.performanceTracker:GetProcessingSpeedAndEstimatedTimeLeft(count)
    return count, speed, timeLeft
end

function GuildHistoryProcessingRequest:GetDebugInfo()
    local debugInfo = {
        pendingEventMetrics = { self:GetPendingEventMetrics() },
        hasAsyncTask = self.task ~= nil,
    }

    local currentIndex = self.currentIndex
    if currentIndex then
        local currentEventTime, currentEventId = self.processor.categoryCache:GetEventInfo(currentIndex)
        debugInfo.currentEvent = {
            id = currentEventId,
            time = currentEventTime,
            index = currentIndex,
        }
    end

    local endIndex = self.endIndex
    if endIndex then
        local endEventTime, endEventId = self.processor.categoryCache:GetEventInfo(endIndex)
        debugInfo.endEvent = {
            id = endEventId,
            time = endEventTime,
            index = endIndex,
        }
    end

    return debugInfo
end

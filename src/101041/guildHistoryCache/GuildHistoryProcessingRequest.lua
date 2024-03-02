-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local GuildHistoryProcessingRequest = ZO_InitializingObject:Subclass()
internal.class.GuildHistoryProcessingRequest = GuildHistoryProcessingRequest

function GuildHistoryProcessingRequest:Initialize(listener, onEvent, onCompleted)
    self.listener = listener
    self.onEvent = onEvent
    self.onCompleted = onCompleted
    self.performanceTracker = internal.class.PerformanceTracker:New()
end

function GuildHistoryProcessingRequest:StartProcessing(endId)
    logger:Debug("start processing")
    self:StopProcessing()

    local listener = self.listener
    local startId = listener.currentEventId
    if not startId then
        logger:Verbose("no startId - find one")
        startId = self:FindStartId()
    end

    if not startId then
        logger:Verbose("still no startId - are we done?")
        self:EnsureIterationIsComplete()
        return
    end
    listener.currentEventId = startId

    endId = endId or self:FindEndId()
    assert(endId and startId <= endId,
        "Invalid event range for " ..
        (listener.GetAddonName and listener:GetAddonName() or "legacy listener") .. " (" .. listener:GetKey() .. ")")

    local startIndex, endIndex = listener.categoryCache:GetIndexRangeForEventIdRange(startId, endId)
    self.currentIndex = startIndex
    self.endIndex = endIndex
    self.performanceTracker:Reset()
    self.task = internal:CreateAsyncTask()
    logger:Debug("run processing task", endIndex, startIndex)
    self.task:For(startIndex, endIndex, -1):Do(function(i)
        self.currentIndex = i
        self.performanceTracker:Increment()
        local event = listener.categoryCache:GetEvent(i)
        local eventId = event:GetEventId()
        if eventId < startId or eventId > endId then
            logger:Verbose("event out of range", eventId, startId, endId)
            return
        end
        self.onEvent(listener, event)
    end):Then(function()
        self.task = nil
        self:EnsureIterationIsComplete()
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
    local listener = self.listener
    if listener.afterEventId then
        startId = listener.categoryCache:FindFirstAvailableEventIdForEventId(listener.afterEventId + 1)
        logger:Verbose("afterEventId", listener.afterEventId, startId)
    elseif listener.afterEventTime then
        startId = listener.categoryCache:FindFirstAvailableEventIdForEventTime(listener.afterEventTime + 1)
        logger:Verbose("afterEventTime", listener.afterEventTime, startId)
    end
    if not startId then
        startId = listener.categoryCache:GetOldestLinkedEventInfo()
        logger:Verbose("no currentEventId - use oldest", startId)
    end
    return startId
end

function GuildHistoryProcessingRequest:FindEndId()
    local endId
    local listener = self.listener
    if listener.beforeEventId then
        endId = listener.categoryCache:FindLastAvailableEventIdForEventId(listener.beforeEventId - 1)
    elseif listener.beforeEventTime then
        endId = listener.categoryCache:FindLastAvailableEventIdForEventTime(listener.beforeEventTime - 1)
    end
    if not endId then
        endId = listener.categoryCache:GetNewestLinkedEventInfo()
        logger:Verbose("no endId - use newest", endId)
    end
    return endId
end

function GuildHistoryProcessingRequest:EnsureIterationIsComplete()
    local endId = self:FindEndId()
    local listener = self.listener
    if listener.currentEventId == endId then
        logger:Verbose("iterated all stored events - register for callback")
        self.onCompleted(listener)
    else
        logger:Verbose("has not reached the end yet - go for another round")
        self:StartProcessing(endId)
    end
end

function GuildHistoryProcessingRequest:GetPendingEventMetrics()
    if not self.task then return 0, -1, -1 end
    local count = self.endIndex - self.currentIndex
    local speed, timeLeft = self.performanceTracker:GetProcessingSpeedAndEstimatedTimeLeft(count)
    return count, speed, timeLeft
end

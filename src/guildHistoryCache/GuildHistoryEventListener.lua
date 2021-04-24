-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local GuildHistoryEventListener = ZO_Object:Subclass()
internal.class.GuildHistoryEventListener = GuildHistoryEventListener

local function ShouldHandleEvent(listener, event)
    if listener.afterEventId and event:GetEventId() <= listener.afterEventId then
        return false
    elseif listener.afterEventTime and event:GetEventTime() <= listener.afterEventTime then
        return false
    end
    return true
end

local function HasIterationCompleted(listener, event)
    if listener.beforeEventId and event:GetEventId() > listener.beforeEventId then
        return true
    elseif listener.beforeEventTime and event:GetEventTime() > listener.beforeEventTime then
        return true
    end
    return false
end

local function HandleEvent(listener, event, index)
    listener:InternalCountEvent(index)
    if not ShouldHandleEvent(listener, event) then return end
    if HasIterationCompleted(listener, event) then
        listener:Stop()
        if listener.iterationCompletedCallback then listener.iterationCompletedCallback() end
        return
    end

    local eventId = event:GetEventId()
    if listener.missedEventCallback and eventId < listener.lastEventId then
        listener.missedEventCallback(event:Unpack())
    elseif listener.nextEventCallback and eventId > listener.lastEventId then
        listener.nextEventCallback(event:Unpack())
        listener.lastEventId = eventId
    end
end

function GuildHistoryEventListener:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function GuildHistoryEventListener:Initialize(categoryCache)
    self.categoryCache = categoryCache
    self.task = internal:CreateAsyncTask()
    self.running = false
    self.lastEventId = 0
    self.afterEventId = nil
    self.afterEventTime = nil
    self.beforeEventId = nil
    self.beforeEventTime = nil
    self.nextEventCallback = nil
    self.missedEventCallback = nil
    self.iterationCompletedCallback = nil

    self.currentIndex = 0
    self.performanceTracker = internal.class.PerformanceTracker:New()

    self.nextEventProcessor = function(guildId, category, event, index)
        if not categoryCache:IsFor(guildId, category) then return end
        HandleEvent(self, event, index)
    end
end

function GuildHistoryEventListener:InternalCountEvent(index)
    self.currentIndex = index
    self.performanceTracker:Increment()
end

function GuildHistoryEventListener:InternalResetEventCount()
    self.currentIndex = 0
    self.performanceTracker:Reset()
end

function internal:IterateStoredEvents(listener, onCompleted, initializeLastEventId)
    local startIndex, endIndex
    if listener.afterEventId then
        startIndex = listener.categoryCache:FindIndexForEventId(listener.afterEventId)
    elseif listener.afterEventTime then
        startIndex = listener.categoryCache:FindClosestIndexForEventTime(listener.afterEventTime)
    end

    if listener.beforeEventId then
        endIndex = listener.categoryCache:FindIndexForEventId(listener.beforeEventId) + 1
    elseif listener.beforeEventTime then
        endIndex = listener.categoryCache:FindClosestIndexForEventTime(listener.beforeEventTime + 1)
    end
    if endIndex ~= listener.categoryCache:GetNumEvents() then
        listener.endIndex = endIndex
    end

    listener.currentIndex = (startIndex or 1) - 1

    if initializeLastEventId then
        local startEvent = listener.categoryCache:GetEvent(startIndex or 0)
        listener.lastEventId = startEvent and startEvent:GetEventId() or 0
    end

    listener.task:For(listener.categoryCache:GetIterator(startIndex)):Do(function(i, event)
        HandleEvent(listener, event, i)
    end):Then(function()
        internal:EnsureIterationIsComplete(listener, onCompleted)
    end)
end

function internal:EnsureIterationIsComplete(listener, onCompleted)
    local categoryCache = listener.categoryCache
    local lastStoredEntry = categoryCache:GetNewestEvent()
    if listener.lastEventId == 0 or not lastStoredEntry or listener.lastEventId == lastStoredEntry:GetEventId() then
        logger:Verbose("iterated all stored events - register for callback")
        onCompleted(listener)
    else
        logger:Verbose("has not reached the end yet - go for another round")
        internal:IterateStoredEvents(listener, onCompleted)
    end
end

--- public api

-- returns a key consisting of server, guild id and history category, which can be used to store the last received eventId
function GuildHistoryEventListener:GetKey()
    return self.categoryCache:GetKey()
end

-- returns the guild id
function GuildHistoryEventListener:GetGuildId()
    return self.categoryCache:GetGuildId()
end

-- returns the category
function GuildHistoryEventListener:GetCategory()
    return self.categoryCache:GetCategory()
end

-- returns information about history events that need to be sent to the listener
-- number - the amount of queued history events that are currently waiting to be processed by the listener
-- number - the processing speed in events per second (rolling average over 5 seconds)
-- number - the estimated time in seconds it takes to process the remaining events or -1 if it cannot be estimated
function GuildHistoryEventListener:GetPendingEventMetrics()
    if not self.running then return 0, -1, -1 end

    local endIndex = self.endIndex or (self.categoryCache:GetNumEvents() + self.categoryCache:GetNumPendingEvents())
    local count = endIndex - self.currentIndex
    local speed, timeLeft = self.performanceTracker:GetProcessingSpeedAndEstimatedTimeLeft(count)
    return count, speed, timeLeft
end

-- the last known eventId (id64). The nextEventCallback will only return events which have a higher eventId
function GuildHistoryEventListener:SetAfterEventId(eventId)
    if self.running then return false end
    self.afterEventId = internal:ConvertId64ToNumber(eventId)
    return true
end

-- if no eventId has been specified, the nextEventCallback will only receive events after the specified timestamp
function GuildHistoryEventListener:SetAfterEventTime(eventTime)
    if self.running then return false end
    self.afterEventTime = eventTime
    return true
end

-- the highest desired eventId (id64). The nextEventCallback will only return events which have a lower eventId
function GuildHistoryEventListener:SetBeforeEventId(eventId)
    if self.running then return false end
    self.beforeEventId = internal:ConvertId64ToNumber(eventId)
    return true
end

-- if no eventId has been specified, the nextEventCallback will only receive events up to (including) the specified timestamp
function GuildHistoryEventListener:SetBeforeEventTime(eventTime)
    if self.running then return false end
    self.beforeEventTime = eventTime
    return true
end

-- convenience method to specify a range which includes the startTime and excludes the endTime
-- which is usually more desirable than the behaviour of SetAfterEventTime and SetBeforeEventTime which excludes the start time and includes the end time
function GuildHistoryEventListener:SetTimeFrame(startTime, endTime)
    if self.running then return false end
    self.afterEventTime = startTime - 1
    self.beforeEventTime = endTime - 1
    return true
end

-- set a callback which is passed stored and received events in the correct historic order (sorted by eventId)
-- the callback will be handed the following parameters:
-- GuildEventType eventType -- the eventType
-- Id64 eventId -- the unique eventId
-- integer eventTime -- the timestamp for the event
-- variant param1 - 6 -- same as returned by GetGuildEventInfo
function GuildHistoryEventListener:SetNextEventCallback(callback)
    if self.running then return false end
    self.nextEventCallback = callback
    return true
end

-- set a callback which is passed events that had not previously been stored (sorted by eventId)
-- see SetNextEventCallback for information about the callback
function GuildHistoryEventListener:SetMissedEventCallback(callback)
    if self.running then return false end
    self.missedEventCallback = callback
    return true
end

-- convenience method to set both callback types at once
-- see SetNextEventCallback for information about the callback
function GuildHistoryEventListener:SetEventCallback(callback)
    if self.running then return false end
    self.nextEventCallback = callback
    self.missedEventCallback = callback
    return true
end

-- set a callback which is called when beforeEventId or beforeEventTime is reached and the listener is stopped
function GuildHistoryEventListener:SetIterationCompletedCallback(callback)
    if self.running then return false end
    self.iterationCompletedCallback = callback
    return true
end

-- starts iterating over stored events and afterwards registers a listener for future events internally
function GuildHistoryEventListener:Start()
    if self.running then return false end

    if self.nextEventCallback or self.missedEventCallback then
        internal:IterateStoredEvents(self, function()
            logger:Verbose("RegisterForFutureEvents")
            internal:RegisterCallback(internal.callback.EVENT_STORED, self.nextEventProcessor)
        end, true)
    else
        logger:Warn("Tried to start a listener without setting an event callback first")
        return false
    end

    self.running = true
    return true
end

-- stops iterating over stored events and unregisters the listener for future events
function GuildHistoryEventListener:Stop()
    if not self.running then return false end

    if self.nextEventCallback or self.missedEventCallback then
        self.task:Cancel()
        internal:UnregisterCallback(internal.callback.EVENT_STORED, self.nextEventProcessor)
    end

    self:InternalResetEventCount()

    self.running = false
    return true
end

-- returns true while iterating over or listening for events
function GuildHistoryEventListener:IsRunning()
    return self.running
end

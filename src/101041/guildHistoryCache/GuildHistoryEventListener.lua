-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local GuildHistoryEventListener = ZO_InitializingObject:Subclass()
internal.class.GuildHistoryEventListener = GuildHistoryEventListener

local function ShouldHandleEvent(listener, event)
    if listener.afterEventId and event:GetEventId() <= listener.afterEventId then
        logger:Verbose("event before afterEventId", event:GetEventId(), listener.afterEventId)
        return false
    elseif listener.afterEventTime and event:GetEventTimestampS() <= listener.afterEventTime then
        logger:Verbose("event before afterEventTime", event:GetEventTimestampS(), listener.afterEventTime)
        return false
    end
    return true
end

local function HasIterationCompleted(listener, event)
    if listener.beforeEventId and event:GetEventId() >= listener.beforeEventId then
        logger:Verbose("beforeEventId reached", event:GetEventId(), listener.beforeEventId)
        return true
    elseif listener.beforeEventTime and event:GetEventTimestampS() >= listener.beforeEventTime then
        logger:Verbose("beforeEventTime reached", event:GetEventTimestampS(), listener.beforeEventTime)
        return true
    end
    return false
end

local function HandleEvent(listener, event)
    if not ShouldHandleEvent(listener, event) then return end
    if HasIterationCompleted(listener, event) then
        listener:Stop()
        if listener.iterationCompletedCallback then listener.iterationCompletedCallback() end
        return
    end

    local eventId = event:GetEventId()
    if listener.missedEventCallback and eventId < listener.currentEventId then
        listener.missedEventCallback(event)
    elseif listener.nextEventCallback and eventId > listener.currentEventId then
        listener.nextEventCallback(event)
        listener.currentEventId = eventId
    end
end

function GuildHistoryEventListener:Initialize(categoryCache, addonName)
    self.categoryCache = categoryCache
    self.addonName = addonName
    self.running = false
    self.afterEventId = nil
    self.afterEventTime = nil
    self.beforeEventId = nil
    self.beforeEventTime = nil
    self.nextEventCallback = nil
    self.missedEventCallback = nil
    self.iterationCompletedCallback = nil
    self.stopOnLastEvent = false

    self.nextEventProcessor = function(guildId, category, event)
        if not categoryCache:IsFor(guildId, category) then return end
        HandleEvent(self, event)
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
    if not self.running or not self.request then return 0, -1, -1 end
    return self.request:GetPendingEventMetrics()
end

-- the last known eventId (id53). The nextEventCallback will only return events which have a higher eventId
function GuildHistoryEventListener:SetAfterEventId(eventId)
    if self.running then return false end
    self.afterEventId = eventId
    return true
end

-- if no eventId has been specified, the nextEventCallback will only receive events after the specified timestamp
function GuildHistoryEventListener:SetAfterEventTime(eventTime)
    if self.running then return false end
    self.afterEventTime = eventTime
    return true
end

-- the highest desired eventId (id53). The nextEventCallback will only return events which have a lower eventId
function GuildHistoryEventListener:SetBeforeEventId(eventId)
    if self.running then return false end
    self.beforeEventId = eventId
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
-- the callback will be handed an event object (see guildhistory_data.lua) which must not be stored or modified
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

-- sets if the listener should stop instead of listening for future events when it runs out of events before encountering the end criteria
function GuildHistoryEventListener:SetStopOnLastEvent(shouldStop)
    if self.running then return false end
    self.stopOnLastEvent = shouldStop
    return true
end

-- starts iterating over stored events and afterwards registers a listener for future events internally
function GuildHistoryEventListener:Start()
    if self.running then return false end

    if self.nextEventCallback or self.missedEventCallback then
        self.request = internal.class.GuildHistoryProcessingRequest:New(self, HandleEvent, function()
            self.categoryCache:RemoveProcessingRequest(self.request)
            self.request = nil
            if self.stopOnLastEvent then
                logger:Verbose("stopOnLastEvent")
                self:Stop()
                if self.iterationCompletedCallback then self.iterationCompletedCallback() end
            else
                logger:Verbose("RegisterForFutureEvents")
                internal:RegisterCallback(internal.callback.PROCESS_LINKED_EVENT, self.nextEventProcessor)
                internal:RegisterCallback(internal.callback.PROCESS_MISSED_EVENT, self.nextEventProcessor)
            end
        end)
        self.categoryCache:QueueProcessingRequest(self.request)
    else
        logger:Warn("Tried to start a listener without setting an event callback first")
        return false
    end

    self.categoryCache:RegisterListener(self)
    self.running = true
    return true
end

-- stops iterating over stored events and unregisters the listener for future events
function GuildHistoryEventListener:Stop()
    if not self.running then return false end

    if self.request then
        self.categoryCache:RemoveProcessingRequest(self.request)
        self.request = nil
    end

    if self.nextEventCallback or self.missedEventCallback then
        internal:UnregisterCallback(internal.callback.PROCESS_LINKED_EVENT, self.nextEventProcessor)
        internal:UnregisterCallback(internal.callback.PROCESS_MISSED_EVENT, self.nextEventProcessor)
    end

    self.categoryCache:UnregisterListener(self)
    self.currentEventId = nil
    self.running = false
    return true
end

-- returns true while iterating over or listening for events
function GuildHistoryEventListener:IsRunning()
    return self.running
end

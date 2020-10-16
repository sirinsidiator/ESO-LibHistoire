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

local function HandleEvent(listener, event)
    if not ShouldHandleEvent(listener, event) then return end

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
    self.nextEventCallback = nil
    self.missedEventCallback = nil

    self.nextEventProcessor = function(guildId, category, event)
        if not categoryCache:IsFor(guildId, category) then return end
        HandleEvent(self, event)
    end
end

function internal:IterateStoredEvents(listener, onCompleted)
    local startIndex
    if listener.afterEventId then
        startIndex = listener.categoryCache:FindIndexForEventId(listener.afterEventId)
    elseif listener.afterEventTime then
        startIndex = listener.categoryCache:FindClosestIndexForEventTime(listener.afterEventTime)
    end
    listener.task:For(listener.categoryCache:GetIterator(startIndex)):Do(function(i, event)
        HandleEvent(listener, event)
    end):Then(function()
        internal:EnsureIterationIsComplete(listener, onCompleted)
    end)
end

function internal:EnsureIterationIsComplete(listener, onCompleted)
    local categoryCache = listener.categoryCache
    local lastStoredEntry = categoryCache:GetNewestEvent()
    if listener.lastEventId == 0 or (lastStoredEntry and listener.lastEventId == lastStoredEntry:GetEventId()) then
        logger:Debug("iterated all stored events - register for callback")
        onCompleted(listener)
    else
        logger:Debug("has not reached the end yet - go for another round")
        internal:IterateStoredEvents(listener, onCompleted)
    end
end

--- public api

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

-- starts iterating over stored events and afterwards registers a listener for future events internally
function GuildHistoryEventListener:Start()
    if self.running then return false end

    self.lastEventId = self.afterEventId or 0
    if self.nextEventCallback or self.missedEventCallback then
        internal:IterateStoredEvents(self, function()
            logger:Debug("RegisterForFutureEvents")
            internal:RegisterCallback(internal.callback.EVENT_STORED, self.nextEventProcessor)
        end)
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

    self.running = false
    return true
end

-- returns true while iterating over or listening for events
function GuildHistoryEventListener:IsRunning()
    return self.running
end

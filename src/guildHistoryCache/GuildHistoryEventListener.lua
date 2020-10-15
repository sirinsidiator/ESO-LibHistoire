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
    self.historyReloadedCallback = nil

    self.nextEventProcessor = function(guildId, category, event)
        if not categoryCache:IsFor(guildId, category) then return end
        HandleEvent(self, event)
    end

    self.historyReloadedProcessor = function(guildId, category)
        if not categoryCache:IsFor(guildId, category) then return end
        self.historyReloadedCallback()
    end
end

function internal:IterateStoredEvents(listener, onCompleted)
    listener.task:For(listener.categoryCache:GetIterator(listener.afterEventId)):Do(function(i, event)
        HandleEvent(listener, event)
    end):Then(function()
        internal:EnsureIterationIsComplete(listener, onCompleted)
    end)
end

function internal:EnsureIterationIsComplete(listener, onCompleted)
    local categoryCache = listener.categoryCache
    local lastStoredEntry = categoryCache:GetNewestEvent()
    if listener.lastEventId == 0 or (lastStoredEntry and listener.lastEventId == lastStoredEntry:GetEventId()) then
        logger:Info("iterated all stored events - register for callback")
        onCompleted(listener)
    else
        logger:Info("has not reached the end yet - go for another round")
        internal:IterateStoredEvents(listener, onCompleted)
    end
end

--- public api

function GuildHistoryEventListener:SetAfterEventId(eventId)
    if self.running then return false end
    self.afterEventId = eventId
    return true
end

function GuildHistoryEventListener:SetAfterEventTime(eventTime)
    if self.running then return false end
    self.afterEventTime = eventTime
    return true
end

function GuildHistoryEventListener:SetNextEventCallback(callback)
    if self.running then return false end
    self.nextEventCallback = callback
    return true
end

function GuildHistoryEventListener:SetMissedEventCallback(callback)
    if self.running then return false end
    self.missedEventCallback = callback
    return true
end

function GuildHistoryEventListener:SetHistoryReloadedCallback(callback)
    if self.running then return false end
    self.historyReloadedCallback = callback
    return true
end

function GuildHistoryEventListener:Start()
    if self.running then return false end

    self.lastEventId = self.afterEventId or 0
    if self.nextEventCallback or self.missedEventCallback then
        internal:IterateStoredEvents(self, function()
            logger:Info("RegisterForFutureEvents")
            internal:RegisterCallback(internal.callback.EVENT_STORED, self.nextEventProcessor)
        end)
    end

    if self.historyReloadedCallback then
        internal:RegisterCallback(internal.callback.HISTORY_RELOADED, self.historyReloadedProcessor)
    end

    self.running = true
    return true
end

function GuildHistoryEventListener:Stop()
    if not self.running then return false end

    if self.nextEventCallback or self.missedEventCallback then
        self.task:Cancel()
        internal:UnregisterCallback(internal.callback.EVENT_STORED, self.nextEventProcessor)
    end

    if self.historyReloadedCallback then
        internal:UnregisterCallback(internal.callback.HISTORY_RELOADED, self.historyReloadedProcessor)
    end

    self.running = false
    return true
end

function GuildHistoryEventListener:IsRunning()
    return self.running
end

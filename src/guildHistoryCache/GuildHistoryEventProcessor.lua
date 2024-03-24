-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local GuildHistoryEventProcessor = ZO_InitializingObject:Subclass()
internal.class.GuildHistoryEventProcessor = GuildHistoryEventProcessor

local function ShouldHandleEvent(processor, event)
    if processor.afterEventId and event:GetEventId() <= processor.afterEventId then
        return false
    elseif processor.afterEventTime and event:GetEventTimestampS() <= processor.afterEventTime then
        return false
    end
    return true
end

local function HasIterationCompleted(processor, event)
    if processor.beforeEventId and event:GetEventId() >= processor.beforeEventId then
        logger:Verbose("beforeEventId reached", event:GetEventId(), processor.beforeEventId)
        return true
    elseif processor.beforeEventTime and event:GetEventTimestampS() >= processor.beforeEventTime then
        logger:Verbose("beforeEventTime reached", event:GetEventTimestampS(), processor.beforeEventTime)
        return true
    end
    return false
end

local function HandleEvent(processor, event)
    if not ShouldHandleEvent(processor, event) then return end
    if HasIterationCompleted(processor, event) then
        processor:Stop(internal.STOP_REASON_ITERATION_COMPLETED)
        return
    end

    local eventId = event:GetEventId()
    if processor.missedEventCallback and processor.currentEventId and eventId < processor.currentEventId then
        processor.missedEventCallback(event)
    elseif processor.nextEventCallback and (not processor.currentEventId or eventId > processor.currentEventId) then
        processor.nextEventCallback(event)
        processor.currentEventId = eventId
    end
end

function GuildHistoryEventProcessor:Initialize(categoryCache, addonName)
    self.categoryCache = categoryCache
    self.addonName = addonName
    self.running = false
    self.afterEventId = nil
    self.afterEventTime = nil
    self.beforeEventId = nil
    self.beforeEventTime = nil
    self.nextEventCallback = nil
    self.missedEventCallback = nil
    self.onStopCallback = nil
    self.stopOnLastCachedEvent = false
    self.receiveMissedEventsOutsideIterationRange = false

    self.nextEventProcessor = function(guildId, category, event)
        if not categoryCache:IsFor(guildId, category) then return end
        HandleEvent(self, event)
    end

    self.missedEventProcessor = function(guildId, category, event)
        if not categoryCache:IsFor(guildId, category) then return end
        if self.receiveMissedEventsOutsideIterationRange and self.missedEventCallback then
            self.missedEventCallback(event)
        else
            HandleEvent(self, event)
        end
    end
end

--- public api

-- returns the name of the addon that created the processor
function GuildHistoryEventProcessor:GetAddonName()
    return self.addonName
end

-- returns a key consisting of server, guild id and history category, which can be used to store the last received eventId
function GuildHistoryEventProcessor:GetKey()
    return self.categoryCache:GetKey()
end

-- returns the guild id
function GuildHistoryEventProcessor:GetGuildId()
    return self.categoryCache:GetGuildId()
end

-- returns the category
function GuildHistoryEventProcessor:GetCategory()
    return self.categoryCache:GetCategory()
end

-- returns information about history events that need to be sent to the processor
-- number - the amount of queued history events that are currently waiting to be processed by the processor
-- number - the processing speed in events per second (rolling average over 5 seconds)
-- number - the estimated time in seconds it takes to process the remaining events or -1 if it cannot be estimated
function GuildHistoryEventProcessor:GetPendingEventMetrics()
    if not self.running or not self.request then return 0, -1, -1 end
    return self.request:GetPendingEventMetrics()
end

-- the last known eventId (id53). The nextEventCallback will only return events which have a higher eventId
function GuildHistoryEventProcessor:SetAfterEventId(eventId)
    if self.running then
        logger:Warn("Tried to call SetAfterEventId while processor is running")
        return false
    end

    self.afterEventId = eventId
    return true
end

-- if no eventId has been specified, the nextEventCallback will only receive events after the specified timestamp
function GuildHistoryEventProcessor:SetAfterEventTime(eventTime)
    if self.running then
        logger:Warn("Tried to call SetAfterEventTime while processor is running")
        return false
    end

    self.afterEventTime = eventTime
    return true
end

-- the highest desired eventId (id53). The nextEventCallback will only return events which have a lower eventId
function GuildHistoryEventProcessor:SetBeforeEventId(eventId)
    if self.running then
        logger:Warn("Tried to call SetBeforeEventId while processor is running")
        return false
    end

    self.beforeEventId = eventId
    return true
end

-- if no eventId has been specified, the nextEventCallback will only receive events before the specified timestamp
function GuildHistoryEventProcessor:SetBeforeEventTime(eventTime)
    if self.running then
        logger:Warn("Tried to call SetBeforeEventTime while processor is running")
        return false
    end

    self.beforeEventTime = eventTime
    return true
end

-- set a callback which is passed stored and received events in the correct historic order (sorted by eventId)
-- the callback will be handed an event object (see guildhistory_data.lua) which must not be stored or modified
function GuildHistoryEventProcessor:SetNextEventCallback(callback)
    if self.running then
        logger:Warn("Tried to call SetNextEventCallback while processor is running")
        return false
    end

    self.nextEventCallback = callback
    return true
end

-- set a callback which is passed events that had not previously been stored (sorted by eventId)
-- see SetNextEventCallback for information about the callback
function GuildHistoryEventProcessor:SetMissedEventCallback(callback)
    if self.running then
        logger:Warn("Tried to call SetMissedEventCallback while processor is running")
        return false
    end

    self.missedEventCallback = callback
    return true
end

-- convenience method to set both callback types at once
-- see SetNextEventCallback for information about the callback
function GuildHistoryEventProcessor:SetEventCallback(callback)
    if self.running then
        logger:Warn("Tried to call SetEventCallback while processor is running")
        return false
    end

    self.nextEventCallback = callback
    self.missedEventCallback = callback
    return true
end

-- set a callback which is called after the listener has stopped
-- receives a reason (see lib.StopReason) why the processor has stopped
function GuildHistoryEventProcessor:SetOnStopCallback(callback)
    if self.running then
        logger:Warn("Tried to call SetOnStopCallback while processor is running")
        return false
    end

    self.onStopCallback = callback
    return true
end

-- sets if the processor should stop instead of listening for future events when it runs out of events before encountering the end criteria
function GuildHistoryEventProcessor:SetStopOnLastCachedEvent(shouldStop)
    if self.running then
        logger:Warn("Tried to call SetStopOnLastCachedEvent while processor is running")
        return false
    end

    self.stopOnLastCachedEvent = shouldStop
    return true
end

-- set a callback which is called when the processor starts waiting for future events
function GuildHistoryEventProcessor:SetRegisteredForFutureEventsCallback(callback)
    if self.running then
        logger:Warn("Tried to call SetRegisteredForFutureEventsCallback while processor is running")
        return false
    end

    self.futureEventsCallback = callback
    return true
end

-- sets if the processor should forward missed events outside of the specified iteration range to the missedEventCallback
function GuildHistoryEventProcessor:SetReceiveMissedEventsOutsideIterationRange(shouldReceive)
    if self.running then
        logger:Warn("Tried to call SetReceiveMissedEventsOutsideIterationRange while processor is running")
        return false
    end

    self.receiveMissedEventsOutsideIterationRange = shouldReceive
    return true
end

-- starts iterating over stored events and afterwards registers a processor for future events internally
function GuildHistoryEventProcessor:Start()
    if self.running then return false end

    if self.nextEventCallback or self.missedEventCallback then
        self.request = internal.class.GuildHistoryProcessingRequest:New(self, HandleEvent, function()
            self.categoryCache:RemoveProcessingRequest(self.request)
            self.request = nil
            if self.stopOnLastCachedEvent then
                logger:Verbose("stopOnLastEvent", self:GetKey(), self.addonName)
                assert(self.running,
                    string.format("Processor %s should be running (%s)", self:GetKey(), self.addonName or "-"))
                self:Stop(internal.STOP_REASON_LAST_CACHED_EVENT_REACHED)
            else
                logger:Verbose("RegisterForFutureEvents")
                internal:RegisterCallback(internal.callback.PROCESS_LINKED_EVENT, self.nextEventProcessor)
                internal:RegisterCallback(internal.callback.PROCESS_MISSED_EVENT, self.missedEventProcessor)
                if self.futureEventsCallback then self.futureEventsCallback() end
            end
        end)
        self.categoryCache:QueueProcessingRequest(self.request)
    else
        logger:Warn("Tried to start a processor without setting an event callback first")
        return false
    end

    if self.addonName then
        self.categoryCache:RegisterProcessor(self)
    end
    self.running = true
    return true
end

-- convenience method to specify a time range and directly start the processor
-- this range will include the start time and exclude the end time
-- optionally takes the nextEvent callback in case it has not been set before
function GuildHistoryEventProcessor:StartIteratingTimeRange(startTime, endTime, callback)
    if self.running then return false end

    self.afterEventTime = startTime - 1
    self.beforeEventTime = endTime
    if callback ~= nil then
        self.nextEventCallback = callback
    end

    return self:Start()
end

-- convenience method to specify an id range and directly start the processor
-- this range will include both the start id and the end id
-- optionally takes the nextEvent callback in case it has not been set before
function GuildHistoryEventProcessor:StartIteratingIdRange(startId, endId, callback)
    if self.running then return false end

    self.afterEventId = startId - 1
    self.beforeEventId = endId + 1
    if callback ~= nil then
        self.nextEventCallback = callback
    end
    return self:Start()
end

-- convenience method to start the processor with a callback and optionally only receive events after the specified eventId
function GuildHistoryEventProcessor:StartStreaming(callback, fromId)
    if self.running then return false end

    self.nextEventCallback = callback
    self.afterEventId = fromId
    return self:Start()
end

-- stops iterating over stored events and unregisters the processor for future events
function GuildHistoryEventProcessor:Stop(reason)
    if not self.running then return false end

    reason = reason or internal.STOP_REASON_MANUAL_STOP
    logger:Info("Stop processor", self:GetKey(), reason)
    if self.request then
        self.categoryCache:RemoveProcessingRequest(self.request)
        self.request = nil
    end

    if self.nextEventCallback or self.missedEventCallback then
        internal:UnregisterCallback(internal.callback.PROCESS_LINKED_EVENT, self.nextEventProcessor)
        internal:UnregisterCallback(internal.callback.PROCESS_MISSED_EVENT, self.nextEventProcessor)
    end

    if self.addonName then
        self.categoryCache:UnregisterProcessor(self)
    end
    self.currentEventId = nil
    self.running = false

    if self.onStopCallback then
        self.onStopCallback(reason)
    end
    return true
end

-- returns true while iterating over or listening for events
function GuildHistoryEventProcessor:IsRunning()
    return self.running
end

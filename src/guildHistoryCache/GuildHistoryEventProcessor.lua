-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

--- @class GuildHistoryEventProcessor
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
        processor:StopInternal(internal.STOP_REASON_ITERATION_COMPLETED)
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

--- @internal
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

--- @internal
function GuildHistoryEventProcessor:StopInternal(reason)
    if not self.running then return false end

    reason = reason or internal.STOP_REASON_MANUAL_STOP
    logger:Info("Stop processor", self:GetKey(), reason)
    if self.request then
        self.categoryCache:RemoveProcessingRequest(self.request)
        self.request = nil
    end

    if self.nextEventCallback or self.missedEventCallback then
        internal:UnregisterCallback(internal.callback.PROCESS_LINKED_EVENT, self.nextEventProcessor)
        internal:UnregisterCallback(internal.callback.PROCESS_MISSED_EVENT, self.missedEventProcessor)
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

--- public api

--- Returns the name of the addon that created the processor.
--- @return string addonName The name of the addon that created the processor.
function GuildHistoryEventProcessor:GetAddonName()
    return self.addonName
end

--- Returns a key consisting of server, guild id and history category, which can be used to store the last received eventId.
--- @return string key The key that identifies the processor.
function GuildHistoryEventProcessor:GetKey()
    return self.categoryCache:GetKey()
end

--- Returns the guild id.
--- @return integer guildId The id of the guild the processor is listening to.
function GuildHistoryEventProcessor:GetGuildId()
    return self.categoryCache:GetGuildId()
end

--- Returns the category.
--- @return GuildHistoryEventCategory category The event category the processor is listening to.
function GuildHistoryEventProcessor:GetCategory()
    return self.categoryCache:GetCategory()
end

--- Returns information about history events that need to be sent to the processor.
--- @return integer numEventsRemaining The amount of queued history events that are currently waiting to be processed by the processor.
--- @return integer processingSpeed The processing speed in events per second (rolling average over 5 seconds).
--- @return integer timeLeft The estimated time in seconds it takes to process the remaining events or -1 if it cannot be estimated.
function GuildHistoryEventProcessor:GetPendingEventMetrics()
    if not self.running or not self.request then return 0, -1, -1 end
    return self.request:GetPendingEventMetrics()
end

--- Allows to specify a start condition. The nextEventCallback will only return events which have a higher eventId.
--- @param eventId integer53 An eventId to start after.
--- @return boolean success true if the condition was set successfully, false if the processor is already running.
function GuildHistoryEventProcessor:SetAfterEventId(eventId)
    if self.running then
        logger:Warn("Tried to call SetAfterEventId while processor is running")
        return false
    end

    self.afterEventId = eventId
    return true
end

--- Allows to specify a start condition. The nextEventCallback will only receive events after the specified timestamp. Only is considered if no afterEventId has been specified.
--- @param eventTime integer53 A timestamp to start after.
--- @return boolean success true if the condition was set successfully, false if the processor is already running.
function GuildHistoryEventProcessor:SetAfterEventTime(eventTime)
    if self.running then
        logger:Warn("Tried to call SetAfterEventTime while processor is running")
        return false
    end

    self.afterEventTime = eventTime
    return true
end

--- Allows to specify an end condition. The nextEventCallback will only return events which have a lower eventId.
--- @param eventId integer53 An eventId to end before.
--- @return boolean success true if the condition was set successfully, false if the processor is already running.
function GuildHistoryEventProcessor:SetBeforeEventId(eventId)
    if self.running then
        logger:Warn("Tried to call SetBeforeEventId while processor is running")
        return false
    end

    self.beforeEventId = eventId
    return true
end

--- Allows to specify an end condition. The nextEventCallback will only return events which have a lower timestamp. Only is considered if no beforeEventId has been specified.
--- @param eventTime integer53 A timestamp to end before.
--- @return boolean success true if the condition was set successfully, false if the processor is already running.
function GuildHistoryEventProcessor:SetBeforeEventTime(eventTime)
    if self.running then
        logger:Warn("Tried to call SetBeforeEventTime while processor is running")
        return false
    end

    self.beforeEventTime = eventTime
    return true
end

--- Sets a callback which will get passed all events in the specified range in the correct historic order (sorted by eventId).
--- The callback will be handed an event object (see guildhistory_data.lua) which must not be stored or modified, as it can change after the function returns.
--- @see ZO_GuildHistoryEventData_Base
--- @param callback fun(event: ZO_GuildHistoryEventData_Base) The function that will be called for each event that is processed.
--- @return boolean success true if the condition was set successfully, false if the processor is already running.
function GuildHistoryEventProcessor:SetNextEventCallback(callback)
    if self.running then
        logger:Warn("Tried to call SetNextEventCallback while processor is running")
        return false
    end

    self.nextEventCallback = callback
    return true
end

--- Sets a callback which will get passed events that had not previously been included in the managed range, but are inside the start and end criteria. The order of the events is not guaranteed.
--- If SetReceiveMissedEventsOutsideIterationRange is set to true, this callback will also receive events that are outside of the specified iteration range.
--- The callback will be handed an event object (see guildhistory_data.lua) which must not be stored or modified, as it can change after the function returns.
--- @see ZO_GuildHistoryEventData_Base
--- @see GuildHistoryEventProcessor.SetReceiveMissedEventsOutsideIterationRange
--- @param callback fun(event: ZO_GuildHistoryEventData_Base) The function that will be called for each missed event that was found.
--- @return boolean success true if the condition was set successfully, false if the processor is already running.
function GuildHistoryEventProcessor:SetMissedEventCallback(callback)
    if self.running then
        logger:Warn("Tried to call SetMissedEventCallback while processor is running")
        return false
    end

    self.missedEventCallback = callback
    return true
end

--- Convenience method to set both callback types at once.
--- @see GuildHistoryEventProcessor.SetNextEventCallback
--- @see GuildHistoryEventProcessor.SetMissedEventCallback
--- @param callback fun(event: ZO_GuildHistoryEventData_Base) The function that will be called for each missed event that was found.
--- @return boolean success true if the condition was set successfully, false if the processor is already running.
function GuildHistoryEventProcessor:SetEventCallback(callback)
    if self.running then
        logger:Warn("Tried to call SetEventCallback while processor is running")
        return false
    end

    self.nextEventCallback = callback
    self.missedEventCallback = callback
    return true
end

--- Set a callback which is called after the listener has stopped.
--- Receives a reason (see lib.StopReason) why the processor has stopped.
--- @see LibHistoire.StopReason
--- @param callback fun(reason: StopReason) The function that will be called when the processor stops.
--- @return boolean success true if the condition was set successfully, false if the processor is already running.
function GuildHistoryEventProcessor:SetOnStopCallback(callback)
    if self.running then
        logger:Warn("Tried to call SetOnStopCallback while processor is running")
        return false
    end

    self.onStopCallback = callback
    return true
end

--- Controls if the processor should stop instead of listening for future events when it runs out of events before encountering an end criteria.
--- @param shouldStop boolean true if the processor should stop when it runs out of events, false if it should wait for future events.
--- @return boolean success true if the condition was set successfully, false if the processor is already running.
function GuildHistoryEventProcessor:SetStopOnLastCachedEvent(shouldStop)
    if self.running then
        logger:Warn("Tried to call SetStopOnLastCachedEvent while processor is running")
        return false
    end

    self.stopOnLastCachedEvent = shouldStop
    return true
end

--- Sets a callback which is called when the processor starts waiting for future events.
--- @param callback function The function that will be called when the processor starts waiting for future events.
--- @return boolean success true if the condition was set successfully, false if the processor is already running.
function GuildHistoryEventProcessor:SetRegisteredForFutureEventsCallback(callback)
    if self.running then
        logger:Warn("Tried to call SetRegisteredForFutureEventsCallback while processor is running")
        return false
    end

    self.futureEventsCallback = callback
    return true
end

--- Controls if the processor should forward missed events outside of the specified iteration range to the missedEventCallback.
--- @see GuildHistoryEventProcessor.SetMissedEventCallback
--- @param shouldReceive boolean true if missed events outside of the specified iteration range should be forwarded, false if they should be ignored.
--- @return boolean success true if the condition was set successfully, false if the processor is already running.
function GuildHistoryEventProcessor:SetReceiveMissedEventsOutsideIterationRange(shouldReceive)
    if self.running then
        logger:Warn("Tried to call SetReceiveMissedEventsOutsideIterationRange while processor is running")
        return false
    end

    self.receiveMissedEventsOutsideIterationRange = shouldReceive
    return true
end

--- Starts the processor and passes events to the specified callbacks asyncronously. The exact behavior depends on the set conditions and callbacks.
--- @return boolean started true if the processor was started successfully, false if it is already running.
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
                self:StopInternal(internal.STOP_REASON_LAST_CACHED_EVENT_REACHED)
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

--- Convenience method to configure and start the processor to iterate over a specific time range and stop after it has passed all available events.
--- @see GuildHistoryEventProcessor.SetAfterEventTime
--- @see GuildHistoryEventProcessor.SetBeforeEventTime
--- @see GuildHistoryEventProcessor.SetStopOnLastCachedEvent
--- @see GuildHistoryEventProcessor.SetNextEventCallback
--- @see GuildHistoryEventProcessor.SetOnStopCallback
--- @param startTime integer53 The start time of the range (inclusive).
--- @param endTime integer53 The end time of the range (exclusive).
--- @param eventCallback fun(event: ZO_GuildHistoryEventData_Base) The function that will be called for each event that is processed.
--- @param finishedCallback fun(reason: StopReason) The function that will be called when the processor stops. Only when StopReason.ITERATION_COMPLETED is passed, all events in the range have been processed.
--- @return boolean started true if the processor was started successfully, false if it is already running.
function GuildHistoryEventProcessor:StartIteratingTimeRange(startTime, endTime, eventCallback, finishedCallback)
    if self.running then return false end

    self.afterEventTime = startTime - 1
    self.beforeEventTime = endTime
    self.stopOnLastCachedEvent = true
    self.nextEventCallback = eventCallback
    self.onStopCallback = finishedCallback

    return self:Start()
end

--- Convenience method to start the processor with a callback and optionally only receive events after the specified eventId.
--- @param lastProcessedId integer53|nil The last eventId that was processed by the addon or nil to start with the oldest managed event.
--- @param eventCallback fun(event: ZO_GuildHistoryEventData_Base) The function that will be called for each event that is processed. If not provided here, it has to be set with SetNextEventCallback beforehand, or the processor won't start.
--- @return boolean started true if the processor was started successfully, false if it is already running.
function GuildHistoryEventProcessor:StartStreaming(lastProcessedId, eventCallback)
    if self.running then return false end

    self.afterEventId = lastProcessedId
    if eventCallback then
        self.nextEventCallback = eventCallback
    end

    if not self.nextEventCallback then
        logger:Warn("Tried to start a processor without setting an event callback first")
        return false
    end

    return self:Start()
end

--- Stops iterating over stored events and unregisters the processor for future events.
--- @return boolean stopped true if the processor was stopped successfully, false if it is not running.
function GuildHistoryEventProcessor:Stop()
    return self:StopInternal()
end

--- Returns true while iterating over or listening for events.
--- @return boolean running true if the processor is currently running.
function GuildHistoryEventProcessor:IsRunning()
    return self.running
end

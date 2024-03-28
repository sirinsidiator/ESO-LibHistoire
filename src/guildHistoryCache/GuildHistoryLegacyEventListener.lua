-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

--- @class GuildHistoryLegacyEventListener
local GuildHistoryLegacyEventListener = ZO_InitializingObject:Subclass()
internal.class.GuildHistoryLegacyEventListener = GuildHistoryLegacyEventListener

function GuildHistoryLegacyEventListener:Initialize(guildId, legacyCategory, caches)
    self.guildId = guildId
    self.legacyCategory = legacyCategory
    self.key = string.format("%s/%d/%d", internal.WORLD_NAME, guildId, legacyCategory)
    self.caches = caches
    self.processors = {}
    self.listeners = self.processors -- TODO remove once ATT is updated
    self.cachedEvents = {}
    self.iterationCompletedCount = 0
    self.eventsLeft = 0
    self.performanceTracker = internal.class.PerformanceTracker:New()
    self.hasReachedEndCriteria = false

    for _, cache in ipairs(caches) do
        local processor = internal.class.GuildHistoryEventProcessor:New(cache)
        processor:SetStopOnLastCachedEvent(true)
        processor:SetOnStopCallback(function(reason)
            if reason == internal.STOP_REASON_ITERATION_COMPLETED or reason == internal.STOP_REASON_LAST_CACHED_EVENT_REACHED then
                if reason == internal.STOP_REASON_ITERATION_COMPLETED then
                    self.hasReachedEndCriteria = true
                end
                self.iterationCompletedCount = self.iterationCompletedCount + 1
                logger:Debug("iteration completed", self.key, self.iterationCompletedCount, #self.processors)
                if self.iterationCompletedCount == #self.processors then
                    self:OnIterationsCompleted()
                end
            end
        end)
        self.processors[#self.processors + 1] = processor
    end

    local function IsFor(guildId, category)
        for _, cache in ipairs(caches) do
            if cache:IsFor(guildId, category) then
                return true
            end
        end
        return false
    end

    local function ShouldHandleEvent(event)
        if self.afterEventId and event:GetEventId() <= self.afterEventId then
            return false
        elseif self.afterEventTime and event:GetEventTimestampS() <= self.afterEventTime then
            return false
        end
        return true
    end

    self.cachedNextEventCallback = function(guildId, category, event)
        if not IsFor(guildId, category) or not ShouldHandleEvent(event) then return end
        self.cachedEvents[#self.cachedEvents + 1] = {
            eventId = event:GetEventId(),
            arguments = { internal.ConvertEventToLegacyFormat(event) }
        }
    end

    self.uncachedNextEventCallback = function(guildId, category, event)
        if not IsFor(guildId, category) or not ShouldHandleEvent(event) then return end
        local eventId = event:GetEventId()
        if self.missedEventCallback and self.currentEventId and eventId < self.currentEventId then
            self.missedEventCallback(internal.ConvertEventToLegacyFormat(event))
        elseif self.nextEventCallback and (not self.currentEventId or eventId > self.currentEventId) then
            self.nextEventCallback(internal.ConvertEventToLegacyFormat(event))
            self.currentEventId = eventId
        end
    end

    if #self.processors > 1 then
        logger:Debug("register cached event callbacks")
        self.onEvent = function(event)
            local guildId = event:GetGuildId()
            local category = event:GetEventCategory()
            return self.cachedNextEventCallback(guildId, category, event)
        end
    else
        logger:Debug("register uncached event callbacks")
        self.onEvent = function(event)
            local guildId = event:GetGuildId()
            local category = event:GetEventCategory()
            return self.uncachedNextEventCallback(guildId, category, event)
        end
    end
end

function GuildHistoryLegacyEventListener:OnIterationsCompleted()
    local events = self.cachedEvents
    logger:Debug("iterations completed", self.key, #events)
    if #events == 0 then
        self:OnProcessingCachedEventsCompleted()
        return
    end

    self.cachedEvents = {}
    self.performanceTracker:Reset()
    logger:Debug("register cached event callbacks")
    internal:RegisterCallback(internal.callback.PROCESS_LINKED_EVENT, self.cachedNextEventCallback)
    internal:RegisterCallback(internal.callback.PROCESS_MISSED_EVENT, self.cachedNextEventCallback)

    table.sort(events, function(a, b)
        return a.eventId < b.eventId
    end)

    local task = internal:CreateAsyncTask()
    local numEvents = #events
    self.eventsLeft = numEvents
    task:For(1, numEvents):Do(function(i)
        self.currentEventId = events[i].eventId
        self.eventsLeft = numEvents - i
        self.performanceTracker:Increment()
        self.nextEventCallback(unpack(events[i].arguments))
    end):Then(function()
        self:OnProcessingCachedEventsCompleted()
        self.performanceTracker:Reset()
        self.eventsLeft = 0
        self.task = nil
    end)
    self.task = task
end

function GuildHistoryLegacyEventListener:OnProcessingCachedEventsCompleted()
    local events = self.cachedEvents
    logger:Debug("processing cached events completed", self.key, #events)
    if #events > 0 then
        self.cachedEvents = {}
        logger:Debug("unregister cached event callbacks")
        internal:UnregisterCallback(internal.callback.PROCESS_LINKED_EVENT, self.cachedNextEventCallback)
        internal:UnregisterCallback(internal.callback.PROCESS_MISSED_EVENT, self.cachedNextEventCallback)

        table.sort(events, function(a, b)
            return a.eventId < b.eventId
        end)

        for _, event in ipairs(events) do
            self.currentEventId = event.eventId
            self.nextEventCallback(unpack(event.arguments))
        end
    end

    local shouldFireIterationCompleted = false
    if self.shouldStop then
        logger:Debug("stop after iteration")
        self:Stop()
        shouldFireIterationCompleted = true
    else
        logger:Debug("register uncached event callbacks")
        internal:RegisterCallback(internal.callback.PROCESS_LINKED_EVENT, self.uncachedNextEventCallback)
        internal:RegisterCallback(internal.callback.PROCESS_MISSED_EVENT, self.uncachedNextEventCallback)
        shouldFireIterationCompleted = self.hasReachedEndCriteria
    end

    if self.iterationCompletedCallback and shouldFireIterationCompleted then
        self.iterationCompletedCallback()
    end
end

function GuildHistoryLegacyEventListener:StopInternal()
    if not self.running then return false end

    logger:Debug("Stopping legacy event listener", self.key)
    for _, processor in ipairs(self.processors) do
        if processor:IsRunning() and not processor:Stop() then
            logger:Warn("Failed to stop processor", processor:GetKey())
        end
    end

    internal:UnregisterCallback(internal.callback.PROCESS_LINKED_EVENT, self.cachedNextEventCallback)
    internal:UnregisterCallback(internal.callback.PROCESS_MISSED_EVENT, self.cachedNextEventCallback)
    internal:UnregisterCallback(internal.callback.PROCESS_LINKED_EVENT, self.uncachedNextEventCallback)
    internal:UnregisterCallback(internal.callback.PROCESS_MISSED_EVENT, self.uncachedNextEventCallback)
    if self.task then
        self.task:Cancel()
        self.task = nil
    end
    self.cachedEvents = {}
    self.hasReachedEndCriteria = false

    for _, cache in ipairs(self.caches) do
        cache:UnregisterProcessor(self)
    end

    self.running = false
    return true
end

--- public api

-- returns a key consisting of server, guild id and history category, which can be used to store the last received eventId
function GuildHistoryLegacyEventListener:GetKey()
    return self.key
end

-- returns the guild id
function GuildHistoryLegacyEventListener:GetGuildId()
    return self.guildId
end

-- returns the category
function GuildHistoryLegacyEventListener:GetCategory()
    return self.legacyCategory
end

-- returns information about history events that need to be sent to the listener
-- number - the amount of queued history events that are currently waiting to be processed by the listener
-- number - the processing speed in events per second (rolling average over 5 seconds)
-- number - the estimated time in seconds it takes to process the remaining events or -1 if it cannot be estimated
function GuildHistoryLegacyEventListener:GetPendingEventMetrics()
    local numProcessors = #self.processors
    if not self.running or numProcessors == 0 then return 0, -1, -1 end

    if self.iterationCompletedCount < numProcessors then
        if numProcessors == 1 then
            return self.processors[1]:GetPendingEventMetrics()
        end

        local count = 0
        local speed = 0
        local time = 0
        for _, processor in ipairs(self.processors) do
            local c, s, t = processor:GetPendingEventMetrics()
            count = count + c
            if s > 0 then
                speed = speed + s
            end
            if t > 0 then
                time = time + t
            end
        end
        speed = speed / numProcessors
        time = time / numProcessors

        return count, speed, time
    else
        local count = self.eventsLeft
        local speed, time = self.performanceTracker:GetProcessingSpeedAndEstimatedTimeLeft(count)
        return count, speed, time
    end
end

-- the last known eventId (id64). The nextEventCallback will only return events which have a higher eventId
function GuildHistoryLegacyEventListener:SetAfterEventId(eventId)
    if self.running then return false end

    local id = internal.ConvertLegacyId64ToEventId(eventId)
    if not id then return false end

    for _, processor in ipairs(self.processors) do
        processor:SetAfterEventId(id)
    end
    self.afterEventId = id
    return true
end

-- if no eventId has been specified, the nextEventCallback will only receive events after the specified timestamp
function GuildHistoryLegacyEventListener:SetAfterEventTime(eventTime)
    if self.running then return false end

    for _, processor in ipairs(self.processors) do
        processor:SetAfterEventTime(eventTime)
    end
    self.afterEventTime = eventTime
    return true
end

-- the highest desired eventId (id64). The nextEventCallback will only return events which have a lower eventId
function GuildHistoryLegacyEventListener:SetBeforeEventId(eventId)
    if self.running then return false end

    local id = internal.ConvertLegacyId64ToEventId(eventId)
    if not id then return false end

    for _, processor in ipairs(self.processors) do
        processor:SetBeforeEventId(id)
    end
    self.beforeEventId = id
    return true
end

-- if no eventId has been specified, the nextEventCallback will only receive events up to (including) the specified timestamp
function GuildHistoryLegacyEventListener:SetBeforeEventTime(eventTime)
    if self.running then return false end

    for _, processor in ipairs(self.processors) do
        processor:SetBeforeEventTime(eventTime + 1)
    end
    self.beforeEventTime = eventTime
    return true
end

-- convenience method to specify a range which includes the startTime and excludes the endTime
-- which is usually more desirable than the behaviour of SetAfterEventTime and SetBeforeEventTime which excludes the start time and includes the end time
function GuildHistoryLegacyEventListener:SetTimeFrame(startTime, endTime)
    if self.running then return false end

    for _, processor in ipairs(self.processors) do
        processor:SetAfterEventTime(startTime - 1)
        processor:SetBeforeEventTime(endTime)
    end
    return true
end

-- set a callback which is passed stored and received events in the correct historic order (sorted by eventId)
-- the callback will be handed the following parameters:
-- GuildEventType eventType -- the eventType
-- Id64 eventId -- the unique eventId
-- integer eventTime -- the timestamp for the event
-- variant param1 - 6 -- same as returned by GetGuildEventInfo
function GuildHistoryLegacyEventListener:SetNextEventCallback(callback)
    if self.running then return false end

    self.nextEventCallback = callback
    for _, processor in ipairs(self.processors) do
        processor:SetNextEventCallback(self.onEvent)
    end
    return true
end

-- set a callback which is passed events that had not previously been stored (sorted by eventId)
-- see SetNextEventCallback for information about the callback
function GuildHistoryLegacyEventListener:SetMissedEventCallback(callback)
    if self.running then return false end

    self.missedEventCallback = callback
    for _, processor in ipairs(self.processors) do
        processor:SetMissedEventCallback(self.onEvent)
    end
    return true
end

-- convenience method to set both callback types at once
-- see SetNextEventCallback for information about the callback
function GuildHistoryLegacyEventListener:SetEventCallback(callback)
    if self.running then return false end
    self:SetNextEventCallback(callback)
    self:SetMissedEventCallback(callback)
    return true
end

-- set a callback which is called when beforeEventId or beforeEventTime is reached and the listener is stopped
function GuildHistoryLegacyEventListener:SetIterationCompletedCallback(callback)
    if self.running then return false end

    self.iterationCompletedCallback = callback
    return true
end

-- sets if the listener should stop instead of listening for future events when it runs out of events before encountering the end criteria
function GuildHistoryLegacyEventListener:SetStopOnLastEvent(shouldStop)
    if self.running then return false end

    self.shouldStop = shouldStop
    return true
end

-- starts iterating over stored events and afterwards registers a listener for future events internally
function GuildHistoryLegacyEventListener:Start()
    if self.running then return false end

    self.iterationCompletedCount = 0
    self.cachedEvents = {}
    for _, processor in ipairs(self.processors) do
        if not processor:Start() then
            logger:Warn("Failed to start processor", processor:GetKey())
        end
    end

    for _, cache in ipairs(self.caches) do
        cache:RegisterProcessor(self)
    end

    self.running = true
    return true
end

-- stops iterating over stored events and unregisters the listener for future events
function GuildHistoryLegacyEventListener:Stop()
    return self:StopInternal()
end

-- returns true while iterating over or listening for events
function GuildHistoryLegacyEventListener:IsRunning()
    return self.running
end

-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

--- @meta LibHistoire

--- @class LibHistoire
local LibHistoire = {}

--- @class GuildHistoryEventProcessor
local GuildHistoryEventProcessor = {}

--- @class GuildHistoryLegacyEventListener
local GuildHistoryLegacyEventListener = {}

--- This function can be used to check if the library is ready to be used. It will return true after the INITIALIZED callback has been fired.
--- When the library is not ready yet, make sure to register to the INITIALIZED callback to know when it is.
--- @see Callbacks.INITIALIZED
--- @return boolean isReady True if the library is ready to be used, false otherwise.
function LibHistoire:IsReady() end

--- A convenience function to execute a callback when the library is ready. When the library is already initialized, the callback will be executed immediately.
--- @param callback fun(lib: LibHistoire) The function to call when the library is ready. It will receive the LibHistoire object as an argument.
--- @see Callbacks.INITIALIZED
--- @see LibHistoire.IsReady
function LibHistoire:OnReady(callback) end

--- @enum Callbacks
local Callbacks = {
    --- Fired when the library has finished setting everything up.
    --- Any calls to the api (aside of registering for the event) should happen after this has fired.
    --- It will receive the LibHistoire object as an argument.
    ---
    --- Keep in mind that this may fire before EVENT_ADD_ON_LOADED, so make sure to check if the library is ready before listening to the callback.
    --- @see LibHistoire.IsReady
    --- @type string
    INITIALIZED = "",

    --- @deprecated Rescan no longer exists.
    --- @type string
    HISTORY_RESCAN_STARTED = "",

    --- @deprecated Rescan no longer exists.
    --- @type string
    HISTORY_RESCAN_ENDED = "",

    --- @deprecated Use MANAGED_RANGE_LOST instead.
    --- @see Callbacks.MANAGED_RANGE_LOST
    --- @type string
    LINKED_RANGE_LOST = "",

    --- @deprecated Use MANAGED_RANGE_FOUND instead.
    --- @see Callbacks.MANAGED_RANGE_FOUND
    --- @type string
    LINKED_RANGE_FOUND = "",

    --- Fired when the managed range has been lost. The guildId and category are passed as arguments.
    --- This could be due to the cache being deleted, the library detecting inconsistencies in its own save data or the user manually resetting the range.
    --- @type string
    MANAGED_RANGE_LOST = "",

    --- Fired when a new managed range has been found. The guildId and category are passed as arguments.
    --- This happens when the managed range is established initially or after the managed range was lost.
    --- @type string
    MANAGED_RANGE_FOUND = "",

    --- @type string Fired when a category has linked the managed range to present events. The guildId and category are passed as arguments.
    CATEGORY_LINKED = "",
}

--- The exposed callbacks that can be used with RegisterCallback and UnregisterCallback.
--- @see Callbacks
--- @see LibHistoire.RegisterCallback
--- @see LibHistoire.UnregisterCallback
LibHistoire.callback = Callbacks

--- Register to a callback fired by the library. Usage is the same as with ZO_CallbackObject.RegisterCallback. You can find the list of exposed callbacks in api.lua
--- @param callbackName Callbacks One of the exposed callbacks.
--- @param callback function The function to call when the callback is fired.
--- @see Callbacks
function LibHistoire:RegisterCallback(callbackName, callback, ...) end

--- Unregister from a callback fired by the library. Usage is the same as with ZO_CallbackObject.UnregisterCallback.
--- @param callbackName Callbacks One of the exposed callbacks.
--- @param callback function The function to unregister.
--- @see Callbacks
function LibHistoire:UnregisterCallback(callbackName, callback, ...) end

--- Creates a legacy listener object which emulates the old guild history api. See guildHistoryCache/GuildHistoryLegacyEventListener.lua for details.
--- It's highly recommended to transition to CreateGuildHistoryProcessor instead, to take better advantage of the new history api.
--- @deprecated This method will be removed in a future version. Use CreateGuildHistoryProcessor instead.
--- @see GuildHistoryLegacyEventListener
--- @see LibHistoire.CreateGuildHistoryProcessor
--- @param guildId integer The id of the guild to listen to.
--- @param category integer The legacy category to listen to. One of the GUILD_HISTORY_* constants. See guildHistoryCache/compatibility.lua for details.
--- @return GuildHistoryLegacyEventListener|nil listener The created listener object or nil if no caches were found for the provided guildId and category.
function LibHistoire:CreateGuildHistoryListener(guildId, category) end

--- Creates a processor object which can be configured before it starts sending history events to an addon. See guildHistoryCache/GuildHistoryEventProcessor.lua for details.
--- @see GuildHistoryEventProcessor
--- @param guildId integer The id of the guild to process history events for.
--- @param category GuildHistoryEventCategory The category to process history events for.
--- @param addonName string The name of the addon that is processing the events. This is used to allow users to identify addons that are registered to a category, as well as to provide better logging.
--- @return GuildHistoryEventProcessor|nil processor The created processor object or nil if no caches were found for the provided guildId and category.
function LibHistoire:CreateGuildHistoryProcessor(guildId, category, addonName) end

--- Utility function to convert id64s that have been artificially created by a legacy listener to the new id53 equivalent.
--- Should be used one time only to convert all id64s that have been stored by the addon when switching to the new event processor api, since it's not the fastest operation.
--- @param id64 string The id64 to convert.
--- @return integer53|nil id53 The converted id53 or nil if the id64 cannot be converted.
function LibHistoire:ConvertArtificialLegacyId64ToEventId(id64) end

--- @enum StopReason
local StopReason = {
    --- Stop has been called by the addon
    --- @see GuildHistoryEventProcessor.Stop
    --- @type string
    MANUAL_STOP = "",

    --- The stopOnLastCachedEvent flag has been set and the last cached event was reached
    --- @see GuildHistoryEventProcessor.SetStopOnLastCachedEvent
    --- @type string
    LAST_CACHED_EVENT_REACHED = "",

    --- An end condition has been set and the first event outside of the specified range was encountered
    --- @see GuildHistoryEventProcessor.SetBeforeEventId
    --- @see GuildHistoryEventProcessor.SetBeforeEventTime
    --- @type string
    ITERATION_COMPLETED = "",

    --- The managed range was lost (fires right after MANAGED_RANGE_LOST callback)
    --- @see Callbacks.MANAGED_RANGE_LOST
    --- @type string
    MANAGED_RANGE_LOST = "",
}

--- Enumeration of the possible stop reasons passed to the onStopCallback of a GuildHistoryEventProcessor
--- @see StopReason
--- @see GuildHistoryEventProcessor.SetOnStopCallback
LibHistoire.StopReason = StopReason



--- Returns the name of the addon that created the processor.
--- @return string addonName The name of the addon that created the processor.
function GuildHistoryEventProcessor:GetAddonName() end

--- Returns a key consisting of server, guild id and history category, which can be used to store the last received eventId.
--- @return string key The key that identifies the processor.
function GuildHistoryEventProcessor:GetKey() end

--- Returns the guild id.
--- @return integer guildId The id of the guild the processor is listening to.
function GuildHistoryEventProcessor:GetGuildId() end

--- Returns the category.
--- @return GuildHistoryEventCategory category The event category the processor is listening to.
function GuildHistoryEventProcessor:GetCategory() end

--- Returns information about history events that need to be sent to the processor.
--- @return integer numEventsRemaining The amount of queued history events that are currently waiting to be processed by the processor.
--- @return integer processingSpeed The processing speed in events per second (rolling average over 5 seconds).
--- @return integer timeLeft The estimated time in seconds it takes to process the remaining events or -1 if it cannot be estimated.
function GuildHistoryEventProcessor:GetPendingEventMetrics() end

--- Allows to specify a start condition. The nextEventCallback will only return events which have a higher eventId.
--- @param eventId integer53 An eventId to start after.
--- @return boolean success true if the condition was set successfully, false if the processor is already running.
function GuildHistoryEventProcessor:SetAfterEventId(eventId) end

--- Allows to specify a start condition. The nextEventCallback will only receive events after the specified timestamp. Only is considered if no afterEventId has been specified.
--- @param eventTime integer53 A timestamp to start after.
--- @return boolean success true if the condition was set successfully, false if the processor is already running.
function GuildHistoryEventProcessor:SetAfterEventTime(eventTime) end

--- Allows to specify an end condition. The nextEventCallback will only return events which have a lower eventId.
--- @param eventId integer53 An eventId to end before.
--- @return boolean success true if the condition was set successfully, false if the processor is already running.
function GuildHistoryEventProcessor:SetBeforeEventId(eventId) end

--- Allows to specify an end condition. The nextEventCallback will only return events which have a lower timestamp. Only is considered if no beforeEventId has been specified.
--- @param eventTime integer53 A timestamp to end before.
--- @return boolean success true if the condition was set successfully, false if the processor is already running.
function GuildHistoryEventProcessor:SetBeforeEventTime(eventTime) end

--- Sets a callback which will get passed all events in the specified range in the correct historic order (sorted by eventId).
--- The callback will be handed an event object (see guildhistory_data.lua) which must not be stored or modified, as it can change after the function returns.
--- @see ZO_GuildHistoryEventData_Base
--- @param callback fun(event: ZO_GuildHistoryEventData_Base) The function that will be called for each event that is processed.
--- @return boolean success true if the condition was set successfully, false if the processor is already running.
function GuildHistoryEventProcessor:SetNextEventCallback(callback) end

--- Sets a callback which will get passed events that had not previously been included in the managed range, but are inside the start and end criteria. The order of the events is not guaranteed.
--- If SetReceiveMissedEventsOutsideIterationRange is set to true, this callback will also receive events that are outside of the specified iteration range.
--- The callback will be handed an event object (see guildhistory_data.lua) which must not be stored or modified, as it can change after the function returns.
--- @see ZO_GuildHistoryEventData_Base
--- @see GuildHistoryEventProcessor.SetReceiveMissedEventsOutsideIterationRange
--- @param callback fun(event: ZO_GuildHistoryEventData_Base) The function that will be called for each missed event that was found.
--- @return boolean success true if the condition was set successfully, false if the processor is already running.
function GuildHistoryEventProcessor:SetMissedEventCallback(callback) end

--- Convenience method to set both callback types at once.
--- @see GuildHistoryEventProcessor.SetNextEventCallback
--- @see GuildHistoryEventProcessor.SetMissedEventCallback
--- @param callback fun(event: ZO_GuildHistoryEventData_Base) The function that will be called for each missed event that was found.
--- @return boolean success true if the condition was set successfully, false if the processor is already running.
function GuildHistoryEventProcessor:SetEventCallback(callback) end

--- Set a callback which is called after the listener has stopped.
--- Receives a reason (see lib.StopReason) why the processor has stopped.
--- @see LibHistoire.StopReason
--- @param callback fun(reason: StopReason) The function that will be called when the processor stops.
--- @return boolean success true if the condition was set successfully, false if the processor is already running.
function GuildHistoryEventProcessor:SetOnStopCallback(callback) end

--- Controls if the processor should stop instead of listening for future events when it runs out of events before encountering an end criteria.
--- @param shouldStop boolean true if the processor should stop when it runs out of events, false if it should wait for future events.
--- @return boolean success true if the condition was set successfully, false if the processor is already running.
function GuildHistoryEventProcessor:SetStopOnLastCachedEvent(shouldStop) end

--- Sets a callback which is called when the processor starts waiting for future events.
--- @param callback function The function that will be called when the processor starts waiting for future events.
--- @return boolean success true if the condition was set successfully, false if the processor is already running.
function GuildHistoryEventProcessor:SetRegisteredForFutureEventsCallback(callback) end

--- Controls if the processor should forward missed events outside of the specified iteration range to the missedEventCallback.
--- @see GuildHistoryEventProcessor.SetMissedEventCallback
--- @param shouldReceive boolean true if missed events outside of the specified iteration range should be forwarded, false if they should be ignored.
--- @return boolean success true if the condition was set successfully, false if the processor is already running.
function GuildHistoryEventProcessor:SetReceiveMissedEventsOutsideIterationRange(shouldReceive) end

--- Starts the processor and passes events to the specified callbacks asyncronously. The exact behavior depends on the set conditions and callbacks.
--- @return boolean started true if the processor was started successfully, false if it is already running.
function GuildHistoryEventProcessor:Start() end

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
function GuildHistoryEventProcessor:StartIteratingTimeRange(startTime, endTime, eventCallback, finishedCallback) end

--- Convenience method to start the processor with a callback and optionally only receive events after the specified eventId.
--- @param lastProcessedId integer53|nil The last eventId that was processed by the addon or nil to start with the oldest managed event.
--- @param eventCallback fun(event: ZO_GuildHistoryEventData_Base) The function that will be called for each event that is processed. If not provided here, it has to be set with SetNextEventCallback beforehand, or the processor won't start.
--- @return boolean started true if the processor was started successfully, false if it is already running.
function GuildHistoryEventProcessor:StartStreaming(lastProcessedId, eventCallback) end

--- Stops iterating over stored events and unregisters the processor for future events.
--- @return boolean stopped true if the processor was stopped successfully, false if it is not running.
function GuildHistoryEventProcessor:Stop() end

--- Returns true while iterating over or listening for events.
--- @return boolean running true if the processor is currently running.
function GuildHistoryEventProcessor:IsRunning() end

-- SPDX-FileCopyrightText: 2025 sirinsidiator
--
-- SPDX-License-Identifier: Artistic-2.0

--- @module "guildHistoryCache.GuildHistoryLegacyEventListener"
--- @module "guildHistoryCache.GuildHistoryEventProcessor"

--- @class LibHistoire
local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

--- public api

--- This function can be used to check if the library is ready to be used. It will return true after the INITIALIZED callback has been fired.
--- When the library is not ready yet, make sure to register to the INITIALIZED callback to know when it is.
--- @see Callbacks.INITIALIZED
--- @return boolean isReady True if the library is ready to be used, false otherwise.
function lib:IsReady()
    return internal.initialized
end

--- This function returns false while the guild history system is unavailable. 
--- It's currently based on hardcoded data, which may not be 100% accurate and will require the library to be updated by the user.
--- @return boolean isDisabled True if the guild history system is disabled, false otherwise.
function lib:IsGuildHistorySystemDisabled()
    return internal:IsGuildHistorySystemDisabled()
end

--- A convenience function to execute a callback when the library is ready. When the library is already initialized, the callback will be executed immediately.
--- @param callback fun(lib: LibHistoire) The function to call when the library is ready. It will receive the LibHistoire object as an argument.
--- @see Callbacks.INITIALIZED
--- @see LibHistoire.IsReady
function lib:OnReady(callback)
    if internal.initialized then
        callback(self)
    else
        internal:RegisterCallback(internal.callback.INITIALIZED, callback)
    end
end

--- @enum Callbacks
local Callbacks = {
    --- Fired when the library has finished setting everything up.
    --- Any calls to the api (aside of registering for the event) should happen after this has fired.
    --- It will receive the LibHistoire object as an argument.
    ---
    --- Keep in mind that this may fire before EVENT_ADD_ON_LOADED, so make sure to check if the library is ready before listening to the callback.
    --- @see LibHistoire.IsReady
    --- @type string
    INITIALIZED = internal.callback.INITIALIZED,

    --- @deprecated Rescan no longer exists.
    --- @type string
    HISTORY_RESCAN_STARTED = internal.callback.DEPRECATED,

    --- @deprecated Rescan no longer exists.
    --- @type string
    HISTORY_RESCAN_ENDED = internal.callback.DEPRECATED,

    --- @deprecated Use MANAGED_RANGE_LOST instead.
    --- @see Callbacks.MANAGED_RANGE_LOST
    --- @type string
    LINKED_RANGE_LOST = internal.callback.MANAGED_RANGE_LOST,

    --- @deprecated Use MANAGED_RANGE_FOUND instead.
    --- @see Callbacks.MANAGED_RANGE_FOUND
    --- @type string
    LINKED_RANGE_FOUND = internal.callback.MANAGED_RANGE_FOUND,

    --- Fired when the managed range has been lost. The guildId and category are passed as arguments.
    --- This could be due to the cache being deleted, the library detecting inconsistencies in its own save data or the user manually resetting the range.
    --- @type string
    MANAGED_RANGE_LOST = internal.callback.MANAGED_RANGE_LOST,

    --- Fired when a new managed range has been found. The guildId and category are passed as arguments.
    --- This happens when the managed range is established initially or after the managed range was lost.
    --- @type string
    MANAGED_RANGE_FOUND = internal.callback.MANAGED_RANGE_FOUND,

    --- @type string Fired when a category has linked the managed range to present events. The guildId and category are passed as arguments.
    CATEGORY_LINKED = internal.callback.CATEGORY_LINKED,
}

--- The exposed callbacks that can be used with RegisterCallback and UnregisterCallback.
--- @see Callbacks
--- @see LibHistoire.RegisterCallback
--- @see LibHistoire.UnregisterCallback
lib.callback = Callbacks

--- Register to a callback fired by the library. Usage is the same as with ZO_CallbackObject.RegisterCallback. You can find the list of exposed callbacks in api.lua
--- @param callbackName Callbacks One of the exposed callbacks.
--- @param callback function The function to call when the callback is fired.
--- @see Callbacks
function lib:RegisterCallback(callbackName, callback, ...)
    return internal:RegisterCallback(callbackName, callback, ...)
end

--- Unregister from a callback fired by the library. Usage is the same as with ZO_CallbackObject.UnregisterCallback.
--- @param callbackName Callbacks One of the exposed callbacks.
--- @param callback function The function to unregister.
--- @see Callbacks
function lib:UnregisterCallback(callbackName, callback, ...)
    return internal:UnregisterCallback(callbackName, callback, ...)
end

--- Creates a legacy listener object which emulates the old guild history api. See guildHistoryCache/GuildHistoryLegacyEventListener.lua for details.
--- It's highly recommended to transition to CreateGuildHistoryProcessor instead, to take better advantage of the new history api.
--- @deprecated This method will be removed in a future version. Use CreateGuildHistoryProcessor instead.
--- @see GuildHistoryLegacyEventListener
--- @see LibHistoire.CreateGuildHistoryProcessor
--- @param guildId integer The id of the guild to listen to.
--- @param category integer The legacy category to listen to. One of the GUILD_HISTORY_* constants. See guildHistoryCache/compatibility.lua for details.
--- @return GuildHistoryLegacyEventListener|nil listener The created listener object or nil if no caches were found for the provided guildId and category.
function lib:CreateGuildHistoryListener(guildId, category)
    local listener = nil
    logger:Warn("No addon name provided for guild history listener - creating a legacy listener")
    local caches = internal.GetCachesForLegacyCategory(guildId, category)
    if #caches > 0 then
        listener = internal.class.GuildHistoryLegacyEventListener:New(guildId, category, caches)
    else
        logger:Warn("No category caches found for guild", guildId, "and legacy category", category)
    end
    return listener
end

--- Creates a processor object which can be configured before it starts sending history events to an addon. See guildHistoryCache/GuildHistoryEventProcessor.lua for details.
--- @see GuildHistoryEventProcessor
--- @param guildId integer The id of the guild to process history events for.
--- @param category GuildHistoryEventCategory The category to process history events for.
--- @param addonName string The name of the addon that is processing the events. This is used to allow users to identify addons that are registered to a category, as well as to provide better logging.
--- @return GuildHistoryEventProcessor|nil processor The created processor object or nil if no caches were found for the provided guildId and category.
function lib:CreateGuildHistoryProcessor(guildId, category, addonName)
    local processor = nil
    local categoryCache = internal.historyCache:GetCategoryCache(guildId, category)
    if categoryCache then
        processor = internal.class.GuildHistoryEventProcessor:New(categoryCache, addonName)
    else
        logger:Warn("No category cache found for guild", guildId, "and category", category)
    end
    return processor
end

--- Utility function to convert id64s that have been artificially created by a legacy listener to the new id53 equivalent.
--- Should be used one time only to convert all id64s that have been stored by the addon when switching to the new event processor api, since it's not the fastest operation.
--- @param id64 string The id64 to convert.
--- @return integer53|nil id53 The converted id53 or nil if the id64 cannot be converted.
function lib:ConvertArtificialLegacyId64ToEventId(id64)
    return internal.ConvertLegacyId64ToEventId(id64)
end

--- @enum StopReason
local StopReason = {
    --- Stop has been called by the addon
    --- @see GuildHistoryEventProcessor.Stop
    --- @type string
    MANUAL_STOP = internal.STOP_REASON_MANUAL_STOP,

    --- The stopOnLastCachedEvent flag has been set and the last cached event was reached
    --- @see GuildHistoryEventProcessor.SetStopOnLastCachedEvent
    --- @type string
    LAST_CACHED_EVENT_REACHED = internal.STOP_REASON_LAST_CACHED_EVENT_REACHED,

    --- An end condition has been set and the first event outside of the specified range was encountered
    --- @see GuildHistoryEventProcessor.SetBeforeEventId
    --- @see GuildHistoryEventProcessor.SetBeforeEventTime
    --- @type string
    ITERATION_COMPLETED = internal.STOP_REASON_ITERATION_COMPLETED,

    --- The managed range was lost (fires right after MANAGED_RANGE_LOST callback)
    --- @see Callbacks.MANAGED_RANGE_LOST
    --- @type string
    MANAGED_RANGE_LOST = internal.STOP_REASON_MANAGED_RANGE_LOST,
}

--- Enumeration of the possible stop reasons passed to the onStopCallback of a GuildHistoryEventProcessor
--- @see StopReason
--- @see GuildHistoryEventProcessor.SetOnStopCallback
lib.StopReason = StopReason

internal:Initialize()

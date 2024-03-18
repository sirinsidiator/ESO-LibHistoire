-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

-- exposed callbacks
lib.callback = {
    -- fired when the library has finished setting everything up
    -- any calls to the api (aside of registering for the event) should happen after this has fired
    INITIALIZED = internal.callback.INITIALIZED,
    --- @deprecated rescan is no longer needed
    HISTORY_RESCAN_STARTED = "deprecated",
    --- @deprecated rescan is no longer needed
    HISTORY_RESCAN_ENDED = "deprecated",
    --- @deprecated use MANAGED_RANGE_LOST instead
    LINKED_RANGE_LOST = internal.callback.MANAGED_RANGE_LOST,
    --- @deprecated use MANAGED_RANGE_FOUND instead
    LINKED_RANGE_FOUND = internal.callback.MANAGED_RANGE_FOUND,
    -- fired when the managed range has been lost
    -- this could be due to the cache being deleted, the lib detecting inconsistencies in its own save data or the user manually resetting the range
    MANAGED_RANGE_LOST = internal.callback.MANAGED_RANGE_LOST,
    -- fired when a new managed range has been found
    -- this happens when the managed range is established initially or after the managed range was lost
    MANAGED_RANGE_FOUND = internal.callback.MANAGED_RANGE_FOUND,
}

-- Register to a callback fired by the library. Usage is the same as with CALLBACK_MANAGER:RegisterCallback. You can find the list of exposed callbacks in api.lua
function lib:RegisterCallback(...)
    return internal:RegisterCallback(...)
end

-- Unregister from a callback. Usage is the same as with CALLBACK_MANAGER:UnregisterCallback.
function lib:UnregisterCallback(...)
    return internal:UnregisterCallback(...)
end

--- Creates a deprecated legacy listener object which can be configured before it starts listening to history events. See guildHistory/GuildHistoryEventProcessor.lua for details
--- @deprecated Use CreateGuildHistoryProcessor instead
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

-- Creates a processor object which can be configured before it starts sending history events to an addon. See guildHistory/GuildHistoryEventProcessor.lua for details
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

-- Function to convert id64s that have been artificially created by a legacy listener to the new id53 equivalent. Returns nil if the id64 cannot be converted.
lib.ConvertArtificialLegacyId64ToEventId = internal.ConvertLegacyId64ToEventId

internal:Initialize()

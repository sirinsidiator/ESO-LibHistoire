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
    -- fired when the linked range has been lost
    -- this could be due to the cache being deleted or the lib detecting inconsistencies in its own save data
    LINKED_RANGE_LOST = internal.callback.LINKED_RANGE_LOST,
    -- fired when a new linked range has been found
    -- this happens when the linked range is established initially or after the linked range was lost
    LINKED_RANGE_FOUND = internal.callback.LINKED_RANGE_FOUND,
}

-- Register to a callback fired by the library. Usage is the same as with CALLBACK_MANAGER:RegisterCallback. You can find the list of exposed callbacks in api.lua
function lib:RegisterCallback(...)
    return internal:RegisterCallback(...)
end

-- Unregister from a callback. Usage is the same as with CALLBACK_MANAGER:UnregisterCallback.
function lib:UnregisterCallback(...)
    return internal:UnregisterCallback(...)
end

-- Creates a listener object which can be configured before it starts listening to history events. See guildHistory/GuildHistoryEventListener.lua for details
function lib:CreateGuildHistoryListener(guildId, category, addonName)
    local listener = nil
    if not addonName then
        logger:Warn("No addon name provided for guild history listener - creating a legacy listener")
        local caches = internal.GetCachesForLegacyCategory(guildId, category)
        if #caches > 0 then
            listener = internal.class.GuildHistoryLegacyEventListener:New(guildId, category, caches)
        else
            logger:Warn("No category caches found for guild", guildId, "and legacy category", category)
        end
    else
        local categoryCache = internal.historyCache:GetCategoryCache(guildId, category)
        if categoryCache then
            listener = internal.class.GuildHistoryEventListener:New(categoryCache)
        else
            logger:Warn("No category cache found for guild", guildId, "and category", category)
        end
    end
    return listener
end

-- Function to convert id64s that have been artificially created by a legacy listener to the new id53 equivalent. Returns nil if the id64 cannot be converted.
lib.ConvertArtificialLegacyId64ToEventId = internal.ConvertLegacyId64ToEventId

internal:Initialize()

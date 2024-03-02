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

internal:Initialize()

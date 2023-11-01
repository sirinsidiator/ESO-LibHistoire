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
    -- fired when a category rescan is about to start
    -- passes the guildId and category to the callback
    HISTORY_RESCAN_STARTED = internal.callback.HISTORY_RESCAN_STARTED,
    -- fired after a category rescan has finished
    -- passes the guildId and category as well as the number of events that have been added before,
    -- inside and after the stored history and a boolean in case invalid events have been detected and the rescan aborted early
    HISTORY_RESCAN_ENDED = internal.callback.HISTORY_RESCAN_ENDED,
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
function lib:CreateGuildHistoryListener(guildId, category)
    if GetAPIVersion() >= 101041 then
        return internal.class.GuildHistoryNoopListener:New(guildId, category)
    end

    local listener = nil
    if internal.historyCache:HasCategoryCache(guildId, category) then
        local categoryCache = internal.historyCache:GetOrCreateCategoryCache(guildId, category)
        listener = internal.class.GuildHistoryEventListener:New(categoryCache)
    end
    return listener
end

internal:Initialize()

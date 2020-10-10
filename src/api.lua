-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

function lib:CreateGuildHistoryListener(guildId, category)
    local listener = nil
    if internal.historyCache:HasCategoryCache(guildId, category) then
        local categoryCache = internal.historyCache:GetOrCreateCategoryCache(guildId, category)
        listener = internal.class.GuildHistoryEventListener:New(categoryCache)
    end
    return listener
end

internal:Initialize()

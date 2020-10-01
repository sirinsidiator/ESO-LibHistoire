-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local GuildHistoryCache = ZO_Object:Subclass()
internal.class.GuildHistoryCache = GuildHistoryCache

local GuildHistoryCacheCategory = internal.class.GuildHistoryCacheCategory
local GuildHistoryCacheEntry = internal.class.GuildHistoryCacheEntry
local RegisterForEvent = internal.RegisterForEvent


local GUILD_HISTORY_CATEGORIES = {
    GUILD_HISTORY_ALLIANCE_WAR,
    GUILD_HISTORY_BANK,
    GUILD_HISTORY_COMBAT,
    GUILD_HISTORY_GENERAL,
    GUILD_HISTORY_STORE
}

function GuildHistoryCache:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function GuildHistoryCache:Initialize(nameCache, saveData)
    self.nameCache = nameCache
    self.saveData = saveData
    self.cache = {}

    RegisterForEvent(EVENT_GUILD_HISTORY_REFRESHED, function()
        logger:Info("EVENT_GUILD_HISTORY_REFRESHED")
    end)
    RegisterForEvent(EVENT_GUILD_HISTORY_CATEGORY_UPDATED, function(_, guildId, category)
        logger:Info("EVENT_GUILD_HISTORY_CATEGORY_UPDATED")
        self:OnEventsReceived(guildId, category)
    end)
    RegisterForEvent(EVENT_GUILD_HISTORY_RESPONSE_RECEIVED, function(_, guildId, category)
        logger:Info("EVENT_GUILD_HISTORY_RESPONSE_RECEIVED")
        self:OnEventsReceived(guildId, category)
    end)

    self:UpdateAllCategories()
end

function GuildHistoryCache:UpdateAllCategories()
    logger:Info("UpdateAllCategories")
    for i = 1, #GUILD_HISTORY_CATEGORIES do -- TODO should use LibAsync to process all
        local category = GUILD_HISTORY_CATEGORIES[i]
        for index = 1, GetNumGuilds() do
            local guildId = GetGuildId(index)
            logger:Info("update %d for %d", category, guildId)
            if HasGuildHistoryCategoryEverBeenRequested(guildId, category) then
                self:OnEventsReceived(guildId, category)
            end
        end
    end
end

function GuildHistoryCache:OnEventsReceived(guildId, category)
    self:GetOrCreateCategoryCache(guildId, category):ReceiveEvents()
end

function GuildHistoryCache:GetOrCreateCategoryCache(guildId, category)
    if not self.cache[guildId] then
        self.cache[guildId] = {}
        logger:Info("create cache for guild %s (%d)", GetGuildName(guildId), guildId)
    end
    local guildCache = self.cache[guildId]
    if not guildCache[category] then
        guildCache[category] = GuildHistoryCacheCategory:New(self.nameCache, self.saveData, guildId, category)
        logger:Info("create cache for category %d in guild %s (%d)", category, GetGuildName(guildId), guildId)
    end
    return guildCache[category]
end

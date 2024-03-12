-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local GuildHistoryCache = ZO_InitializingObject:Subclass()
internal.class.GuildHistoryCache = GuildHistoryCache

local GuildHistoryCacheGuild = internal.class.GuildHistoryCacheGuild

function GuildHistoryCache:Initialize(adapter, manager, saveData)
    self.saveData = saveData
    self.manager = manager
    self.requestManager = internal.class.GuildHistoryServerRequestManager:New()
    self.cache = {}

    local function CreateGuildCache(guildId)
        local guildData = manager:GetGuildData(guildId)
        self.cache[guildId] = GuildHistoryCacheGuild:New(adapter, self.requestManager, saveData, guildData)
    end

    for i = 1, GetNumGuilds() do
        local guildId = GetGuildId(i)
        CreateGuildCache(guildId)
    end

    internal.RegisterForEvent(EVENT_GUILD_SELF_JOINED_GUILD, function(_, guildId)
        CreateGuildCache(guildId)
    end)

    -- TODO get a list of all guilds in the cache that we are not currently in if the setting to keep history for all guilds is enabled

    manager:RegisterCallback("CategoryUpdated", function(categoryData, flags)
        local guildId = categoryData:GetGuildData():GetId()
        local category = categoryData:GetEventCategory()
        local categoryCache = self:GetCategoryCache(guildId, category)
        categoryCache:OnCategoryUpdated(flags)
        self.requestManager:RequestSendNext()
    end)
end

function GuildHistoryCache:ForEachActiveGuild(func)
    for i = 1, GetNumGuilds() do
        local guildId = GetGuildId(i)
        local guildCache = self:GetGuildCache(guildId)
        if guildCache and func(guildCache) then
            return
        end
    end
end

function GuildHistoryCache:StartRequests()
    self:ForEachActiveGuild(function(guildCache)
        guildCache:StartRequests()
    end)
end

function GuildHistoryCache:VerifyRequests()
    self:ForEachActiveGuild(function(guildCache)
        guildCache:VerifyRequests()
    end)
end

function GuildHistoryCache:DeleteRequests()
    self:ForEachActiveGuild(function(guildCache)
        guildCache:DeleteRequests()
    end)
end

function GuildHistoryCache:HasLinkedAllCaches()
    local allLinked = true
    self:ForEachActiveGuild(function(guildCache)
        if not guildCache:HasLinked() then
            allLinked = false
            return true -- break
        end
    end)
    return allLinked
end

function GuildHistoryCache:IsProcessing()
    local isProcessing = false
    self:ForEachActiveGuild(function(guildCache)
        if guildCache:IsProcessing() then
            isProcessing = true
            return true -- break
        end
    end)
    return isProcessing
end

function GuildHistoryCache:GetGuildCache(guildId)
    return self.cache[guildId]
end

function GuildHistoryCache:GetCategoryCache(guildId, category)
    local guildCache = self:GetGuildCache(guildId)
    if not guildCache then
        return
    end
    local categoryCache = guildCache:GetCategoryCache(category)
    return categoryCache
end

function GuildHistoryCache:Shutdown()
    self.requestManager:Shutdown()
end
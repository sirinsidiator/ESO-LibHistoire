-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local GuildHistoryCache = ZO_InitializingObject:Subclass()
internal.class.GuildHistoryCache = GuildHistoryCache

local GuildHistoryCacheGuild = internal.class.GuildHistoryCacheGuild

function GuildHistoryCache:Initialize(adapter, manager)
    self.requestManager = internal.class.GuildHistoryServerRequestManager:New()
    self.cache = {}

    local function CreateGuildCache(guildId)
        local guildData = manager:GetGuildData(guildId)
        self.cache[guildId] = GuildHistoryCacheGuild:New(adapter, self.requestManager, guildData)
    end

    for i = 1, GetNumGuilds() do
        local guildId = GetGuildId(i)
        CreateGuildCache(guildId)
    end

    if adapter:IsAutoDeleteLeftGuildsEnabled() then
        adapter:DeleteInactiveCacheSaveData()
    end

    internal.RegisterForEvent(EVENT_GUILD_SELF_JOINED_GUILD, function(_, guildId)
        CreateGuildCache(guildId)
    end)

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
    logger:Debug("VerifyRequests")
    self:ForEachActiveGuild(function(guildCache)
        guildCache:VerifyRequests()
    end)
    logger:Debug("VerifyRequests done")
    self.requestManager:RequestSendNext()
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

function GuildHistoryCache:HasLinkedAllCachesRecently()
    local allLinked = true
    self:ForEachActiveGuild(function(guildCache)
        if not guildCache:HasLinkedRecently() then
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

function GuildHistoryCache:GetDebugInfo()
    local debugInfo = {}
    debugInfo.hasLinkedAllCaches = self:HasLinkedAllCaches()
    debugInfo.hasLinkedAllCachesRecently = self:HasLinkedAllCachesRecently()
    debugInfo.isProcessing = self:IsProcessing()
    debugInfo.guildCount = GetNumGuilds()
    debugInfo.guildCacheCount = NonContiguousCount(self.cache)

    debugInfo.activeGuilds = {}
    self:ForEachActiveGuild(function(guildCache)
        debugInfo.activeGuilds[#debugInfo.activeGuilds + 1] = guildCache:GetDebugInfo()
    end)

    debugInfo.requestManager = self.requestManager:GetDebugInfo()

    return debugInfo
end

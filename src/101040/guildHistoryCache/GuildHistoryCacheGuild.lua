-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local GuildHistoryCacheGuild = ZO_Object:Subclass()
internal.class.GuildHistoryCacheGuild = GuildHistoryCacheGuild

local GuildHistoryCacheCategory = internal.class.GuildHistoryCacheCategory

function GuildHistoryCacheGuild:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function GuildHistoryCacheGuild:Initialize(nameCache, saveData, guildId)
    self.nameCache = nameCache
    self.saveData = saveData
    self.guildId = guildId
    self.cache = {}
end

function GuildHistoryCacheGuild:HasCategoryCache(category)
    if not self.cache[category] then return false end
    return true
end

function GuildHistoryCacheGuild:GetOrCreateCategoryCache(category)
    if not self.cache[category] then
        self.cache[category] = GuildHistoryCacheCategory:New(self.nameCache, self.saveData, self.guildId, category)
    end
    return self.cache[category]
end

function GuildHistoryCacheGuild:GetProgress()
    local progress = 0
    local count = 0
    for _, cache in pairs(self.cache) do
        progress = progress + cache:GetProgress()
        count = count + 1
    end
    if count == 0 then
        return 0
    end
    return progress / count
end

function GuildHistoryCacheGuild:GetNumEvents()
    local count = 0
    for _, cache in pairs(self.cache) do
        count = count + cache:GetNumEvents()
    end
    return count
end

function GuildHistoryCacheGuild:GetOldestEvent()
    local oldest
    for _, cache in pairs(self.cache) do
        local event = cache:GetOldestEvent()
        if event and (not oldest or event:GetEventId() < oldest:GetEventId()) then
            oldest = event
        end
    end
    return oldest
end

function GuildHistoryCacheGuild:GetNewestEvent()
    local newest
    for _, cache in pairs(self.cache) do
        local event = cache:GetNewestEvent()
        if event and (not newest or event:GetEventId() > newest:GetEventId()) then
            newest = event
        end
    end
    return newest
end

function GuildHistoryCacheGuild:HasLinked()
    if not next(self.cache) then return false end
    for _, cache in pairs(self.cache) do
        if not cache:HasLinked() then return false end
    end
    return true
end

function GuildHistoryCacheGuild:IsProcessing()
    if not next(self.cache) then return false end
    for _, cache in pairs(self.cache) do
        if cache:IsProcessing() then return true end
    end
    return false
end

function GuildHistoryCacheGuild:IsAggregated()
    return true
end

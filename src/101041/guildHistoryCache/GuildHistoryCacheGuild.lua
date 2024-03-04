-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local GuildHistoryCacheGuild = ZO_InitializingObject:Subclass()
internal.class.GuildHistoryCacheGuild = GuildHistoryCacheGuild

local GuildHistoryCacheCategory = internal.class.GuildHistoryCacheCategory

function GuildHistoryCacheGuild:Initialize(adapter, saveData, guildData)
    self.saveData = saveData
    self.guildData = guildData
    self.guildId = guildData:GetId()
    self.cache = {}

    for eventCategory = GUILD_HISTORY_EVENT_CATEGORY_ITERATION_BEGIN, GUILD_HISTORY_EVENT_CATEGORY_ITERATION_END do
        local categoryData = guildData:GetEventCategoryData(eventCategory)
        if categoryData then
            self.cache[eventCategory] = GuildHistoryCacheCategory:New(adapter, saveData, categoryData)
        end
    end
end

function GuildHistoryCacheGuild:GetGuildId()
    return self.guildId
end

function GuildHistoryCacheGuild:StartRequests()
    for _, cache in pairs(self.cache) do
        cache:RequestMissingData()
    end
end

function GuildHistoryCacheGuild:VerifyRequests()
    for _, cache in pairs(self.cache) do
        cache:VerifyRequest()
    end
end

function GuildHistoryCacheGuild:SendRequests(newestTime, oldestTime)
    for _, cache in pairs(self.cache) do
        cache:CreateRequest(newestTime, oldestTime)
        cache:QueueRequest()
    end
end

function GuildHistoryCacheGuild:GetCategoryCache(eventCategory)
    return self.cache[eventCategory]
end

function GuildHistoryCacheGuild:GetProgress()
    local progress = 0
    local count = 0
    for _, cache in pairs(self.cache) do
        if cache:IsWatching() then
            progress = progress + cache:GetProgress()
            count = count + 1
        end
    end
    if count == 0 then
        return 0
    end
    return progress / count
end

function GuildHistoryCacheGuild:UpdateProgressBar(bar)
    local isProcessing = self:IsProcessing()
    local isRequesting = self:HasPendingRequests()
    if isProcessing or isRequesting then
        bar:SetValue(1)
    else
        local progress = self:GetProgress()
        bar:SetValue(progress)
    end

    local gradient
    if isProcessing then
        gradient = internal.GRADIENT_GUILD_PROCESSING
    elseif isRequesting then
        gradient = internal.GRADIENT_GUILD_REQUESTING
    elseif self:HasLinked() then
        gradient = internal.GRADIENT_GUILD_COMPLETED
    else
        gradient = internal.GRADIENT_GUILD_INCOMPLETE
    end
    bar:SetGradient(gradient)
end

function GuildHistoryCacheGuild:GetNumLinkedEvents()
    local count = 0
    for _, cache in pairs(self.cache) do
        count = count + cache:GetNumLinkedEvents()
    end
    return count
end

function GuildHistoryCacheGuild:GetOldestLinkedEvent()
    local oldest
    for _, cache in pairs(self.cache) do
        local event = cache:GetOldestLinkedEvent()
        if event and (not oldest or event:GetEventId() < oldest:GetEventId()) then
            oldest = event
        end
    end
    return oldest
end

function GuildHistoryCacheGuild:GetNewestLinkedEvent()
    local newest
    for _, cache in pairs(self.cache) do
        local event = cache:GetNewestLinkedEvent()
        if event and (not newest or event:GetEventId() > newest:GetEventId()) then
            newest = event
        end
    end
    return newest
end

function GuildHistoryCacheGuild:HasLinked()
    if not next(self.cache) then return false end
    for _, cache in pairs(self.cache) do
        if cache:IsWatching() and not cache:HasLinked() then return false end
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

function GuildHistoryCacheGuild:HasPendingRequests()
    if not next(self.cache) then return false end
    for _, cache in pairs(self.cache) do
        if cache:HasPendingRequest() then return true end
    end
    return false
end

function GuildHistoryCacheGuild:IsAggregated()
    return true
end

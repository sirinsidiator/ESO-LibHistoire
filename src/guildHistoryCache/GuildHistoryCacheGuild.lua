-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local LINK_TIMOUT_THRESHOLD = 60 * 60 * 24 * 7 -- 1 week

local GuildHistoryCacheGuild = ZO_InitializingObject:Subclass()
internal.class.GuildHistoryCacheGuild = GuildHistoryCacheGuild

local GuildHistoryCacheCategory = internal.class.GuildHistoryCacheCategory

function GuildHistoryCacheGuild:Initialize(adapter, requestManager, guildData)
    self.guildId = guildData:GetId()
    self.cache = {}

    for eventCategory = GUILD_HISTORY_EVENT_CATEGORY_ITERATION_BEGIN, GUILD_HISTORY_EVENT_CATEGORY_ITERATION_END do
        local categoryData = guildData:GetEventCategoryData(eventCategory)
        if categoryData then
            self.cache[eventCategory] = GuildHistoryCacheCategory:New(adapter, requestManager, categoryData)
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

function GuildHistoryCacheGuild:DeleteRequests()
    for _, cache in pairs(self.cache) do
        if cache.request then
            cache:DestroyRequest()
            logger:Debug("Deleted request for", cache.key)
        end
    end
end

function GuildHistoryCacheGuild:GetCategoryCache(eventCategory)
    return self.cache[eventCategory]
end

function GuildHistoryCacheGuild:GetProgress()
    local progress = 0
    local count = 0
    for _, cache in pairs(self.cache) do
        if cache:IsAutoRequesting() then
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

function GuildHistoryCacheGuild:GetNumLoadedManagedEvents()
    local count = 0
    for _, cache in pairs(self.cache) do
        count = count + cache:GetNumLoadedManagedEvents()
    end
    return count
end

function GuildHistoryCacheGuild:GetOldestManagedEventInfo()
    local oldestId, oldestTime
    for _, cache in pairs(self.cache) do
        local eventId, eventTime = cache:GetOldestManagedEventInfo()
        if eventId and (not oldestId or eventId < oldestId) then
            oldestId = eventId
            oldestTime = eventTime
        end
    end
    return oldestId, oldestTime
end

function GuildHistoryCacheGuild:GetNewestManagedEventInfo()
    local newestId, newestTime
    for _, cache in pairs(self.cache) do
        local eventId, eventTime = cache:GetNewestManagedEventInfo()
        if eventId and (not newestId or eventId > newestId) then
            newestId = eventId
            newestTime = eventTime
        end
    end
    return newestId, newestTime
end

function GuildHistoryCacheGuild:HasLinked()
    if not next(self.cache) then return false end
    for _, cache in pairs(self.cache) do
        if cache:IsAutoRequesting() and not cache:HasLinked() then return false end
    end
    return true
end

function GuildHistoryCacheGuild:HasLinkedRecently()
    if not next(self.cache) then return false end
    for _, cache in pairs(self.cache) do
        local linkTimeout = GetTimeStamp() - cache:GetLastLinkedTime()
        if cache:IsAutoRequesting() and cache:HasCachedEvents() and linkTimeout > LINK_TIMOUT_THRESHOLD then return false end
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

function GuildHistoryCacheGuild:GetDebugInfo()
    local debugInfo = {
        guildId = self.guildId,
        name = GetGuildName(self.guildId),
        hasLinked = self:HasLinked(),
        hasLinkedRecently = self:HasLinkedRecently(),
        isProcessing = self:IsProcessing(),
        hasPendingRequests = self:HasPendingRequests(),
        numLoadedManagedEvents = self:GetNumLoadedManagedEvents(),
    }

    local oldestId, oldestTime = self:GetOldestManagedEventInfo()
    if oldestId then
        debugInfo.oldestManagedEvent = {
            id = oldestId,
            time = oldestTime,
        }
    end

    local newestId, newestTime = self:GetNewestManagedEventInfo()
    if newestId then
        debugInfo.newestManagedEvent = {
            id = newestId,
            time = newestTime,
        }
    end

    debugInfo.categories = {}
    for eventCategory = GUILD_HISTORY_EVENT_CATEGORY_ITERATION_BEGIN, GUILD_HISTORY_EVENT_CATEGORY_ITERATION_END do
        local cache = self.cache[eventCategory]
        if cache then
            debugInfo.categories[eventCategory] = cache:GetDebugInfo()
        end
    end

    return debugInfo
end

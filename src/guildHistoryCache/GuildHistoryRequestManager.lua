-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local RegisterForEvent = internal.RegisterForEvent
local RegisterForUpdate = internal.RegisterForUpdate
local UnregisterForUpdate = internal.UnregisterForUpdate

local WATCHDOG_TIMER = 15000

local GuildHistoryRequestManager = ZO_Object:Subclass()
internal.class.GuildHistoryRequestManager = GuildHistoryRequestManager

function GuildHistoryRequestManager:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function GuildHistoryRequestManager:Initialize(cache)
    self.cache = cache
    self.queue = {}

    RegisterForEvent(EVENT_GUILD_HISTORY_REFRESHED, function()
        logger:Info("EVENT_GUILD_HISTORY_REFRESHED")
        -- happens when permissions change and events change visibility
        -- TODO handle this
    end)
    RegisterForEvent(EVENT_GUILD_HISTORY_RESPONSE_RECEIVED, function(_, guildId, category)
        logger:Info("EVENT_GUILD_HISTORY_RESPONSE_RECEIVED")
        local categoryCache = self.cache:GetOrCreateCategoryCache(guildId, category)
        categoryCache:ReceiveEvents()
        self:QueueRequest(categoryCache)
        self:SendNextRequest()
    end)
    RegisterForEvent(EVENT_GUILD_SELF_JOINED_GUILD, function(guildId)
        self:RefillQueueForGuild(guildId)
        self:Start()
        self:SendNextRequest()
    end)
    RegisterForEvent(EVENT_GUILD_SELF_LEFT_GUILD, function(guildId)
        -- TODO handle this
        end)

    local function ensureQueueIsActive()
        if #self.queue == 0 then
            self:RefillQueue()
        end
        if #self.queue == 0 then
            logger:Info("no more requests needed - UnregisterForUpdate")
            self:Stop()
            return
        end
        self:SendNextRequest()
    end
    self.ensureQueueIsActive = ensureQueueIsActive
    self:UpdateAllCategories()
    self:Start()
end

function GuildHistoryRequestManager:Start()
    if not self.watchDogHandle then
        self.watchDogHandle = RegisterForUpdate(WATCHDOG_TIMER, self.ensureQueueIsActive)
    end
end

function GuildHistoryRequestManager:Stop()
    if self.watchDogHandle then
        UnregisterForUpdate(self.watchDogHandle)
        self.watchDogHandle = nil
    end
end

local function ForEachCategory(callback, guildId)
    for category = 1, GetNumGuildHistoryCategories() do
        if GUILD_HISTORY_CATEGORIES[category] then
            callback(guildId, category)
        end
    end
end

local function ForEachGuildAndCategory(callback)
    for index = 1, GetNumGuilds() do
        local guildId = GetGuildId(index)
        ForEachCategory(callback, guildId)
    end
end

function GuildHistoryRequestManager:UpdateAllCategories()
    logger:Info("UpdateAllCategories")
    ForEachGuildAndCategory(function(guildId, category)
        if HasGuildHistoryCategoryEverBeenRequested(guildId, category) then
            local categoryCache = self.cache:GetOrCreateCategoryCache(guildId, category)
            categoryCache:ReceiveEvents()
        end
    end)
end

function GuildHistoryRequestManager:RefillQueue()
    logger:Info("RefillQueue")
    ForEachGuildAndCategory(function(guildId, category)
        local categoryCache = self.cache:GetOrCreateCategoryCache(guildId, category)
        self:QueueRequest(categoryCache)
    end)
end

function GuildHistoryRequestManager:RefillQueueForGuild(guildId)
    logger:Info("RefillQueueForGuild")
    ForEachCategory(function(_, category)
        local categoryCache = self.cache:GetOrCreateCategoryCache(guildId, category)
        self:QueueRequest(categoryCache)
    end)
end

function GuildHistoryRequestManager:QueueRequest(categoryCache)
    if not categoryCache:HasLinked() then
        logger:Info("QueueRequest for %d/%d", categoryCache.guildId, categoryCache.category)
        self.queue[#self.queue + 1] = categoryCache
    end
end

function GuildHistoryRequestManager:SendNextRequest()
    local categoryCache = self.queue[1]
    if not categoryCache then return end
    table.remove(self.queue, 1)

    local guildId, category = categoryCache.guildId, categoryCache.category
    local success = RequestMoreGuildHistoryCategoryEvents(categoryCache.guildId, categoryCache.category, true)
    logger:Info("SendNextRequest for %d/%d: %s", guildId, category, tostring(success))
end

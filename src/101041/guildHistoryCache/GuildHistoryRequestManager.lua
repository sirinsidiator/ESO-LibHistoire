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
        ForEachGuildAndCategory(function(guildId, category)
            local categoryCache = self.cache:GetOrCreateCategoryCache(guildId, category)
            if not HasGuildHistoryCategoryEverBeenRequested(guildId, category) or categoryCache.lastIndex ~= GetNumGuildEvents(guildId, category) then
                logger:Info("Detected reset of guild %s (%d) category %s (%d)", GetGuildName(guildId), guildId, GetString("SI_GUILDHISTORYCATEGORY", category), category)
                categoryCache:ResetUnlinkedEvents()
                self:QueueRequest(categoryCache)
                internal:FireCallbacks(internal.callback.HISTORY_RELOADED, guildId, category)
            end
        end)

        self:SendNextRequest()
        if #self.queue > 0 then
            self:Start()
        end
    end)

    RegisterForEvent(EVENT_GUILD_HISTORY_RESPONSE_RECEIVED, function(_, guildId, category)
        local categoryCache = self.cache:GetOrCreateCategoryCache(guildId, category)
        categoryCache:ReceiveEvents()
        self:QueueRequest(categoryCache)
        self:SendNextRequest()
    end)

    local guildNames = internal.guildNames
    for i = 1, GetNumGuilds() do
        local guildId = GetGuildId(i)
        guildNames[guildId] = GetGuildName(guildId)
    end
    RegisterForEvent(EVENT_GUILD_SELF_JOINED_GUILD, function(guildId)
        guildNames[guildId] = GetGuildName(guildId)
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
            logger:Verbose("No more requests needed")
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

function GuildHistoryRequestManager:UpdateAllCategories()
    ForEachGuildAndCategory(function(guildId, category)
        local categoryCache = self.cache:GetOrCreateCategoryCache(guildId, category)
        if HasGuildHistoryCategoryEverBeenRequested(guildId, category) then
            categoryCache:ReceiveEvents()
        end
    end)
end

function GuildHistoryRequestManager:RefillQueue()
    ForEachGuildAndCategory(function(guildId, category)
        local categoryCache = self.cache:GetOrCreateCategoryCache(guildId, category)
        self:QueueRequest(categoryCache)
    end)
end

function GuildHistoryRequestManager:RefillQueueForGuild(guildId)
    ForEachCategory(function(_, category)
        local categoryCache = self.cache:GetOrCreateCategoryCache(guildId, category)
        self:QueueRequest(categoryCache)
    end)
end

function GuildHistoryRequestManager:QueueRequest(categoryCache)
    if not categoryCache:HasLinked() then
        self.queue[#self.queue + 1] = categoryCache
    end
end

function GuildHistoryRequestManager:SendNextRequest()
    local categoryCache = self.queue[1]
    if not categoryCache or categoryCache:IsOnRequestCooldown() then return end
    table.remove(self.queue, 1)

    local success = categoryCache:SendRequest()
end

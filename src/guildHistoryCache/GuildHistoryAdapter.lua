-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local MAX_NUMBER_OF_DAYS_CVAR_SUFFIX = {
    [GUILD_HISTORY_EVENT_CATEGORY_ACTIVITY] = "activity",
    [GUILD_HISTORY_EVENT_CATEGORY_AVA_ACTIVITY] = "ava_activity",
    [GUILD_HISTORY_EVENT_CATEGORY_BANKED_CURRENCY] = "banked_currency",
    [GUILD_HISTORY_EVENT_CATEGORY_BANKED_ITEM] = "banked_item",
    [GUILD_HISTORY_EVENT_CATEGORY_MILESTONE] = "milestone",
    [GUILD_HISTORY_EVENT_CATEGORY_ROSTER] = "roster",
    [GUILD_HISTORY_EVENT_CATEGORY_TRADER] = "trader"
}
local SECONDS_PER_DAY = 60 * 60 * 24
local DEFAULT_MAX_CACHE_TIMERANGE = 30 * SECONDS_PER_DAY
local MAX_SERVER_TIMERANGE_FOR_CATEGORY = {}
for eventCategory = GUILD_HISTORY_EVENT_CATEGORY_ITERATION_BEGIN, GUILD_HISTORY_EVENT_CATEGORY_ITERATION_END do
    MAX_SERVER_TIMERANGE_FOR_CATEGORY[eventCategory] = DEFAULT_MAX_CACHE_TIMERANGE
end
MAX_SERVER_TIMERANGE_FOR_CATEGORY[GUILD_HISTORY_EVENT_CATEGORY_MILESTONE] = 180 * SECONDS_PER_DAY
MAX_SERVER_TIMERANGE_FOR_CATEGORY[GUILD_HISTORY_EVENT_CATEGORY_ROSTER] = 180 * SECONDS_PER_DAY

local GuildHistoryAdapter = ZO_InitializingObject:Subclass()
internal.class.GuildHistoryAdapter = GuildHistoryAdapter

function GuildHistoryAdapter:Initialize(saveData)
    self.machineWideSaveData = saveData
    self.accountSaveData = saveData[GetDisplayName()]
end

function GuildHistoryAdapter:GetOrCreateCacheSaveData(key)
    if self.machineWideSaveData[key] then
        logger:Info("Migrating machine wide save data for", key, "to account wide save data")
        self.accountSaveData[key] = self.machineWideSaveData[key]
        self.machineWideSaveData[key] = nil
    end
    local saveData = self.accountSaveData[key] or {}
    self.accountSaveData[key] = saveData
    return saveData
end

function GuildHistoryAdapter:InitializeDeferred(history, cache)
    self.history = history
    self.cache = cache
    self.selectedCategoryCache = cache:GetCategoryCache(history.guildId, history.selectedEventCategory)

    local function RefreshSelectedCategoryCache()
        local selectedCategoryCache = cache:GetCategoryCache(history.guildId, history.selectedEventCategory)
        if selectedCategoryCache ~= self.selectedCategoryCache then
            self.selectedCategoryCache = selectedCategoryCache
            internal:FireCallbacks(internal.callback.SELECTED_CATEGORY_CACHE_CHANGED, selectedCategoryCache)
        end
    end

    local guildSelectionProxy = {
        SetGuildId = RefreshSelectedCategoryCache
    }
    local guildWindows = GUILD_SELECTOR.guildWindows
    guildWindows[#guildWindows + 1] = guildSelectionProxy

    local function OnSelectionChanged(control, data, selected, reselectingDuringRebuild)
        if selected then
            RefreshSelectedCategoryCache()
        end
    end

    self.nodesByCategory = {}
    local categoryTree = history.categoryTree
    local root = categoryTree.rootNode
    for i = 1, #root.children do
        local child = root.children[i]
        if child.children then
            self.nodesByCategory[child.data.eventCategory] = child.children[1]
            for j = 1, #child.children do
                local leaf = child.children[j]
                SecurePostHook(leaf, "selectionFunction", OnSelectionChanged)
            end
        else
            self.nodesByCategory[child.data.eventCategory] = child
            SecurePostHook(child, "selectionFunction", OnSelectionChanged)
        end
    end
end

function GuildHistoryAdapter:SelectGuildByIndex(guildIndex)
    -- GUILD_SELECTOR:SelectGuildByIndex(guildIndex)
end

function GuildHistoryAdapter:SelectCategory(category)
    -- local node = self.nodesByCategory[category]
    -- if node then
    --     self.history.categoryTree:SelectNode(node)
    -- end
end

function GuildHistoryAdapter:GetSelectedCategoryCache()
    return self.selectedCategoryCache
end

function GuildHistoryAdapter:GetGuildHistoryEventIndicesForTimeRange(guildId, category, newestTime, oldestTime)
    assert(newestTime >= oldestTime, "newestTime must be greater or equal to oldestTime")
    return GetGuildHistoryEventIndicesForTimeRange(guildId, category, newestTime, oldestTime)
end

function GuildHistoryAdapter:GetGuildHistoryCacheMaxTime(category)
    local days = GetCVar("GuildHistoryCacheMaxNumberOfDays_" .. MAX_NUMBER_OF_DAYS_CVAR_SUFFIX[category])
    return days and tonumber(days) * SECONDS_PER_DAY or DEFAULT_MAX_CACHE_TIMERANGE
end

function GuildHistoryAdapter:GetGuildHistoryServerMaxTime(category)
    return MAX_SERVER_TIMERANGE_FOR_CATEGORY[category] or DEFAULT_MAX_CACHE_TIMERANGE
end

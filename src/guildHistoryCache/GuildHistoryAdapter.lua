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
local DEFAULT_MAX_CACHE_DAYS = 30
local MAX_SERVER_DAYS_FOR_CATEGORY = {}
for eventCategory = GUILD_HISTORY_EVENT_CATEGORY_ITERATION_BEGIN, GUILD_HISTORY_EVENT_CATEGORY_ITERATION_END do
    MAX_SERVER_DAYS_FOR_CATEGORY[eventCategory] = DEFAULT_MAX_CACHE_DAYS
end
MAX_SERVER_DAYS_FOR_CATEGORY[GUILD_HISTORY_EVENT_CATEGORY_MILESTONE] = 180
MAX_SERVER_DAYS_FOR_CATEGORY[GUILD_HISTORY_EVENT_CATEGORY_ROSTER] = 180

local GuildHistoryAdapter = ZO_InitializingObject:Subclass()
internal.class.GuildHistoryAdapter = GuildHistoryAdapter

function GuildHistoryAdapter:Initialize(saveData, settings)
    self.machineWideSaveData = saveData
    self.accountSaveData = saveData[GetDisplayName()]
    self.settings = settings
    self.activeKeys = {}

    if settings.markGapsInHistory then
        self:InitializeGapRows()
    end
end

function GuildHistoryAdapter:InitializeGapRows()
    logger:Info("Initializing gap row marker feature")
    local GUILD_EVENT_DATA = 1
    local GUILD_EVENT_GAP_DATA = 2

    SecurePostHook(ZO_GuildHistory_Shared, "InitializeSortFilterList", function(self, rowTemplate, rowHeight)
        if rowTemplate == "ZO_GuildHistoryRow_Keyboard" then
            rowTemplate = "LibHistoire_GuildHistoryGapRow_Keyboard"
        elseif rowTemplate == "ZO_GuildHistoryRow_Gamepad" then
            rowTemplate = "LibHistoire_GuildHistoryGapRow_Gamepad"
        else
            return
        end
        ZO_ScrollList_AddDataType(self.list, GUILD_EVENT_GAP_DATA, rowTemplate, rowHeight, nil, ZO_ObjectPool_DefaultResetControl)

        local dataType = ZO_ScrollList_GetDataTypeTable(self.list, GUILD_EVENT_DATA)
        dataType.hideCallback = ZO_ObjectPool_DefaultResetControl
    end)

    SecurePostHook(ZO_GuildHistory_Shared, "FilterScrollList", function(self)
        local scrollData = ZO_ScrollList_GetDataList(self.list)

        if #scrollData < 2 then return end

        local guildId = self.guildId
        local category = self.selectedEventCategory
        local hasGaplessRange = GetOldestGuildHistoryEventIndexForUpToDateEventsWithoutGaps(guildId, category) ~= nil
        local gapIndices = {}
        for i = 1, #scrollData do
            local entryData = scrollData[i]
            if not hasGaplessRange or entryData:GetEventIndex() > 1 then
                local eventId = entryData.data:GetEventId()
                local rangeIndex = GetGuildHistoryEventRangeIndexForEventId(guildId, category, eventId)
                local _, _, newestEventId = GetGuildHistoryEventRangeInfo(guildId, category, rangeIndex)
                if eventId == newestEventId or IsGuildHistoryEventRedacted(guildId, category, newestEventId) then
                    gapIndices[#gapIndices + 1] = i
                end
            end
        end

        for i = #gapIndices, 1, -1 do
            local gapIndex = gapIndices[i]
            local gapData = self.entryDataPool:AcquireObject()
            gapData:SetupAsScrollListDataEntry(GUILD_EVENT_GAP_DATA)
            table.insert(scrollData, gapIndex, gapData)
        end
    end)
end

function GuildHistoryAdapter:GetOrCreateCacheSaveData(key)
    if self.machineWideSaveData[key] then
        logger:Info("Migrating machine wide save data for", key, "to account wide save data")
        self.accountSaveData[key] = self.machineWideSaveData[key]
        self.machineWideSaveData[key] = nil
    end
    local saveData = self.accountSaveData[key] or {}
    self.accountSaveData[key] = saveData
    self.activeKeys[key] = true

    if saveData.lastListenerRegisteredTime then
        saveData.lastProcessorRegisteredTime = saveData.lastListenerRegisteredTime
        saveData.lastListenerRegisteredTime = nil
    end

    if saveData.newestLinkedEventId then
        saveData.newestManagedEventId = saveData.newestLinkedEventId
        saveData.newestLinkedEventId = nil
    end

    if saveData.newestLinkedEventTime then
        saveData.newestManagedEventTime = saveData.newestLinkedEventTime
        saveData.newestLinkedEventTime = nil
    end

    if saveData.oldestLinkedEventId then
        saveData.oldestManagedEventId = saveData.oldestLinkedEventId
        saveData.oldestLinkedEventId = nil
    end

    if saveData.oldestLinkedEventTime then
        saveData.oldestManagedEventTime = saveData.oldestLinkedEventTime
        saveData.oldestLinkedEventTime = nil
    end

    return saveData
end

function GuildHistoryAdapter:DeleteInactiveCacheSaveData()
    local keys = {}
    for key in pairs(self.accountSaveData) do
        if key:find("^" .. internal.WORLD_NAME) then
            keys[#keys + 1] = key
        end
    end

    for _, key in ipairs(keys) do
        if not self.activeKeys[key] then
            self.accountSaveData[key] = nil
            logger:Info("Removed inactive cache save data for", key)
        end
    end
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

    local root = history.categoryTree.rootNode
    for i = 1, #root.children do
        local child = root.children[i]
        if child.children then
            for j = 1, #child.children do
                local leaf = child.children[j]
                SecurePostHook(leaf, "selectionFunction", OnSelectionChanged)
            end
        else
            SecurePostHook(child, "selectionFunction", OnSelectionChanged)
        end
    end
end

function GuildHistoryAdapter:SelectGuildByIndex(guildIndex)
    self.history:SwapToGuildIndexWithoutAutoRequest(guildIndex)
end

function GuildHistoryAdapter:SelectCategory(category)
    self.history:SelectNodeForEventCategory(category, 1, true)
end

function GuildHistoryAdapter:GetSelectedCategoryCache()
    return self.selectedCategoryCache
end

function GuildHistoryAdapter:GetGuildHistoryEventIndicesForTimeRange(guildId, category, newestTime, oldestTime)
    assert(newestTime >= oldestTime, "newestTime must be greater or equal to oldestTime")
    return GetGuildHistoryEventIndicesForTimeRange(guildId, category, newestTime, oldestTime)
end

function GuildHistoryAdapter:GetGuildHistoryCacheMaxDays(category)
    local days = GetCVar("GuildHistoryCacheMaxNumberOfDays_" .. MAX_NUMBER_OF_DAYS_CVAR_SUFFIX[category])
    return days and tonumber(days) or DEFAULT_MAX_CACHE_DAYS
end

function GuildHistoryAdapter:SetGuildHistoryCacheMaxDays(category, days)
    SetCVar("GuildHistoryCacheMaxNumberOfDays_" .. MAX_NUMBER_OF_DAYS_CVAR_SUFFIX[category], days)
end

function GuildHistoryAdapter:GetGuildHistoryCacheMaxTime(category)
    return self:GetGuildHistoryCacheMaxDays(category) * SECONDS_PER_DAY
end

function GuildHistoryAdapter:GetGuildHistoryServerMaxDays(category)
    return MAX_SERVER_DAYS_FOR_CATEGORY[category] or DEFAULT_MAX_CACHE_DAYS
end

function GuildHistoryAdapter:GetGuildHistoryServerMaxTime(category)
    return self:GetGuildHistoryServerMaxDays(category) * SECONDS_PER_DAY
end

function GuildHistoryAdapter:IsAutoDeleteLeftGuildsEnabled()
    return GetCVar("GuildHistoryCacheAutoDeleteLeftGuilds") == "1"
end

function GuildHistoryAdapter:SetAutoDeleteLeftGuildsEnabled(enabled)
    SetCVar("GuildHistoryCacheAutoDeleteLeftGuilds", enabled and "1" or "0")
end

function GuildHistoryAdapter:IsGuildHistoryLoggingEnabled()
    return GetCVar("EnableGuildHistoryLogging") == "1"
end

function GuildHistoryAdapter:SetGuildHistoryLoggingEnabled(enabled)
    SetCVar("EnableGuildHistoryLogging", enabled and "1" or "0")
end

function GuildHistoryAdapter:IsMarkGapsFeatureEnabled()
    return self.settings.markGapsInHistory
end

function GuildHistoryAdapter:SetMarkGapsFeatureEnabled(enabled)
    self.settings.markGapsInHistory = enabled
end
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

local LINKED_ICON = "LibHistoire/image/linked_down.dds"
local UNLINKED_ICON = "LibHistoire/image/unlinked_down.dds"

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

    self.linkedIcon = WINDOW_MANAGER:CreateControlFromVirtual("LibHistoireLinkedIcon", ZO_GuildHistory, "LibHistoireLinkedIconTemplate")
    local icon = self.linkedIcon
    icon:SetHandler("OnMouseEnter", function()
        local cache = self:GetSelectedCache()
        if cache then
            InitializeTooltip(InformationTooltip, icon, RIGHT, 0, 0)

            local storedEventCount = cache:GetNumEntries()
            SetTooltipText(InformationTooltip, zo_strformat("Stored events: |cffffff<<1>>|r", ZO_LocalizeDecimalNumber(storedEventCount)))
            local firstStoredEvent = cache:GetEntry(1)
            if firstStoredEvent then
                local date, time = FormatAchievementLinkTimestamp(firstStoredEvent:GetEventTime())
                SetTooltipText(InformationTooltip, zo_strformat("Oldest stored event: |cffffff<<1>> <<2>>|r", date, time))
            else
                SetTooltipText(InformationTooltip, "Stored events: |cffffff-|r")
            end

            local lastStoredEvent = cache:GetEntry(storedEventCount)
            if lastStoredEvent then
                local date, time = FormatAchievementLinkTimestamp(lastStoredEvent:GetEventTime())
                SetTooltipText(InformationTooltip, zo_strformat("Newest stored event: |cffffff<<1>> <<2>>|r", date, time))
            end

            if cache:HasLinked() then
                SetTooltipText(InformationTooltip, "History has been linked to stored events", 0, 1, 0)
            else
                SetTooltipText(InformationTooltip, "History has not linked to stored events yet", 1, 0, 0)
                SetTooltipText(InformationTooltip, zo_strformat("Unlinked events: |cffffff<<1>>|r", ZO_LocalizeDecimalNumber(cache:GetNumUnlinkedEntries())))
                local firstUnlinkedEvent = cache:GetUnlinkedEntry(1)
                if firstUnlinkedEvent then
                    local date, time = FormatAchievementLinkTimestamp(firstUnlinkedEvent:GetEventTime())
                    SetTooltipText(InformationTooltip, zo_strformat("Oldest unlinked event: |cffffff<<1>> <<2>>|r", date, time))
                    if lastStoredEvent then
                        local delta = firstUnlinkedEvent:GetEventTime() - lastStoredEvent:GetEventTime()
                        local deltaDate = ZO_FormatTime(delta, TIME_FORMAT_STYLE_DESCRIPTIVE_MINIMAL)
                        local percentage = 100 - delta / (GetTimeStamp() - lastStoredEvent:GetEventTime()) * 100
                        SetTooltipText(InformationTooltip, string.format("Missing time: |cffffff%s (%.1f%%)|r", deltaDate, percentage))
                    end
                end
            end
        end
    end)
    icon:SetHandler("OnMouseExit", function()
        ClearTooltip(InformationTooltip)
    end)

    SecurePostHook(GUILD_HISTORY, "SetGuildId",function(manager, guildId)
        logger:Info("selected guild changed to ", guildId)
        self:UpdateLinkedIcon()
    end)

    local function OnSelectionChanged(control, data, selected, reselectingDuringRebuild)
        if selected then
            logger:Info("selected category changed to ", data.categoryId)
            self:UpdateLinkedIcon()
        end
    end

    local function HookAllChildren(node)
        for i = 1, #node.children do
            local child = node.children[i]
            SecurePostHook(child, "selectionFunction", OnSelectionChanged)
            if child.children then
                HookAllChildren(child)
            end
        end
    end

    local categoryTree = GUILD_HISTORY.categoryTree
    HookAllChildren(categoryTree.rootNode)
    for key, info in pairs(categoryTree.templateInfo) do
        SecurePostHook(info, "selectionFunction", OnSelectionChanged)
    end

    internal.callbackObject:RegisterCallback(lib.callback.HISTORY_LINKED, function(guildId, category)
        logger:Info("history has become linked", guildId, category)
        local manager = GUILD_HISTORY
        if manager.guildId == guildId and manager.selectedCategory == category then
            self:UpdateLinkedIcon()
        end
    end)

    self:UpdateAllCategories()
end

function GuildHistoryCache:GetSelectedCache()
    local manager = GUILD_HISTORY
    if manager.guildId and manager.selectedCategory then
        return self:GetOrCreateCategoryCache(manager.guildId, manager.selectedCategory)
    end
end

function GuildHistoryCache:UpdateLinkedIcon()
    local cache = self:GetSelectedCache()
    if cache then
        logger:Debug("show and update linked icon")
        self.linkedIcon:SetTexture(cache:HasLinked() and LINKED_ICON or UNLINKED_ICON)
        self.linkedIcon:SetHidden(false)
    else
        logger:Debug("hide linked icon")
        self.linkedIcon:SetHidden(true)
    end
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

-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local GuildHistoryCache = ZO_Object:Subclass()
internal.class.GuildHistoryCache = GuildHistoryCache

local GuildHistoryRequestManager = internal.class.GuildHistoryRequestManager
local GuildHistoryCacheCategory = internal.class.GuildHistoryCacheCategory
local GuildHistoryCacheEntry = internal.class.GuildHistoryCacheEntry
local RegisterForEvent = internal.RegisterForEvent

local LINKED_ICON = "LibHistoire/image/linked_down.dds"
local UNLINKED_ICON = "LibHistoire/image/unlinked_down.dds"

function GuildHistoryCache:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function GuildHistoryCache:Initialize(nameCache, saveData)
    self.nameCache = nameCache
    self.saveData = saveData
    self.cache = {}

    self.linkedIcon = WINDOW_MANAGER:CreateControlFromVirtual("LibHistoireLinkedIcon", ZO_GuildHistory, "LibHistoireLinkedIconTemplate")
    local icon = self.linkedIcon
    local tooltipShowing = false

    local function SetupTooltip(tooltip, cache)
        InitializeTooltip(tooltip, icon, RIGHT, 0, 0)

        local storedEventCount = cache:GetNumEntries()
        SetTooltipText(tooltip, zo_strformat("Stored events: |cffffff<<1>>|r", ZO_LocalizeDecimalNumber(storedEventCount)))
        local firstStoredEvent = cache:GetEntry(1)
        if firstStoredEvent then
            local date, time = FormatAchievementLinkTimestamp(firstStoredEvent:GetEventTime())
            SetTooltipText(tooltip, zo_strformat("Oldest stored event: |cffffff<<1>> <<2>>|r", date, time))
        else
            SetTooltipText(tooltip, "Stored events: |cffffff-|r")
        end

        local lastStoredEvent = cache:GetEntry(storedEventCount)
        if lastStoredEvent then
            local date, time = FormatAchievementLinkTimestamp(lastStoredEvent:GetEventTime())
            SetTooltipText(tooltip, zo_strformat("Newest stored event: |cffffff<<1>> <<2>>|r", date, time))
        end

        if cache:IsProcessing() then
            SetTooltipText(tooltip, "Unlinked Events are being processed...", 1, 1, 0)
        elseif cache:HasLinked() then
            SetTooltipText(tooltip, "History has been linked to stored events", 0, 1, 0)
        else
            SetTooltipText(tooltip, "History has not linked to stored events yet", 1, 0, 0)
            SetTooltipText(tooltip, zo_strformat("Unlinked events: |cffffff<<1>>|r", ZO_LocalizeDecimalNumber(cache:GetNumUnlinkedEntries())))
            local firstUnlinkedEvent = cache:GetUnlinkedEntry(1)
            if firstUnlinkedEvent then
                local date, time = FormatAchievementLinkTimestamp(firstUnlinkedEvent:GetEventTime())
                SetTooltipText(tooltip, zo_strformat("Oldest unlinked event: |cffffff<<1>> <<2>>|r", date, time))
                if lastStoredEvent then
                    local delta = firstUnlinkedEvent:GetEventTime() - lastStoredEvent:GetEventTime()
                    local deltaDate = ZO_FormatTime(delta, TIME_FORMAT_STYLE_DESCRIPTIVE_MINIMAL)
                    local percentage = 100 - delta / (GetTimeStamp() - lastStoredEvent:GetEventTime()) * 100
                    SetTooltipText(tooltip, string.format("Missing time: |cffffff%s (%.1f%%)|r", deltaDate, percentage))
                end
            end
        end
    end

    icon:SetHandler("OnMouseEnter", function()
        local cache = self:GetSelectedCache()
        if cache then
            tooltipShowing = true
            SetupTooltip(InformationTooltip, cache)
        end
    end)
    icon:SetHandler("OnMouseExit", function()
        ClearTooltip(InformationTooltip)
        tooltipShowing = false
    end)

    SecurePostHook(GUILD_HISTORY, "SetGuildId",function(manager, guildId)
        logger:Info("selected guild changed to ", guildId)
        self:UpdateLinkedIcon()
        if tooltipShowing then
            local cache = self:GetSelectedCache()
            SetupTooltip(InformationTooltip, cache)
        end
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

    local function RefreshLinkInformation(guildId, category)
        local manager = GUILD_HISTORY
        if manager.guildId == guildId and manager.selectedCategory == category then
            self:UpdateLinkedIcon()
            if tooltipShowing then
                local cache = self:GetSelectedCache()
                SetupTooltip(InformationTooltip, cache)
            end
        end
    end

    internal:RegisterCallback(internal.callback.UNLINKED_EVENTS_ADDED, RefreshLinkInformation)
    internal:RegisterCallback(internal.callback.HISTORY_BEGIN_LINKING, RefreshLinkInformation)
    internal:RegisterCallback(internal.callback.HISTORY_LINKED, RefreshLinkInformation)

    self.requestManager = GuildHistoryRequestManager:New(self)
    self:UpdateLinkedIcon()
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

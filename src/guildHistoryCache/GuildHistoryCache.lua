-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local GuildHistoryCache = ZO_Object:Subclass()
internal.class.GuildHistoryCache = GuildHistoryCache

local GuildHistoryRequestManager = internal.class.GuildHistoryRequestManager
local GuildHistoryCacheGuild = internal.class.GuildHistoryCacheGuild
local GuildHistoryCacheEntry = internal.class.GuildHistoryCacheEntry
local RegisterForEvent = internal.RegisterForEvent

local LINKED_ICON = "LibHistoire/image/linked_down.dds"
local UNLINKED_ICON = "LibHistoire/image/unlinked_down.dds"

function GuildHistoryCache:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function GuildHistoryCache:Initialize(nameCache, statusTooltip, saveData)
    self.nameCache = nameCache
    self.statusTooltip = statusTooltip
    self.saveData = saveData
    self.cache = {}

    self.linkedIcon = WINDOW_MANAGER:CreateControlFromVirtual("LibHistoireLinkedIcon", ZO_GuildHistory, "LibHistoireLinkedIconTemplate")
    local icon = self.linkedIcon

    icon:SetHandler("OnMouseEnter", function()
        local cache = self:GetSelectedCache()
        if cache then
            statusTooltip:Show(icon, cache)
        end
    end)
    icon:SetHandler("OnMouseExit", function()
        statusTooltip:Hide()
    end)

    SecurePostHook(GUILD_HISTORY, "SetGuildId",function(manager, guildId)
        self:UpdateLinkedIcon()
        if statusTooltip:GetTarget() == icon then
            local cache = self:GetSelectedCache()
            statusTooltip:Show(icon, cache)
        end
    end)

    local function OnSelectionChanged(control, data, selected, reselectingDuringRebuild)
        if selected then
            self:UpdateLinkedIcon()
        end
    end

    for key, info in pairs(GUILD_HISTORY.categoryTree.templateInfo) do
        SecurePostHook(info, "selectionFunction", OnSelectionChanged)
    end

    local function RefreshLinkInformation(guildId, category)
        local manager = GUILD_HISTORY
        if manager.guildId == guildId and manager.selectedCategory == category then
            self:UpdateLinkedIcon()
            if statusTooltip:GetTarget() == icon then
                local cache = self:GetSelectedCache()
                statusTooltip:Show(icon, cache)
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

function GuildHistoryCache:HasLinkedAllCaches()
    for i = 1, GetNumGuilds() do
        local guildId = GetGuildId(i)
        local cache = self:GetOrCreateGuildCache(guildId)
        if not cache:HasLinked() then 
            return false
        end
    end
    return true
end

function GuildHistoryCache:UpdateLinkedIcon()
    local cache = self:GetSelectedCache()
    if cache then
        self.linkedIcon:SetTexture(cache:HasLinked() and LINKED_ICON or UNLINKED_ICON)
        self.linkedIcon:SetHidden(false)
    else
        self.linkedIcon:SetHidden(true)
    end
end

function GuildHistoryCache:HasGuildCache(guildId)
    if not self.cache[guildId] then return false end
    return true
end

function GuildHistoryCache:GetOrCreateGuildCache(guildId)
    if not self.cache[guildId] then
        self.cache[guildId] = GuildHistoryCacheGuild:New(self.nameCache, self.saveData, guildId)
    end
    return self.cache[guildId]
end

function GuildHistoryCache:HasCategoryCache(guildId, category)
    if not self.cache[guildId] or not self.cache[guildId]:HasCategoryCache(category) then return false end
    return true
end

function GuildHistoryCache:GetOrCreateCategoryCache(guildId, category)
    local guildCache = self:GetOrCreateGuildCache(guildId)
    local categoryCache = guildCache:GetOrCreateCategoryCache(category)
    return categoryCache
end

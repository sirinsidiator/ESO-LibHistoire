-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local LINKED_ICON = "LibHistoire/image/linked_down.dds"
local UNLINKED_ICON = "LibHistoire/image/unlinked_down.dds"

local GuildHistoryStatusLinkedIcon = ZO_InitializingObject:Subclass()
internal.class.GuildHistoryStatusLinkedIcon = GuildHistoryStatusLinkedIcon

function GuildHistoryStatusLinkedIcon:Initialize(history, adapter, statusTooltip)
    self.history = history
    self.adapter = adapter
    self.statusTooltip = statusTooltip
    self.control = WINDOW_MANAGER:CreateControlFromVirtual("LibHistoireLinkedIcon", history.control,
        "LibHistoireLinkedIconTemplate")
    local control = self.control

    control:SetHandler("OnMouseEnter", function()
        local cache = self:GetSelectedCache()
        if cache then
            statusTooltip:Show(control, cache)
        end
    end)
    control:SetHandler("OnMouseExit", function()
        statusTooltip:Hide()
    end)

    local function RefreshLinkInformation()
        self:Update()
    end

    internal:RegisterCallback(internal.callback.SELECTED_CATEGORY_CACHE_CHANGED, RefreshLinkInformation)
    internal:RegisterCallback(internal.callback.PROCESSING_STARTED, RefreshLinkInformation)
    internal:RegisterCallback(internal.callback.PROCESSING_LINKED_EVENTS_FINISHED, RefreshLinkInformation)

    self:Update()
end

function GuildHistoryStatusLinkedIcon:Update()
    local control = self.control
    local statusTooltip = self.statusTooltip

    local cache = self.adapter:GetSelectedCategoryCache()
    if cache then
        self.control:SetTexture(cache:HasLinked() and LINKED_ICON or UNLINKED_ICON)
        self.control:SetHidden(false)
    else
        self.control:SetHidden(true)
    end

    if statusTooltip:GetTarget() == control then
        statusTooltip:Show(control, cache)
    end
end

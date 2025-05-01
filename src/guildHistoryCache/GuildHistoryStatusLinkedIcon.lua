-- SPDX-FileCopyrightText: 2025 sirinsidiator
--
-- SPDX-License-Identifier: Artistic-2.0

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local LINKED_ICON = "LibHistoire/image/linked_down.dds"
local UNLINKED_ICON = "LibHistoire/image/unlinked_down.dds"
local REQUEST_MODE_FORCE_OFF_ICON = "EsoUI/Art/Miscellaneous/Keyboard/hidden_down.dds"

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
        local cache = self.adapter:GetSelectedCategoryCache()
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
    internal:RegisterCallback(internal.callback.PROCESS_LINKED_EVENTS_STARTED, RefreshLinkInformation)
    internal:RegisterCallback(internal.callback.PROCESS_LINKED_EVENTS_FINISHED, RefreshLinkInformation)
    internal:RegisterCallback(internal.callback.PROCESS_LINKED_EVENTS_STARTED, RefreshLinkInformation)
    internal:RegisterCallback(internal.callback.PROCESS_MISSED_EVENTS_FINISHED, RefreshLinkInformation)
    internal:RegisterCallback(internal.callback.REQUEST_MODE_CHANGED, RefreshLinkInformation)
    internal:RegisterCallback(internal.callback.MANAGED_RANGE_LOST, RefreshLinkInformation)
    internal:RegisterCallback(internal.callback.MANAGED_RANGE_FOUND, RefreshLinkInformation)

    self:Update()
end

function GuildHistoryStatusLinkedIcon:Update()
    local control = self.control
    local statusTooltip = self.statusTooltip

    local cache = self.adapter:GetSelectedCategoryCache()
    if cache then
        local texture = UNLINKED_ICON
        if not cache:IsAutoRequesting() then
            texture = REQUEST_MODE_FORCE_OFF_ICON
        elseif cache:HasLinked() then
            texture = LINKED_ICON
        end
        self.control:SetTexture(texture)
        self.control:SetHidden(false)
    else
        self.control:SetHidden(true)
    end

    if statusTooltip:GetTarget() == control then
        statusTooltip:Show(control, cache)
    end
end

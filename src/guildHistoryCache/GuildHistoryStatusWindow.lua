-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local BUTTON_NORMAL_TEXTURE = "LibHistoire/image/histy_up.dds"
local BUTTON_PRESSED_TEXTURE = "LibHistoire/image/histy_down.dds"
local LINKED_ICON = "LibHistoire/image/linked_down.dds"
local UNLINKED_ICON = "LibHistoire/image/unlinked_down.dds"
local DEFAULT_COLOR = ZO_NORMAL_TEXT
local SELECTED_COLOR = ZO_SELECTED_TEXT

local DATA_ENTRY = 1
local ROW_HEIGHT = 52

local guildHistoryScene = SCENE_MANAGER:GetScene("guildHistory")

local GuildHistoryStatusWindow = ZO_Object:Subclass()
internal.class.GuildHistoryStatusWindow = GuildHistoryStatusWindow

function GuildHistoryStatusWindow:New(...)
    local obj = ZO_Object.New(self)
    obj:Initialize(...)
    return obj
end

function GuildHistoryStatusWindow:Initialize(historyAdapter, statusTooltip, saveData)
    self.historyAdapter = historyAdapter
    self.statusTooltip = statusTooltip
    self.saveData = saveData

    self.guildId = GetGuildId(1)
    self.category = GUILD_HISTORY_GENERAL

    local control = LibHistoireGuildHistoryStatusWindow
    self.fragment = ZO_SimpleSceneFragment:New(control)

    self.labelControl = control:GetNamedChild("Label")
    self.labelControl:SetText("LibHistoire - Guild History Status")
    self.guildListControl = control:GetNamedChild("GuildList")
    self.categoryListControl = control:GetNamedChild("CategoryList")
    self.selectionWidget = internal.class.GuildHistoryStatusSelectionWidget:New(control, ROW_HEIGHT)
    self.statusIcon = control:GetNamedChild("StatusIcon")
    self.statusIcon:SetHandler("OnMouseEnter", function(icon)
        InitializeTooltip(InformationTooltip, icon, RIGHT, 0, 0)
        if self.hasLinkedEverything then
            SetTooltipText(InformationTooltip, "History has been linked for all guilds and categories")
            SetTooltipText(InformationTooltip, "New events will be sent on the server's sole discretion and may arrive at any time, or sometimes even never")
            SetTooltipText(InformationTooltip, "If they do not show up after several hours, you may want to restart your game")
        else
            SetTooltipText(InformationTooltip, "The history has not been linked to the stored events yet.")
            SetTooltipText(InformationTooltip, "Automatic requests are on cooldown and may take a while")
            SetTooltipText(InformationTooltip, "You can manually send requests to receive missing history faster")
            SetTooltipText(InformationTooltip, "You can also force history to link, but it will create a hole in the stored records")
        end
    end)
    self.statusIcon:SetHandler("OnMouseExit", function()
        ClearTooltip(InformationTooltip)
    end)
    control:SetHandler("OnMoveStop", function() self:SavePosition() end)
    self.control = control

    self:InitializeButtons()
    self:InitializeGuildList(self.guildListControl)
    self:InitializeCategoryList(self.categoryListControl)

    local function DoUpdate()
        self:Update()
    end
    internal:RegisterCallback(internal.callback.UNLINKED_EVENTS_ADDED, DoUpdate)
    internal:RegisterCallback(internal.callback.HISTORY_BEGIN_LINKING, DoUpdate)
    internal:RegisterCallback(internal.callback.HISTORY_LINKED, DoUpdate)
    internal:RegisterCallback(internal.callback.SELECTED_GUILD_CHANGED, function(guildId) self:SetGuildId(guildId) end)
    internal:RegisterCallback(internal.callback.SELECTED_CATEGORY_CHANGED, function(category) self:SetCategory(category) end)
    guildHistoryScene:RegisterCallback("StateChange", DoUpdate)

    self:LoadPosition()
end

function GuildHistoryStatusWindow:InitializeButtons()
    local optionsButton = self.control:GetNamedChild("Options")
    optionsButton:SetHandler("OnClicked", function(control)
        ClearMenu()

        if(self:IsLocked()) then
            AddCustomMenuItem("Unlock Window", function() self:Unlock() end)
        else
            AddCustomMenuItem("Lock Window", function() self:Lock() end)
            AddCustomMenuItem("Reset Position", function() self:ResetPosition() end)
        end

        AddCustomMenuItem("Hide Window", function() self:Disable() end)

        ShowMenu(optionsButton)
    end)
    self.optionsButton = optionsButton

    local toggleWindowButton = WINDOW_MANAGER:CreateControlFromVirtual("LibHistoireGuildHistoryStatusWindowToggleButton", ZO_GuildHistory, "LibHistoireGuildHistoryStatusWindowToggleButtonTemplate")
    toggleWindowButton:SetHandler("OnClicked", function(control)
        if(self:IsEnabled()) then
            self:Disable()
        else
            self:Enable()
        end
    end)
    toggleWindowButton:SetHandler("OnMouseEnter", function(control)
        InitializeTooltip(InformationTooltip, control, RIGHT, 0, 0)
        SetTooltipText(InformationTooltip, "Toggle Guild History Status Window")
    end)
    toggleWindowButton:SetHandler("OnMouseExit", function(control)
        ClearTooltip(InformationTooltip)
    end)
    self.toggleWindowButton = toggleWindowButton

    -- properly initialize the button state
    if(self:IsEnabled()) then
        self:Enable()
    else
        self:Disable()
    end
end

local function InitializeProgress(rowControl)
    local statusBarControl = rowControl:GetNamedChild("StatusBar")
    statusBarControl:GetNamedChild("BGLeft"):SetDrawLevel(2)
    statusBarControl:GetNamedChild("BGRight"):SetDrawLevel(2)
    statusBarControl:GetNamedChild("BGMiddle"):SetDrawLevel(2)
    statusBarControl:SetMinMax(0, 1)
end

local function InitializeHighlight(rowControl)
    local highlight = rowControl:GetNamedChild("Highlight")
    highlight:SetAlpha(0)
    highlight.animation = ANIMATION_MANAGER:CreateTimelineFromVirtual("ShowOnMouseOverLabelAnimation", highlight)
    highlight.animation:GetFirstAnimation():SetAlphaValues(0, 1)

    rowControl:SetHandler("OnMouseEnter", function()
        highlight.animation:PlayForward()
    end, "LibHistoire_Highlight")

    rowControl:SetHandler("OnMouseExit", function()
        highlight.animation:PlayBackward()
    end, "LibHistoire_Highlight")
end

local function InitializeTooltip(rowControl, tooltip)
    rowControl:SetHandler("OnMouseEnter", function()
        local entry = ZO_ScrollList_GetData(rowControl)
        tooltip:Show(rowControl, entry.cache)
    end, "LibHistoire_Tooltip")

    rowControl:SetHandler("OnMouseExit", function()
        tooltip:Hide()
    end, "LibHistoire_Tooltip")
end

local function InitializeClickHandler(rowControl, OnSelect)
    rowControl:SetHandler("OnMouseUp", function(control, button, isInside, ctrl, alt, shift, command)
        if(isInside and button == MOUSE_BUTTON_INDEX_LEFT) then
            local entry = ZO_ScrollList_GetData(rowControl)
            OnSelect(entry)
            PlaySound("Click")
        end
    end, "LibHistoire_Select")
end

local function SetLabel(rowControl, entry)
    local labelControl = rowControl:GetNamedChild("Label")
    labelControl:SetText(entry.label)
    local color = entry.selected and SELECTED_COLOR or DEFAULT_COLOR
    labelControl:SetColor(color:UnpackRGBA())
end

local function SetProgress(rowControl, entry)
    local gradient
    local cache = entry.cache
    local statusBarControl = rowControl:GetNamedChild("StatusBar")

    local hasLinked = cache:HasLinked()
    if hasLinked and cache:IsProcessing() then
        statusBarControl:SetValue(1)
        gradient = ZO_SKILL_XP_BAR_GRADIENT_COLORS
    else
        local progress = cache:GetProgress()
        statusBarControl:SetValue(progress)
        gradient = hasLinked and ZO_XP_BAR_GRADIENT_COLORS or ZO_CP_BAR_GRADIENT_COLORS[CHAMPION_DISCIPLINE_TYPE_CONDITIONING]
    end

    ZO_StatusBar_SetGradientColor(statusBarControl, gradient)
end

local function SetSelected(rowControl, entry)
    local minAlpha = entry.selected and 0.5 or 0
    local highlight = rowControl:GetNamedChild("Highlight")
    highlight:SetAlpha(minAlpha)
    highlight.animation:GetFirstAnimation():SetAlphaValues(minAlpha, 1)
end

local function DestroyRow(rowControl)
    local highlight = rowControl:GetNamedChild("Highlight")
    highlight.animation:PlayFromEnd(highlight.animation:GetDuration())
    ZO_ObjectPool_DefaultResetControl(rowControl)
end

function GuildHistoryStatusWindow:InitializeBaseList(listControl, template, OnInit, OnUpdate)
    local function InitializeRow(rowControl, entry)
        if not rowControl.initialized then
            InitializeProgress(rowControl)
            InitializeHighlight(rowControl)
            InitializeTooltip(rowControl, self.statusTooltip)
            OnInit(rowControl)
            rowControl.initialized = true
        end

        SetLabel(rowControl, entry)
        SetProgress(rowControl, entry)
        SetSelected(rowControl, entry)

        if self.statusTooltip:GetTarget() == rowControl then
            self.statusTooltip:Show(rowControl, entry.cache)
        end

        if OnUpdate then
            OnUpdate(rowControl, entry)
        end
    end

    ZO_ScrollList_Initialize(listControl)
    ZO_ScrollList_AddDataType(listControl, DATA_ENTRY, template, ROW_HEIGHT, InitializeRow, nil, nil, DestroyRow)
    ZO_ScrollList_AddResizeOnScreenResize(listControl)
end

function GuildHistoryStatusWindow:InitializeGuildList(listControl)
    local function OnSelectRow(entry)
        self.historyAdapter:SelectGuildByIndex(entry.value)
    end

    self:InitializeBaseList(listControl, "LibHistoireGuildHistoryStatusGuildRowTemplate", function(rowControl)
        InitializeClickHandler(rowControl, OnSelectRow)
    end)

    self.emptyGuildListRow = CreateControlFromVirtual("$(parent)EmptyRow", listControl, "ZO_SortFilterListEmptyRow_Keyboard")
    GetControl(self.emptyGuildListRow, "Message"):SetText("No Guilds")
end

function GuildHistoryStatusWindow:InitializeCategoryList(listControl)
    local function OnSelectRow(entry)
        self.historyAdapter:SelectCategory(entry.value)
    end

    self:InitializeBaseList(listControl, "LibHistoireGuildHistoryStatusCategoryRowTemplate", function(rowControl)
        InitializeClickHandler(rowControl, OnSelectRow)

        local forceLinkButton = rowControl:GetNamedChild("ForceLinkButton")
        forceLinkButton:SetHandler("OnMouseUp", function(control, button, isInside, ctrl, alt, shift, command)
            if(isInside and button == MOUSE_BUTTON_INDEX_LEFT) then
                internal:ShowForceLinkWarningDialog(function()
                    local entry = ZO_ScrollList_GetData(rowControl)
                    if entry.cache:LinkHistory() then
                        rowControl.forceLinkButton:SetEnabled(false)
                    end
                end)
                PlaySound("Click")
            end
        end, "LibHistoire_Click")
        forceLinkButton:SetHandler("OnMouseEnter", function()
            self.statusTooltip:ShowText(forceLinkButton, "Force history to link now")
        end, "LibHistoire_Tooltip")
        forceLinkButton:SetHandler("OnMouseExit", function()
            self.statusTooltip:Hide()
        end, "LibHistoire_Tooltip")
        rowControl.forceLinkButton = forceLinkButton

        local rescanButton = rowControl:GetNamedChild("RescanButton")
        rescanButton:SetHandler("OnMouseUp", function(control, button, isInside, ctrl, alt, shift, command)
            if(isInside and button == MOUSE_BUTTON_INDEX_LEFT) then
                local entry = ZO_ScrollList_GetData(rowControl)
                if entry.cache:RescanEvents() then
                    rowControl.rescanButton:SetEnabled(false)
                end
                PlaySound("Click")
            end
        end, "LibHistoire_Click")
        rescanButton:SetHandler("OnMouseEnter", function()
            self.statusTooltip:ShowText(rescanButton, "Rescan history for missing events")
        end, "LibHistoire_Tooltip")
        rescanButton:SetHandler("OnMouseExit", function()
            self.statusTooltip:Hide()
        end, "LibHistoire_Tooltip")
        rowControl.rescanButton = rescanButton
    end, function(rowControl, entry)
        local cache = entry.cache
        local hasLinked = cache:HasLinked()
        rowControl.forceLinkButton:SetHidden(hasLinked)
        rowControl.rescanButton:SetHidden(not hasLinked)

        local isIdle = not cache:IsProcessing()
        rowControl.rescanButton:SetEnabled(isIdle)
        rowControl.forceLinkButton:SetEnabled(isIdle)
    end)
end

function GuildHistoryStatusWindow:SetGuildId(guildId)
    self.guildId = guildId
    self:Update()
end

function GuildHistoryStatusWindow:SetCategory(category)
    self.category = category
    self:Update()
end

function GuildHistoryStatusWindow:CreateDataEntry(label, cache, value, selected)
    return ZO_ScrollList_CreateDataEntry(DATA_ENTRY, {
        label = label,
        cache = cache,
        value = value,
        selected = selected
    })
end

function GuildHistoryStatusWindow:Update()
    if(self:IsShowing()) then
        local hasLinkedEverything = true

        local guildListControl = self.guildListControl
        local guildScrollData = ZO_ScrollList_GetDataList(guildListControl)
        ZO_ScrollList_Clear(guildListControl)
        local numGuilds = GetNumGuilds()
        for i = 1, numGuilds do
            local guildId = GetGuildId(i)
            local label = GetGuildName(guildId)
            local cache = internal.historyCache:GetOrCreateGuildCache(guildId)
            local selected = (self.guildId == guildId)
            guildScrollData[#guildScrollData + 1] = self:CreateDataEntry(label, cache, i, selected)
            if selected then self.selectionWidget:SelectGuild(i) end
            if not cache:HasLinked() then hasLinkedEverything = false end
        end
        self.emptyGuildListRow:SetHidden(numGuilds > 0)
        ZO_ScrollList_Commit(guildListControl)

        local categoryListControl = self.categoryListControl
        local categoryScrollData = ZO_ScrollList_GetDataList(categoryListControl)
        ZO_ScrollList_Clear(categoryListControl)
        if numGuilds > 0 then
            for category = 1, GetNumGuildHistoryCategories() do
                if GUILD_HISTORY_CATEGORIES[category] then
                    local label = GetString("SI_GUILDHISTORYCATEGORY", category)
                    local cache = internal.historyCache:GetOrCreateCategoryCache(self.guildId, category)
                    local selected = (self.category == category)
                    categoryScrollData[#categoryScrollData + 1] = self:CreateDataEntry(label, cache, category, selected)
                    if selected then self.selectionWidget:SelectCategory(#categoryScrollData) end
                end
            end
        end
        ZO_ScrollList_Commit(categoryListControl)

        self.selectionWidget:SetGuildCount(numGuilds)
        self.selectionWidget:SetCategoryCount(#categoryScrollData)
        self.selectionWidget:Update()

        self.statusIcon:SetTexture(hasLinkedEverything and LINKED_ICON or UNLINKED_ICON)
        self.hasLinkedEverything = hasLinkedEverything
    end
end

function GuildHistoryStatusWindow:SavePosition()
    local control, saveData = self.control, self.saveData
    saveData.x, saveData.y = control:GetScreenRect()
end

function GuildHistoryStatusWindow:LoadPosition()
    local control, saveData = self.control, self.saveData
    control:ClearAnchors()
    if not saveData.x or not saveData.y then
        control:SetAnchor(BOTTOMRIGHT, ZO_GuildHistory, BOTTOMLEFT, -30, 30)
    else
        control:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, saveData.x, saveData.y)
    end
end

function GuildHistoryStatusWindow:ResetPosition()
    local saveData = self.saveData
    saveData.x = nil
    saveData.y = nil
    self:LoadPosition()
end

function GuildHistoryStatusWindow:IsLocked()
    return self.saveData.locked
end

function GuildHistoryStatusWindow:Lock()
    self.saveData.locked = true
    self.control:SetMovable(false)
end

function GuildHistoryStatusWindow:Unlock()
    self.saveData.locked = false
    self.control:SetMovable(true)
end

function GuildHistoryStatusWindow:IsShowing()
    return guildHistoryScene:IsShowing() and self:IsEnabled()
end

function GuildHistoryStatusWindow:IsEnabled()
    return self.saveData.enabled
end

function GuildHistoryStatusWindow:Enable()
    self.saveData.enabled = true
    guildHistoryScene:AddFragment(self.fragment)
    self.toggleWindowButton:SetNormalTexture(BUTTON_PRESSED_TEXTURE)
    self.toggleWindowButton:SetPressedTexture(BUTTON_NORMAL_TEXTURE)
    self:Update()
end

function GuildHistoryStatusWindow:Disable()
    self.saveData.enabled = false
    guildHistoryScene:RemoveFragment(self.fragment)
    self.toggleWindowButton:SetNormalTexture(BUTTON_NORMAL_TEXTURE)
    self.toggleWindowButton:SetPressedTexture(BUTTON_PRESSED_TEXTURE)
end

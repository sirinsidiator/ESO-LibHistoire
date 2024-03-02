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

local GuildHistoryStatusWindow = ZO_InitializingObject:Subclass()
internal.class.GuildHistoryStatusWindow = GuildHistoryStatusWindow

function GuildHistoryStatusWindow:Initialize(historyAdapter, statusTooltip, saveData)
    self.historyAdapter = historyAdapter
    self.statusTooltip = statusTooltip
    self.saveData = saveData

    self.guildId = GetGuildId(1)
    self.category = GUILD_HISTORY_EVENT_CATEGORY_ROSTER

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
            SetTooltipText(InformationTooltip,
                "New events will be sent on the server's sole discretion and may arrive at any time, or sometimes even never")
            SetTooltipText(InformationTooltip,
                "If they do not show up after several hours, you may want to restart your game")
        else
            SetTooltipText(InformationTooltip, "The history has not been linked to the stored events yet.")
            SetTooltipText(InformationTooltip, "Automatic requests are on cooldown and may take a while")
            SetTooltipText(InformationTooltip, "You can manually send requests to receive missing history faster")
            SetTooltipText(InformationTooltip,
                "You can also force history to link, but it will create a hole in the stored records")
        end
    end)
    self.statusIcon:SetHandler("OnMouseExit", function()
        ClearTooltip(InformationTooltip)
    end)
    control:SetHandler("OnMoveStop", function() self:SavePosition() end)
    self.control = control

    self:InitializeGuildList(self.guildListControl)
    self:InitializeCategoryList(self.categoryListControl)
    self:InitializeButtons()

    local function DoUpdate() -- TODO defer update and check which controls have to be updated
        self:Update()
    end
    internal:RegisterCallback(internal.callback.CATEGORY_DATA_UPDATED, DoUpdate)
    internal:RegisterCallback(internal.callback.PROCESSING_STARTED, DoUpdate)
    internal:RegisterCallback(internal.callback.PROCESSING_LINKED_EVENTS_FINISHED, DoUpdate)
    internal:RegisterCallback(internal.callback.PROCESSING_FINISHED, DoUpdate)
    internal:RegisterCallback(internal.callback.PROCESSING_STOPPED, DoUpdate)
    internal:RegisterCallback(internal.callback.WATCH_MODE_CHANGED, DoUpdate)
    internal:RegisterCallback(internal.callback.ZOOM_MODE_CHANGED, DoUpdate)
    internal:RegisterCallback(internal.callback.SELECTED_CATEGORY_CACHE_CHANGED, function(cache)
        self:SetGuildId(cache:GetGuildId())
        self:SetCategory(cache:GetCategory())
    end)
    guildHistoryScene:RegisterCallback("StateChange", DoUpdate)

    self:LoadPosition()

    SLASH_COMMANDS["/testrequest"] = function(daysAgo) -- TODO remove
        daysAgo = tonumber(daysAgo) or 1
        local newestTime = GetTimeStamp() - (daysAgo * 24 * 3600)
        local oldestTime = newestTime - 24 * 3600
        logger:Info("Send requests for", daysAgo, "days ago")
        internal.historyCache:GetGuildCache(self.guildId):SendRequests(newestTime, oldestTime)
        internal:FireCallbacks(internal.callback.CATEGORY_DATA_UPDATED)
    end
end

function GuildHistoryStatusWindow:InitializeButtons()
    local optionsButton = self.control:GetNamedChild("Options")
    optionsButton:SetHandler("OnClicked", function(control)
        ClearMenu()

        if (self:IsLocked()) then
            AddCustomMenuItem("Unlock Window", function() self:Unlock() end)
        else
            AddCustomMenuItem("Lock Window", function() self:Lock() end)
            AddCustomMenuItem("Reset Position", function() self:ResetPosition() end)
        end

        AddCustomSubMenuItem("Zoom Mode", {
            {
                label = "Automatic",
                itemType = MENU_ADD_OPTION_CHECKBOX,
                callback = function()
                    self:SetZoomMode(internal.ZOOM_MODE_AUTO)
                end,
                checked = function()
                    return self:GetZoomMode() == internal.ZOOM_MODE_AUTO
                end
            },
            {
                label = "Full Range",
                itemType = MENU_ADD_OPTION_CHECKBOX,
                callback = function()
                    self:SetZoomMode(internal.ZOOM_MODE_FULL_RANGE)
                end,
                checked = function()
                    return self:GetZoomMode() == internal.ZOOM_MODE_FULL_RANGE
                end
            },
            {
                label = "Missing Range",
                itemType = MENU_ADD_OPTION_CHECKBOX,
                callback = function()
                    self:SetZoomMode(internal.ZOOM_MODE_MISSING_RANGE)
                end,
                checked = function()
                    return self:GetZoomMode() == internal.ZOOM_MODE_MISSING_RANGE
                end
            }
        })

        AddCustomMenuItem("Hide Window", function() self:Disable() end)

        ShowMenu(optionsButton)
    end)
    self.optionsButton = optionsButton

    local toggleWindowButton = WINDOW_MANAGER:CreateControlFromVirtual("LibHistoireGuildHistoryStatusWindowToggleButton",
        ZO_GuildHistory_Keyboard_TL, "LibHistoireGuildHistoryStatusWindowToggleButtonTemplate")
    toggleWindowButton:SetHandler("OnClicked", function(control)
        if (self:IsEnabled()) then
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
    if (self:IsEnabled()) then
        self:Enable()
    else
        self:Disable()
    end
end

local function InitializeProgress(rowControl, window)
    local control = rowControl:GetNamedChild("StatusBar")
    rowControl.statusBar = internal.class.CacheStatusBar:New(control, window)
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
        if (isInside and button == MOUSE_BUTTON_INDEX_LEFT) then
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
    entry.cache:UpdateProgressBar(rowControl.statusBar)
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
            InitializeProgress(rowControl, self)
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

    self.emptyGuildListRow = CreateControlFromVirtual("$(parent)EmptyRow", listControl,
        "ZO_SortFilterListEmptyRow_Keyboard")
    GetControl(self.emptyGuildListRow, "Message"):SetText("No Guilds")
end

local function GetCacheFromRow(rowControl)
    local entry = ZO_ScrollList_GetData(rowControl)
    return entry.cache
end

function GuildHistoryStatusWindow:InitializeCategoryList(listControl)
    local function OnSelectRow(entry)
        self.historyAdapter:SelectCategory(entry.value)
    end

    self:InitializeBaseList(listControl, "LibHistoireGuildHistoryStatusCategoryRowTemplate", function(rowControl)
        InitializeClickHandler(rowControl, OnSelectRow)

        local menuButton = rowControl:GetNamedChild("MenuButton")
        menuButton:SetHandler("OnMouseUp", function(control, button, isInside, ctrl, alt, shift, command)
            if (isInside and button == MOUSE_BUTTON_INDEX_LEFT) then
                local cache = GetCacheFromRow(rowControl)
                ClearMenu()
                AddCustomMenuItem("Force Link", function()
                    -- TODO show confirmation dialog and then set the newest event id to first one without a gap
                end)
                AddCustomMenuItem("Clear Cache", function()
                    -- TODO show confirmation dialog and then clear cache
                    local entry = ZO_ScrollList_GetData(rowControl)
                    entry.cache:Clear()
                end)
                AddCustomSubMenuItem("Watch Mode", {
                    {
                        label = "Automatic",
                        itemType = MENU_ADD_OPTION_CHECKBOX,
                        callback = function()
                            cache:SetWatchMode(internal.WATCH_MODE_AUTO)
                        end,
                        checked = function()
                            return cache:GetWatchMode() == internal.WATCH_MODE_AUTO
                        end
                    },
                    {
                        label = "Force off",
                        itemType = MENU_ADD_OPTION_CHECKBOX,
                        callback = function()
                            cache:SetWatchMode(internal.WATCH_MODE_OFF)
                        end,
                        checked = function()
                            return cache:GetWatchMode() == internal.WATCH_MODE_OFF
                        end
                    },
                    {
                        label = "Force on",
                        itemType = MENU_ADD_OPTION_CHECKBOX,
                        callback = function()
                            cache:SetWatchMode(internal.WATCH_MODE_ON)
                        end,
                        checked = function()
                            return cache:GetWatchMode() == internal.WATCH_MODE_ON
                        end
                    }
                })
                ShowMenu(menuButton)
            end
        end, "LibHistoire_Click")
        rowControl.menuButton = menuButton
    end, function(rowControl, entry)
        local cache = entry.cache
        local hasLinked = cache:HasLinked()
        local isIdle = not cache:IsProcessing()
        -- TODO refresh menu state if it is open
    end)
end

function GuildHistoryStatusWindow:SetGuildId(guildId)
    if self.guildId == guildId then return end
    self.guildId = guildId
    self:Update()
end

function GuildHistoryStatusWindow:SetCategory(category)
    if self.category == category then return end
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
    if (self:IsShowing()) then
        local hasLinkedEverything = true

        local guildListControl = self.guildListControl
        local guildScrollData = ZO_ScrollList_GetDataList(guildListControl)
        ZO_ScrollList_Clear(guildListControl)
        local numGuilds = 0
        internal.historyCache:ForEachActiveGuild(function(guildCache)
            numGuilds = numGuilds + 1
            local guildId = guildCache:GetGuildId()
            local label = GetGuildName(guildId)
            local selected = (self.guildId == guildId)
            guildScrollData[#guildScrollData + 1] = self:CreateDataEntry(label, guildCache, numGuilds, selected)
            if selected then self.selectionWidget:SelectGuild(numGuilds) end
            if not guildCache:HasLinked() then hasLinkedEverything = false end
        end)
        self.emptyGuildListRow:SetHidden(numGuilds > 0)
        ZO_ScrollList_Commit(guildListControl)

        local categoryListControl = self.categoryListControl
        local categoryScrollData = ZO_ScrollList_GetDataList(categoryListControl)
        ZO_ScrollList_Clear(categoryListControl)
        if numGuilds > 0 then
            for eventCategory = GUILD_HISTORY_EVENT_CATEGORY_ITERATION_BEGIN, GUILD_HISTORY_EVENT_CATEGORY_ITERATION_END do
                local label = GetString("SI_GUILDHISTORYEVENTCATEGORY", eventCategory)
                local cache = internal.historyCache:GetCategoryCache(self.guildId, eventCategory)
                local selected = (self.category == eventCategory)
                categoryScrollData[#categoryScrollData + 1] = self:CreateDataEntry(label, cache, eventCategory, selected)
                if selected then self.selectionWidget:SelectCategory(#categoryScrollData) end
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

function GuildHistoryStatusWindow:GetZoomMode()
    return self.saveData.zoomMode or internal.ZOOM_MODE_AUTO
end

function GuildHistoryStatusWindow:SetZoomMode(zoomMode)
    self.saveData.zoomMode = zoomMode
    internal:FireCallbacks(internal.callback.ZOOM_MODE_CHANGED, zoomMode)
end

-- SPDX-FileCopyrightText: 2025 sirinsidiator
--
-- SPDX-License-Identifier: Artistic-2.0

local LIB_IDENTIFIER = "LibHistoire"

assert(not _G[LIB_IDENTIFIER], LIB_IDENTIFIER .. " is already loaded")

local lib = {}
_G[LIB_IDENTIFIER] = lib

local nextNamespaceId = 1

local function RegisterForEvent(event, callback)
    local namespace = LIB_IDENTIFIER .. nextNamespaceId
    EVENT_MANAGER:RegisterForEvent(namespace, event, callback)
    nextNamespaceId = nextNamespaceId + 1
    return namespace
end

local function UnregisterForEvent(namespace, event)
    return EVENT_MANAGER:UnregisterForEvent(namespace, event)
end

local function RegisterForUpdate(interval, callback)
    local namespace = LIB_IDENTIFIER .. nextNamespaceId
    EVENT_MANAGER:RegisterForUpdate(namespace, interval, callback)
    nextNamespaceId = nextNamespaceId + 1
    return namespace
end

local function UnregisterForUpdate(namespace)
    return EVENT_MANAGER:UnregisterForUpdate(namespace)
end

local callbackObject = ZO_CallbackObject:New()
lib.internal = {
    callbackObject = callbackObject,
    callback = {
        INITIALIZED = "HistyIsReadyForAction",
        CATEGORY_DATA_UPDATED = "HistyHasUpdatedCategoryData",
        PROCESS_LINKED_EVENTS_STARTED = "HistyHasStartedProcessingLinkedEvents",
        PROCESS_LINKED_EVENT = "HistyIsProcessingALinkedEvent",
        PROCESS_LINKED_EVENTS_FINISHED = "HistyHasFinishedProcessingLinkedEvents",
        PROCESS_MISSED_EVENTS_STARTED = "HistyHasStartedProcessingMissedEvents",
        PROCESS_MISSED_EVENT = "HistyIsProcessingAMissedEvent",
        PROCESS_MISSED_EVENTS_FINISHED = "HistyHasFinishedProcessingMissedEvents",
        SELECTED_CATEGORY_CACHE_CHANGED = "HistyDetectedTheSelectedCategoryCacheHasChanged",
        REQUEST_MODE_CHANGED = "HistyDetectedTheRequestModeHasChanged",
        ZOOM_MODE_CHANGED = "HistyDetectedTheZoomModeHasChanged",
        REQUEST_CREATED = "HistyHasCreatedARequest",
        REQUEST_DESTROYED = "HistyHasDestroyedARequest",
        MANAGED_RANGE_LOST = "HistyDetectedTheManagedRangeHasBeenLost",
        MANAGED_RANGE_FOUND = "HistyDetectedTheManagedRangeHasBeenFound",
        CATEGORY_LINKED = "HistyDetectedACategoryHasBeenLinked",
        DEPRECATED = "deprecated"
    },
    class = {},
    logger = LibDebugLogger(LIB_IDENTIFIER),
    RegisterForEvent = RegisterForEvent,
    UnregisterForEvent = UnregisterForEvent,
    RegisterForUpdate = RegisterForUpdate,
    UnregisterForUpdate = UnregisterForUpdate,
}
local internal = lib.internal

internal.UI_LOAD_TIME = GetTimeStamp()
internal.WORLD_NAME = GetWorldName()

internal.REQUEST_MODE_AUTO = 'auto'
internal.REQUEST_MODE_OFF = 'off'
internal.REQUEST_MODE_ON = 'on'

internal.ZOOM_MODE_AUTO = 'auto'
internal.ZOOM_MODE_FULL_RANGE = 'full'
internal.ZOOM_MODE_MISSING_RANGE = 'missing'

internal.STOP_REASON_MANUAL_STOP = "manualStop"
internal.STOP_REASON_LAST_CACHED_EVENT_REACHED = "lastCachedEventReached"
internal.STOP_REASON_ITERATION_COMPLETED = "iterationCompleted"
internal.STOP_REASON_MANAGED_RANGE_LOST = "managedRangeLost"

function internal:FireCallbacks(...)
    return callbackObject:FireCallbacks(...)
end

function internal:RegisterCallback(...)
    return callbackObject:RegisterCallback(...)
end

function internal:UnregisterCallback(...)
    return callbackObject:UnregisterCallback(...)
end

function internal:InitializeCaches()
    local logger = self.logger
    logger:Verbose("Initializing Caches")
    self.historyAdapter = self.class.GuildHistoryAdapter:New(LibHistoire_GuildHistoryCache, LibHistoire_Settings)
    self.historyCache = self.class.GuildHistoryCache:New(self.historyAdapter, GUILD_HISTORY_MANAGER)
    if not IsConsoleUI() then
        SecurePostHook(ZO_GuildHistory_Keyboard, "OnDeferredInitialize", function(history)
            if self.statusWindow then return end
            logger:Verbose("Initializing user interface")
            self.historyAdapter:InitializeDeferred(history, self.historyCache)
            self.statusTooltip = self.class.GuildHistoryStatusTooltip:New()
            self.linkedIcon = self.class.GuildHistoryStatusLinkedIcon:New(history, self.historyAdapter,
                self.statusTooltip)
            self.statusWindow = self.class.GuildHistoryStatusWindow:New(self.historyAdapter, self.statusTooltip,
                LibHistoire_Settings.statusWindow)
            logger:Verbose("User interface initialized")
        end)
    end

    internal:InitializeQuickNavigation()
    logger:Verbose("Caches initialized")
end

local function HasLegacyData()
    return (LibHistoire_NameDictionary and next(LibHistoire_NameDictionary) ~= nil) or
        (LibHistoire_GuildNames and next(LibHistoire_GuildNames) ~= nil) or
        (LibHistoire_GuildHistory and next(LibHistoire_GuildHistory) ~= nil)
end

function internal:InitializeChatMessage()
    local logger = self.logger
    logger:Verbose("Initializing chat message")
    if not HasLegacyData() then
        logger:Verbose("Chat message initialization skipped")
        return
    end

    local legacyData = {}
    legacyData.LibHistoire_NameDictionary = LibHistoire_NameDictionary
    legacyData.LibHistoire_GuildNames = LibHistoire_GuildNames
    legacyData.LibHistoire_GuildHistory = LibHistoire_GuildHistory
    LibHistoire_NameDictionary = {}
    LibHistoire_GuildNames = {}
    LibHistoire_GuildHistory = {}

    local UNDELETE_LINK_TYPE = "histy_undelete"
    local function HandleLinkClick(link, button, text, linkStyle, linkType)
        if button ~= MOUSE_BUTTON_INDEX_LEFT then return end
        if linkType == UNDELETE_LINK_TYPE then
            LibHistoire_NameDictionary = legacyData.LibHistoire_NameDictionary
            LibHistoire_GuildNames = legacyData.LibHistoire_GuildNames
            LibHistoire_GuildHistory = legacyData.LibHistoire_GuildHistory
            CHAT_ROUTER:AddSystemMessage("[LibHistoire] Obsolete data temporarily restored.")
            return true
        end
    end
    LINK_HANDLER:RegisterCallback(LINK_HANDLER.LINK_CLICKED_EVENT, HandleLinkClick)
    LINK_HANDLER:RegisterCallback(LINK_HANDLER.LINK_MOUSE_UP_EVENT, HandleLinkClick)

    local undeleteLink = ZO_LinkHandler_CreateLink("Click here to keep it for now", nil, UNDELETE_LINK_TYPE)
    CHAT_ROUTER:AddSystemMessage(
        "|cff6a00[LibHistoire][Warning] You have old LibHistoire data which is no longer used. " ..
        "It will be automatically deleted now, to speed up your loading times. " ..
        "This is your last chance to create a backup.\n" .. undeleteLink)
    logger:Verbose("Chat message initialized")
end

function internal:Initialize()
    local logger = self.logger
    logger:Info("Begin pre-initialization")
    local namespace
    namespace = RegisterForEvent(EVENT_ADD_ON_LOADED, function(event, name)
        if (name ~= LIB_IDENTIFIER) then return end
        UnregisterForEvent(namespace, EVENT_ADD_ON_LOADED)
        logger:Info("Begin initialization")
        self:InitializeSaveData()
        self:InitializeCaches()
        self:InitializeDialogs()
        self:InitializeSettingsMenu()
        self.initialized = true
        logger:Info("Initialization complete")
        self:FireCallbacks(self.callback.INITIALIZED, LibHistoire)
        logger:Debug("INITIALIZED callback fired")
    end)

    local eventHandle
    eventHandle = RegisterForEvent(EVENT_PLAYER_ACTIVATED, function()
        UnregisterForEvent(eventHandle, EVENT_PLAYER_ACTIVATED)
        zo_callLater(function()
            logger:Info("Begin deferred initialization")
            self:InitializeChatMessage()
            self.historyCache:StartRequests()
            logger:Info("Deferred initialization complete")
        end, 5000)
    end)
    logger:Info("Pre-initialization complete")
end

function internal:CreateAsyncTask()
    local taskId = self.nextTaskId or 1
    self.nextTaskId = taskId + 1
    local task = LibAsync:Create(LIB_IDENTIFIER .. taskId)
    return task
end

function internal:IsGuildStatusVisible(guildId)
    if not self.historyAdapter or not self.statusWindow or not self.statusWindow:IsShowing() then return false end

    local cache = self.historyAdapter:GetSelectedCategoryCache()
    if not cache then return false end

    return cache:GetGuildId() == guildId
end

do
    -- https://forums.elderscrollsonline.com/en/discussion/682758/guild-history-turned-off-sept-4
    local ESTIMATED_GUILD_HISTORY_RE_ENABLE_TIME_PC = 1757925000 -- Mon Sep 15 2025 08:30:00 GMT+0000
    local ESTIMATED_GUILD_HISTORY_RE_ENABLE_TIME_CONSOLE = 1758011400 -- Tue Sep 16 2025 08:30:00 GMT+0000
    local ESTIMATED_GUILD_HISTORY_RE_ENABLE_TIME = {
        ["NA Megaserver"] = ESTIMATED_GUILD_HISTORY_RE_ENABLE_TIME_PC,
        ["EU Megaserver"] = ESTIMATED_GUILD_HISTORY_RE_ENABLE_TIME_PC,
        ["XB1live"] = ESTIMATED_GUILD_HISTORY_RE_ENABLE_TIME_CONSOLE,
        ["PS4live"] = ESTIMATED_GUILD_HISTORY_RE_ENABLE_TIME_CONSOLE,
        ["XB1live-eu"] = ESTIMATED_GUILD_HISTORY_RE_ENABLE_TIME_CONSOLE,
        ["PS4live-eu"] = ESTIMATED_GUILD_HISTORY_RE_ENABLE_TIME_CONSOLE,
    }
    function internal:IsGuildHistorySystemDisabled()
        local world = GetWorldName()
        local reenableTime = ESTIMATED_GUILD_HISTORY_RE_ENABLE_TIME[world]
        if not reenableTime then return false end
        return GetTimeStamp() < reenableTime
    end
end

-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

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
        PROCESS_MISSED_EVENTS_STARTED =  "HistyHasStartedProcessingMissedEvents",
        PROCESS_MISSED_EVENT = "HistyIsProcessingAMissedEvent",
        PROCESS_MISSED_EVENTS_FINISHED = "HistyHasFinishedProcessingMissedEvents",
        SELECTED_CATEGORY_CACHE_CHANGED = "HistyDetectedTheSelectedCategoryCacheHasChanged",
        WATCH_MODE_CHANGED = "HistyDetectedTheWatchModeHasChanged",
        ZOOM_MODE_CHANGED = "HistyDetectedTheZoomModeHasChanged",
        REQUEST_CREATED = "HistyHasCreatedARequest",
        REQUEST_DESTROYED = "HistyHasDestroyedARequest",
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

internal.WATCH_MODE_AUTO = 'auto'
internal.WATCH_MODE_OFF = 'off'
internal.WATCH_MODE_ON = 'on'

internal.ZOOM_MODE_AUTO = 'auto'
internal.ZOOM_MODE_FULL_RANGE = 'full'
internal.ZOOM_MODE_MISSING_RANGE = 'missing'

function internal:FireCallbacks(...)
    return callbackObject:FireCallbacks(...)
end

function internal:RegisterCallback(...)
    return callbackObject:RegisterCallback(...)
end

function internal:UnregisterCallback(...)
    return callbackObject:UnregisterCallback(...)
end

function internal:InitializeSaveData()
    local server = internal.WORLD_NAME
    self.logger:Verbose("Initializing save data")

    LibHistoire_Settings = LibHistoire_Settings or {
        version = 1,
        statusWindow = {
            enabled = true,
            locked = true
        }
    }

    LibHistoire_GuildNames = LibHistoire_GuildNames or {}
    LibHistoire_NameDictionary = LibHistoire_NameDictionary or {}
    LibHistoire_GuildHistory = LibHistoire_GuildHistory or {}

    self.guildNames = LibHistoire_GuildNames[server] or {}
    LibHistoire_GuildNames[server] = self.guildNames
    self.logger:Verbose("Save data initialized")
end

function internal:InitializeCaches()
    local logger = self.logger
    logger:Verbose("Initializing Caches")
    self.historyCache = self.class.GuildHistoryCache:New(GUILD_HISTORY_MANAGER, LibHistoire_GuildHistory)
    SecurePostHook(ZO_GuildHistory_Keyboard, "OnDeferredInitialize", function(history)
        if self.historyAdapter then return end
        logger:Verbose("Initializing user interface")
        self.historyAdapter = self.class.GuildHistoryAdapter:New(history, self.historyCache)
        self.statusTooltip = self.class.GuildHistoryStatusTooltip:New()
        self.linkedIcon = self.class.GuildHistoryStatusLinkedIcon:New(history, self.historyAdapter, self.statusTooltip)
        self.statusWindow = self.class.GuildHistoryStatusWindow:New(self.historyAdapter, self.statusTooltip,
            LibHistoire_Settings.statusWindow)
        logger:Verbose("User interface initialized")
    end)
    logger:Verbose("Caches initialized")
end

function internal:InitializeChatMessage()
    local logger = self.logger
    logger:Verbose("Initializing chat message")
    if not self.historyCache:HasLegacyData() then
        logger:Verbose("Chat message initialization skipped")
        return
    end
    local DELETE_LINK_TYPE = "histy_delete"
    local function HandleLinkClick(link, button, text, linkStyle, linkType)
        if button ~= MOUSE_BUTTON_INDEX_LEFT then return end
        if linkType == DELETE_LINK_TYPE then
            self.historyCache:DeleteLegacyData()
            CHAT_ROUTER:AddSystemMessage("[LibHistoire] Obsolete data deleted.")
            return true
        end
    end
    LINK_HANDLER:RegisterCallback(LINK_HANDLER.LINK_CLICKED_EVENT, HandleLinkClick)
    LINK_HANDLER:RegisterCallback(LINK_HANDLER.LINK_MOUSE_UP_EVENT, HandleLinkClick)

    local deleteLink = ZO_LinkHandler_CreateLink("Click here to delete it now", nil, DELETE_LINK_TYPE)
    CHAT_ROUTER:AddSystemMessage(
        "|cff6a00[LibHistoire][Warning] You have old LibHistoire data which is no longer used. " ..
        "This is your last chance to back it up in case you want to keep it.\n|cff6a00" ..
        "It is highly recommended you delete it to improve loading times!\n" .. deleteLink)
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
        self:InitializeExitHooks()
        logger:Info("Initialization complete")
        self:FireCallbacks(self.callback.INITIALIZED)
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
    task:OnError(function()
        self.logger:Error(task.Error)
    end)
    return task
end

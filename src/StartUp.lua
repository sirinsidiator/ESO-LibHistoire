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
        UNLINKED_EVENTS_ADDED = "HistyHasAddedUnlinkedEvents",
        EVENT_STORED = "HistyStoredAnEvent",
        HISTORY_BEGIN_LINKING = "HistyHasStartedLinkingEvents",
        HISTORY_LINKED = "HistyHasLinkedEvents",
        HISTORY_RELOADED = "HistyHasDetectedAHistoryReload",
    },
    class = {},
    logger = LibDebugLogger(LIB_IDENTIFIER),
    RegisterForEvent = RegisterForEvent,
    UnregisterForEvent = UnregisterForEvent,
    RegisterForUpdate = RegisterForUpdate,
    UnregisterForUpdate = UnregisterForUpdate,
}
local internal = lib.internal

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
    LibHistoire_GuildNames = LibHistoire_GuildNames or {}
    LibHistoire_NameDictionary = LibHistoire_NameDictionary or {}
    LibHistoire_GuildHistory = LibHistoire_GuildHistory or {}

    local server = GetWorldName()
    self.guildNames = LibHistoire_GuildNames[server] or {}
    LibHistoire_GuildNames[server] = self.guildNames
end

function internal:Initialize()
    local logger = self.logger
    logger:Debug("Initializing LibHistoire...")

    local namespace
    namespace = RegisterForEvent(EVENT_ADD_ON_LOADED, function(event, name)
        if(name ~= LIB_IDENTIFIER) then return end
        UnregisterForEvent(namespace, EVENT_ADD_ON_LOADED)
        self:InitializeSaveData()
        logger:Debug("Saved Variables loaded")

        self.nameCache = self.class.DisplayNameCache:New(LibHistoire_NameDictionary)
        self.historyCache = self.class.GuildHistoryCache:New(self.nameCache, LibHistoire_GuildHistory)

        local function ParseInput(input)
            local guildIndex, category, eventId = input:match("(%d) (%d) ?(.*)")
            if(not guildIndex) then
                return GetGuildId(1), 1, nil
            end
            guildIndex = tonumber(guildIndex) or 1
            category = tonumber(category) or 1
            return GetGuildId(guildIndex), category, tonumber(eventId)
        end

        SLASH_COMMANDS["/gtest1"] = function(input)
            local guildId, category = ParseInput(input)
            local cache = self.historyCache:GetOrCreateCategoryCache(guildId, category)
            logger:Info("rescan events:", cache:RescanEvents())
        end

        local listener
        SLASH_COMMANDS["/gtest2"] = function(input)
            if listener then
                listener:Stop()
                listener = nil
                logger:Info("stopped listener")
            else
                local guildId, category, afterId = ParseInput(input)
                listener = lib:CreateGuildHistoryListener(guildId, category)
                listener:SetNextEventCallback(function(eventType, eventId, eventTime, p1, p2, p3, p4, p5, p6)
                    logger:Debug("next event - guildId: %d, category: %d, eventId: %d", guildId, category, eventId)
                end)
                listener:SetMissedEventCallback(function(eventType, eventId, eventTime, p1, p2, p3, p4, p5, p6)
                    logger:Debug("missed event - guildId: %d, category: %d, eventId: %d", guildId, category, eventId)
                end)
                listener:SetHistoryReloadedCallback(function()
                    logger:Debug("History has reloaded - guildId: %d, category: %d", guildId, category)
                end)
                if afterId then
                    logger:Info("set after event id", afterId)
                    listener:SetAfterEventId(afterId)
                end
                listener:Start()
                logger:Info("started listener")
            end
        end

        logger:Debug("Initialization complete")
    end)
end

function internal:EventIdToId64(eventId)
    return StringToId64(tostring(eventId))
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

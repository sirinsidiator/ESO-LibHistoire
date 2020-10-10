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
    LibHistoire_NameDictionary = LibHistoire_NameDictionary or {}
    LibHistoire_GuildHistory = LibHistoire_GuildHistory or {}
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

        local l5
        SLASH_COMMANDS["/gtest5"] = function(afterId)
            if l5 then
                l5:Stop()
                l5 = nil
                logger:Info("stopped listener")
            else
                local guildId = GetGuildId(3)
                local category = 2
                l5 = lib:CreateGuildHistoryListener(guildId, category)
                l5:SetNextEventCallback(function(eventType, eventId, eventTime, p1, p2, p3, p4, p5, p6)
                    logger:Debug("next event - guildId: %d, category: %d, eventId: %d", guildId, category, eventId)
                end)
                l5:SetMissedEventCallback(function(eventType, eventId, eventTime, p1, p2, p3, p4, p5, p6)
                    logger:Debug("missed event - guildId: %d, category: %d, eventId: %d", guildId, category, eventId)
                end)
                l5:SetHistoryReloadedCallback(function()
                    logger:Debug("History has reloaded - guildId: %d, category: %d", guildId, category)
                end)
                if afterId ~= "" then
                    logger:Info("set after event id", afterId)
                    l5:SetAfterEventId(tonumber(afterId))
                end
                l5:Start()
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

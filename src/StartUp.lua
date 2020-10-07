-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local LIB_IDENTIFIER = "LibHistoire"

assert(not _G[LIB_IDENTIFIER], LIB_IDENTIFIER .. " is already loaded")

local lib = {}
_G[LIB_IDENTIFIER] = lib

local function RegisterForEvent(event, callback)
    return EVENT_MANAGER:RegisterForEvent(LIB_IDENTIFIER, event, callback)
end

local function UnregisterForEvent(event)
    return EVENT_MANAGER:UnregisterForEvent(LIB_IDENTIFIER, event)
end

local callbackObject = ZO_CallbackObject:New()
lib.internal = {
    callbackObject = callbackObject,
    callback = {
        UNLINKED_EVENTS_ADDED = "HistyHasAddedUnlinkedEvents",
        EVENT_STORED = "HistyStoredAnEvent",
        HISTORY_BEGIN_LINKING = "HistyHasStartedLinkingEvents",
        HISTORY_LINKED = "HistyHasLinkedEvents",
    },
    class = {},
    logger = LibDebugLogger(LIB_IDENTIFIER),
    RegisterForEvent = RegisterForEvent,
    UnregisterForEvent = UnregisterForEvent,
}
local internal = lib.internal

function internal:FireCallbacks(...)
    return callbackObject:FireCallbacks(...)
end

function internal:RegisterCallback(...)
    return callbackObject:RegisterCallback(...)
end

function internal:InitializeSaveData()
    LibHistoire_NameDictionary = LibHistoire_NameDictionary or {}
    LibHistoire_GuildHistory = LibHistoire_GuildHistory or {}
end

function internal:Initialize()
    local logger = self.logger
    logger:Debug("Initializing LibHistoire...")

    RegisterForEvent(EVENT_ADD_ON_LOADED, function(event, name)
        if(name ~= LIB_IDENTIFIER) then return end
        UnregisterForEvent(EVENT_ADD_ON_LOADED)
        self:InitializeSaveData()
        logger:Debug("Saved Variables loaded")

        self.nameCache = self.class.DisplayNameCache:New(LibHistoire_NameDictionary)
        self.historyCache = self.class.GuildHistoryCache:New(self.nameCache, LibHistoire_GuildHistory)

        SLASH_COMMANDS["/gtest4"] = function()
            -- iterate over all available events in a category
            local guildId = GetGuildId(3)
            local category = 3
            self:RegisterForGuildHistory(guildId, category, function(index, eventType, eventId, eventTime)
                logger:Debug("iterate event - guildId: %d, category: %d, eventId: %d (%d)", guildId, category, eventId, index)
            end)
        end

        logger:Debug("Initialization complete")
    end)
end

local function EventIterator(categoryCache, index)
    index = index + 1
    local event = categoryCache:GetEntry(index)
    if event then
        return index, event
    end
end

function internal:GetEventIterator(guildId, category, startEventId)
    local categoryCache = self.historyCache:GetOrCreateCategoryCache(guildId, category)
    local index = categoryCache:FindIndexFor(startEventId)
    return EventIterator, categoryCache, index
end

function internal:GetEvent(guildId, category, eventId)
    local categoryCache = self.historyCache:GetOrCreateCategoryCache(guildId, category)
    local index = categoryCache:FindIndexFor(eventId)
    local event = categoryCache:GetEntry(index)
    return event, index
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

function internal:RegisterForGuildHistory(guildId, category, callback, startEventId)
    local iterateStoredEventsUntilLastIsReached, lastEventId
    local task = self:CreateAsyncTask()

    local function registerCallback()
        self:RegisterCallback(self.callback.EVENT_STORED, function(storedGuildId, storedCategory, event, index)
            if guildId ~= storedGuildId or category ~= storedCategory then return end
            callback(index, event:Unpack())
        end)
    end

    local function onFinishedIterating()
        local categoryCache = self.historyCache:GetOrCreateCategoryCache(guildId, category)
        local lastStoredEntry = categoryCache:GetEntry(categoryCache:GetNumEntries())
        if not lastEventId or (lastStoredEntry and lastEventId == lastStoredEntry:GetEventId()) then
            self.logger:Info("iterated all stored events - register for callback")
            registerCallback()
        else
            self.logger:Info("has not reached the end yet - go for another round")
            iterateStoredEventsUntilLastIsReached(lastEventId)
        end
    end

    function iterateStoredEventsUntilLastIsReached(startEventId)
        lastEventId = nil
        task:For(self:GetEventIterator(guildId, category, startEventId)):Do(function(i, event)
            callback(i, event:Unpack())
            lastEventId = event:GetEventId()
        end):Then(onFinishedIterating)
    end
    iterateStoredEventsUntilLastIsReached(startEventId)
end

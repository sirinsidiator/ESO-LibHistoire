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

lib.internal = {
    class = {},
    logger = LibDebugLogger(LIB_IDENTIFIER),
    RegisterForEvent = RegisterForEvent,
    UnregisterForEvent = UnregisterForEvent,
}

function lib.internal:InitializeSaveData()
    LibHistoire_NameDictionary = LibHistoire_NameDictionary or {}
    LibHistoire_GuildHistory = LibHistoire_GuildHistory or {}
end

function lib.internal:Initialize()
    local class = self.class
    local logger = self.logger

    logger:Debug("Initializing LibHistoire...")
    local internal = lib.internal

    RegisterForEvent(EVENT_ADD_ON_LOADED, function(event, name)
        if(name ~= LIB_IDENTIFIER) then return end
        UnregisterForEvent(EVENT_ADD_ON_LOADED)
        internal:InitializeSaveData()
        logger:Debug("Saved Variables loaded")

        self.nameCache = internal.class.DisplayNameCache:New(LibHistoire_NameDictionary)
        self.historyCache = internal.class.GuildHistoryCache:New(self.nameCache, LibHistoire_GuildHistory)

        SLASH_COMMANDS["/gtest2"] = function()
            self.historyCache:UpdateAllCategories()
        end

        SLASH_COMMANDS["/gtest3"] = function()
            LibHistoire_NameDictionary = {}
            LibHistoire_GuildHistory = {}
            ReloadUI()
        end

        logger:Debug("Initialization complete")
    end)
end

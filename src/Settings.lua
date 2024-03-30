-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local LAM = LibAddonMenu2
local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

function internal:InitializeSaveData()
    self.logger:Verbose("Initializing save data")

    LibHistoire_Settings = LibHistoire_Settings or {
        version = 1,
        statusWindow = {
            enabled = true,
            locked = true
        }
    }

    LibHistoire_GuildHistoryCache = LibHistoire_GuildHistoryCache or {}
    local account = GetDisplayName()
    LibHistoire_GuildHistoryCache[account] = LibHistoire_GuildHistoryCache[account] or {}

    self.logger:Verbose("Save data initialized")
end

function internal:InitializeSettingsMenu()
    local adapter = self.historyAdapter

    local panelData = {
        type = "panel",
        name = "LibHistoire",
        author = "sirinsidiator",
        version = "@FULL_VERSION_NUMBER@",
        website = "https://www.esoui.com/downloads/info2817-LibHistoire-GuildHistory.html",
        feedback = "https://www.esoui.com/downloads/info2817-LibHistoire-GuildHistory.html#comments",
        donation = "https://www.esoui.com/downloads/info2817-LibHistoire-GuildHistory.html#donate",
        registerForRefresh = true,
        registerForDefaults = true
    }
    local panel = LAM:RegisterAddonPanel("LibHistoireOptions", panelData)

    local optionsData = {}

    optionsData[#optionsData + 1] = {
        type = "header",
        name = "Cache Retention Time",
    }

    optionsData[#optionsData + 1] = {
        type = "description",
        text = "These settings control how long the game keeps guild history data cached. " ..
            "The game will automatically delete data that is older than the specified number of days on each login. " ..
            "The maximum number of days you can set is not limited, but longer retention times will negatively affect loading times.",
    }

    for eventCategory = GUILD_HISTORY_EVENT_CATEGORY_ITERATION_BEGIN, GUILD_HISTORY_EVENT_CATEGORY_ITERATION_END do
        local serverMaxDays = adapter:GetGuildHistoryServerMaxDays(eventCategory)
        optionsData[#optionsData + 1] = {
            type = "slider",
            name = GetString("SI_GUILDHISTORYEVENTCATEGORY", eventCategory),
            min = serverMaxDays,
            max = 365,
            clampInput = false,
            getFunc = function()
                return adapter:GetGuildHistoryCacheMaxDays(eventCategory)
            end,
            setFunc = function(value)
                if value < serverMaxDays then
                    value = serverMaxDays
                end
                adapter:SetGuildHistoryCacheMaxDays(eventCategory, value)
            end,
            default = serverMaxDays,
        }
    end

    optionsData[#optionsData + 1] = {
        type = "button",
        name = "Clear all history caches",
        tooltip = "Pressing this button will delete all stored guild history data and reload the UI.",
        warning =
        "This is usually not needed and as such not recommended, unless you know what you are doing and already tried everything else.",
        isDangerous = true,
        func = function()
            logger:Warn("Clearing all caches")
            for i = 1, GetNumGuilds() do
                local guildId = GetGuildId(i)
                local result = ClearGuildHistoryCache(guildId)
                logger:Info("Cache clear result for guild", guildId, result)
            end
            ReloadUI()
        end,
    }

    optionsData[#optionsData + 1] = {
        type = "editbox",
        reference = "LibHistoireCachePathEditbox",
        name = "Cache Path",
        tooltip = "This is the folder where the cache files are stored.",
        isExtraWide = true,
        getFunc = function()
            if IsMacUI() then
                return "~/Documents/Elder Scrolls Online/live/CachedData/GuildHistory"
            else
                return "%AppData%/../Local/Elder Scrolls Online/live/CachedData/GuildHistory"
            end
        end,
        setFunc = function(value)
            -- do nothing
        end,
    }
    LAM:RegisterOptionControls("LibHistoireOptions", optionsData)

    CALLBACK_MANAGER:RegisterCallback("LAM-PanelControlsCreated", function(openedPanel)
        if panel ~= openedPanel then return end
        local editbox = LibHistoireCachePathEditbox.editbox
        editbox:SetEditEnabled(false)
        editbox:SetSelectAllOnFocus(true)
        editbox:SetCursorPosition(0)
    end)

    internal.OpenSettingsPanel = function()
        LAM:OpenToPanel(panel)
    end
end

-- SPDX-FileCopyrightText: 2025 sirinsidiator
--
-- SPDX-License-Identifier: Artistic-2.0

local LAM = LibAddonMenu2
local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

function internal:InitializeSaveData()
    self.logger:Verbose("Initializing save data")

    local settings = LibHistoire_Settings or {
        version = 2,
        statusWindow = {
            enabled = true,
            locked = true
        },
        markGapsInHistory = true,
    }

    if settings.version < 2 then
        settings.version = 2
        settings.markGapsInHistory = true
    end

    LibHistoire_Settings = settings
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
        name = "General",
    }

    optionsData[#optionsData + 1] = {
        type = "checkbox",
        name = "Enable guild history logging",
        tooltip =
        "When enabled, the game will log additional information about the guild history cache to the Logs directory in the user folder.",
        warning = "Changes to this setting are only applied when the game is restarted.",
        getFunc = function()
            return adapter:IsGuildHistoryLoggingEnabled()
        end,
        setFunc = function(value)
            adapter:SetGuildHistoryLoggingEnabled(value)
        end,
    }

    optionsData[#optionsData + 1] = {
        type = "checkbox",
        name = "Mark gaps in history list",
        tooltip =
        "When enabled, LibHistoire will inject additional rows into the ingame guild history to mark gaps in the history.",
        requiresReload = true,
        getFunc = function()
            return adapter:IsMarkGapsFeatureEnabled()
        end,
        setFunc = function(value)
            adapter:SetMarkGapsFeatureEnabled(value)
        end,
    }

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
        type = "checkbox",
        name = "Keep cache data after leaving a guild",
        tooltip =
            "When enabled, the game won't automatically delete the cached data when leaving a guild. " ..
            "This is only useful if you plan to rejoin the guild later, " ..
            "as the information cannot be accessed while you are not a member of that guild.",
        getFunc = function()
            return not adapter:IsAutoDeleteLeftGuildsEnabled()
        end,
        setFunc = function(value)
            adapter:SetAutoDeleteLeftGuildsEnabled(not value)
        end,
    }

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
                return "~/Documents/Elder Scrolls Online/live/GuildHistory"
            else
                return "%UserProfile%\\Documents\\Elder Scrolls Online\\live\\GuildHistory"
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

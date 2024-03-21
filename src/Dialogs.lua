local internal = LibHistoire.internal

local DIALOG_ID = "LibHistoire"

local function GetWarningDialog()
    if not ESO_Dialogs[DIALOG_ID] then
        ESO_Dialogs[DIALOG_ID] = {
            canQueue = true,
            gamepadInfo = {
                dialogType = GAMEPAD_DIALOGS.CENTERED
            },
            setup = function(dialog)
                dialog:setupFunc()
            end,
            title = {
                text = "",
            },
            mainText = {
                text = "",
            },
            buttons = {
                [1] = {
                    text = "",
                    callback = function(dialog) end,
                },
                [2] = {
                    text = "",
                }
            }
        }
    end
    return ESO_Dialogs[DIALOG_ID]
end

local function ShowWarningDialog()
    if IsInGamepadPreferredMode() then
        ZO_Dialogs_ShowGamepadDialog(DIALOG_ID)
    else
        ZO_Dialogs_ShowDialog(DIALOG_ID)
    end
end

local function ShowShutdownWarningDialog(message, buttonText, callback)
    local dialog = GetWarningDialog()
    dialog.title.text = "Warning"
    dialog.mainText.text = message

    local primaryButton = dialog.buttons[1]
    primaryButton.text = "Open History"
    primaryButton.callback = function(dialog)
        MAIN_MENU_KEYBOARD:ShowScene("guildHistory")
    end

    local secondaryButton = dialog.buttons[2]
    secondaryButton.text = buttonText
    secondaryButton.callback = callback

    ZO_Dialogs_ReleaseDialogOnButtonPress("GAMEPAD_LOG_OUT")
    ShowWarningDialog()
end

local function ShowResetManagedRangeDialog(_, callback)
    local dialog = GetWarningDialog()
    dialog.title.text = "Warning"
    dialog.mainText.text =
        "Resetting the managed range will make LibHistoire forget from which point to start requesting events and what data has already been sent to addons.\n\n" ..
        "This action is usually not necessary, but can be used to skip over a large gap of missing data after a prolonged absence.\n\n" ..
        "Use it with caution, as it means addons may miss out on events to process, which can cause holes in your data!"

    local primaryButton = dialog.buttons[1]
    primaryButton.text = SI_DIALOG_CONFIRM
    primaryButton.callback = callback

    local secondaryButton = dialog.buttons[2]
    secondaryButton.text = SI_DIALOG_CANCEL
    secondaryButton.callback = nil

    ShowWarningDialog()
end

local function ShowClearCacheDialog(_, callback)
    local dialog = GetWarningDialog()
    dialog.title.text = "Warning"
    dialog.mainText.text =
        "Clearing the cache will delete locally stored events and force the game to fetch them again from the server.\n\n" ..
        "This action is not recommended as it will have a negative effect on the server and you will potentially delete data that cannot be requested again.\n\n" ..
        "It will implicitly also reset the managed range and thus will cause addons to potentially miss out on events, which can cause holes in your data!\n\n" ..
        "You should only use this as an absolute last resort when nothing else has worked!\n\n" ..
        "The UI will be reloaded when you confirm this action."

    local primaryButton = dialog.buttons[1]
    primaryButton.text = SI_DIALOG_CONFIRM
    primaryButton.callback = callback

    local secondaryButton = dialog.buttons[2]
    secondaryButton.text = SI_DIALOG_CANCEL
    secondaryButton.callback = nil

    ShowWarningDialog()
end

local function ShowShutdownWarningIfNeeded(cache, buttonText, originalCallback, ...)
    if cache:IsProcessing() then
        ShowShutdownWarningDialog(
            "LibHistoire is currently processing events! If you exit now, you may corrupt your save data.\n\n" ..
            "You are advised to check the status window and wait until all events have been processed before reloading the UI.",
            buttonText, originalCallback)
    elseif not cache:HasLinkedAllCachesRecently() then
        ShowShutdownWarningDialog(
            "LibHistoire has not been able to link the managed history range of one or more categories to present history for over a week.\n\n" ..
            "You are advised to check the status window and try to manually request missing data to avoid interruptions in the data flow for dependent addons.",
            buttonText, originalCallback)
    else
        return originalCallback(...)
    end
end

local function SetupDialogHook(cache, name)
    local primaryButton = ESO_Dialogs[name].buttons[1]
    local originalCallback = primaryButton.callback
    primaryButton.callback = function(...)
        return ShowShutdownWarningIfNeeded(cache, primaryButton.text, originalCallback, ...)
    end
end

local function SetupSlashCommandHook(cache, name, buttonText)
    local originalSlashCommand = SLASH_COMMANDS[name]
    SLASH_COMMANDS[name] = function(...)
        return ShowShutdownWarningIfNeeded(cache, buttonText, originalSlashCommand, ...)
    end
end

function internal:InitializeDialogs()
    local cache = self.historyCache
    SetupDialogHook(cache, "LOG_OUT")
    SetupDialogHook(cache, "GAMEPAD_LOG_OUT")
    SetupDialogHook(cache, "QUIT")
    SetupSlashCommandHook(cache, GetString(SI_SLASH_LOGOUT), GetString(SI_LOG_OUT_GAME_CONFIRM_KEYBIND))
    SetupSlashCommandHook(cache, GetString(SI_SLASH_CAMP), GetString(SI_LOG_OUT_GAME_CONFIRM_KEYBIND))
    SetupSlashCommandHook(cache, GetString(SI_SLASH_QUIT), GetString(SI_QUIT_GAME_CONFIRM_KEYBIND))

    local originalReloadUI = ReloadUI
    function ReloadUI(...)
        if cache:IsProcessing() then
            local params = { ... }
            ShowShutdownWarningDialog(
                "LibHistoire is currently processing events! If you reload the UI now, you may corrupt your save data.\n\n" ..
                "You are advised to check the status window and wait until all events have been processed before reloading the UI.",
                "Reload UI", function()
                    cache:Shutdown()
                    return originalReloadUI(unpack(params))
                end)
        else
            cache:Shutdown()
            return originalReloadUI(...)
        end
    end

    internal.ShowClearCacheDialog = ShowClearCacheDialog
    internal.ShowResetManagedRangeDialog = ShowResetManagedRangeDialog
end

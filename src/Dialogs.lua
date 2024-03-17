local internal = LibHistoire.internal

local DIALOG_ID = "LibHistoire"

function internal:GetWarningDialog()
    if not ESO_Dialogs[DIALOG_ID] then
        ESO_Dialogs[DIALOG_ID] = {
            canQueue = true,
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

function internal:ShowQuitWarningDialog(message, buttonText, callback)
    local dialog = self:GetWarningDialog()
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

    ZO_Dialogs_ShowDialog(DIALOG_ID)
end

function internal:ShowResetLinkedRangeDialog(callback)
    local dialog = self:GetWarningDialog()
    dialog.title.text = "Warning"
    dialog.mainText.text =
        "Resetting the linked range will make LibHistoire forget from which point to start requesting events and what data has already been sent to addons.\n\n" ..
        "This action is usually not necessary, but can be used to skip over a large gap of missing data after a prolonged absence.\n\n" ..
        "Use it with caution, as it means addons may miss out on events to process, which can cause holes in your data!"

    local primaryButton = dialog.buttons[1]
    primaryButton.text = SI_DIALOG_CONFIRM
    primaryButton.callback = callback

    local secondaryButton = dialog.buttons[2]
    secondaryButton.text = SI_DIALOG_CANCEL

    ZO_Dialogs_ShowDialog(DIALOG_ID)
end

function internal:ShowClearCacheDialog(callback)
    local dialog = self:GetWarningDialog()
    dialog.title.text = "Warning"
    dialog.mainText.text =
        "Clearing the cache will delete locally stored events and force the game to fetch them again from the server.\n\n" ..
        "This action is not recommended as it will have a negative effect on the server and you will potentially delete data that cannot be requested again.\n\n" ..
        "It will implicitly also reset the linked range and thus will cause addons to potentially miss out on events, which can cause holes in your data!\n\n" ..
        "You should only use this as an absolute last resort when nothing else has worked!\n\n" ..
        "The UI will be reloaded when you confirm this action."

    local primaryButton = dialog.buttons[1]
    primaryButton.text = SI_DIALOG_CONFIRM
    primaryButton.callback = callback

    local secondaryButton = dialog.buttons[2]
    secondaryButton.text = SI_DIALOG_CANCEL

    ZO_Dialogs_ShowDialog(DIALOG_ID)
end

function internal:SetupDialogHook(name)
    local primaryButton = ESO_Dialogs[name].buttons[1]
    local originalCallback = primaryButton.callback
    primaryButton.callback = function(dialog)
        if self.historyCache:IsProcessing() then
            self:ShowQuitWarningDialog(
                "LibHistoire is currently processing history! If you close the game now, you may corrupt your save data.",
                primaryButton.text, originalCallback)
        elseif not self.historyCache:HasLinkedAllCaches() then
            self:ShowQuitWarningDialog(
                "LibHistoire has not linked your history yet! If you close the game now, you will lose any progress and have to start over the next time.",
                primaryButton.text, originalCallback)
        else
            originalCallback(dialog)
        end
    end
end

function internal:InitializeExitHooks()
    self:SetupDialogHook("LOG_OUT")
    self:SetupDialogHook("QUIT")
    local originalReloadUI = ReloadUI
    function ReloadUI(...)
        internal.logger:Debug("ReloadUI called")
        if self.historyCache:IsProcessing() then
            local params = { ... }
            self:ShowQuitWarningDialog(
                "LibHistoire is currently processing history! If you reload the UI now, you may corrupt your save data.",
                "Reload UI", function()
                    self.historyCache:Shutdown()
                    return originalReloadUI(unpack(params))
                end)
        else
            self.historyCache:Shutdown()
            return originalReloadUI(...)
        end
    end
end

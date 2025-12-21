-- SPDX-FileCopyrightText: 2025 sirinsidiator
--
-- SPDX-License-Identifier: Artistic-2.0

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local GuildHistoryStatusTooltip = ZO_InitializingObject:Subclass()
internal.class.GuildHistoryStatusTooltip = GuildHistoryStatusTooltip

local TOOLTIP_UPDATE_INTERVAL = 500 -- ms

function GuildHistoryStatusTooltip:Initialize()
    self.control = InformationTooltip
    self.target = nil
end

function GuildHistoryStatusTooltip:Show(target, cache)
    local tooltip = self.control
    InitializeTooltip(tooltip, target, RIGHT, 0, 0)

    if cache:IsAggregated() then
        self:SetupForGuild(cache)
    else
        self:SetupForCategory(cache)
    end

    self.target = target
    self.cache = cache
end

function GuildHistoryStatusTooltip:SetupForCategory(cache)
    local tooltip = self.control

    if cache:IsAutoRequesting() then
        SetTooltipText(tooltip,
            zo_strformat("Loaded managed events: |cffffff<<1>>|r", ZO_CommaDelimitDecimalNumber(cache:GetNumLoadedManagedEvents())))
        local _, oldestManagedEventTime = cache:GetOldestManagedEventInfo()
        if oldestManagedEventTime then
            local date, time = FormatAchievementLinkTimestamp(oldestManagedEventTime)
            SetTooltipText(tooltip, zo_strformat("Oldest managed event: |cffffff<<1>> <<2>>|r", date, time))
        end

        local _, newestManagedEventTime = cache:GetNewestManagedEventInfo()
        if newestManagedEventTime then
            local date, time = FormatAchievementLinkTimestamp(newestManagedEventTime)
            SetTooltipText(tooltip, zo_strformat("Newest managed event: |cffffff<<1>> <<2>>|r", date, time))
        end
    else
        SetTooltipText(tooltip, "Missing events are not requested automatically", 0, 1, 0)
    end

    local shouldUnregisterForUpdate = true
    if cache:IsProcessing() then
        SetTooltipText(tooltip, "Events are being processed...", 1, 1, 0)
        local count, speed, timeLeft = cache:GetPendingEventMetrics()
        SetTooltipText(tooltip, zo_strformat("<<1>> events left", count), 1, 1, 0)
        if timeLeft >= 0 then
            timeLeft = math.floor(timeLeft / 60)
            if speed < 100 then
                speed = string.format("%.1f", speed)
            else
                speed = string.format("%d", speed)
            end
            SetTooltipText(tooltip,
                zo_strformat("<<1[less than a minute/one minute/$d minutes]>> remaining (<<2>> events per second)",
                    timeLeft, speed), 1, 1, 0)
        else
            SetTooltipText(tooltip, "Calculating time remaining...", 1, 1, 0)
        end
        self:RegisterForUpdate()
        shouldUnregisterForUpdate = false
    elseif cache:HasLinked() then
        if cache:HasCachedEvents() then
            SetTooltipText(tooltip, "History has been linked to present events", 0, 1, 0)
        end
    elseif cache:HasPendingRequest() then
        SetTooltipText(tooltip, "Waiting for request to be sent", 1, 0, 0)
    else
        SetTooltipText(tooltip, "History has not linked to present events yet", 1, 0, 0)
        SetTooltipText(tooltip,
            zo_strformat("Unlinked events: |cffffff<<1>>|r", ZO_CommaDelimitDecimalNumber(cache:GetNumUnlinkedEvents())))

        local oldestUnlinkedEventTime = cache:GetOldestUnlinkedEventTime()
        if oldestUnlinkedEventTime then
            local date, time = FormatAchievementLinkTimestamp(oldestUnlinkedEventTime)
            SetTooltipText(tooltip, zo_strformat("Oldest unlinked event: |cffffff<<1>> <<2>>|r", date, time))
        end

        local progress, missingTime = cache:GetProgress()
        if missingTime > 0 then
            missingTime = ZO_FormatTime(missingTime, TIME_FORMAT_STYLE_DESCRIPTIVE_MINIMAL)
            SetTooltipText(tooltip, string.format("Missing time: |cffffff%s (%.1f%%)|r", missingTime, progress * 100))
        end
    end

    local names, count, lastSeenTime = cache:GetProcessorInfo()
    if count > 0 then
        names[#names + 1] = string.format("%d legacy listener%s", count, count > 1 and "s" or "")
    end
    if #names > 0 then
        SetTooltipText(tooltip, "Active Processors:")
        for i = 1, #names do
            SetTooltipText(tooltip, string.format("|cffffff%s|r", names[i]))
        end
    else
        SetTooltipText(tooltip, "No active processors")
        if lastSeenTime and lastSeenTime > 0 then
            SetTooltipText(tooltip,
                string.format("Last processor seen: |cffffff%s|r", ZO_FormatDurationAgo(GetTimeStamp() - lastSeenTime)))
        end
    end

    if shouldUnregisterForUpdate then
        self:UnregisterForUpdate()
    end
end

function GuildHistoryStatusTooltip:SetupForGuild(cache)
    local tooltip = self.control

    SetTooltipText(tooltip,
        zo_strformat("Loaded managed events: |cffffff<<1>>|r", ZO_CommaDelimitDecimalNumber(cache:GetNumLoadedManagedEvents())))
    local _, oldestManagedEventTime = cache:GetOldestManagedEventInfo()
    if oldestManagedEventTime then
        local date, time = FormatAchievementLinkTimestamp(oldestManagedEventTime)
        SetTooltipText(tooltip, zo_strformat("Oldest managed event: |cffffff<<1>> <<2>>|r", date, time))
    end

    local _, newestManagedEventTime = cache:GetNewestManagedEventInfo()
    if newestManagedEventTime then
        local date, time = FormatAchievementLinkTimestamp(newestManagedEventTime)
        SetTooltipText(tooltip, zo_strformat("Newest managed event: |cffffff<<1>> <<2>>|r", date, time))
    end

    SetTooltipText(tooltip, "For progress details check each category")
end

function GuildHistoryStatusTooltip:RegisterForUpdate()
    if not self.updateHandle then
        self.updateHandle = internal.RegisterForUpdate(TOOLTIP_UPDATE_INTERVAL, function()
            self:Show(self.target, self.cache)
        end)
    end
end

function GuildHistoryStatusTooltip:UnregisterForUpdate()
    if self.updateHandle then
        internal.UnregisterForUpdate(self.updateHandle)
        self.updateHandle = nil
    end
end

function GuildHistoryStatusTooltip:ShowText(target, text)
    local tooltip = self.control
    InitializeTooltip(tooltip, target, RIGHT, 0, 0)
    SetTooltipText(tooltip, text)
    self.target = target
    self:UnregisterForUpdate()
end

function GuildHistoryStatusTooltip:Hide()
    ClearTooltip(self.control)
    self.target = nil
    self.cache = nil
    self:UnregisterForUpdate()
end

function GuildHistoryStatusTooltip:GetTarget()
    return self.target
end

-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local GuildHistoryStatusTooltip = ZO_Object:Subclass()
internal.class.GuildHistoryStatusTooltip = GuildHistoryStatusTooltip

function GuildHistoryStatusTooltip:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function GuildHistoryStatusTooltip:Initialize()
    self.control = InformationTooltip
    self.target = nil
end

function GuildHistoryStatusTooltip:Show(target, cache)
    local tooltip = self.control
    InitializeTooltip(tooltip, target, RIGHT, 0, 0)

    SetTooltipText(tooltip, zo_strformat("Stored events: |cffffff<<1>>|r", ZO_LocalizeDecimalNumber(cache:GetNumEvents())))
    local firstStoredEvent = cache:GetOldestEvent()
    if firstStoredEvent then
        local date, time = FormatAchievementLinkTimestamp(firstStoredEvent:GetEventTime())
        SetTooltipText(tooltip, zo_strformat("Oldest stored event: |cffffff<<1>> <<2>>|r", date, time))
    end

    local lastStoredEvent = cache:GetNewestEvent()
    if lastStoredEvent then
        local date, time = FormatAchievementLinkTimestamp(lastStoredEvent:GetEventTime())
        SetTooltipText(tooltip, zo_strformat("Newest stored event: |cffffff<<1>> <<2>>|r", date, time))
    end

    if cache:IsAggregated() then
        SetTooltipText(tooltip, "For progress details check each category")
    elseif cache:IsProcessing() then
        SetTooltipText(tooltip, "Events are being processed...", 1, 1, 0)
    elseif cache:HasLinked() then
        SetTooltipText(tooltip, "History has been linked to stored events", 0, 1, 0)
    else
        SetTooltipText(tooltip, "History has not linked to stored events yet", 1, 0, 0)
        SetTooltipText(tooltip, zo_strformat("Unlinked events: |cffffff<<1>>|r", ZO_LocalizeDecimalNumber(cache:GetNumUnlinkedEvents())))

        local firstUnlinkedEvent = cache:GetUnlinkedEntry(1)
        if firstUnlinkedEvent then
            local date, time = FormatAchievementLinkTimestamp(firstUnlinkedEvent:GetEventTime())
            SetTooltipText(tooltip, zo_strformat("Oldest unlinked event: |cffffff<<1>> <<2>>|r", date, time))
        end

        local progress, missingTime = cache:GetProgress()
        if missingTime > 0 then
            missingTime = ZO_FormatTime(missingTime, TIME_FORMAT_STYLE_DESCRIPTIVE_MINIMAL)
            SetTooltipText(tooltip, string.format("Missing time: |cffffff%s (%.1f%%)|r", missingTime, progress * 100))
        end
    end

    self.target = target
end

function GuildHistoryStatusTooltip:ShowText(target, text)
    local tooltip = self.control
    InitializeTooltip(tooltip, target, RIGHT, 0, 0)
    SetTooltipText(tooltip, text)
    self.target = target
end

function GuildHistoryStatusTooltip:Hide()
    ClearTooltip(self.control)
    self.target = nil
end

function GuildHistoryStatusTooltip:GetTarget()
    return self.target
end

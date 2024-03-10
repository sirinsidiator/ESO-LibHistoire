-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local DEFAULT_COLOR = ZO_DISABLED_TEXT
local DEFAULT_LINE_THICKNESS = 3
local SELECTED_COLOR = ZO_SELECTED_TEXT
local SELECTED_LINE_THICKNESS = 6
local HORIZONTAL_LINE_LENGTH = 15

local GuildHistoryStatusSelectionWidget = ZO_Object:Subclass()
internal.class.GuildHistoryStatusSelectionWidget = GuildHistoryStatusSelectionWidget

function GuildHistoryStatusSelectionWidget:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function GuildHistoryStatusSelectionWidget:Initialize(parent, rowHeight)
    self.container = parent:GetNamedChild("SelectionWidget")
    self.rowHeight = rowHeight
    self.nextLineId = 1
    self.verticalLine = self:CreateVerticalLine(DEFAULT_COLOR, DEFAULT_LINE_THICKNESS)
    self.verticalLine:SetAnchor(TOP, self.container, TOP, 0, 0)
    self.verticalSelectionLine = self:CreateVerticalLine(SELECTED_COLOR, SELECTED_LINE_THICKNESS)
    self.verticalSelectionLine:SetDrawLevel(1)
    self.guildCount = 0
    self.guildIndex = 0
    self.guildSelectionLine = self:CreateHorizontalLine(SELECTED_COLOR, SELECTED_LINE_THICKNESS)
    self.guildSelectionLine:SetDrawLevel(1)
    self.categoryCount = 0
    self.categoryIndex = 0
    self.categorySelectionLine = self:CreateHorizontalLine(SELECTED_COLOR, SELECTED_LINE_THICKNESS)
    self.categorySelectionLine:SetDrawLevel(1)
    self.categoryLines = {}
end

function GuildHistoryStatusSelectionWidget:CreateLine(color)
    local line = self.container:CreateControl("$(parent)Line" .. self.nextLineId, CT_TEXTURE)
    self.nextLineId = self.nextLineId + 1
    line:SetColor(color:UnpackRGBA())
    line:SetDrawLevel(0)
    return line
end

function GuildHistoryStatusSelectionWidget:CreateVerticalLine(color, thickness)
    local line = self:CreateLine(color)
    line:SetWidth(thickness)
    return line
end

function GuildHistoryStatusSelectionWidget:CreateHorizontalLine(color, thickness)
    local line = self:CreateLine(color)
    line:SetWidth(HORIZONTAL_LINE_LENGTH)
    line:SetHeight(thickness)
    return line
end

function GuildHistoryStatusSelectionWidget:SetGuildCount(count)
    self.guildCount = count
end

function GuildHistoryStatusSelectionWidget:SelectGuild(index)
    self.guildIndex = index
end

function GuildHistoryStatusSelectionWidget:SetCategoryCount(count)
    for i = 1, math.max(self.categoryCount, count) do
        if not self.categoryLines[i] then
            local line = self:CreateHorizontalLine(DEFAULT_COLOR, DEFAULT_LINE_THICKNESS)
            line:SetAnchor(TOPLEFT, self.container, TOP, 0, (i - 1) * self.rowHeight)
            self.categoryLines[i] = line
        end
        self.categoryLines[i]:SetHidden(i > count)
    end
    self.categoryCount = count
end

function GuildHistoryStatusSelectionWidget:SelectCategory(index)
    self.categoryIndex = index
end

function GuildHistoryStatusSelectionWidget:Update()
    local rowCount = math.max(self.guildCount, self.categoryCount)
    self.verticalLine:SetHeight((rowCount - 1) * self.rowHeight + DEFAULT_LINE_THICKNESS)

    local guildRowOffset = (self.guildIndex - 1) * self.rowHeight
    local categoryRowOffset = (self.categoryIndex - 1) * self.rowHeight
    self.verticalSelectionLine:SetAnchor(TOP, self.container, TOP, 0, math.min(guildRowOffset, categoryRowOffset))
    self.verticalSelectionLine:SetHeight(math.abs(guildRowOffset - categoryRowOffset) + SELECTED_LINE_THICKNESS)
    self.guildSelectionLine:SetAnchor(TOPRIGHT, self.container, TOP, 0, guildRowOffset)
    self.categorySelectionLine:SetAnchor(TOPLEFT, self.container, TOP, 0, categoryRowOffset)
end

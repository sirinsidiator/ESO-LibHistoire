-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local CacheStatusBar = ZO_InitializingObject:Subclass()
internal.class.CacheStatusBar = CacheStatusBar

local GRADIENT_CACHE_SEGMENT_BEFORE_LINKED_RANGE = { ZO_ColorDef:New("FF929292"), ZO_ColorDef:New("FFACACAC") }
local GRADIENT_CACHE_SEGMENT_LINKED_RANGE = { ZO_ColorDef:New("FF0074C2"), ZO_ColorDef:New("FF0099FF") }
local GRADIENT_CACHE_SEGMENT_LINKED_RANGE_UNWATCHED = { ZO_ColorDef:New("FFC1C1C1"), ZO_ColorDef:New("FFD3D3D3") }
local GRADIENT_CACHE_SEGMENT_AFTER_LINKED_RANGE = { ZO_ColorDef:New("FFC73F00"), ZO_ColorDef:New("FFFC5000") }
local GRADIENT_CACHE_SEGMENT_AFTER_LINKED_RANGE_UNWATCHED = { ZO_ColorDef:New("FFBDBDBD"), ZO_ColorDef:New("FFCACACA") }
local GRADIENT_LINKED_RANGE = { ZO_ColorDef:New("FF00CA4E"), ZO_ColorDef:New("FF00E457") }
local GRADIENT_LINKED_RANGE_UNWATCHED = { ZO_ColorDef:New("FF888888"), ZO_ColorDef:New("FF9C9C9C") }
local GRADIENT_PROCESSING_RANGE = { ZO_ColorDef:New("7FC5B100"), ZO_ColorDef:New("7FFFEA00") }
local GRADIENT_REQUEST_RANGE = { ZO_ColorDef:New("7FB900CA"), ZO_ColorDef:New("7FEA00FF") }

internal.GRADIENT_GUILD_INCOMPLETE = GRADIENT_CACHE_SEGMENT_AFTER_LINKED_RANGE
internal.GRADIENT_GUILD_PROCESSING = { ZO_ColorDef:New("FFC5B100"), ZO_ColorDef:New("FFFFEA00") }
internal.GRADIENT_GUILD_REQUESTING = { ZO_ColorDef:New("FFB900CA"), ZO_ColorDef:New("FFEA00FF") }
internal.GRADIENT_GUILD_COMPLETED = GRADIENT_LINKED_RANGE

local WATCH_MODE_FRAME_COLOR = {
    [internal.WATCH_MODE_AUTO] = ZO_ColorDef:New("FFFFFFFF"),
    [internal.WATCH_MODE_OFF] = ZO_ColorDef:New("FF808080"),
    [internal.WATCH_MODE_ON] = ZO_ColorDef:New("FFFF0000"),
}
local LEADING_EDGE_WIDTH = 10 -- see ZO_ArrowStatusBarOverlayRight

function CacheStatusBar:Initialize(control, window)
    self.control = control
    self.window = window
    self.frame = control:GetNamedChild("Overlay")

    self.segmentControlPool = ZO_ControlPool:New("ZO_ArrowStatusBar", control:GetNamedChild("Segments"), "Segment")
    self.segmentControlPool:SetCustomFactoryBehavior(function(segment)
        -- "This ensures proper draw ordering using accumulators" according to ZO_MultisegmentProgressBar
        segment:SetAutoRectClipChildren(true) -- TODO check if it works without that?
        segment:EnableLeadingEdge(false)
        segment.gloss:EnableLeadingEdge(false)
    end)
    self.segmentControlPool:SetCustomResetBehavior(function(segment)
        segment:SetWidth(nil)
        segment:SetValue(1)
        segment:EnableLeadingEdge(false)
        segment.gloss:EnableLeadingEdge(false)
    end)
end

function CacheStatusBar:Clear()
    self.segmentControlPool:ReleaseAllObjects()
    self.segment = nil
end

function CacheStatusBar:SetValue(value)
    self:Clear()
    local segmentControl = self.segmentControlPool:AcquireObject()
    segmentControl:SetWidth(nil)
    segmentControl:SetAnchorFill(self.control)
    segmentControl:SetValue(value)
    segmentControl:EnableLeadingEdge(true)
    segmentControl.gloss:EnableLeadingEdge(true)
    self.segment = segmentControl
end

function CacheStatusBar:SetGradient(gradient)
    ZO_StatusBar_SetGradientColor(self.segment, gradient)
end

function CacheStatusBar:SetFrameColor(color)
    for i = 1, self.frame:GetNumChildren() do
        local child = self.frame:GetChild(i)
        child:SetColor(color:UnpackRGBA())
    end
end

function CacheStatusBar:Update(cache)
    self:Clear()

    if self.control:GetWidth() <= 0 then
        logger:Verbose("invalid bar width", cache:GetGuildId(), cache:GetCategory())
        return
    end

    local startTime, endTime
    local zoomMode = self.window:GetZoomMode()
    if not zoomMode or zoomMode == internal.ZOOM_MODE_AUTO then
        zoomMode = cache:HasLinked() and internal.ZOOM_MODE_FULL_RANGE or internal.ZOOM_MODE_MISSING_RANGE
    end

    if zoomMode == internal.ZOOM_MODE_FULL_RANGE then
        startTime = cache:GetCacheStartTime()
        endTime = GetTimeStamp()
    else
        startTime = cache:GetUnprocessedEventsStartTime()
        local newestEvent = cache:GetEvent(1)
        if newestEvent then
            endTime = newestEvent:GetEventTimestampS()
        else
            endTime = GetTimeStamp()
        end
    end

    if not startTime then
        logger:Debug("no start time - use full range")
        startTime = cache:GetCacheStartTime()
    end

    if not endTime then
        logger:Debug("no end time - use full range")
        endTime = GetTimeStamp()
    end

    local overallTime = endTime - startTime
    if overallTime <= 0 then return end

    local isWatching = cache:IsWatching()
    local watchMode = cache:GetWatchMode()
    local frameColor = WATCH_MODE_FRAME_COLOR[watchMode]
    self:SetFrameColor(frameColor)

    local _, oldestLinkedEventTime = cache:GetOldestLinkedEventInfo()
    local _, newestLinkedEventTime = cache:GetNewestLinkedEventInfo()

    for i = 1, cache:GetNumRanges() do
        local rangeEndTime, rangeStartTime = cache:GetRangeInfo(i)
        local data = {
            startTime = startTime,
            endTime = endTime,
            segmentStartTime = rangeStartTime,
            segmentEndTime = rangeEndTime,
        }

        if not oldestLinkedEventTime or rangeStartTime > newestLinkedEventTime then
            if isWatching then
                data.color = GRADIENT_CACHE_SEGMENT_AFTER_LINKED_RANGE
            else
                data.color = GRADIENT_CACHE_SEGMENT_AFTER_LINKED_RANGE_UNWATCHED
            end
        elseif rangeEndTime < oldestLinkedEventTime then
            data.color = GRADIENT_CACHE_SEGMENT_BEFORE_LINKED_RANGE
        elseif isWatching then
            data.color = GRADIENT_CACHE_SEGMENT_LINKED_RANGE
        else
            data.color = GRADIENT_CACHE_SEGMENT_LINKED_RANGE_UNWATCHED
        end

        self:AddSegment(data)
    end

    if oldestLinkedEventTime then
        local data = {
            startTime = startTime,
            endTime = endTime,
            segmentStartTime = oldestLinkedEventTime,
            segmentEndTime = newestLinkedEventTime,
            color = isWatching and GRADIENT_LINKED_RANGE or GRADIENT_LINKED_RANGE_UNWATCHED,
        }
        self:AddSegment(data)
    end

    local requestStartTime, requestEndTime = cache:GetRequestTimeRange()
    if requestStartTime then
        local data = {
            startTime = startTime,
            endTime = endTime,
            segmentStartTime = requestStartTime,
            segmentEndTime = requestEndTime,
            color = GRADIENT_REQUEST_RANGE,
        }
        self:AddSegment(data)
    end

    local processingStartTime, processingEndTime = cache:GetProcessingTimeRange()
    if processingStartTime then
        local data = {
            startTime = startTime,
            endTime = endTime,
            segmentStartTime = processingStartTime,
            segmentEndTime = processingEndTime,
            color = GRADIENT_PROCESSING_RANGE,
        }
        self:AddSegment(data)
    end

    logger:Debug("updated cache status bar", cache:GetGuildId(), cache:GetCategory())
end

function CacheStatusBar:AddSegment(data)
    local trimmedStartTime, trimmedEndTime = self:GetTrimmedTimeRange(data)
    if not trimmedStartTime then return end

    local barWidth = self.control:GetWidth()
    local overallTime = data.endTime - data.startTime
    local segmentStart = (trimmedStartTime - data.startTime) / overallTime * barWidth
    local segmentWidth = zo_max(1, (trimmedEndTime - trimmedStartTime) / overallTime * barWidth)

    local control = self.segmentControlPool:AcquireObject()
    control:SetAnchor(TOPLEFT, self.control, TOPLEFT, segmentStart, 0)
    control:SetWidth(segmentWidth)
    control:SetValue(data.value or 1)

    local enableLeadingEdge = (segmentStart + segmentWidth > barWidth - LEADING_EDGE_WIDTH)
    control:EnableLeadingEdge(enableLeadingEdge)
    control.gloss:EnableLeadingEdge(enableLeadingEdge)

    ZO_StatusBar_SetGradientColor(control, data.color)
    return control
end

function CacheStatusBar:GetTrimmedTimeRange(data)
    if data.segmentEndTime < data.startTime or data.segmentStartTime > data.endTime then
        logger:Debug("segment outside display range - skip")
        return nil, nil
    end

    local segmentStartTime = zo_max(data.segmentStartTime, data.startTime)
    local segmentEndTime = zo_min(data.segmentEndTime, data.endTime)

    return segmentStartTime, segmentEndTime
end

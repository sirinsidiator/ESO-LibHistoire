-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local CacheStatusBar = ZO_InitializingObject:Subclass()
internal.class.CacheStatusBar = CacheStatusBar

local GRADIENT_CACHE_SEGMENT_LINKED_RANGE = { ZO_ColorDef:New("0000FF"), ZO_ColorDef:New("4169E1") }
local GRADIENT_CACHE_SEGMENT_LINKED_RANGE_UNWATCHED = { ZO_ColorDef:New("808080"), ZO_ColorDef:New("A9A9A9") }
local GRADIENT_CACHE_SEGMENT_LINKED_PROCESSED_RANGE = { ZO_ColorDef:New("00FF00"), ZO_ColorDef:New("32CD32") }
local GRADIENT_CACHE_SEGMENT_LINKED_PROCESSED_RANGE_UNWATCHED = { ZO_ColorDef:New("808080"), ZO_ColorDef:New("A9A9A9") }
local GRADIENT_CACHE_SEGMENT_BEFORE_LINKED_RANGE = { ZO_ColorDef:New("808080"), ZO_ColorDef:New("A9A9A9") }
local GRADIENT_CACHE_SEGMENT_AFTER_LINKED_RANGE = { ZO_ColorDef:New("FF0000"), ZO_ColorDef:New("FF4500") }
local GRADIENT_CACHE_SEGMENT_AFTER_LINKED_RANGE_UNWATCHED = { ZO_ColorDef:New("808080"), ZO_ColorDef:New("A9A9A9") }
local GRADIENT_PROCESSING_RANGE = { ZO_ColorDef:New("FFFF00"), ZO_ColorDef:New("FFD700") }
local GRADIENT_REQUEST_RANGE = { ZO_ColorDef:New("800080"), ZO_ColorDef:New("9932CC") }

local WATCH_MODE_FRAME_COLOR = {
    [internal.WATCH_MODE_AUTO] = ZO_ColorDef:New("FFFFFF"),
    [internal.WATCH_MODE_OFF] = ZO_ColorDef:New("808080"),
    [internal.WATCH_MODE_ON] = ZO_ColorDef:New("FF0000"),
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
    local width = self.control:GetWidth()
    self:Clear()

    if not cache:HasCachedEvents() or width <= 0 then
        logger:Verbose("no cached events or invalid width", cache:GetGuildId(), cache:GetCategory())
        return
    end

    local startTime
    local zoomMode = self.window:GetZoomMode()
    if not zoomMode or zoomMode == internal.ZOOM_MODE_AUTO then
        zoomMode = cache:HasLinked() and internal.ZOOM_MODE_FULL_RANGE or internal.ZOOM_MODE_MISSING_RANGE
    end

    if zoomMode == internal.ZOOM_MODE_FULL_RANGE then
        startTime = cache:GetCacheStartTime()
    else
        startTime = cache:GetUnprocessedEventsStartTime()
    end

    if not startTime then
        logger:Debug("no start time - use full range")
        startTime = cache:GetCacheStartTime()
    end

    local endTime = GetTimeStamp()
    local overallTime = endTime - startTime
    if overallTime <= 0 then
        logger:Warn("invalid overallTime", overallTime, cache:GetGuildId(), cache:GetCategory())
        return
    end

    local isWatching = cache:IsWatching()
    local watchMode = cache:GetWatchMode()
    local frameColor = WATCH_MODE_FRAME_COLOR[watchMode]
    self:SetFrameColor(frameColor)

    local oldestLinkedEvent = cache:GetOldestLinkedEvent()
    local newestLinkedEvent = cache:GetNewestLinkedEvent()
    local linkedRangeStartTime = oldestLinkedEvent and oldestLinkedEvent:GetEventTimestampS() or startTime
    local linkedRangeEndTime = newestLinkedEvent and newestLinkedEvent:GetEventTimestampS() or endTime
    local gaplessRangeStartTime = cache:GetGaplessRangeStartTime()

    logger:Debug("update cache status bar", cache:GetGuildId(), cache:GetCategory())

    local requestStartTime, requestEndTime = cache:GetRequestTimeRange()
    if requestStartTime then
        logger:Debug("add request time range", requestStartTime, requestEndTime)
        self:AddSegment({
            startTime = startTime,
            endTime = endTime,
            segmentStartTime = requestStartTime,
            segmentEndTime = requestEndTime,
            color = GRADIENT_REQUEST_RANGE,
        })
    end

    for i = 1, cache:GetNumRanges() do
        local rangeEndTime, rangeStartTime, startId, endId = cache:GetRangeInfo(i)
        if rangeEndTime and rangeStartTime then
            local isGaplessRange = gaplessRangeStartTime and rangeStartTime == gaplessRangeStartTime
            local data = {
                startTime = startTime,
                endTime = endTime,
                segmentStartTime = rangeStartTime,
                segmentEndTime = isGaplessRange and endTime or rangeEndTime,
            }

            data.color = isWatching and GRADIENT_CACHE_SEGMENT_LINKED_RANGE or
                GRADIENT_CACHE_SEGMENT_LINKED_RANGE_UNWATCHED
            if rangeEndTime < linkedRangeStartTime then
                data.color = GRADIENT_CACHE_SEGMENT_BEFORE_LINKED_RANGE
            elseif rangeStartTime > linkedRangeEndTime then
                data.color = isWatching and GRADIENT_CACHE_SEGMENT_AFTER_LINKED_RANGE or
                    GRADIENT_CACHE_SEGMENT_AFTER_LINKED_RANGE_UNWATCHED
            end

            logger:Debug("add cache range", i, rangeEndTime, rangeStartTime, startId, endId, isGaplessRange)
            self:AddSegment(data)
        else
            logger:Debug("skip empty range", i)
        end
    end

    if oldestLinkedEvent and newestLinkedEvent then
        local isGaplessRange = gaplessRangeStartTime and linkedRangeStartTime == gaplessRangeStartTime
        local data = {
            startTime = startTime,
            endTime = endTime,
            segmentStartTime = linkedRangeStartTime,
            segmentEndTime = isGaplessRange and endTime or linkedRangeEndTime,
            color = isWatching and GRADIENT_CACHE_SEGMENT_LINKED_PROCESSED_RANGE or
                GRADIENT_CACHE_SEGMENT_LINKED_PROCESSED_RANGE_UNWATCHED,
        }
        logger:Debug("add linked range", linkedRangeStartTime, linkedRangeEndTime, isGaplessRange)
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
        logger:Debug("add processing time range", processingStartTime, processingEndTime)
        self:AddSegment(data)
    end
end

function CacheStatusBar:AddSegment(data)
    local trimmedStartTime, trimmedEndTime = self:GetTrimmedTimeRange(data)
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

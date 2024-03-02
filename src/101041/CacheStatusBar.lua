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

function CacheStatusBar:Initialize(control)
    self.control = control
    self.frame = control:GetNamedChild("Overlay")

    self.segmentControlPool = ZO_ControlPool:New("ZO_ArrowStatusBar", control:GetNamedChild("Segments"), "Segment")
    self.segmentControlPool:SetCustomFactoryBehavior(function(segment)
        -- "This ensures proper draw ordering using accumulators" according to ZO_MultisegmentProgressBar
        segment:SetAutoRectClipChildren(true) -- TODO check if it works without that?
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
    local startTime = cache:GetUnprocessedEventsStartTime()
    -- if cache:HasLinked() or self.viewRange == FULL_RANGE then
    if not startTime then
        startTime = cache:GetCacheStartTime()
    end
    local endTime = GetTimeStamp()

    local overallTime = endTime - startTime
    local width = self.control:GetWidth()
    if width <= 0 or overallTime <= 0 then
        logger:Warn("invalid width or time", width, overallTime)
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

    self:Clear()
    logger:Debug("update cache status bar", cache:GetGuildId(), cache:GetCategory())

    local requestStartTime, requestEndTime = cache:GetRequestTimeRange()
    if requestStartTime then
        logger:Debug("add request time range", requestStartTime, requestEndTime)
        self:AddSegment({
            start = (endTime - requestStartTime) / overallTime * width,
            width = (requestEndTime - requestStartTime) / overallTime * width,
            color = GRADIENT_REQUEST_RANGE,
        })
    end

    for i = 1, cache:GetNumRanges() do
        local rangeEndTime, rangeStartTime = cache:GetRangeInfo(i)
        if rangeEndTime and rangeStartTime then
            local trimmedStartTime, trimmedEndTime = self:GetTrimmedRangeTimes(rangeStartTime, rangeEndTime, startTime,
                endTime)
            if trimmedStartTime and trimmedEndTime then
                local data = {}
                data.color = isWatching and GRADIENT_CACHE_SEGMENT_LINKED_RANGE or
                    GRADIENT_CACHE_SEGMENT_LINKED_RANGE_UNWATCHED
                if rangeEndTime < linkedRangeStartTime then
                    data.color = GRADIENT_CACHE_SEGMENT_BEFORE_LINKED_RANGE
                elseif rangeStartTime > linkedRangeEndTime then
                    data.color = isWatching and GRADIENT_CACHE_SEGMENT_AFTER_LINKED_RANGE or
                        GRADIENT_CACHE_SEGMENT_AFTER_LINKED_RANGE_UNWATCHED
                end

                local isGaplessRange = gaplessRangeStartTime and rangeStartTime == gaplessRangeStartTime
                if isGaplessRange then
                    data.width = (endTime - trimmedStartTime) / overallTime * width
                    data.enableLeadingEdge = true
                else
                    data.width = (trimmedEndTime - trimmedStartTime) / overallTime * width
                end
                data.start = (trimmedStartTime - startTime) / overallTime * width
                logger:Debug("add cache range", i)
                self:AddSegment(data)
            end
        else
            logger:Debug("skip empty range", i)
        end
    end

    if oldestLinkedEvent and newestLinkedEvent then
        local trimmedStartTime, trimmedEndTime = self:GetTrimmedRangeTimes(linkedRangeStartTime, linkedRangeEndTime,
            startTime, endTime)
        if trimmedStartTime and trimmedEndTime then
            local linkedRangeStart = (trimmedStartTime - startTime) / overallTime * width
            local linkedRangeWidth = (trimmedEndTime - trimmedStartTime) / overallTime * width
            local isGaplessRange = gaplessRangeStartTime and linkedRangeStartTime == gaplessRangeStartTime
            if isGaplessRange then
                linkedRangeWidth = (endTime - trimmedStartTime) / overallTime * width
            end
            logger:Debug("add linked range", linkedRangeStartTime, linkedRangeEndTime)

            self:AddSegment({
                start = linkedRangeStart,
                width = linkedRangeWidth,
                color = isWatching and GRADIENT_CACHE_SEGMENT_LINKED_PROCESSED_RANGE or
                    GRADIENT_CACHE_SEGMENT_LINKED_PROCESSED_RANGE_UNWATCHED,
                enableLeadingEdge = isGaplessRange,
            })
        end
    end

    local processingStartTime, processingEndTime = cache:GetProcessingTimeRange()
    if processingStartTime then
        logger:Debug("add processing time range", processingStartTime, processingEndTime)
        self:AddSegment({
            start = (endTime - processingStartTime) / overallTime * width,
            width = (processingEndTime - processingStartTime) / overallTime * width,
            color = GRADIENT_PROCESSING_RANGE,
            enableLeadingEdge = true,
        })
    end
end

function CacheStatusBar:GetTrimmedRangeTimes(rangeStartTime, rangeEndTime, startTime, endTime)
    if rangeEndTime < startTime or rangeStartTime > endTime then
        logger:Debug("range outside display range - skip")
        return nil, nil
    end

    if rangeStartTime < startTime then
        logger:Verbose("range start time before display range - trim", rangeStartTime, startTime)
        rangeStartTime = startTime
    end

    if rangeEndTime > endTime then
        logger:Verbose("range end time after display range - trim", rangeEndTime, endTime)
        rangeEndTime = endTime
    end

    return rangeStartTime, rangeEndTime
end

function CacheStatusBar:AddSegment(data)
    assert(data.start >= 0 and data.start <= self.control:GetWidth(), "start out of bounds")
    assert(data.width >= 0 and data.width <= self.control:GetWidth(), "width out of bounds")

    if data.width == 0 then
        data.width = 1 -- ensure it is visible
    end

    local control = self.segmentControlPool:AcquireObject()
    control:SetAnchor(TOPLEFT, self.control, TOPLEFT, data.start, 0)
    control:SetWidth(data.width)
    control:SetValue(data.value or 1)
    if data.enableLeadingEdge then
        control:EnableLeadingEdge(true)
        control.gloss:EnableLeadingEdge(true)
    end
    ZO_StatusBar_SetGradientColor(control, data.color)
    return control
end

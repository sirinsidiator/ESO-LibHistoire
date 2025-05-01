-- SPDX-FileCopyrightText: 2025 sirinsidiator
--
-- SPDX-License-Identifier: Artistic-2.0

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local CacheStatusBar = ZO_InitializingObject:Subclass()
internal.class.CacheStatusBar = CacheStatusBar

local GRADIENT_GAPLESS_RANGE_AFTER_MANAGED_RANGE_INACTIVE = { ZO_ColorDef:New("FF4D4D4D"), ZO_ColorDef:New("FF5E5E5E") }
local GRADIENT_GAPLESS_RANGE_AFTER_MANAGED_RANGE_ACTIVE = { ZO_ColorDef:New("FF00406B"), ZO_ColorDef:New("FF00548B") }
local GRADIENT_GAPLESS_RANGE_BEFORE_MANAGED_RANGE_INACTIVE = { ZO_ColorDef:New("FF5A5A5A"), ZO_ColorDef:New("FFA3A3A3") }
local GRADIENT_GAPLESS_RANGE_BEFORE_MANAGED_RANGE_ACTIVE = { ZO_ColorDef:New("FF611F00"), ZO_ColorDef:New("FFA33400") }
local GRADIENT_GAPLESS_RANGE_MANAGED_RANGE_INACTIVE = { ZO_ColorDef:New("FF4D4D4D"), ZO_ColorDef:New("FF5E5E5E") }
local GRADIENT_GAPLESS_RANGE_MANAGED_RANGE_ACTIVE = { ZO_ColorDef:New("FF005521"), ZO_ColorDef:New("FF008031") }
local GRADIENT_GAPLESS_RANGE_MANAGED_RANGE_ACTIVE_UNLINKED = { ZO_ColorDef:New("FF381200"), ZO_ColorDef:New("FF5E1E00") }
local GRADIENT_CACHE_SEGMENT_BEFORE_MANAGED_RANGE = { ZO_ColorDef:New("FF929292"), ZO_ColorDef:New("FFACACAC") }
local GRADIENT_CACHE_SEGMENT_MANAGED_RANGE_ACTIVE = { ZO_ColorDef:New("FF0074C2"), ZO_ColorDef:New("FF0099FF") }
local GRADIENT_CACHE_SEGMENT_MANAGED_RANGE_INACTIVE = { ZO_ColorDef:New("FFC1C1C1"), ZO_ColorDef:New("FFD3D3D3") }
local GRADIENT_CACHE_SEGMENT_AFTER_MANAGED_RANGE_ACTIVE = { ZO_ColorDef:New("FFC73F00"), ZO_ColorDef:New("FFFC5000") }
local GRADIENT_CACHE_SEGMENT_AFTER_MANAGED_RANGE_INACTIVE = { ZO_ColorDef:New("FFBDBDBD"), ZO_ColorDef:New("FFCACACA") }
local GRADIENT_MANAGED_RANGE_ACTIVE = { ZO_ColorDef:New("FF0CAD4A"), ZO_ColorDef:New("FF17B955") }
local GRADIENT_MANAGED_RANGE_INACTIVE = { ZO_ColorDef:New("FF888888"), ZO_ColorDef:New("FF9C9C9C") }
local GRADIENT_REQUEST_RANGE_BACKGROUND = { ZO_ColorDef:New("FF462449"), ZO_ColorDef:New("FF592A5E") }
local GRADIENT_REQUEST_RANGE_FOREGROUND = { ZO_ColorDef:New("FFB900CA"), ZO_ColorDef:New("FFEA00FF") }
local GRADIENT_PROCESSING_RANGE_BACKGROUND = { ZO_ColorDef:New("FF5E582A"), ZO_ColorDef:New("FF726D34") }
local GRADIENT_PROCESSING_RANGE_FOREGROUND = { ZO_ColorDef:New("FFC5B100"), ZO_ColorDef:New("FFFFEA00") }

internal.GRADIENT_GUILD_INCOMPLETE = GRADIENT_CACHE_SEGMENT_AFTER_MANAGED_RANGE_ACTIVE
internal.GRADIENT_GUILD_PROCESSING = { ZO_ColorDef:New("FFC5B100"), ZO_ColorDef:New("FFFFEA00") }
internal.GRADIENT_GUILD_REQUESTING = { ZO_ColorDef:New("FFB900CA"), ZO_ColorDef:New("FFEA00FF") }
internal.GRADIENT_GUILD_COMPLETED = GRADIENT_MANAGED_RANGE_ACTIVE

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

function CacheStatusBar:Update(cache)
    self:Clear()

    if self.control:GetWidth() <= 0 then
        logger:Verbose("invalid bar width", cache:GetGuildId(), cache:GetCategory())
        return
    end

    local zoomMode = self.window:GetZoomMode()
    if not zoomMode or zoomMode == internal.ZOOM_MODE_AUTO then
        if not cache:GetNewestManagedEventInfo() or cache:HasLinked() then
            zoomMode = internal.ZOOM_MODE_FULL_RANGE
        else
            zoomMode = internal.ZOOM_MODE_MISSING_RANGE
        end
    end

    local startTime
    local endTime = GetTimeStamp()
    if zoomMode == internal.ZOOM_MODE_FULL_RANGE then
        startTime = cache:GetCacheStartTime()
    else
        startTime = cache:GetUnprocessedEventsStartTime() or endTime
        -- ensure we see at least one day
        startTime = zo_min(startTime, endTime - 24 * 3600)
        -- add a bit extra to the start, so we actually see when there is already stored data
        startTime = startTime - (endTime - startTime) * 0.05
    end

    local overallTime = endTime - startTime
    if overallTime <= 0 then return end

    local isActive = cache:IsAutoRequesting()
    local _, oldestManagedEventTime = cache:GetOldestManagedEventInfo()
    local _, newestManagedEventTime = cache:GetNewestManagedEventInfo()
    local gaplessRangeStartTime = cache:GetGaplessRangeStartTime()
    local requestStartTime, requestEndTime = cache:GetRequestTimeRange()
    local processingStartTime, processingEndTime, processingCurrentTime = cache:GetProcessingTimeRange()

    if gaplessRangeStartTime then
        local data = {
            startTime = startTime,
            endTime = endTime,
            segmentStartTime = gaplessRangeStartTime,
            segmentEndTime = endTime,
        }

        if not newestManagedEventTime then
            data.color = isActive and GRADIENT_GAPLESS_RANGE_BEFORE_MANAGED_RANGE_ACTIVE or
                GRADIENT_GAPLESS_RANGE_BEFORE_MANAGED_RANGE_INACTIVE
        elseif gaplessRangeStartTime > newestManagedEventTime then
            data.color = isActive and GRADIENT_GAPLESS_RANGE_AFTER_MANAGED_RANGE_ACTIVE or
                GRADIENT_GAPLESS_RANGE_AFTER_MANAGED_RANGE_INACTIVE
        elseif isActive then
            local isLinked = cache:IsManagedRangeConnectedToPresent()
            data.color = isLinked and GRADIENT_GAPLESS_RANGE_MANAGED_RANGE_ACTIVE or
                GRADIENT_GAPLESS_RANGE_MANAGED_RANGE_ACTIVE_UNLINKED
        else
            data.color = GRADIENT_GAPLESS_RANGE_MANAGED_RANGE_INACTIVE
        end
        self:AddSegment(data)
    end

    local cacheSegementsInsideRequestRange = {}
    for i = 1, cache:GetNumRanges() do
        local rangeEndTime, rangeStartTime = cache:GetRangeInfo(i)

        if requestStartTime and rangeEndTime > requestStartTime and rangeStartTime < requestEndTime then
            local trimmedStartTime, trimmedEndTime = self:GetTrimmedTimeRange({
                startTime = requestStartTime,
                endTime = requestEndTime,
                segmentStartTime = rangeStartTime,
                segmentEndTime = rangeEndTime,
            })
            if trimmedStartTime then
                table.insert(cacheSegementsInsideRequestRange, { trimmedStartTime, trimmedEndTime })
            end
        end

        local data = {
            startTime = startTime,
            endTime = endTime,
            segmentStartTime = rangeStartTime,
            segmentEndTime = rangeEndTime,
        }

        if not oldestManagedEventTime or rangeStartTime > newestManagedEventTime then
            if isActive then
                data.color = GRADIENT_CACHE_SEGMENT_AFTER_MANAGED_RANGE_ACTIVE
            else
                data.color = GRADIENT_CACHE_SEGMENT_AFTER_MANAGED_RANGE_INACTIVE
            end
        elseif rangeEndTime < oldestManagedEventTime then
            data.color = GRADIENT_CACHE_SEGMENT_BEFORE_MANAGED_RANGE
        elseif isActive then
            data.color = GRADIENT_CACHE_SEGMENT_MANAGED_RANGE_ACTIVE
        else
            data.color = GRADIENT_CACHE_SEGMENT_MANAGED_RANGE_INACTIVE
        end

        self:AddSegment(data)
    end

    if oldestManagedEventTime and cache:HasLinked() then
        local data = {
            startTime = startTime,
            endTime = endTime,
            segmentStartTime = oldestManagedEventTime,
            segmentEndTime = newestManagedEventTime,
            color = isActive and GRADIENT_MANAGED_RANGE_ACTIVE or GRADIENT_MANAGED_RANGE_INACTIVE,
        }
        self:AddSegment(data)
    end

    if requestStartTime then
        local data = {
            startTime = startTime,
            endTime = endTime,
            segmentStartTime = requestStartTime,
            segmentEndTime = requestEndTime,
            color = GRADIENT_REQUEST_RANGE_BACKGROUND,
        }
        self:AddSegment(data)

        for _, range in ipairs(cacheSegementsInsideRequestRange) do
            local data = {
                startTime = startTime,
                endTime = endTime,
                segmentStartTime = range[1],
                segmentEndTime = range[2],
                color = GRADIENT_REQUEST_RANGE_FOREGROUND,
            }
            self:AddSegment(data)
        end
    end

    if processingStartTime then
        local data = {
            startTime = startTime,
            endTime = endTime,
            segmentStartTime = processingStartTime,
            segmentEndTime = processingEndTime,
            color = GRADIENT_PROCESSING_RANGE_BACKGROUND,
        }
        self:AddSegment(data)

        if processingCurrentTime then
            if processingCurrentTime < 0 then
                data.segmentStartTime = -processingCurrentTime
            else
                data.segmentEndTime = processingCurrentTime
            end
            data.color = GRADIENT_PROCESSING_RANGE_FOREGROUND
            self:AddSegment(data)
        end
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
        logger:Verbose("segment outside display range - skip")
        return nil, nil
    end

    local segmentStartTime = zo_max(data.segmentStartTime, data.startTime)
    local segmentEndTime = zo_min(data.segmentEndTime, data.endTime)

    return segmentStartTime, segmentEndTime
end

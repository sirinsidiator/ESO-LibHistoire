-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local PerformanceTracker = ZO_Object:Subclass()
internal.class.PerformanceTracker = PerformanceTracker

local ROLLING_AVERAGE_INTERVAL = 10 -- seconds
local MIN_DATA_COUNT = 2
local CURRENT_SPEED_WEIGHT = 0.1

function PerformanceTracker:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function PerformanceTracker:Initialize()
    self:Reset()
end

function PerformanceTracker:Reset()
    self.processingSpeed = -1
    self.lastEventCountSlot = -1
    self.processedEventCount = {}
    self.slotStartTime = {}
    self.slotEndTime = {}
end

function PerformanceTracker:Increment()
    local slot = GetTimeStamp() % ROLLING_AVERAGE_INTERVAL
    local now = GetGameTimeMilliseconds()
    self.slotEndTime[slot] = now
    if slot ~= self.lastEventCountSlot then
        self:PrepareNextSlot(slot, now)
    end
    self.processedEventCount[slot] = self.processedEventCount[slot] + 1
end

function PerformanceTracker:PrepareNextSlot(slot, now)
    self.processedEventCount[slot] = 0
    self.slotStartTime[slot] = now
    self.lastEventCountSlot = slot

    local currentSpeed = 0
    local count = 0
    for i = 0, ROLLING_AVERAGE_INTERVAL - 1 do
        if self.processedEventCount[i] then
            local deltaMs = self.slotEndTime[i] - self.slotStartTime[i]
            if deltaMs > 0 then
                currentSpeed = currentSpeed + self.processedEventCount[i] / deltaMs
                count = count + 1
            end
        end
    end

    if count > MIN_DATA_COUNT then -- wait until we collected some data before showing a speed
        currentSpeed = currentSpeed * 1000 / count

        -- keep it stable by applying the new current speed only partially
        if self.processingSpeed < 0 then
            self.processingSpeed = currentSpeed
        else
            self.processingSpeed = self.processingSpeed * (1 - CURRENT_SPEED_WEIGHT) + currentSpeed * CURRENT_SPEED_WEIGHT
        end
    else
        self.processingSpeed = -1
    end
end

function PerformanceTracker:GetProcessingSpeedAndEstimatedTimeLeft(count)
    local speed = self.processingSpeed

    local time = 0
    if speed > 0 then
        time = count / speed
    elseif count > 0 then
        time = -1
    end

    return speed, time
end
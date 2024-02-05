-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger
local SERVER_NAME = GetWorldName()

local GuildHistoryNoopListener = ZO_Object:Subclass()
internal.class.GuildHistoryNoopListener = GuildHistoryNoopListener

function GuildHistoryNoopListener:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function GuildHistoryNoopListener:Initialize(guildId, category)
    self.key = string.format("%s/%d/%d", SERVER_NAME, guildId, category)
    self.guildId = guildId
    self.category = category
end

function GuildHistoryNoopListener:InternalCountEvent(index)
    -- noop
end

function GuildHistoryNoopListener:InternalResetEventCount()
    -- noop
end

function GuildHistoryNoopListener:GetKey()
    return self.key
end

function GuildHistoryNoopListener:GetGuildId()
    return self.guildId
end

function GuildHistoryNoopListener:GetCategory()
    return self.category
end

function GuildHistoryNoopListener:GetPendingEventMetrics()
    return 0, -1, -1
end

function GuildHistoryNoopListener:SetAfterEventId(eventId)
    return false
end

function GuildHistoryNoopListener:SetAfterEventTime(eventTime)
    return false
end

function GuildHistoryNoopListener:SetBeforeEventId(eventId)
    return false
end

function GuildHistoryNoopListener:SetBeforeEventTime(eventTime)
    return false
end

function GuildHistoryNoopListener:SetTimeFrame(startTime, endTime)
    return false
end

function GuildHistoryNoopListener:SetNextEventCallback(callback)
    return false
end

function GuildHistoryNoopListener:SetMissedEventCallback(callback)
    return false
end

function GuildHistoryNoopListener:SetEventCallback(callback)
    return false
end

function GuildHistoryNoopListener:SetIterationCompletedCallback(callback)
    return false
end

function GuildHistoryNoopListener:SetStopOnLastEvent(shouldStop)
    return false
end

function GuildHistoryNoopListener:Start()
    return false
end

function GuildHistoryNoopListener:Stop()
    return false
end

function GuildHistoryNoopListener:IsRunning()
    return false
end

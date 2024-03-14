-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local GuildHistoryServerRequest = ZO_InitializingObject:Subclass()
internal.class.GuildHistoryServerRequest = GuildHistoryServerRequest

function GuildHistoryServerRequest:Initialize(cache, newestTime, oldestTime)
    self.cache = cache
    self.newestTime = newestTime or GetTimeStamp()
    self.oldestTime = oldestTime or 0
    self.destroyed = false
    self.queued = false
end

function GuildHistoryServerRequest:IsInitialRequest()
    return self.oldestTime == 0
end

function GuildHistoryServerRequest:IsValid()
    if self.destroyed then
        return false
    end

    if self.request then
        return self.request:IsValid()
    end

    return true
end

function GuildHistoryServerRequest:IsComplete()
    if self.request then
        return self.request:IsComplete()
    end

    return false
end

function GuildHistoryServerRequest:IsRequestQueued()
    if self.queued then
        return true
    end

    if self.request then
        return self.request:IsRequestQueued()
    end

    return false
end

function GuildHistoryServerRequest:SetQueued(queued)
    self.queued = queued
end

function GuildHistoryServerRequest:ShouldContinue()
    if self.oldestTime == 0 or not self.cache:IsAutoRequesting() then
        return false
    end

    if self.request then
        return self.request:IsValid() and not self.request:IsComplete()
    end

    return true
end

function GuildHistoryServerRequest:ShouldSend()
    if not self:IsValid() or self:IsComplete() then
        logger:Warn("Found invalid or completed request in queue")
        return false
    end

    return true
end

function GuildHistoryServerRequest:Send()
    if not self.request then
        local guildId = self.cache:GetGuildId()
        local category = self.cache:GetCategory()
        self.request = ZO_GuildHistoryRequest:New(guildId, category, self.newestTime, self.oldestTime)
    end

    local request = self.request
    logger:Debug("Send request", request.requestId, request.guildId, request.eventCategory, request.newestTimeS,
        request.oldestTimeS)
    return request:RequestMoreEvents()
end

function GuildHistoryServerRequest:Destroy()
    if self.destroyed then
        return true
    end
    self.destroyed = true
    if self.request then
        local id = self.request:GetRequestId()
        if not DestroyGuildHistoryRequest(id) then
            logger:Warn("Failed to destroy request", id)
            return false
        end
    end
    self.cache:DestroyRequest(self)
    return true
end

function GuildHistoryServerRequest:GetPriority()
    return 0
end

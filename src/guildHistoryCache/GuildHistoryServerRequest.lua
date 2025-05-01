-- SPDX-FileCopyrightText: 2025 sirinsidiator
--
-- SPDX-License-Identifier: Artistic-2.0

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local SHOWN_GUILD_PRIORITY_BONUS = 1000

local GuildHistoryServerRequest = ZO_InitializingObject:Subclass()
internal.class.GuildHistoryServerRequest = GuildHistoryServerRequest

function GuildHistoryServerRequest:Initialize(cache, newestTime, oldestTime)
    self.cache = cache
    self.newestTime = newestTime
    self.oldestTime = oldestTime
    self.destroyed = false
    self.queued = false
end

function GuildHistoryServerRequest:GetNewestTime()
    return self.newestTime or GetTimeStamp()
end

function GuildHistoryServerRequest:GetOldestTime()
    return self.oldestTime or 0
end

function GuildHistoryServerRequest:GetRequestId()
    return self.request and self.request:GetRequestId() or -1
end

function GuildHistoryServerRequest:IsInitialRequest()
    return not self.oldestTime or self.oldestTime == 0
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
    if self:IsInitialRequest() or self.cache:IsManagedRangeConnectedToPresent() or not self.cache:IsAutoRequesting() then
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

    return not self.cache:IsManagedRangeConnectedToPresent()
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
    if self.request and not self:IsInitialRequest() then
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
    local priority = self.cache:GetRequestPriority()
    if internal:IsGuildStatusVisible(self.cache:GetGuildId()) then
        priority = priority + SHOWN_GUILD_PRIORITY_BONUS
    end
    return priority
end

function GuildHistoryServerRequest:GetDebugInfo()
    return {
        id = self:GetRequestId(),
        oldestTime = self.oldestTime,
        newestTime = self.newestTime,
        valid = self:IsValid(),
        complete = self:IsComplete(),
        queued = self:IsRequestQueued(),
        shouldContinue = self:ShouldContinue(),
        priority = self:GetPriority(),
    }
end

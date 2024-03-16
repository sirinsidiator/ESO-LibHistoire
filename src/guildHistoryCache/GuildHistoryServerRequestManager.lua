-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local WATCHDOG_INTERVAL = 30 * 1000

local GuildHistoryServerRequestManager = ZO_InitializingObject:Subclass()
internal.class.GuildHistoryServerRequestManager = GuildHistoryServerRequestManager

function GuildHistoryServerRequestManager:Initialize(saveData)
    self.saveData = saveData
    self.requestQueue = {}
    self.cleanUpQueue = {}
end

function GuildHistoryServerRequestManager:StartWatchdog()
    if self.watchdog then return end
    logger:Debug("Start Watchdog")
    self.watchdog = internal.RegisterForUpdate(WATCHDOG_INTERVAL, function()
        logger:Debug("Request Watchdog")
        self:RequestSendNext()
    end)
end

function GuildHistoryServerRequestManager:StopWatchdog()
    if not self.watchdog then return end
    logger:Debug("Stop Watchdog")
    internal.UnregisterForUpdate(self.watchdog)
    self.watchdog = nil
end

function GuildHistoryServerRequestManager:QueueRequest(request, skipRequestSendNext)
    if not request then return end

    logger:Debug("Queue request", request.cache.key, request.request and request.request:GetRequestId() or -1,
        request.newestTime, request.oldestTime)
    table.insert(self.requestQueue, request)
    request:SetQueued(true)

    self:StartWatchdog()

    if not skipRequestSendNext then
        self:RequestSendNext()
    end
end

function GuildHistoryServerRequestManager:RemoveRequest(request)
    for i = 1, #self.requestQueue do
        if self.requestQueue[i] == request then
            table.remove(self.requestQueue, i)
            request:SetQueued(false)
            return
        end
    end
end

local function RemoveObsoleteAndGetNextRequest(self)
    local requests = self.requestQueue
    if #requests == 0 then
        return nil
    end

    for i = #requests, 1, -1 do
        local request = requests[i]
        if not request:ShouldSend() then
            table.remove(requests, i)
            self.cleanUpQueue[#self.cleanUpQueue + 1] = request
        end
    end

    table.sort(requests, function(a, b)
        return a:GetPriority() < b:GetPriority()
    end)

    local request = table.remove(requests)
    if request then
        request:SetQueued(false)
        return request
    end
end

function GuildHistoryServerRequestManager:RequestSendNext()
    if self.handle then
        return
    end

    self.handle = zo_callLater(function()
        self.handle = nil
        self:SendNext()
    end, 0)
end

function GuildHistoryServerRequestManager:SendNext()
    if self.handle then
        zo_removeCallLater(self.handle)
        self.handle = nil
    end

    local request = RemoveObsoleteAndGetNextRequest(self)

    self:CleanUp()

    if not request then
        logger:Debug("No more requests to send")
        self:StopWatchdog()
        return false
    end

    local state = request:Send()
    if state == GUILD_HISTORY_DATA_READY_STATE_INVALID_REQUEST then
        logger:Warn("Request is invalid")
        request:Destroy()
        return self:SendNext()
    elseif state == GUILD_HISTORY_DATA_READY_STATE_ON_COOLDOWN then
        logger:Debug("Cannot request while on cooldown")
        self:QueueRequest(request, true)
        return false
    elseif state == GUILD_HISTORY_DATA_READY_STATE_READY then
        logger:Debug("Request already complete")
        request:Destroy()
        return true
    elseif state == GUILD_HISTORY_DATA_READY_STATE_RESPONSE_PENDING then
        logger:Debug("Waiting for a response")
        return true
    else
        logger:Warn("Unknown state", state)
        request:Destroy()
        return false
    end
end

function GuildHistoryServerRequestManager:HasPendingRequests()
    return DoesGuildHistoryHaveOutstandingRequest()
end

function GuildHistoryServerRequestManager:CleanUp()
    local cleanUpQueue = self.cleanUpQueue
    self.cleanUpQueue = {}
    for i = 1, #cleanUpQueue do
        local request = cleanUpQueue[i]
        if not request:Destroy() then
            logger:Warn("Failed to destroy request", request.requestId)
            self.cleanUpQueue[#self.cleanUpQueue + 1] = request
        end
    end
end

function GuildHistoryServerRequestManager:Shutdown()
    self:StopWatchdog()

    local requestQueue = self.requestQueue
    local cleanUpQueue = self.cleanUpQueue
    logger:Debug("Destroy all requests", #requestQueue, #cleanUpQueue)

    for i = #requestQueue, 1, -1 do
        local request = requestQueue[i]
        if not request:Destroy() then
            logger:Warn("Failed to destroy pending request", request.requestId)
        end
    end

    for i = #cleanUpQueue, 1, -1 do
        local request = cleanUpQueue[i]
        if not request:Destroy() then
            logger:Warn("Failed to destroy finished request", request.requestId)
        end
    end

    ZO_ClearTable(requestQueue)
    ZO_ClearTable(cleanUpQueue)
end

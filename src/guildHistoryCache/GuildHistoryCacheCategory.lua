-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local GuildHistoryCacheEntry = internal.class.GuildHistoryCacheEntry
local AGS = AwesomeGuildStore -- TODO get rid of AGS dependency -> extract codec into a separate lib
local WriteToSavedVariable = AGS.internal.WriteToSavedVariable
local ReadFromSavedVariable = AGS.internal.ReadFromSavedVariable

local SERVER_NAME = GetWorldName()
local MAX_RECEIVED_EVENTS = 500

local function ByEventIdDesc(a, b)
    return a:GetEventId() > b:GetEventId()
end

local function ByEventIdAsc(a, b)
    return b:GetEventId() > a:GetEventId()
end

local GuildHistoryCacheCategory = ZO_Object:Subclass()
internal.class.GuildHistoryCacheCategory = GuildHistoryCacheCategory

function GuildHistoryCacheCategory:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function GuildHistoryCacheCategory:Initialize(nameCache, saveData, guildId, category)
    self.nameCache = nameCache
    self.key = string.format("%s/%d/%d", SERVER_NAME, guildId, category)
    self.saveData = saveData[self.key] or {}
    saveData[self.key] = self.saveData
    self.guildId = guildId
    self.category = category

    self.lastIndex = 0
    self.events = {}
    for i = 1, #self.saveData do
        self.events[i] = false -- add placeholders - deserialization will happen lazily
    end

    -- we store everything in a temporary table until we find the last stored event
    self.unlinkedEvents = {}
end

function GuildHistoryCacheCategory:GetNameDictionary()
    return self.nameCache
end

function GuildHistoryCacheCategory:GetOffsets()
    return self.saveData.idOffset, self.saveData.timeOffset
end

function GuildHistoryCacheCategory:HasLinked()
    return not self.unlinkedEvents
end

function GuildHistoryCacheCategory:GetNumEntries()
    return #self.events
end

function GuildHistoryCacheCategory:GetEntry(i)
    if self.events[i] == false then -- if there is a placeholder we first need to deserialize it
        local serializedData = ReadFromSavedVariable(self.saveData, i)
        self.events[i] = GuildHistoryCacheEntry:New(self, serializedData)
    end
    return self.events[i]
end

function GuildHistoryCacheCategory:IsEventAlreadyStored(event)
    local lastStoredEntry = self:GetEntry(self:GetNumEntries())
    if lastStoredEntry then
        return event:GetEventId() <= lastStoredEntry:GetEventId()
    end
    return false
end

function GuildHistoryCacheCategory:StoreEvent(event)
    local index = #self.events + 1
    self.events[index] = event
    if not self.saveData.idOffset then self.saveData.idOffset = event:GetEventId() end
    if not self.saveData.timeOffset then self.saveData.timeOffset = event:GetEventTime() end
    WriteToSavedVariable(self.saveData, index, event:Serialize())
end

function GuildHistoryCacheCategory:CanReceiveMoreEvents()
    return DoesGuildHistoryCategoryHaveMoreEvents(self.guildId, self.category)
        or DoesGuildHistoryCategoryHaveOutstandingRequest(self.guildId, self.category)
        or IsGuildHistoryCategoryRequestQueued(self.guildId, self.category)
        or not HasGuildHistoryCategoryEverBeenRequested(self.guildId, self.category)
end

function GuildHistoryCacheCategory:GetFirstAndLastUnlinkedEventId()
    if not self:HasLinked() and self.unlinkedEvents[1] then
        local events =  self.unlinkedEvents
        return events[1]:GetEventId(), events[#events]:GetEventId()
    end
end

function GuildHistoryCacheCategory:ReceiveEvents()
    local guildId, category = self.guildId, self.category
    local lastStoredEntry = self:GetEntry(self:GetNumEntries())
    local lastStoredEventId = lastStoredEntry and lastStoredEntry:GetEventId() or 0

    local numEvents = GetNumGuildEvents(guildId, category)
    local nextIndex = self.lastIndex + 1
    local events = {}
    local hasReachedLastStoredEventId = false
    for index = nextIndex, numEvents do
        local eventId = select(9, GetGuildEventInfo(guildId,category, index))
        if eventId > lastStoredEventId then
            events[#events + 1] = GuildHistoryCacheEntry:New(self, guildId, category, index)
        else
            hasReachedLastStoredEventId = true
        end
        self.lastIndex = index
    end

    local eventsBefore = {}
    local eventsAfter = {}
    if #events > 0 then
        local lastEventId, firstEventId = self:GetFirstAndLastUnlinkedEventId()
        local eventId = events[1]:GetEventId()
        if not lastEventId then
            table.sort(events, ByEventIdAsc)
            eventId = events[1]:GetEventId()
            lastEventId = eventId - 1
            firstEventId = eventId + 1
            logger:Debug("is initial - sort asc")
        elseif eventId > lastEventId then
            table.sort(events, ByEventIdAsc)
            logger:Debug("is after - sort asc")
        elseif eventId < firstEventId then
            table.sort(events, ByEventIdDesc)
            logger:Debug("is before - sort desc")
        else
            logger:Warn("fail - first event %d needs to go somewhere between %d and %d", eventId, firstEventId, lastEventId)
        end

        for i = 1, #events do
            local entry = events[i]
            local eventId = entry:GetEventId()

            if eventId > lastEventId then
                eventsAfter[#eventsAfter + 1] = entry
                lastEventId = eventId
            elseif eventId < firstEventId then
                eventsBefore[#eventsBefore + 1] = entry
                firstEventId = eventId
            else
                Zgoo(events)
                logger:Warn("fail - event %d (%d) needs to go somewhere between %d and %d", eventId, i, firstEventId, lastEventId)
            end
        end
    end

    logger:Info("add %d + %d events in guild %s (%d) category %d", #eventsBefore, #eventsAfter, GetGuildName(self.guildId), self.guildId, self.category)
    if #eventsBefore > 0 then
        if not self.unlinkedEvents then
            logger:Warn("fail - have events before, but we are already linked")
        else
            self:AddOlderEvents(eventsBefore)
        end
    end
    if #eventsAfter > 0 then
        self:AddNewestEvents(eventsAfter)
    end

    local unlinkedEvents = self.unlinkedEvents
    -- if we reached the end and still haven't linked up with the stored history we do so now
    logger:Debug("if %s or (%s and %s) then", tostring(not unlinkedEvents), tostring(not hasReachedLastStoredEventId), tostring(self:CanReceiveMoreEvents()))
    if not unlinkedEvents or (not hasReachedLastStoredEventId and self:CanReceiveMoreEvents()) then return end
    logger:Info("link history")
    self.unlinkedEvents = nil
    for i = 1, #unlinkedEvents do
        self:StoreEvent(unlinkedEvents[i])
    end
end

function GuildHistoryCacheCategory:AddOlderEvents(eventsBefore)
    table.sort(eventsBefore, ByEventIdAsc)
    local events = self.unlinkedEvents
    for i = 1, #events do
        eventsBefore[#eventsBefore + 1] = events[i]
    end
    self.unlinkedEvents = eventsBefore
end

function GuildHistoryCacheCategory:AddNewestEvents(eventsAfter)
    local events = self.unlinkedEvents
    for i = 1, #eventsAfter do
        if not events then -- we are already linked to the stored history
            self:StoreEvent(eventsAfter[i])
        else
            events[#events + 1] = eventsAfter[i]
        end
    end
end

-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local GuildHistoryCacheEntry = internal.class.GuildHistoryCacheEntry
local WriteToSavedVariable = internal.WriteToSavedVariable
local ReadFromSavedVariable = internal.ReadFromSavedVariable

local SERVER_NAME = GetWorldName()
local MAX_RECEIVED_EVENTS = 500

local function Ascending(a, b)
    return b > a
end

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
    self.eventIndexLookup = {}
    self.eventIdList = {}
    for i = 1, #self.saveData do
        self.events[i] = false -- add placeholders - deserialization will happen lazily
    end
    -- make sure the first and last event are deserialized
    self:GetEntry(1)
    self:GetEntry(self:GetNumEntries())

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

function GuildHistoryCacheCategory:IsProcessing()
    return self.storeEventsTask ~= nil
end

function GuildHistoryCacheCategory:GetNumUnlinkedEntries()
    if not self.unlinkedEvents then return 0 end
    return #self.unlinkedEvents
end

function GuildHistoryCacheCategory:GetUnlinkedEntry(i)
    if not self.unlinkedEvents then return end
    return self.unlinkedEvents[i]
end

function GuildHistoryCacheCategory:GetNumEntries()
    return #self.events
end

function GuildHistoryCacheCategory:GetEntry(i)
    if self.events[i] == false then -- if there is a placeholder we first need to deserialize it
        local serializedData = ReadFromSavedVariable(self.saveData, i)
        self.events[i] = GuildHistoryCacheEntry:New(self, serializedData)
        local eventId = self.events[i]:GetEventId()
        self.eventIdList[#self.eventIdList + 1] = eventId
        self.eventIndexLookup[eventId] = i
    end
    return self.events[i]
end

function GuildHistoryCacheCategory:FindIndexFor(eventId)
    -- lookup if we know the answer already
    if self.eventIndexLookup[eventId] then
        return self.eventIndexLookup[eventId]
    end

    -- otherwise check which is the closest known id (if any)
    local closestIndex = self:FindClosestIndexFor(eventId)

    -- if no closest id was found, return 0
    if closestIndex <= 0 then return 0 end

    -- otherwise serialize the eventId and start searching the save data for a matching string
    local serialized = GuildHistoryCacheEntry.CreateEventIdSearchString(eventId)

    local saveData = self.saveData
    for i = closestIndex, #saveData do
        -- if a match was found, deserialize the event and check if it is really a match
        if PlainStringFind(saveData[i], serialized) then
            local event = self:GetEvent(i)
            if event:GetEventId() == eventId then
                return i
            end
        end
        -- otherwise continue until we reach the end
    end

    return 0
end

function GuildHistoryCacheCategory:FindClosestIndexFor(eventId)
    if not eventId or #self.eventIdList == 0 then return 0 end

    local eventIdList = self.eventIdList
    table.sort(eventIdList, Ascending)

    local firstEventId = eventIdList[1]
    if eventId < firstEventId then return 0 end
    if eventId == firstEventId then return 1 end

    local lastEventId = eventIdList[#eventIdList]
    if eventId >= lastEventId then return self.eventIndexLookup[lastEventId] end

    for i = 1, #eventIdList do
        if eventIdList[i] > eventId then
            local closestEventId = eventIdList[i - 1] or firstEventId
            return self.eventIndexLookup[closestEventId] or 0
        end
    end

    return 0
end

function GuildHistoryCacheCategory:StoreEvent(event)
    local index = #self.events + 1
    self.events[index] = event
    if not self.saveData.idOffset then self.saveData.idOffset = event:GetEventId() end
    if not self.saveData.timeOffset then self.saveData.timeOffset = event:GetEventTime() end
    WriteToSavedVariable(self.saveData, index, event:Serialize())
    local eventId = event:GetEventId()
    self.eventIdList[#self.eventIdList + 1] = eventId
    self.eventIndexLookup[eventId] = index
    internal:FireCallbacks(internal.callback.EVENT_STORED, self.guildId, self.category, event, index)
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
    if self.storeEventsTask then
        self.hasPendingEvents = true
        return
    end

    local events, hasReachedLastStoredEventId, hasEncounteredInvalidEvent = self:GetFilteredReceivedEvents()
    local eventsBefore, eventsAfter = self:SeparateReceivedEvents(events)
    if #events > 0 then
        logger:Info("Add %d + %d events in guild %s (%d) category %s (%d)", #eventsBefore, #eventsAfter, GetGuildName(self.guildId), self.guildId, GetString("SI_GUILDHISTORYCATEGORY", self.category), self.category)
    end

    local unlinkedEvents = self.unlinkedEvents
    if unlinkedEvents then
        local hasOlder = self:AddOlderUnlinkedEvents(eventsBefore)
        local hasNewer = self:AddNewestUnlinkedEvents(eventsAfter)

        -- if we reached the end and still haven't linked up with the stored history we do so now
        if hasReachedLastStoredEventId or not self:CanReceiveMoreEvents() then
            self.unlinkedEvents = nil
            self.storeEventsTask = self:StoreReceivedEvents(unlinkedEvents, true)
        elseif hasOlder or hasNewer then
            internal:FireCallbacks(internal.callback.UNLINKED_EVENTS_ADDED, self.guildId, self.category)
        end
    else
        assert(#eventsBefore == 0, "Got events before when already linked")
        self.storeEventsTask = self:StoreReceivedEvents(eventsAfter)
    end

    if hasEncounteredInvalidEvent then
        if self.storedEventsTask then
            self.hasPendingEvents = true
        else
            zo_callLater(function() self:ReceiveEvents() end, 0)
        end
        logger:Debug("Has found invalid events")
    end
end

function GuildHistoryCacheCategory:GetFilteredReceivedEvents()
    local guildId, category = self.guildId, self.category
    local lastStoredEntry = self:GetEntry(self:GetNumEntries())
    local lastStoredEventId = lastStoredEntry and lastStoredEntry:GetEventId() or 0
    local numEvents = GetNumGuildEvents(guildId, category)
    local nextIndex = self.lastIndex + 1

    local events = {}
    local hasReachedLastStoredEventId = false
    local hasEncounteredInvalidEvent = false
    for index = nextIndex, numEvents do
        local eventId = select(9, GetGuildEventInfo(guildId, category, index))
        if eventId > lastStoredEventId then
            local event = GuildHistoryCacheEntry:New(self, guildId, category, index)
            if not event:IsValid() then
                hasEncounteredInvalidEvent = true
                break
            end
            events[#events + 1] = event
        else
            hasReachedLastStoredEventId = true
        end
        self.lastIndex = index
    end

    return events, hasReachedLastStoredEventId, hasEncounteredInvalidEvent
end

function GuildHistoryCacheCategory:SeparateReceivedEvents(events)
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
        elseif eventId > lastEventId then
            table.sort(events, ByEventIdAsc)
        elseif eventId < firstEventId then
            table.sort(events, ByEventIdDesc)
        else
            logger:Warn("First event %d needs to go somewhere between %d and %d", eventId, firstEventId, lastEventId)
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
                logger:Warn("Event %d (%d) needs to go somewhere between %d and %d", eventId, i, firstEventId, lastEventId)
            end
        end
    end

    return eventsBefore, eventsAfter
end

function GuildHistoryCacheCategory:StoreReceivedEvents(events, hasLinked)
    if hasLinked then
        internal:FireCallbacks(internal.callback.HISTORY_BEGIN_LINKING, self.guildId, self.category, #events)
    end
    if #events == 0 then return end
    local task = internal:CreateAsyncTask()
    task:For(1, #events):Do(function(i)
        self:StoreEvent(events[i])
    end):Then(function()
        self.storeEventsTask = nil
        if hasLinked then
            logger:Info("Linked %d events in guild %s (%d) category %s (%d)", #events, GetGuildName(self.guildId), self.guildId, GetString("SI_GUILDHISTORYCATEGORY", self.category), self.category)
            internal:FireCallbacks(internal.callback.HISTORY_LINKED, self.guildId, self.category)
        end
        if self.hasPendingEvents then
            self.hasPendingEvents = false
            self:ReceiveEvents()
        end
    end)
    return task
end

function GuildHistoryCacheCategory:AddOlderUnlinkedEvents(eventsBefore)
    if #eventsBefore == 0 then return false end
    table.sort(eventsBefore, ByEventIdAsc)
    local events = self.unlinkedEvents
    for i = 1, #events do
        eventsBefore[#eventsBefore + 1] = events[i]
    end
    self.unlinkedEvents = eventsBefore
    return true
end

function GuildHistoryCacheCategory:AddNewestUnlinkedEvents(eventsAfter)
    if #eventsAfter == 0 then return false end
    local events = self.unlinkedEvents
    for i = 1, #eventsAfter do
        events[#events + 1] = eventsAfter[i]
    end
    return true
end

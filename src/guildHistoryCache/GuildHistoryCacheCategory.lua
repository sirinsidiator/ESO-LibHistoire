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
local RETRY_ON_INVALID_DELAY = 5000 -- ms
local RETRY_WAIT_FOR_MORE_DELAY = 250 -- ms
local REQUEST_COOLDOWN = 1 -- s

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
    self.performanceTracker = internal.class.PerformanceTracker:New()

    self.events = {}
    self.eventTimeLookup = {}
    self.eventIndexLookup = {}
    self.eventIndexLookupDirty = false
    self.progressDirty = true
    self.lastRequestTime = 0

    -- remove holes in the saved vars
    for i = #self.saveData, 1, -1 do
        if self.saveData[i] == nil then
            logger:Warn("Entry %d in %s is nil - closing hole", i, self.key)
            self.saveData[i] = ""
            table.remove(self.saveData, i)
        end
    end

    -- add placeholders - deserialization will happen lazily
    for i in ipairs(self.saveData) do
        self.events[i] = false
    end

    -- make sure the first and last event are deserialized
    self:GetOldestEvent()
    self.newestEventAtStart = self:GetNewestEvent()

    self:ResetUnlinkedEvents()
end

function GuildHistoryCacheCategory:ResetUnlinkedEvents()
    self.lastIndex = 0
    self.waitForMore = 0
    -- we store everything in a temporary table until we find the last stored event
    self.unlinkedEvents = {}
end

function GuildHistoryCacheCategory:GetKey()
    return self.key
end

function GuildHistoryCacheCategory:GetGuildId()
    return self.guildId
end

function GuildHistoryCacheCategory:GetCategory()
    return self.category
end

function GuildHistoryCacheCategory:GetNameDictionary()
    return self.nameCache
end

function GuildHistoryCacheCategory:GetOffsets()
    return self.saveData.idOffset, self.saveData.timeOffset
end

function GuildHistoryCacheCategory:HasLinked()
    return not self.unlinkedEvents and not self.storeEventsTask
end

function GuildHistoryCacheCategory:IsFor(guildId, category)
    return self.guildId == guildId and self.category == category
end

function GuildHistoryCacheCategory:IsProcessing()
    return self.storeEventsTask ~= nil or self.rescanEventsTask ~= nil
end

function GuildHistoryCacheCategory:IsOnRequestCooldown()
    return GetTimeStamp() < self.lastRequestTime + REQUEST_COOLDOWN
end

function GuildHistoryCacheCategory:SendRequest()
    local success = RequestMoreGuildHistoryCategoryEvents(self.guildId, self.category, true)
    self.lastRequestTime = GetTimeStamp()
    return success
end

function GuildHistoryCacheCategory:GetNumPendingEvents()
    return self.numPendingEvents or 0
end

function GuildHistoryCacheCategory:GetNumUnlinkedEvents()
    if not self.unlinkedEvents then return 0 end
    return #self.unlinkedEvents
end

function GuildHistoryCacheCategory:GetUnlinkedEntry(i)
    if not self.unlinkedEvents then return end
    return self.unlinkedEvents[i]
end

function GuildHistoryCacheCategory:GetNumEvents()
    return #self.events
end

function GuildHistoryCacheCategory:GetEvent(i)
    if self.events[i] == false then -- if there is a placeholder we first need to deserialize it
        local serializedData = ReadFromSavedVariable(self.saveData, i)
        local event = GuildHistoryCacheEntry:New(self, serializedData)
        self.events[i] = event
        self:UpdateEventLookup(event, i)
    end
    return self.events[i]
end

function GuildHistoryCacheCategory:UpdateEventLookup(event, index)
    local eventId = event:GetEventId()
    self.eventIndexLookup[eventId] = index

    local eventTime = event:GetEventTime()
    if self.eventTimeLookup[eventTime] and eventId < self.eventTimeLookup[eventTime] then
        self.eventTimeLookup[eventTime] = eventId
    end
end

function GuildHistoryCacheCategory:GetOldestEvent()
    return self:GetEvent(1)
end

function GuildHistoryCacheCategory:GetNewestEvent()
    return self:GetEvent(self:GetNumEvents())
end

local function EventIterator(categoryCache, index)
    index = index + 1
    local event = categoryCache:GetEvent(index)
    if event then
        return index, event
    end
end

function GuildHistoryCacheCategory:GetIterator(startIndex)
    return EventIterator, self, startIndex or 0
end

function GuildHistoryCacheCategory:HasStoredEventId(eventId)
    local index = self:FindIndexForEventId(eventId)
    return not (index < 1 or index > self:GetNumEvents())
end

function GuildHistoryCacheCategory:FindIndexForEventId(eventId)
    if self:GetNumEvents() == 0 then return 0 end

    -- lookup if we know the answer already
    self:RebuildEventLookup()
    if self.eventIndexLookup[eventId] then
        return self.eventIndexLookup[eventId]
    end

    -- check if the event is inside the stored range
    if eventId < self:GetOldestEvent():GetEventId() then return 0 end
    if eventId > self:GetNewestEvent():GetEventId() then return self:GetNumEvents() + 1 end

    -- just use the full interval. iterating over the eventIndexLookup is slow and becomes increasingly slower the more entries it has
    local firstIndex = 1
    local lastIndex = self:GetNumEvents()

    -- and do a binary search for the event
    local event, index = self:SearchEventIdInInterval(eventId, firstIndex, lastIndex)
    if event then
        return index
    end

    return 0, firstIndex, lastIndex
end

function GuildHistoryCacheCategory:SearchEventIdInInterval(eventId, firstIndex, lastIndex)
    if lastIndex - firstIndex < 2 then return nil, nil end

    local firstEventId = self:GetEvent(firstIndex):GetEventId()
    local lastEventId = self:GetEvent(lastIndex):GetEventId()
    if eventId < firstEventId or eventId > lastEventId then
        logger:Warn("Abort SearchEventIdInInterval", eventId < firstEventId, eventId > lastEventId)
        return nil, nil
    end

    local distanceFromFirst = (eventId - firstEventId) / (lastEventId - firstEventId)
    local index = firstIndex + math.floor(distanceFromFirst * (lastIndex - firstIndex))
    if index == firstIndex or index == lastIndex then
        -- our approximation is likely incorrect, so we just do a regular binary search
        index = firstIndex + math.floor(0.5 * (lastIndex - firstIndex))
    end

    local event = self:GetEvent(index)
    local foundEventId = event:GetEventId()

    if eventId > foundEventId then
        return self:SearchEventIdInInterval(eventId, index, lastIndex)
    elseif eventId < foundEventId then
        return self:SearchEventIdInInterval(eventId, firstIndex, index)
    end

    return event, index
end

function GuildHistoryCacheCategory:FindClosestIndexForEventTime(eventTime)
    if self:GetNumEvents() == 0 then return 0 end

    -- lookup if we know the answer already
    self:RebuildEventLookup()
    if self.eventTimeLookup[eventTime] then
        local eventId = self.eventTimeLookup[eventTime]
        if self.eventIndexLookup[eventId] then
            return self.eventIndexLookup[eventId]
        end
    end

    -- check if the event is inside the stored range
    if eventTime < self:GetOldestEvent():GetEventTime() then return 0 end
    if eventTime > self:GetNewestEvent():GetEventTime() then return self:GetNumEvents() + 1 end

    -- otherwise find the smallest known interval
    local firstIndex = 1
    local lastIndex = self:GetNumEvents()

    for time, id in pairs(self.eventTimeLookup) do
        local index = self.eventIndexLookup[id]
        if index then
            if time < eventTime and index > firstIndex then firstIndex = index end
            if time > eventTime and index < lastIndex then lastIndex = index end
        end
    end

    -- and do a binary search for the event
    local event, index = self:SearchClosestEventTimeInInterval(eventTime, firstIndex, lastIndex)
    if event then
        -- make sure we got the last index for a specific time
        for i = index + 1, self:GetNumEvents() do
            local next = self:GetEvent(i)
            if next:GetEventTime() == eventTime then
                index = i
            else
                break
            end
        end
        self.eventTimeLookup[eventTime] = event:GetEventId()
        return index
    end

    return 0
end

function GuildHistoryCacheCategory:SearchClosestEventTimeInInterval(eventTime, firstIndex, lastIndex)
    local firstEvent = self:GetEvent(firstIndex)
    if lastIndex - firstIndex < 2 then return firstEvent, firstIndex end

    local firstEventTime = firstEvent:GetEventTime()
    local lastEventTime = self:GetEvent(lastIndex):GetEventTime()
    if eventTime < firstEventTime or eventTime > lastEventTime then
        return firstEvent, firstIndex
    end

    local distanceFromFirst = (eventTime - firstEventTime) / (lastEventTime - firstEventTime)
    local index = firstIndex + math.floor(distanceFromFirst * (lastIndex - firstIndex))
    if index == firstIndex or index == lastIndex then
        -- our approximation is likely incorrect, so we just do a regular binary search
        index = firstIndex + math.floor(0.5 * (lastIndex - firstIndex))
    end

    -- ensure we don't get stuck on the boundaries
    if index == firstIndex then
        index = index + 1
    elseif index == lastIndex then
        index = index - 1
    end

    local event = self:GetEvent(index)
    local foundEventTime = event:GetEventTime()

    if eventTime > foundEventTime then
        return self:SearchClosestEventTimeInInterval(eventTime, index, lastIndex)
    elseif eventTime < foundEventTime then
        return self:SearchClosestEventTimeInInterval(eventTime, firstIndex, index)
    end

    return event, index
end

function GuildHistoryCacheCategory:StoreEvent(event, missing)
    if not self.saveData.idOffset then self.saveData.idOffset = event:GetEventId() end
    if not self.saveData.timeOffset then self.saveData.timeOffset = event:GetEventTime() end

    local index = #self.events + 1
    local eventData = event:Serialize()
    assert(eventData, "Failed to serialize history event")

    self.events[index] = event

    WriteToSavedVariable(self.saveData, index, eventData)
    assert(self.saveData[index] ~= nil, "Failed to write history event to save data")

    if missing then
        self.eventIndexLookupDirty = true
    else
        self:UpdateEventLookup(event, index)
    end
    internal:FireCallbacks(internal.callback.EVENT_STORED, self.guildId, self.category, event, index, missing)
end

function GuildHistoryCacheCategory:InsertEvent(event, index)
    local eventData = event:Serialize()
    assert(eventData, "Failed to serialize history event")

    table.insert(self.events, index, event)
    table.insert(self.saveData, index, "") -- insert a placeholder so all indices are moved up by one

    WriteToSavedVariable(self.saveData, index, eventData)
    assert(self.saveData[index] ~= nil, "Failed to write history event to save data")

    self.eventIndexLookupDirty = true
    internal:FireCallbacks(internal.callback.EVENT_STORED, self.guildId, self.category, event, index, true)
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

local function GuildEventIterator(self, i)
    i = i + 1
    if i > GetNumGuildEvents(self.guildId, self.category) then return end
    return i
end

local function GetGuildEventIterator(self, startIndex)
    return GuildEventIterator, self, (startIndex or 1) - 1
end

function GuildHistoryCacheCategory:GetMissingEvents(task, missingEvents)
    local missingEvents = {}
    local hasEncounteredInvalidEvent = false
    local guildId, category = self.guildId, self.category
    self.lastIndex = 0
    self:InitializePendingEventMetrics(GetNumGuildEvents(guildId, category))
    task:For(GetGuildEventIterator(self)):Do(function(index)
        self:IncrementPendingEventMetrics()
        local eventId = select(9, GetGuildEventInfo(guildId, category, index))
        if not self:HasStoredEventId(eventId) then
            local event = GuildHistoryCacheEntry:New(self, guildId, category, index)
            if(event:IsValid()) then
                missingEvents[#missingEvents + 1] = event
            else
                hasEncounteredInvalidEvent = true
            end
        end
        self.lastIndex = index
    end)
    return missingEvents, hasEncounteredInvalidEvent
end

function GuildHistoryCacheCategory:SeparateMissingEvents(missingEvents)
    local eventsBefore = {}
    local eventsInside = {}
    local eventsAfter = {}

    local sessionStartId = self.newestEventAtStart and self.newestEventAtStart:GetEventId() or 0
    local lastRescanId = self.lastRescanEvent and self.lastRescanEvent:GetEventId() or 0
    local firstStoredEntry = self:GetOldestEvent()
    local firstStoredEventId = firstStoredEntry and firstStoredEntry:GetEventId() or 0
    local lastStoredEntry = self:GetNewestEvent()
    local lastStoredEventId = lastStoredEntry and lastStoredEntry:GetEventId() or 0

    local afterSessionStartCount = 0
    local lastRescanCount = 0
    for i = 1, #missingEvents do
        local event = missingEvents[i]
        local eventId = event:GetEventId()
        if eventId > sessionStartId then
            afterSessionStartCount = afterSessionStartCount + 1
        end
        if eventId > lastRescanId then
            lastRescanCount = lastRescanCount + 1
        end
        if firstStoredEntry and eventId < firstStoredEventId then
            eventsBefore[#eventsBefore + 1] = event
        elseif not lastStoredEntry or eventId > lastStoredEventId then
            eventsAfter[#eventsAfter + 1] = event
        else
            eventsInside[#eventsInside + 1] = event
        end
    end
    logger:Debug("#missing: %d - after start: %d - since last rescan: %d", #missingEvents, afterSessionStartCount, lastRescanCount)

    return eventsBefore, eventsInside, eventsAfter
end

function GuildHistoryCacheCategory:StoreMissingEventsBefore(eventsBefore, callback)
    if #eventsBefore == 0 then callback() return end

    -- deserialize all stored events as we need to save them again with the new offsets
    local storedEvents = {}
    local taskA = internal:CreateAsyncTask()
    taskA:For(1, self:GetNumEvents()):Do(function(i)
        storedEvents[i] = self:GetEvent(i)
    end):Then(function()
        ZO_ClearTable(self.events)
        ZO_ClearTable(self.saveData)
        local taskC = internal:CreateAsyncTask()
        taskC:For(ipairs(eventsBefore)):Do(function(i, event)
            self:IncrementPendingEventMetrics()
            self:StoreEvent(event, true)
        end):Then(function()
            local taskD = internal:CreateAsyncTask()
            taskD:For(ipairs(storedEvents)):Do(function(i, event)
                local index = #self.events + 1
                local eventData = event:Serialize()
                assert(eventData, "Failed to serialize history event")

                self.events[index] = event

                WriteToSavedVariable(self.saveData, index, eventData)
                assert(self.saveData[index] ~= nil, "Failed to write history event to save data")
            end):Then(callback)
        end)
    end)
end

function GuildHistoryCacheCategory:StoreMissingEventsInside(eventsInside, callback)
    if #eventsInside == 0 then callback() return end

    local function GetProperIndexFor(eventId, startIndex, endIndex)
        local lastEventId = 0
        for j = startIndex, endIndex do
            local nextEventId = self:GetEvent(j):GetEventId()
            if eventId > lastEventId and eventId < nextEventId then
                lastEventId = eventId
                return j
            end
            lastEventId = nextEventId
        end
    end

    local task = internal:CreateAsyncTask()
    task:For(ipairs(eventsInside)):Do(function(i, event)
        self:IncrementPendingEventMetrics()
        local eventId = event:GetEventId()

        local index, startIndex, endIndex = self:FindIndexForEventId(eventId)
        if index ~= 0 then
            logger:Warn("event with id %d is already stored", eventId)
            return
        elseif not startIndex or not endIndex then
            logger:Warn("Could not find interval for event with id %d", eventId)
            return
        else
            index = GetProperIndexFor(eventId, startIndex, endIndex)
        end

        if index then
            self:InsertEvent(event, index)
        else
            logger:Warn("Could not find proper index for insertion of event with id %d", eventId)
        end
    end):Then(callback)
end

function GuildHistoryCacheCategory:StoreMissingEventsAfter(eventsAfter, callback)
    if #eventsAfter == 0 then callback() return end

    local task = internal:CreateAsyncTask()
    task:For(ipairs(eventsAfter)):Do(function(i, event)
        self:IncrementPendingEventMetrics()
        self:StoreEvent(event, false)
    end):Then(callback)
end

function GuildHistoryCacheCategory:RescanEvents()
    if self:IsProcessing() or not self:HasLinked() then return false end

    local guildId, category = self.guildId, self.category
    local guildName, categoryName = GetGuildName(guildId), GetString("SI_GUILDHISTORYCATEGORY", category)
    self.rescanEventsTask = internal:CreateAsyncTask()
    logger:Info("Start rescanning events in guild %s (%d) category %s (%d)", guildName, guildId, categoryName, category)
    internal:FireCallbacks(internal.callback.HISTORY_RESCAN_STARTED, guildId, category)

    local task = self.rescanEventsTask
    local missingEvents, hasEncounteredInvalidEvent = self:GetMissingEvents(task)

    local eventsBefore, eventsInside, eventsAfter
    task:Then(function()
        if #missingEvents > 0 then
            self:InitializePendingEventMetrics(#missingEvents)
            table.sort(missingEvents, ByEventIdAsc)
        else
            task:Cancel()
            self:ResetPendingEventMetrics()
            self.rescanEventsTask = nil
            logger:Info("Detected no missing events in guild %s (%d) category %s (%d)", guildName, guildId, categoryName, category)
            internal:FireCallbacks(internal.callback.HISTORY_RESCAN_ENDED, guildId, category, 0, 0, 0, hasEncounteredInvalidEvent)
        end
    end):Then(function()
        eventsBefore, eventsInside, eventsAfter = self:SeparateMissingEvents(missingEvents)
        logger:Info("Detected %d + %d + %d missing events in guild %s (%d) category %s (%d)", #eventsBefore, #eventsInside, #eventsAfter, guildName, guildId, categoryName, category)
    end):Then(function()
        self:StoreMissingEventsBefore(eventsBefore, function()
            self:StoreMissingEventsInside(eventsInside, function()
                self:StoreMissingEventsAfter(eventsAfter, function()
                    self:RebuildEventLookup()
                    logger:Info("Finished rescanning events in guild %s (%d) category %s (%d)", guildName, guildId, categoryName, category)
                    self.rescanEventsTask = nil
                    self:ResetPendingEventMetrics()
                    self.lastRescanEvent = self:GetNewestEvent()
                    if hasEncounteredInvalidEvent then
                        ZO_Alert(UI_ALERT_CATEGORY_ERROR, SOUNDS.NEGATIVE_CLICK, "Found invalid events while rescanning history")
                    end
                    internal:FireCallbacks(internal.callback.HISTORY_RESCAN_ENDED, guildId, category, #eventsBefore, #eventsInside, #eventsAfter, hasEncounteredInvalidEvent)

                    if self.hasPendingEvents then
                        self.hasPendingEvents = false
                        self:ReceiveEvents()
                    end
                end)
            end)
        end)
    end)

    return true
end

function GuildHistoryCacheCategory:RebuildEventLookup()
    if self.eventIndexLookupDirty then
        ZO_ClearTable(self.eventIndexLookup)
        for index = 1, #self.events do
            local event = self.events[index]
            if event then
                self:UpdateEventLookup(event, index)
            end
        end
        self.eventIndexLookupDirty = false
    end
end

function GuildHistoryCacheCategory:ReceiveEvents()
    if self:IsProcessing() then
        self.hasPendingEvents = true
        return
    end

    local events, hasReachedLastStoredEventId, retryDelay = self:GetFilteredReceivedEvents()
    if events == false then
        if self.retryHandle then
            zo_removeCallLater(self.retryHandle)
        end
        self.retryHandle = zo_callLater(function() self:ReceiveEvents() end, retryDelay)
        return
    end
    self.retryHandle = nil

    local eventsBefore, eventsAfter, hasEventsBetween = self:SeparateReceivedEvents(events)
    if #events > 0 then
        logger:Info("Add %d + %d events in guild %s (%d) category %s (%d)", #eventsBefore, #eventsAfter, GetGuildName(self.guildId), self.guildId, GetString("SI_GUILDHISTORYCATEGORY", self.category), self.category)
    end

    local unlinkedEvents = self.unlinkedEvents
    if unlinkedEvents then
        local hasOlder, hasNewer
        if hasEventsBetween then
            hasOlder = self:AddUnsortedUnlinkedEvents(eventsBefore)
        else
            hasOlder = self:AddOlderUnlinkedEvents(eventsBefore)
            hasNewer = self:AddNewestUnlinkedEvents(eventsAfter)
        end

        -- if there is nothing stored yet, or  we reached the end and still haven't linked up with the stored history we do so now
        if #self.events == 0 or hasReachedLastStoredEventId or not self:CanReceiveMoreEvents() then
            self:LinkHistory()
        elseif hasOlder or hasNewer then
            self.progressDirty = true
            internal:FireCallbacks(internal.callback.UNLINKED_EVENTS_ADDED, self.guildId, self.category)
        end
    else
        if #eventsBefore > 0 then
            logger:Warn("Got eventsBefore when already linked - do a rescan")
            zo_callLater(function() self:RescanEvents() end, 0)
            return
        end
        self.storeEventsTask = self:StoreReceivedEvents(eventsAfter)
    end
end

function GuildHistoryCacheCategory:LinkHistory()
    if self:IsProcessing() or self:HasLinked() then return false end
    local unlinkedEvents = self.unlinkedEvents
    self.unlinkedEvents = nil
    self.storeEventsTask = self:StoreReceivedEvents(unlinkedEvents, true)
    if #unlinkedEvents > 0 then
        logger:Info("Begin linking %d events in guild %s (%d) category %s (%d)", #unlinkedEvents, GetGuildName(self.guildId), self.guildId, GetString("SI_GUILDHISTORYCATEGORY", self.category), self.category)
    end
    internal:FireCallbacks(internal.callback.HISTORY_BEGIN_LINKING, self.guildId, self.category, #unlinkedEvents)
    return true
end

function GuildHistoryCacheCategory:GetFilteredReceivedEvents()
    local guildId, category = self.guildId, self.category
    local numEvents = GetNumGuildEvents(guildId, category)
    local lastIndex = self.lastIndex
    local nextIndex = lastIndex + 1
    local waitForMore = self.waitForMore
    self.waitForMore = numEvents

    local lastStoredEntry = self:GetNewestEvent()
    local lastStoredEventId = lastStoredEntry and lastStoredEntry:GetEventId() or 0
    local sessionStartId = self.newestEventAtStart and self.newestEventAtStart:GetEventId() or 0

    logger:Verbose("GetFilteredReceivedEvents from %d to %d (%d/%d)", nextIndex, numEvents, guildId, category)
    local skipped = 0
    local events = {}
    local hasReachedLastStoredEventId = false
    for index = nextIndex, numEvents do
        local eventId = select(9, GetGuildEventInfo(guildId, category, index))
        if eventId > lastStoredEventId then
            if waitForMore ~= numEvents and self:HasLinked() then
                logger:Verbose("Detected push events. Wait for more")
                return false, false, RETRY_WAIT_FOR_MORE_DELAY
            end

            local event = GuildHistoryCacheEntry:New(self, guildId, category, index)
            if not event:IsValid() then
                logger:Verbose("Has found invalid events")
                return false, false, RETRY_ON_INVALID_DELAY
            end
            events[#events + 1] = event
        else
            skipped = skipped + 1
            if eventId == lastStoredEventId then
                hasReachedLastStoredEventId = true
            end
            if eventId > sessionStartId then
                logger:Warn("skip event %d", eventId)
            end
        end
        lastIndex = index
    end

    self.lastIndex = lastIndex
    logger:Verbose("#events: %d - skipped: %d (%d/%d)", #events, skipped, guildId, category)
    return events, hasReachedLastStoredEventId
end

function GuildHistoryCacheCategory:SeparateReceivedEvents(events)
    local eventsBefore = {}
    local eventsAfter = {}

    if #events > 0 then
        local lastEventId, firstEventId = self:GetFirstAndLastUnlinkedEventId()
        local eventId = events[1]:GetEventId()
        if not lastEventId then
            table.sort(events, ByEventIdAsc)
            eventId = events[1]:GetEventId() -- need to fetch it again after sorting
            lastEventId = eventId - 1
            firstEventId = eventId + 1
        elseif eventId > lastEventId then
            table.sort(events, ByEventIdAsc)
        elseif eventId < firstEventId then
            table.sort(events, ByEventIdDesc)
        else
            logger:Warn("First event %d needs to go somewhere between %d and %d", eventId, firstEventId, lastEventId)
            return events, {}, true
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
                -- TODO this seems to happen in some rare case. Need to figure out why and fix it
                -- may be related to when the session has a lot of negative event times
                logger:Warn("Event %d (%d) needs to go somewhere between %d and %d", eventId, i, firstEventId, lastEventId)
                return events, {}, true
            end
        end
    end

    return eventsBefore, eventsAfter, false
end

function GuildHistoryCacheCategory:StoreReceivedEvents(events, hasLinked)
    local task = internal:CreateAsyncTask()
    self:InitializePendingEventMetrics(#events)
    task:For(1, #events):Do(function(i)
        self:IncrementPendingEventMetrics()
        self:StoreEvent(events[i], false)
    end):Then(function()
        self.storeEventsTask = nil
        self:ResetPendingEventMetrics()
        if hasLinked then
            self.progressDirty = true
            if #events > 0 then
                logger:Info("Finished linking %d events in guild %s (%d) category %s (%d)", #events, GetGuildName(self.guildId), self.guildId, GetString("SI_GUILDHISTORYCATEGORY", self.category), self.category)
            end
            internal:FireCallbacks(internal.callback.HISTORY_LINKED, self.guildId, self.category)
        end
        if self.hasPendingEvents then
            self.hasPendingEvents = false
            self:ReceiveEvents()
        end
    end)
    return task
end

function GuildHistoryCacheCategory:InitializePendingEventMetrics(numPendingEvents)
    self.numPendingEvents = numPendingEvents
    self.performanceTracker:Reset()
end

function GuildHistoryCacheCategory:ResetPendingEventMetrics()
    self.numPendingEvents = nil
    self.performanceTracker:Reset()
end

function GuildHistoryCacheCategory:IncrementPendingEventMetrics()
    self.numPendingEvents = self.numPendingEvents - 1
    self.performanceTracker:Increment()
end

function GuildHistoryCacheCategory:GetPendingEventMetrics()
    if not self.numPendingEvents or not self:IsProcessing() then return 0, -1, -1 end

    local count = self.numPendingEvents
    local speed, timeLeft = self.performanceTracker:GetProcessingSpeedAndEstimatedTimeLeft(count)
    return count, speed, timeLeft
end

function GuildHistoryCacheCategory:AddUnsortedUnlinkedEvents(unsortedEvents)
    if #unsortedEvents == 0 then return false end
    local events = self.unlinkedEvents
    for i = 1, #unsortedEvents do
        events[#events + 1] = unsortedEvents[i]
    end
    table.sort(events, ByEventIdAsc)
    return true
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

function GuildHistoryCacheCategory:GetProgress()
    if self.progressDirty then
        if self:HasLinked() then
            self.progress = 1
            self.missingTime = 0
        else
            local lastStoredEvent = self:GetNewestEvent()
            local firstUnlinkedEvent = self:GetUnlinkedEntry(1)
            if lastStoredEvent and firstUnlinkedEvent then
                self.missingTime = firstUnlinkedEvent:GetEventTime() - lastStoredEvent:GetEventTime()
                self.progress = 1 - self.missingTime / (GetTimeStamp() - lastStoredEvent:GetEventTime())
            else
                self.progress = 0
                self.missingTime = -1
            end
        end
        self.progressDirty = false
    end
    return self.progress, self.missingTime
end

function GuildHistoryCacheCategory:IsAggregated()
    return false
end

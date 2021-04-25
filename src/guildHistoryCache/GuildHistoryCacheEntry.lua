-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local EncodeData = internal.EncodeData
local DecodeData = internal.DecodeData
local EncodeValue = internal.EncodeValue

local GuildHistoryCacheEntry = ZO_Object:Subclass()
internal.class.GuildHistoryCacheEntry = GuildHistoryCacheEntry

local INDEX_EVENT_TYPE = 1 -- enum (EventType)
local INDEX_EVENT_TIME = 2 -- integer
local INDEX_PARAM_1 = 3 -- mixed
local INDEX_PARAM_2 = 4 -- mixed
local INDEX_PARAM_3 = 5 -- mixed
local INDEX_PARAM_4 = 6 -- mixed
local INDEX_PARAM_5 = 7 -- mixed
local INDEX_PARAM_6 = 8 -- mixed
local INDEX_EVENT_ID = 9 -- integer

local VERSION = 1
local FIELD_SEPARATOR = ";"
local EVENT_ID_SEARCH_STRING_TEMPLATE = ";%s;"
local FIELD_FORMAT = {
    [1] = {
        "integer", -- version
        "integer", -- eventTime
        "integer", -- eventId
        "string", -- params
    }
}
local CURRENT_FIELD_FORMAT = FIELD_FORMAT[VERSION]

local PARAM_SEPARATOR = ":"
local PARAMS_FORMAT_NO_DATA = {
    "integer", -- eventType
}

local PARAMS_FORMAT_ONE_NAME = {
    "integer", -- eventType
    "dictionary", -- param 1
}

local PARAMS_FORMAT_TWO_NAMES = {
    "integer", -- eventType
    "dictionary", -- param 1
    "dictionary", -- param 2
}

local PARAMS_FORMAT_NAME_INTEGER = {
    "integer", -- eventType
    "dictionary", -- param 1
    "integer", -- param 2
}

local PARAMS_FORMAT_THREE_NAMES = {
    "integer", -- eventType
    "dictionary", -- param 1
    "dictionary", -- param 2
    "dictionary", -- param 3
}

local PARAMS_FORMAT_NAME_INTEGER_NAME = {
    "integer", -- eventType
    "dictionary", -- param 1
    "integer", -- param 2
    "dictionary", -- param 3
}

local PARAMS_FORMAT_NAME_INTEGER_LINK = {
    "integer", -- eventType
    "dictionary", -- param 1
    "integer", -- param 2
    "itemLink", -- param 3
}

-- see guildhistory_shared.lua for the event parameters
local PARAMS_FORMAT = {
    [1] = {
        default = {
            "integer", -- eventType
            "base64", -- param 1
            "base64", -- param 2
            "base64", -- param 3
            "base64", -- param 4
            "base64", -- param 5
            "base64", -- param 6
        },
        [GUILD_EVENT_GUILD_PROMOTE] = PARAMS_FORMAT_THREE_NAMES,                    -- (eventType, displayName1, displayName2, rankName)
        [GUILD_EVENT_GUILD_DEMOTE] = PARAMS_FORMAT_THREE_NAMES,                     -- (eventType, displayName1, displayName2, rankName)
        [GUILD_EVENT_GUILD_CREATE] = PARAMS_FORMAT_ONE_NAME,                        -- (eventType, displayName)
        [GUILD_EVENT_GUILD_INVITE] = PARAMS_FORMAT_TWO_NAMES,                       -- (eventType, displayName1, displayName2)
        [GUILD_EVENT_GUILD_JOIN] = PARAMS_FORMAT_TWO_NAMES,                         -- (eventType, joinerDisplayName, optionalInviterDisplayName)
        [GUILD_EVENT_GUILD_LEAVE] = PARAMS_FORMAT_ONE_NAME,                         -- (eventType, displayName)
        [GUILD_EVENT_GUILD_KICKED] = PARAMS_FORMAT_TWO_NAMES,                       -- (eventType, displayName1, displayName2)
        [GUILD_EVENT_BANKITEM_ADDED] = PARAMS_FORMAT_NAME_INTEGER_LINK,           -- (eventType, displayName, itemQuantity, itemName)
        [GUILD_EVENT_BANKITEM_REMOVED] = PARAMS_FORMAT_NAME_INTEGER_LINK,         -- (eventType, displayName, itemQuantity, itemName)
        [GUILD_EVENT_BANKGOLD_ADDED] = PARAMS_FORMAT_NAME_INTEGER,                  -- (eventType, displayName, goldQuantity)
        [GUILD_EVENT_BANKGOLD_REMOVED] = PARAMS_FORMAT_NAME_INTEGER,                -- (eventType, displayName, goldQuantity)
        [GUILD_EVENT_BANKGOLD_KIOSK_BID_REFUND] = PARAMS_FORMAT_NAME_INTEGER,       -- (eventType, kioskName, goldQuantity)
        [GUILD_EVENT_BANKGOLD_KIOSK_BID] = PARAMS_FORMAT_NAME_INTEGER_NAME,         -- (eventType, displayName, goldQuantity, kioskName)
        [GUILD_EVENT_GUILD_KIOSK_PURCHASED] = PARAMS_FORMAT_NAME_INTEGER_NAME,      -- (eventType, displayName, goldQuantity, kioskName)
        [GUILD_EVENT_BANKGOLD_GUILD_STORE_TAX] = PARAMS_FORMAT_NO_DATA,             -- (eventType)
        [GUILD_EVENT_MOTD_EDITED] = PARAMS_FORMAT_ONE_NAME,                         -- (eventType, displayName)
        [GUILD_EVENT_ABOUT_US_EDITED] = PARAMS_FORMAT_ONE_NAME,                     -- (eventType, displayName)
        [GUILD_EVENT_KEEP_CLAIMED] = PARAMS_FORMAT_THREE_NAMES,                     -- (eventType, displayName, keepName, campaignName)
        [GUILD_EVENT_KEEP_RELEASED] = PARAMS_FORMAT_THREE_NAMES,                    -- (eventType, displayName, keepName, campaignName)
        [GUILD_EVENT_KEEP_LOST] = PARAMS_FORMAT_TWO_NAMES,                          -- (eventType, keepName, campaignName)
        [GUILD_EVENT_HERALDRY_EDITED] = PARAMS_FORMAT_NAME_INTEGER,                 -- (eventType, displayName, goldCost)
        [GUILD_EVENT_GUILD_STORE_UNLOCKED] = PARAMS_FORMAT_NO_DATA,                 -- (eventType)
        [GUILD_EVENT_GUILD_STORE_LOCKED] = PARAMS_FORMAT_NO_DATA,                   -- (eventType)
        [GUILD_EVENT_GUILD_BANK_UNLOCKED] = PARAMS_FORMAT_NO_DATA,                  -- (eventType)
        [GUILD_EVENT_GUILD_BANK_LOCKED] = PARAMS_FORMAT_NO_DATA,                    -- (eventType)
        [GUILD_EVENT_GUILD_STANDARD_UNLOCKED] = PARAMS_FORMAT_NO_DATA,              -- (eventType)
        [GUILD_EVENT_GUILD_STANDARD_LOCKED] = PARAMS_FORMAT_NO_DATA,                -- (eventType)
        [GUILD_EVENT_GUILD_KIOSK_UNLOCKED] = PARAMS_FORMAT_NO_DATA,                 -- (eventType)
        [GUILD_EVENT_GUILD_KIOSK_LOCKED] = PARAMS_FORMAT_NO_DATA,                   -- (eventType)
        [GUILD_EVENT_GUILD_TABARD_UNLOCKED] = PARAMS_FORMAT_NO_DATA,                -- (eventType)
        [GUILD_EVENT_GUILD_TABARD_LOCKED] = PARAMS_FORMAT_NO_DATA,                  -- (eventType)
        [GUILD_EVENT_GUILD_APPLICATION_DECLINED] = PARAMS_FORMAT_TWO_NAMES,         -- (eventType, displayName1, displayName2)
        [GUILD_EVENT_GUILD_APPLICATION_ACCEPTED] = PARAMS_FORMAT_TWO_NAMES,         -- (eventType, displayName1, displayName2)
        [GUILD_EVENT_REMOVED_FROM_BLACKLIST] = PARAMS_FORMAT_TWO_NAMES,             -- (eventType, displayName1, displayName2)
        [GUILD_EVENT_ADDED_TO_BLACKLIST] = PARAMS_FORMAT_TWO_NAMES,                 -- (eventType, displayName1, displayName2)
        [GUILD_EVENT_EDIT_BLACKLIST_NOTE] = PARAMS_FORMAT_TWO_NAMES,                -- (eventType, displayName1, displayName2)
        [GUILD_EVENT_GUILD_RECRUITMENT_GUILD_LISTED] = PARAMS_FORMAT_ONE_NAME,      -- (eventType, displayName)
        [GUILD_EVENT_GUILD_RECRUITMENT_GUILD_UNLISTED] = PARAMS_FORMAT_ONE_NAME,    -- (eventType, displayName)
        [GUILD_EVENT_ITEM_SOLD] = {
            "integer", -- eventType
            "dictionary", -- sellerName
            "dictionary", -- buyerName
            "integer", -- quantity
            "itemLink", -- itemLink
            "integer", -- price
            "integer", -- tax
        },

    }
}
local CURRENT_PARAMS_FORMAT = PARAMS_FORMAT[VERSION]

local temp = {}

function GuildHistoryCacheEntry.CreateEventIdSearchString(eventId)
    return string.format(EVENT_ID_SEARCH_STRING_TEMPLATE, EncodeValue("integer", eventId))
end

function GuildHistoryCacheEntry:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function GuildHistoryCacheEntry:Initialize(cacheCategory, guildIdOrSerializedData, category, eventIndex)
    self.valid = nil
    self.cacheCategory = cacheCategory
    if category then
        -- assume it's a new entry and get data from the api
        local now = GetTimeStamp()
        self.info = {GetGuildEventInfo(guildIdOrSerializedData, category, eventIndex)}
        self.info[INDEX_EVENT_TIME] = now - self.info[INDEX_EVENT_TIME] -- convert to absolute time
    else
        -- assume it's a stored entry and deserialize it
        self.info = self:Deserialize(guildIdOrSerializedData)
    end
end

function GuildHistoryCacheEntry:Serialize()
    local idOffset, timeOffset = self.cacheCategory:GetOffsets()

    local info = self.info
    local eventType = info[INDEX_EVENT_TYPE]
    local eventId = info[INDEX_EVENT_ID]

    local paramsFormat = CURRENT_PARAMS_FORMAT[eventType]
    if not paramsFormat then
        logger:Warn("No format for eventType %d - use default format", eventType)
        paramsFormat = CURRENT_PARAMS_FORMAT.default
    end

    temp[1] = eventType
    for i = 2, #paramsFormat do
        temp[i] = info[INDEX_PARAM_1 + i - 2]
        if paramsFormat == CURRENT_PARAMS_FORMAT.default and temp[i] == nil then
            temp[i] = ""
        end
    end
    local params = EncodeData(temp, paramsFormat, PARAM_SEPARATOR, self.cacheCategory:GetNameDictionary())

    temp[1] = VERSION
    temp[2] = info[INDEX_EVENT_TIME] - timeOffset
    temp[3] = eventId - idOffset
    if temp[3] < 0 then internal.logger:Warn("Negative eventId after subtracting offset") end
    temp[4] = params
    local serializedData = EncodeData(temp, CURRENT_FIELD_FORMAT, FIELD_SEPARATOR)
    return serializedData
end

function GuildHistoryCacheEntry:Deserialize(serializedData)
    local idOffset, timeOffset = self.cacheCategory:GetOffsets()
    local info = {}

    local data, version = DecodeData(serializedData, FIELD_FORMAT, FIELD_SEPARATOR)
    local i = 2 -- starts with version on 1
    info[INDEX_EVENT_TIME] = data[i] + timeOffset
    i = i + 1
    info[INDEX_EVENT_ID] = data[i] + idOffset
    i = i + 1
    local serializedParams = data[i]

    local paramsFormat = PARAMS_FORMAT[version]
    local params, eventType = DecodeData(serializedParams, paramsFormat, PARAM_SEPARATOR, self.cacheCategory:GetNameDictionary())
    info[INDEX_EVENT_TYPE] = eventType
    for i = 2, #params do
        info[INDEX_PARAM_1 + i - 2] = params[i]
    end

    return info
end

function GuildHistoryCacheEntry:IsValid()
    if self.valid == nil then
        if self:GetEventTime() < 0 then
            self.valid = false
            logger:Warn("EventTime %d is negative", self:GetEventTime())
        else
            self.valid = true
        end
    end
    return self.valid
end

function GuildHistoryCacheEntry:GetEventType()
    return self.info[INDEX_EVENT_TYPE]
end

function GuildHistoryCacheEntry:GetEventTime()
    return self.info[INDEX_EVENT_TIME]
end

function GuildHistoryCacheEntry:GetEventId()
    return self.info[INDEX_EVENT_ID]
end

function GuildHistoryCacheEntry:GetEventId64()
    if not self.eventId64 then
        self.eventId64 = internal:ConvertNumberToId64(self.info[INDEX_EVENT_ID])
    end
    return self.eventId64
end

function GuildHistoryCacheEntry:Unpack()
    return self.info[INDEX_EVENT_TYPE],
        self:GetEventId64(),
        self.info[INDEX_EVENT_TIME],
        self.info[INDEX_PARAM_1],
        self.info[INDEX_PARAM_2],
        self.info[INDEX_PARAM_3],
        self.info[INDEX_PARAM_4],
        self.info[INDEX_PARAM_5],
        self.info[INDEX_PARAM_6]
end

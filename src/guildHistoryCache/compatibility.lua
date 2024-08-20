-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

GUILD_HISTORY_ALLIANCE_WAR = 5
GUILD_HISTORY_ALLIANCE_WAR_ITERATION_BEGIN = 1
GUILD_HISTORY_ALLIANCE_WAR_ITERATION_END = 1
GUILD_HISTORY_ALLIANCE_WAR_MAX_VALUE = 1
GUILD_HISTORY_ALLIANCE_WAR_MIN_VALUE = 1
GUILD_HISTORY_ALLIANCE_WAR_OWNERSHIP = 1
GUILD_HISTORY_BANK = 2
GUILD_HISTORY_BANK_DEPOSITS = 1
GUILD_HISTORY_BANK_ITERATION_BEGIN = 1
GUILD_HISTORY_BANK_ITERATION_END = 2
GUILD_HISTORY_BANK_MAX_VALUE = 2
GUILD_HISTORY_BANK_MIN_VALUE = 1
GUILD_HISTORY_BANK_WITHDRAWALS = 2
GUILD_HISTORY_COMBAT = 4
GUILD_HISTORY_GENERAL = 1
GUILD_HISTORY_GENERAL_CUSTOMIZATION = 2
GUILD_HISTORY_GENERAL_ITERATION_BEGIN = 1
GUILD_HISTORY_GENERAL_ITERATION_END = 3
GUILD_HISTORY_GENERAL_MAX_VALUE = 3
GUILD_HISTORY_GENERAL_MIN_VALUE = 1
GUILD_HISTORY_GENERAL_ROSTER = 1
GUILD_HISTORY_GENERAL_UNLOCKS = 3
GUILD_HISTORY_ITERATION_BEGIN = 1
GUILD_HISTORY_ITERATION_END = 5
GUILD_HISTORY_MAX_VALUE = 5
GUILD_HISTORY_MIN_VALUE = 1
GUILD_HISTORY_STORE = 3
GUILD_HISTORY_STORE_HIRED_TRADER = 2
GUILD_HISTORY_STORE_ITERATION_BEGIN = 1
GUILD_HISTORY_STORE_ITERATION_END = 2
GUILD_HISTORY_STORE_MAX_VALUE = 2
GUILD_HISTORY_STORE_MIN_VALUE = 1
GUILD_HISTORY_STORE_PURCHASES = 1

GUILD_EVENT_ABOUT_US_EDITED = 32
GUILD_EVENT_ADDED_TO_BLACKLIST = 46
GUILD_EVENT_BANKGOLD_ADDED = 21
GUILD_EVENT_BANKGOLD_GUILD_STORE_TAX = 29
GUILD_EVENT_BANKGOLD_KIOSK_BID = 24
GUILD_EVENT_BANKGOLD_KIOSK_BID_REFUND = 23
GUILD_EVENT_BANKGOLD_PURCHASE_HERALDRY = 26
GUILD_EVENT_BANKGOLD_REMOVED = 22
GUILD_EVENT_BANKITEM_ADDED = 13
GUILD_EVENT_BANKITEM_REMOVED = 14
GUILD_EVENT_BATTLE_STANDARD_PICKUP = 27
GUILD_EVENT_BATTLE_STANDARD_PUTDOWN = 28
GUILD_EVENT_EDIT_BLACKLIST_NOTE = 49
GUILD_EVENT_GUILD_APPLICATION_ACCEPTED = 45
GUILD_EVENT_GUILD_APPLICATION_DECLINED = 44
GUILD_EVENT_GUILD_BANK_LOCKED = 36
GUILD_EVENT_GUILD_BANK_UNLOCKED = 35
GUILD_EVENT_GUILD_CREATE = 5
GUILD_EVENT_GUILD_DELETE = 6
GUILD_EVENT_GUILD_DEMOTE = 4
GUILD_EVENT_GUILD_INVITE = 1
GUILD_EVENT_GUILD_INVITEDECLINED = 10
GUILD_EVENT_GUILD_INVITEPURGED = 11
GUILD_EVENT_GUILD_INVITEREVOKED = 9
GUILD_EVENT_GUILD_JOIN = 7
GUILD_EVENT_GUILD_KICKED = 12
GUILD_EVENT_GUILD_KIOSK_LOCKED = 43
GUILD_EVENT_GUILD_KIOSK_PURCHASED = 25
GUILD_EVENT_GUILD_KIOSK_PURCHASE_REFUND = 30
GUILD_EVENT_GUILD_KIOSK_UNLOCKED = 42
GUILD_EVENT_GUILD_LEAVE = 8
GUILD_EVENT_GUILD_PROMOTE = 3
GUILD_EVENT_GUILD_RECRUITMENT_GUILD_LISTED = 50
GUILD_EVENT_GUILD_RECRUITMENT_GUILD_UNLISTED = 51
GUILD_EVENT_GUILD_REMOVE = 2
GUILD_EVENT_GUILD_STANDARD_LOCKED = 38
GUILD_EVENT_GUILD_STANDARD_UNLOCKED = 37
GUILD_EVENT_GUILD_STORE_LOCKED = 34
GUILD_EVENT_GUILD_STORE_UNLOCKED = 33
GUILD_EVENT_GUILD_TABARD_LOCKED = 40
GUILD_EVENT_GUILD_TABARD_UNLOCKED = 39
GUILD_EVENT_GUILD_UNINVITE = 48
GUILD_EVENT_HERALDRY_EDITED = 20
GUILD_EVENT_ITEM_LISTED = 41
GUILD_EVENT_ITEM_SOLD = 15
GUILD_EVENT_ITERATION_BEGIN = 1
GUILD_EVENT_ITERATION_END = 51
GUILD_EVENT_KEEP_CLAIMED = 16
GUILD_EVENT_KEEP_LOST = 17
GUILD_EVENT_KEEP_RELEASED = 19
GUILD_EVENT_MAX_VALUE = 51
GUILD_EVENT_MIN_VALUE = 1
GUILD_EVENT_MOTD_EDITED = 31
GUILD_EVENT_NAME_CHANGED = 18
GUILD_EVENT_REMOVED_FROM_BLACKLIST = 47

internal.LEGACY_EVENT_ID_OFFSET = 3000000000
local function ConvertEventIdToLegacyId64(eventId)
    local idString = tostring(eventId)
    assert(#idString < 10, "eventId is too large to convert")
    while #idString < 9 do
        idString = "0" .. idString
    end
    return StringToId64("3" .. idString)
end

local function ConvertLegacyId64ToEventId(id64)
    local idString = Id64ToString(id64)
    if idString == "0" then return 0 end

    local idNumber, lostPrecision
    if #idString == 10 and idString:sub(1, 1) == "3" then
        local id = StringToId64(idString:sub(2))
        idNumber, lostPrecision = Id64ToNumber(id)
        if lostPrecision then
            logger:Warn("Lost precision converting legacy eventId", idString)
        end
    end
    if not idNumber then
        logger:Warn("Could not convert legacy eventId", idString)
    end
    return idNumber
end
internal.ConvertLegacyId64ToEventId = ConvertLegacyId64ToEventId

local function ConvertEvent(event)
    local oldEventId = ConvertEventIdToLegacyId64(event:GetEventId())
    local eventTime = event:GetEventTimestampS()
    local category = event:GetEventCategory()
    local type = event:GetEventType()
    local info = event:GetEventInfo()

    if category == GUILD_HISTORY_EVENT_CATEGORY_ACTIVITY then
        if type == GUILD_HISTORY_ACTIVITY_EVENT_ABOUT_US_EDITED then
            return GUILD_EVENT_ABOUT_US_EDITED, oldEventId, eventTime, DecorateDisplayName(info.displayName)
        elseif type == GUILD_HISTORY_ACTIVITY_EVENT_MOTD_EDITED then
            return GUILD_EVENT_MOTD_EDITED, oldEventId, eventTime, DecorateDisplayName(info.displayName)
        elseif type == GUILD_HISTORY_ACTIVITY_EVENT_RECRUITMENT_LISTED then
            return GUILD_EVENT_GUILD_RECRUITMENT_GUILD_LISTED, oldEventId, eventTime,
                DecorateDisplayName(info.displayName)
        elseif type == GUILD_HISTORY_ACTIVITY_EVENT_RECRUITMENT_UNLISTED then
            return GUILD_EVENT_GUILD_RECRUITMENT_GUILD_UNLISTED, oldEventId, eventTime,
                DecorateDisplayName(info.displayName)
        else
            logger:Warn("Unsupported activity event type", type)
        end
    elseif category == GUILD_HISTORY_EVENT_CATEGORY_AVA_ACTIVITY then
        if type == GUILD_HISTORY_AVA_ACTIVITY_EVENT_KEEP_CLAIMED then
            return GUILD_EVENT_KEEP_CLAIMED, oldEventId, eventTime, DecorateDisplayName(info.displayName),
                GetKeepName(info.keepId), GetCampaignName(info.campaignId)
        elseif type == GUILD_HISTORY_AVA_ACTIVITY_EVENT_KEEP_LOST then
            return GUILD_EVENT_KEEP_LOST, oldEventId, eventTime, GetKeepName(info.keepId),
                GetCampaignName(info.campaignId)
        elseif type == GUILD_HISTORY_AVA_ACTIVITY_EVENT_KEEP_RELEASED then
            return GUILD_EVENT_KEEP_RELEASED, oldEventId, eventTime, DecorateDisplayName(info.displayName),
                GetKeepName(info.keepId), GetCampaignName(info.campaignId)
        else
            logger:Warn("Unsupported AvA activity event type", type)
        end
    elseif category == GUILD_HISTORY_EVENT_CATEGORY_BANKED_CURRENCY then
        if info.currencyType ~= CURT_MONEY then
            logger:Warn("Unsupported currency type", info.currencyType)
            return
        end
        if type == GUILD_HISTORY_BANKED_CURRENCY_EVENT_DEPOSITED then
            return GUILD_EVENT_BANKGOLD_ADDED, oldEventId, eventTime, DecorateDisplayName(info.displayName), info.amount
        elseif type == GUILD_HISTORY_BANKED_CURRENCY_EVENT_HERALDRY_EDITED then
            return GUILD_EVENT_HERALDRY_EDITED, oldEventId, eventTime, DecorateDisplayName(info.displayName), info
                .amount
        elseif type == GUILD_HISTORY_BANKED_CURRENCY_EVENT_KIOSK_BID then
            return GUILD_EVENT_BANKGOLD_KIOSK_BID, oldEventId, eventTime, DecorateDisplayName(info.displayName),
                info.amount, info.kioskName
        elseif type == GUILD_HISTORY_BANKED_CURRENCY_EVENT_KIOSK_BID_REFUND then
            return GUILD_EVENT_BANKGOLD_KIOSK_BID_REFUND, oldEventId, eventTime, DecorateDisplayName(info.kioskName),
                info.amount
        elseif type == GUILD_HISTORY_BANKED_CURRENCY_EVENT_KIOSK_PURCHASED then
            return GUILD_EVENT_GUILD_KIOSK_PURCHASED, oldEventId, eventTime, DecorateDisplayName(info.displayName),
                info.amount, info.kioskName
        elseif type == GUILD_HISTORY_BANKED_CURRENCY_EVENT_WITHDRAWN then
            return GUILD_EVENT_BANKGOLD_REMOVED, oldEventId, eventTime, DecorateDisplayName(info.displayName),
                info.amount
        else
            logger:Warn("Unsupported bank currency event type", type)
        end
    elseif category == GUILD_HISTORY_EVENT_CATEGORY_BANKED_ITEM then
        if type == GUILD_HISTORY_BANKED_ITEM_EVENT_ADDED then
            return GUILD_EVENT_BANKITEM_ADDED, oldEventId, eventTime, DecorateDisplayName(info.displayName),
                info.quantity, info.itemLink
        elseif type == GUILD_HISTORY_BANKED_ITEM_EVENT_REMOVED then
            return GUILD_EVENT_BANKITEM_REMOVED, oldEventId, eventTime, DecorateDisplayName(info.displayName),
                info.quantity, info.itemLink
        else
            logger:Warn("Unsupported bank item event type", type)
        end
    elseif category == GUILD_HISTORY_EVENT_CATEGORY_MILESTONE then
        if type == GUILD_HISTORY_MILESTONE_EVENT_BANK_LOCKED then
            return GUILD_EVENT_GUILD_BANK_LOCKED, oldEventId, eventTime
        elseif type == GUILD_HISTORY_MILESTONE_EVENT_BANK_UNLOCKED then
            return GUILD_EVENT_GUILD_BANK_UNLOCKED, oldEventId, eventTime
        elseif type == GUILD_HISTORY_MILESTONE_EVENT_KIOSK_LOCKED then
            return GUILD_EVENT_GUILD_KIOSK_LOCKED, oldEventId, eventTime
        elseif type == GUILD_HISTORY_MILESTONE_EVENT_KIOSK_UNLOCKED then
            return GUILD_EVENT_GUILD_KIOSK_UNLOCKED, oldEventId, eventTime
        elseif type == GUILD_HISTORY_MILESTONE_EVENT_STORE_LOCKED then
            return GUILD_EVENT_GUILD_STORE_LOCKED, oldEventId, eventTime
        elseif type == GUILD_HISTORY_MILESTONE_EVENT_STORE_UNLOCKED then
            return GUILD_EVENT_GUILD_STORE_UNLOCKED, oldEventId, eventTime
        elseif type == GUILD_HISTORY_MILESTONE_EVENT_TABARD_LOCKED then
            return GUILD_EVENT_GUILD_TABARD_LOCKED, oldEventId, eventTime
        elseif type == GUILD_HISTORY_MILESTONE_EVENT_TABARD_UNLOCKED then
            return GUILD_EVENT_GUILD_TABARD_UNLOCKED, oldEventId, eventTime
        else
            logger:Warn("Unsupported milestone event type", type)
        end
    elseif category == GUILD_HISTORY_EVENT_CATEGORY_ROSTER then
        if type == GUILD_HISTORY_ROSTER_EVENT_ADDED_TO_BLACKLIST then
            return GUILD_EVENT_ADDED_TO_BLACKLIST, oldEventId, eventTime, DecorateDisplayName(info.actingDisplayName),
                DecorateDisplayName(info.targetDisplayName)
        elseif type == GUILD_HISTORY_ROSTER_EVENT_APPLICATION_ACCEPTED then
            return GUILD_EVENT_GUILD_APPLICATION_ACCEPTED, oldEventId, eventTime,
                DecorateDisplayName(info.actingDisplayName), DecorateDisplayName(info.targetDisplayName)
        elseif type == GUILD_HISTORY_ROSTER_EVENT_APPLICATION_DECLINED then
            return GUILD_EVENT_GUILD_APPLICATION_DECLINED, oldEventId, eventTime,
                DecorateDisplayName(info.actingDisplayName), DecorateDisplayName(info.targetDisplayName)
        elseif type == GUILD_HISTORY_ROSTER_EVENT_DEMOTE then
            return GUILD_EVENT_GUILD_DEMOTE, oldEventId, eventTime, DecorateDisplayName(info.actingDisplayName),
                DecorateDisplayName(info.targetDisplayName), info.rankName
        elseif type == GUILD_HISTORY_ROSTER_EVENT_EDIT_BLACKLIST_NOTE then
            return GUILD_EVENT_EDIT_BLACKLIST_NOTE, oldEventId, eventTime, DecorateDisplayName(info.actingDisplayName),
                DecorateDisplayName(info.targetDisplayName)
        elseif type == GUILD_HISTORY_ROSTER_EVENT_INVITE then
            return GUILD_EVENT_GUILD_INVITE, oldEventId, eventTime, DecorateDisplayName(info.actingDisplayName),
                DecorateDisplayName(info.targetDisplayName)
        elseif type == GUILD_HISTORY_ROSTER_EVENT_JOIN then
            return GUILD_EVENT_GUILD_JOIN, oldEventId, eventTime, DecorateDisplayName(info.actingDisplayName),
                DecorateDisplayName(info.targetDisplayName)
        elseif type == GUILD_HISTORY_ROSTER_EVENT_KICKED then
            return GUILD_EVENT_GUILD_KICKED, oldEventId, eventTime, DecorateDisplayName(info.actingDisplayName),
                DecorateDisplayName(info.targetDisplayName)
        elseif type == GUILD_HISTORY_ROSTER_EVENT_LEAVE then
            return GUILD_EVENT_GUILD_LEAVE, oldEventId, eventTime, DecorateDisplayName(info.actingDisplayName)
        elseif type == GUILD_HISTORY_ROSTER_EVENT_PROMOTE then
            return GUILD_EVENT_GUILD_PROMOTE, oldEventId, eventTime, DecorateDisplayName(info.actingDisplayName),
                DecorateDisplayName(info.targetDisplayName), info.rankName
        elseif type == GUILD_HISTORY_ROSTER_EVENT_REMOVED_FROM_BLACKLIST then
            return GUILD_EVENT_REMOVED_FROM_BLACKLIST, oldEventId, eventTime, DecorateDisplayName(info.actingDisplayName),
                DecorateDisplayName(info.targetDisplayName)
        else
            logger:Warn("Unsupported roster event type", type)
        end
    elseif category == GUILD_HISTORY_EVENT_CATEGORY_TRADER then
        if type == GUILD_HISTORY_TRADER_EVENT_ITEM_SOLD then
            return GUILD_EVENT_ITEM_SOLD, oldEventId, eventTime, DecorateDisplayName(info.sellerDisplayName),
                DecorateDisplayName(info.buyerDisplayName), info.quantity, info.itemLink, info.price, info.tax
        else
            logger:Warn("Unsupported trader event type", type)
        end
    else
        logger:Warn("Unsupported category", category)
    end
end

local function GetCategoriesForLegacyCategory(category)
    if category == GUILD_HISTORY_BANK then
        return { GUILD_HISTORY_EVENT_CATEGORY_BANKED_ITEM, GUILD_HISTORY_EVENT_CATEGORY_BANKED_CURRENCY }
    elseif category == GUILD_HISTORY_COMBAT then
        return { GUILD_HISTORY_EVENT_CATEGORY_AVA_ACTIVITY }
    elseif category == GUILD_HISTORY_GENERAL then
        return { GUILD_HISTORY_EVENT_CATEGORY_ACTIVITY, GUILD_HISTORY_EVENT_CATEGORY_ROSTER,
            GUILD_HISTORY_EVENT_CATEGORY_MILESTONE }
    elseif category == GUILD_HISTORY_STORE then
        return { GUILD_HISTORY_EVENT_CATEGORY_TRADER }
    end
    return {}
end

local function GetCachesForLegacyCategory(guildId, category)
    local categories = GetCategoriesForLegacyCategory(category)
    for i = 1, #categories do
        categories[i] = internal.historyCache:GetCategoryCache(guildId, categories[i])
    end
    return categories
end

internal.ConvertEventToLegacyFormat = ConvertEvent
internal.GetCategoriesForLegacyCategory = GetCategoriesForLegacyCategory
internal.GetCachesForLegacyCategory = GetCachesForLegacyCategory

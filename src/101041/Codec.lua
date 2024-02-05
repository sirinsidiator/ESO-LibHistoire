-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local assert = assert
local select = select
local type = type
local tonumber = tonumber
local tostring = tostring

local mfloor = math.floor
local mpow = math.pow

local tinsert = table.insert
local tconcat = table.concat

local sformat = string.format
local sfind = string.find
local slen = string.len
local sbyte = string.byte
local schar = string.char
local ssub = string.sub
local sgsub = string.gsub
local sgmatch = string.gmatch
local srep = string.rep

local Id64ToString = Id64ToString
local StringToId64 = StringToId64
local zo_strsplit = zo_strsplit
local logger = LibHistoire.internal.logger

local dict = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
local dictLen = #dict
local fDict = {}
local rDict = {}
local fastLookup = {}
sgsub(dict, ".", function(c)
    rDict[sbyte(c)] = #fDict
    fastLookup[c] = #fDict
    tinsert(fDict, c)
end)

local DEFAULT_SEPARATOR = ":"
local MINUS_SIGN = sbyte("-")


local EncodeBase64, DecodeBase64
do
    -- based on http://lua-users.org/wiki/BaseSixtyFour
    local BASE64_SUFFIX = { "", "==", "=" }
    local BASE64_CHARACTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local BASE64_INVALID_CHARACTER_PATTERN = sformat("[^%s=]", BASE64_CHARACTERS)

    local encodeTemp = {}
    local function CharacterToBinary(input)
        local output = ""
        local byte = sbyte(input)
        for i = 8, 1, -1 do
            encodeTemp[9 - i] = byte % 2 ^ i - byte % 2 ^ (i - 1) > 0 and "1" or "0"
        end
        return tconcat(encodeTemp, "")
    end

    local function BinaryToBase64(input)
        if(#input < 6) then return "" end
        local c = 0
        for i = 1, 6 do
            c = c + (ssub(input, i, i) == "1" and 2 ^ (6 - i) or 0)
        end
        return ssub(BASE64_CHARACTERS, c + 1, c + 1)
    end

    function EncodeBase64(value)
        value = tostring(value)
        return sgsub(sgsub(value, ".", CharacterToBinary) .. "0000", "%d%d%d?%d?%d?%d?", BinaryToBase64) .. BASE64_SUFFIX[#value % 3 + 1]
    end

    local decodeTemp = {}
    local function Base64ToBinary(input)
        if(input == "=") then return "" end
        local byte = sfind(BASE64_CHARACTERS, input) - 1
        for i = 6, 1, -1 do
            decodeTemp[7 - i] = byte % 2 ^ i - byte % 2 ^ (i - 1) > 0 and "1" or "0"
        end
        return tconcat(decodeTemp, "")
    end

    local function BinaryToCharacter(input)
        if (#input ~= 8) then return "" end
        local c = 0
        for i = 1, 8 do
            c = c + (ssub(input, i, i) == "1" and 2 ^ (8 - i) or 0)
        end
        return schar(c)
    end

    function DecodeBase64(value)
        value = sgsub(value, BASE64_INVALID_CHARACTER_PATTERN, "")
        return sgsub(sgsub(value, ".", Base64ToBinary), "%d%d%d?%d?%d?%d?%d?%d?", BinaryToCharacter)
    end
end

local function IntegerToString(value, keepZero)
    if(value == 0) then return keepZero and "0" or "" end
    local result, sign = "", ""
    if(value < 0) then
        sign = "-"
        value = -value
    end
    value = mfloor(value)
    repeat
        result = fDict[(value % dictLen) + 1] .. result
        value = mfloor(value / dictLen)
    until value == 0
    return sign .. result
end

local ITEM_LINK_PREFIX = "|H0:item"
local ITEM_LINK_SUFFIX = "|h|h"
local ITEM_LINK_PREFIX_LENGTH = slen(ITEM_LINK_PREFIX)
local ITEM_LINK_SUFFIX_LENGTH = slen(ITEM_LINK_SUFFIX)

local function ItemLinkToString(value)
    value = ssub(value, ITEM_LINK_PREFIX_LENGTH + 2, slen(value) - ITEM_LINK_SUFFIX_LENGTH)
    local fields = {zo_strsplit(":", value)}
    for i = 1, #fields do
        fields[i] = IntegerToString(tonumber(fields[i]), true)
    end
    local temp = tconcat(fields, "#")
    -- this should only find repetitions of #0 and nothing else
    return sgsub(temp, "([#0]+)", function(value)
        local count = slen(value) / 2
        if count >= 3 then
            return sformat("<%d>", count)
        end
    end)
end

local encoders = {
    ["string"] = function(value)
        return tostring(value)
    end,
    ["boolean"] = function(value)
        if(not value) then return "" end
        return "1"
    end,
    ["number"] = function(value)
        if(value == 0) then return "" end
        return tostring(value)
    end,
    ["integer"] = IntegerToString,
    ["base64"] = EncodeBase64,
    ["id64"] = Id64ToString,
    ["itemLink"] = ItemLinkToString,
}

local function StringToInteger(value)
    if(not value or value == "") then return 0 end
    local result, start, sign, j = 0, 1, 1, 0
    if(sbyte(value, 1, 1) == MINUS_SIGN) then
        start = 2
        sign = -1
    end
    for i = #value, start, -1 do
        local c = sbyte(value, i, i)
        if(not rDict[c]) then return 0 end
        result = result + rDict[c] * mpow(dictLen, j)
        j = j + 1
    end
    return result * sign
end

local StringToItemLink
do
    local LINK_COMPACT_DATA_SEPARATOR = "#"
    local LINK_COMPACT_DATA_OLD_ZERO_FIELD = "##"
    local LINK_COMPACT_DATA_NEW_ZERO_FIELD = "#0#"
    -- this isn't 100% clean, but we want the last repetition to end on the separator
    -- and zo_strsplit will collapse multiple separators anyway
    local LINK_COMPACT_DATA_REPLACEMENT = LINK_COMPACT_DATA_SEPARATOR .. "0" .. LINK_COMPACT_DATA_SEPARATOR
    local LINK_ORIGINAL_DATA_SEPARATOR = ":"
    local LINK_PLACEHOLDER_PATTERN = "<(%d+)>"

    local cache = {}
    local function ExpandPlaceholder(count)
        cache[count] = cache[count] or srep(LINK_COMPACT_DATA_REPLACEMENT, tonumber(count))
        return cache[count]
    end

    local function ExpandPlaceholderFix(count)
        return srep(LINK_COMPACT_DATA_REPLACEMENT, tonumber(count) - 1)
    end

    local function ExpandPlaceholderFix2(count)
        return srep(LINK_COMPACT_DATA_REPLACEMENT, tonumber(count) / 2)
    end

    local function FixOldEncoding(value, fields)
        local v2 = value
        for i = 1, 2 do -- need to replace it twice to get all fields
            v2 = sgsub(v2, LINK_COMPACT_DATA_OLD_ZERO_FIELD, LINK_COMPACT_DATA_NEW_ZERO_FIELD)
        end

        if #fields > 22 then
            local expanded = sgsub(v2, LINK_PLACEHOLDER_PATTERN, ExpandPlaceholderFix)
            fields = { ITEM_LINK_PREFIX, zo_strsplit(LINK_COMPACT_DATA_SEPARATOR, expanded) }
        end

        if #fields > 22 then
            local expanded = sgsub(v2, LINK_PLACEHOLDER_PATTERN, ExpandPlaceholderFix2)
            fields = { ITEM_LINK_PREFIX, zo_strsplit(LINK_COMPACT_DATA_SEPARATOR, expanded) }
        end

        while #fields < 22 do
            fields[#fields + 1] = "0"
        end

        assert(#fields == 22, ("Incorrect field count for item link decoded from '%s'"):format(value))
        return fields
    end

    function StringToItemLink(value)
        local expanded = sgsub(value, LINK_PLACEHOLDER_PATTERN, ExpandPlaceholder)
        local fields = { ITEM_LINK_PREFIX, zo_strsplit(LINK_COMPACT_DATA_SEPARATOR, expanded) }

        if #fields ~= 22 then
            -- some links have been encoded differently or plain incorrect in the past
            fields = FixOldEncoding(value, fields)
        end

        for i = 2, #fields do
            fields[i] = fastLookup[fields[i]] or StringToInteger(fields[i])
        end
        return tconcat(fields, LINK_ORIGINAL_DATA_SEPARATOR) .. ITEM_LINK_SUFFIX
    end
end

local decoders = {
    ["string"] = function(value)
        if(not value or value == "") then return "" end
        return tostring(value) or ""
    end,
    ["boolean"] = function(value)
        if(not value or value == "") then return false end
        return true
    end,
    ["number"] = function(value)
        if(not value or value == "") then return 0 end
        return tonumber(value) or 0
    end,
    ["integer"] = StringToInteger,
    ["base64"] = DecodeBase64,
    ["id64"] = StringToId64,
    ["itemLink"] = StringToItemLink,
}

local VARTYPES = {
    ["string"] = "string",
    ["boolean"] = "boolean",
    ["number"] = "number",
    ["integer"] = "number",
    ["base64"] = "string",
    ["id64"] = "number",
    ["itemLink"] = "string",
}

local function EncodeValue(inputType, value, dictionary)
    local actualType = type(value)
    local expectedType = VARTYPES[inputType]
    if inputType == "dictionary" then
        assert(dictionary and dictionary.GetIdFromString, "no valid dictionary provided")
        assert(actualType == "string" or actualType == "nil", sformat("expected type 'string' or 'nil', got '%s'", actualType))
        local id = dictionary:GetIdFromString(value)
        return encoders["integer"](id)
    else
        assert(actualType == expectedType, sformat("expected type '%s', got '%s'", expectedType, actualType))
        return encoders[inputType](value)
    end
end

local function DecodeValue(type, value, dictionary)
    if type == "dictionary" then
        assert(dictionary and dictionary.GetStringFromId, "no valid dictionary provided")
        local id = decoders["integer"](value)
        return dictionary:GetStringFromId(id)
    else
        return decoders[type](value)
    end
end

local function EncodeData(data, type, separator, dictionary)
    for i = 1, #type do
        data[i] = EncodeValue(type[i], data[i], dictionary)
    end
    return tconcat(data, separator or DEFAULT_SEPARATOR, 1, #type)
end

local function DecodeData(encodedString, format, separator, dictionary)
    local type, version
    local data = {}
    separator = separator or DEFAULT_SEPARATOR
    for value in sgmatch(encodedString .. separator, "(.-)" .. separator) do
        if(not type) then
            version = fastLookup[value] or StringToInteger(value)
            type = format[version] or format.default
            if(not type) then return end
            data[#data + 1] = version
        else
            data[#data + 1] = DecodeValue(type[#data + 1], value, dictionary)
        end
    end
    return data, version
end

local MAX_SAVE_DATA_LENGTH = 1999 -- buffer length used by ZOS
local function WriteToSavedVariable(t, key, value)
    local output = value
    local byteLength = #value
    if(byteLength > MAX_SAVE_DATA_LENGTH) then
        output = {}
        local startPos = 1
        local endPos = startPos + MAX_SAVE_DATA_LENGTH - 1
        while startPos <= byteLength do
            output[#output + 1] = ssub(value, startPos, endPos)
            startPos = endPos + 1
            endPos = startPos + MAX_SAVE_DATA_LENGTH - 1
        end
    end
    t[key] = output
end

local function ReadFromSavedVariable(t, key, defaultValue)
    local value = t[key] or defaultValue
    if(type(value) == "table") then
        return tconcat(value, "")
    end
    return value
end

local internal = LibHistoire.internal
internal.EncodeValue = EncodeValue
internal.DecodeValue = DecodeValue
internal.EncodeData = EncodeData
internal.DecodeData = DecodeData
internal.WriteToSavedVariable = WriteToSavedVariable
internal.ReadFromSavedVariable = ReadFromSavedVariable

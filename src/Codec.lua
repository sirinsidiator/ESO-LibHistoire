-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local dict = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
local dictLen = #dict
local fDict = {}
local rDict = {}
dict:gsub(".", function(c) rDict[c] = #fDict table.insert(fDict, c) end)

local DEFAULT_SEPARATOR = ":"

local EncodeBase64, DecodeBase64
do
    -- based on http://lua-users.org/wiki/BaseSixtyFour
    local BASE64_SUFFIX = { "", "==", "=" }
    local BASE64_CHARACTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local BASE64_INVALID_CHARACTER_PATTERN = string.format("[^%s=]", BASE64_CHARACTERS)

    local encodeTemp = {}
    local function CharacterToBinary(input)
        local output = ""
        local byte = input:byte()
        for i = 8, 1, -1 do
            encodeTemp[9 - i] = byte % 2 ^ i - byte % 2 ^ (i - 1) > 0 and "1" or "0"
        end
        return table.concat(encodeTemp, "")
    end

    local function BinaryToBase64(input)
        if(#input < 6) then return "" end
        local c = 0
        for i = 1, 6 do
            c = c + (input:sub(i, i) == "1" and 2 ^ (6 - i) or 0)
        end
        return BASE64_CHARACTERS:sub(c + 1, c + 1)
    end

    function EncodeBase64(value)
        value = tostring(value)
        return (value:gsub(".", CharacterToBinary) .. "0000"):gsub("%d%d%d?%d?%d?%d?", BinaryToBase64) .. BASE64_SUFFIX[#value % 3 + 1]
    end

    local decodeTemp = {}
    local function Base64ToBinary(input)
        if(input == "=") then return "" end
        local byte = BASE64_CHARACTERS:find(input) - 1
        for i = 6, 1, -1 do
            decodeTemp[7 - i] = byte % 2 ^ i - byte % 2 ^ (i - 1) > 0 and "1" or "0"
        end
        return table.concat(decodeTemp, "")
    end

    local function BinaryToCharacter(input)
        if (#input ~= 8) then return "" end
        local c = 0
        for i = 1, 8 do
            c = c + (input:sub(i, i) == "1" and 2 ^ (8 - i) or 0)
        end
        return string.char(c)
    end

    function DecodeBase64(value)
        value = value:gsub(BASE64_INVALID_CHARACTER_PATTERN, "")
        return (value:gsub(".", Base64ToBinary):gsub("%d%d%d?%d?%d?%d?%d?%d?", BinaryToCharacter))
    end
end

local function IntegerToString(value)
    if(value == 0) then return "" end
    local result, sign = "", ""
    if(value < 0) then
        sign = "-"
        value = -value
    end
    value = math.floor(value)
    repeat
        result = fDict[(value % dictLen) + 1] .. result
        value = math.floor(value / dictLen)
    until value == 0
    return sign .. result
end

local ITEM_LINK_PREFIX = "|H0:item"
local ITEM_LINK_SUFFIX = "|h|h"
local ITEM_LINK_PREFIX_LENGTH = ITEM_LINK_PREFIX:len()
local ITEM_LINK_SUFFIX_LENGTH = ITEM_LINK_SUFFIX:len()

local function ItemLinkToString(value)
    value = value:sub(ITEM_LINK_PREFIX_LENGTH + 2, value:len() - ITEM_LINK_SUFFIX_LENGTH)
    local fields = {zo_strsplit(":", value)}
    for i = 1, #fields do
        fields[i] = IntegerToString(tonumber(fields[i]))
    end
    local temp = table.concat(fields, "#")
    return temp:gsub("#+", function(value)
        local count = value:len()
        if count > 3 then
            return string.format("<%d>", count)
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
    local result, sign, j = 0, 1, 0
    if(value:sub(1, 1) == "-") then
        value = value:sub(2)
        sign = -1
    end
    for i = #value, 1, -1 do
        local c = value:sub(i, i)
        if(not rDict[c]) then return 0 end
        result = result + rDict[c] * math.pow(dictLen, j)
        j = j + 1
    end
    return result * sign
end

local function StringToItemLink(value)
    local fields = { ITEM_LINK_PREFIX }
    value = value:gsub("<(%d+)>", function(count)
        return string.rep("#", tonumber(count))
    end)
    for field in (value .. "#"):gmatch("(.-)#") do
        fields[#fields + 1] = StringToInteger(field)
    end
    return table.concat(fields, ":") .. ITEM_LINK_SUFFIX
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
        assert(actualType == "string" or actualType == "nil", string.format("expected type 'string' or 'nil', got '%s'", actualType))
        local id = dictionary:GetIdFromString(value)
        return encoders["integer"](id)
    else
        assert(actualType == expectedType, string.format("expected type '%s', got '%s'", expectedType, actualType))
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
    return table.concat(data, separator or DEFAULT_SEPARATOR, 1, #type)
end

local function DecodeData(encodedString, format, separator, dictionary)
    local type, version
    local data = {}
    separator = separator or DEFAULT_SEPARATOR
    for value in (encodedString .. separator):gmatch("(.-)" .. separator) do
        if(not type) then
            version = DecodeValue("integer", value)
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
            output[#output + 1] = value:sub(startPos, endPos)
            startPos = endPos + 1
            endPos = startPos + MAX_SAVE_DATA_LENGTH - 1
        end
    end
    t[key] = output
end

local function ReadFromSavedVariable(t, key, defaultValue)
    local value = t[key] or defaultValue
    if(type(value) == "table") then
        return table.concat(value, "")
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

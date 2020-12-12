require 'esoui/baseobject'
local uv = require('luv')

local function EmitMessage(text)
    if(text == "") then
        text = "[Empty String]"
    end

    print(text)
end

local function EmitTable(t, indent, tableHistory)
    indent          = indent or "."
    tableHistory    = tableHistory or {}

    for k, v in pairs(t) do
        local vType = type(v)

        EmitMessage(indent.."("..vType.."): "..tostring(k).." = "..tostring(v))

        if(vType == "table") then
            if(tableHistory[v]) then
                EmitMessage(indent.."Avoiding cycle on table...")
            else
                tableHistory[v] = true
                EmitTable(v, indent.."  ", tableHistory)
            end
        end
    end
end

function d(...)
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if(type(value) == "table") then
            EmitTable(value)
        else
            EmitMessage(tostring(value))
        end
    end
end

function df(formatter, ...)
    return d(formatter:format(...))
end

function setTimeout(func, timeout)
    local timer = uv.new_timer()
    timer:start(timeout, 0, function()
        timer:close()
        func()
    end)
end
zo_callLater = setTimeout

local isRunning = false
function resolveTimeouts()
    if(isRunning) then return end
    isRunning = true
    uv.run()
    isRunning = false
end

LibHistoire = {
    internal = {
        logger = {
            Warn = function(self, ...) df(...) end
        }
    }
}

function Id64ToString()
end

function StringToId64()
end

function zo_strsplit(sep, input)
    local out = {}
    for part in string.gmatch(input .. sep, "(.-)" .. sep) do
        if part ~= "" then
            out[#out + 1] = part
        end
    end
    return unpack(out)
end

-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal

local DisplayNameCache = ZO_Object:Subclass()
internal.class.DisplayNameCache = DisplayNameCache

function DisplayNameCache:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function DisplayNameCache:Initialize(saveData)
    self.saveData = saveData
    saveData[1] = ""
    self.lookup = {}
    for id = 1, #saveData do
        self.lookup[saveData[id]] = id
    end
end

function DisplayNameCache:GetIdFromString(value)
    if not value then return 0 end

    if not self.lookup[value] then
        local id = #self.saveData + 1
        self.saveData[id] = value
        self.lookup[value] = id
    end
    return self.lookup[value]
end

function DisplayNameCache:GetStringFromId(id)
    if id == 0 then return nil end
    return self.saveData[id]
end

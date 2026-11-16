local addonName, ns = ...

-- Volatile lookup index: never saved to SavedVariables.
local dirty = true
local keys, guids = {}, {}

function ns.InvalidateIdentityIndex()
    dirty = true
    if ns.InvalidateBattleNetIndex then ns.InvalidateBattleNetIndex() end
end

local function Rebuild()
    if not dirty then return end
    keys, guids = {}, {}
    for key, record in pairs(KnownPlayersDB.players or {}) do
        if type(record) == "table" and type(record.categories) == "table" then
            keys[key] = record
            if type(record.guid) == "string" and record.guid:match("^Player%-") then
                guids[record.guid] = record
            end
        end
    end
    dirty = false
end

-- Never match unrelated players on character name alone when both GUIDs disagree.
function ns.FindDirectRecord(name, guid)
    Rebuild()
    if type(guid) == "string" and guid:match("^Player%-") then
        local matched = guids[guid]
        if matched then return matched end
    end
    local record = keys[name]
    if record and (not guid or not record.guid or record.guid == guid) then
        return record
    end
    return nil
end

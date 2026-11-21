local addonName, ns = ...

-- Volatile lookup index: never saved to SavedVariables.
local dirty = true
local keys, guids, guidKeys, aliases = {}, {}, {}, {}

function ns.InvalidateIdentityIndex()
    dirty = true
    if ns.InvalidateBattleNetIndex then ns.InvalidateBattleNetIndex() end
end

local function Rebuild()
    if not dirty then return end
    keys, guids, guidKeys, aliases = {}, {}, {}, {}
    for key, record in pairs(KnownPlayersDB.players or {}) do
        if type(record) == "table" and type(record.categories) == "table" then
            keys[key] = record
            local normalized = ns.NormalizePlayerKey and ns.NormalizePlayerKey(key, record.realm)
            if normalized then
                local alias = normalized:lower()
                aliases[alias] = aliases[alias] or {}
                aliases[alias][#aliases[alias] + 1] = key
            end
            local guid = ns.SafePlayerGUID(record.guid)
            if guid then
                guids[guid] = record
                guidKeys[guid] = key
            end
        end
    end
    dirty = false
end

-- Exact GUID wins. Otherwise match a normalized name only within the same
-- realm, and refuse ambiguous matches or conflicting GUIDs.
function ns.FindDirectKeyByName(name, guid)
    Rebuild()
    name = ns.SafeString(name)
    if not name then return nil end
    guid = ns.SafePlayerGUID(guid)
    local normalized = ns.NormalizePlayerKey and ns.NormalizePlayerKey(name)
    local candidates = normalized and aliases[normalized:lower()] or nil
    if not candidates then
        local exact = keys[name]
        if exact and (not guid or not ns.SafePlayerGUID(exact.guid)
            or ns.SafePlayerGUID(exact.guid) == guid) then return name end
        return nil
    end
    local match
    for _, key in ipairs(candidates) do
        local record = keys[key]
        local storedGUID = record and ns.SafePlayerGUID(record.guid)
        if record and (not guid or not storedGUID or storedGUID == guid) then
            if match then return nil end -- different saved characters: ambiguous
            match = key
        end
    end
    return match
end

function ns.FindDirectRecord(name, guid)
    Rebuild()
    guid = ns.SafePlayerGUID(guid)
    if guid and guids[guid] then return guids[guid] end
    local key = ns.FindDirectKeyByName(name, guid)
    return key and keys[key] or nil
end

function ns.FindDirectKeyByGUID(guid)
    guid = ns.SafePlayerGUID(guid)
    if not guid then return nil end
    Rebuild()
    return guidKeys[guid]
end

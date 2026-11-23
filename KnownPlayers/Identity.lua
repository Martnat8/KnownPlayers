local _, ns = ...

-- Volatile lookup index. Entries keep their old aliases for incremental updates.
local dirty = true
local entries, aliases, guids = {}, {}, {}

function ns.InvalidateIdentityIndex()
    dirty = true
    if ns.InvalidateBattleNetIndex then ns.InvalidateBattleNetIndex() end
end

local function AddIndexKey(index, value, key)
    if not value then return end
    local keys = index[value] or {}
    keys[key] = true
    index[value] = keys
end

local function RemoveIndexKey(index, value, key)
    if not value then return end
    local keys = index[value]
    keys[key] = nil
    if not next(keys) then index[value] = nil end
end

local function Alias(name, realm)
    local normalized = ns.NormalizePlayerKey(name, realm)
    return normalized and normalized:lower()
end

local function AddRecord(key, record)
    if type(record) ~= "table" or type(record.categories) ~= "table" then return end
    local preferredName, realm = ns.SafeString(record.displayName), ns.SafeString(record.realm)
    local alias = Alias(key, realm)
    local preferred = preferredName and realm and Alias(preferredName .. "-" .. realm, realm)
    local guid = ns.SafePlayerGUID(record.guid)
    entries[key] = {record = record, guid = guid, alias = alias, preferred = preferred ~= alias and preferred or nil}
    AddIndexKey(aliases, alias, key)
    AddIndexKey(aliases, entries[key].preferred, key)
    AddIndexKey(guids, guid, key)
end

local function Rebuild()
    if not dirty then return end
    entries, aliases, guids = {}, {}, {}
    for key, record in pairs(KnownPlayersDB.players) do AddRecord(key, record) end
    dirty = false
end

function ns.UpdateIdentityIndex(key, record)
    if not dirty then
        local old = entries[key]
        if old then
            RemoveIndexKey(aliases, old.alias, key)
            RemoveIndexKey(aliases, old.preferred, key)
            RemoveIndexKey(guids, old.guid, key)
        end
        AddRecord(key, record)
    end
    if ns.InvalidateBattleNetIndex then ns.InvalidateBattleNetIndex() end
end

-- Match only an unambiguous name on the same realm, without a conflicting GUID.
function ns.FindDirectKeyByName(name, guid)
    name = ns.SafeString(name)
    if not name then return nil end
    Rebuild()
    guid = ns.SafePlayerGUID(guid)
    local candidates = aliases[Alias(name)]
    if not candidates then
        local exact = entries[name]
        if exact and (not guid or not exact.guid or exact.guid == guid) then return name end
        return nil
    end
    local match
    for key in pairs(candidates) do
        local storedGUID = entries[key].guid
        if not guid or not storedGUID or storedGUID == guid then
            if match then return nil, true end
            match = key
        end
    end
    return match
end

function ns.FindDirectKeyByGUID(guid)
    guid = ns.SafePlayerGUID(guid)
    if not guid then return nil end
    Rebuild()
    local candidates = guids[guid]
    if not candidates then return nil end
    local match
    for key in pairs(candidates) do
        if not match or key < match then match = key end
    end
    return match
end

function ns.FindDirectRecord(name, guid)
    local key = ns.FindDirectKeyByGUID(guid) or ns.FindDirectKeyByName(name, guid)
    return key and entries[key].record or nil
end

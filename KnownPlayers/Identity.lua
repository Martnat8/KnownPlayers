local _, ns = ...

-- Volatile lookup index. Entries keep their old aliases for incremental updates.
local dirty = true
local liveIndex
local IdentityIndex = {}
IdentityIndex.__index = IdentityIndex

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

function ns.PlayerIdentityAliases(key, record)
    local preferredName, realm = ns.SafeString(record.displayName), ns.SafeString(record.realm)
    local alias = Alias(key, realm)
    local preferred = preferredName and realm and Alias(preferredName .. "-" .. realm, realm)
    return alias, preferred ~= alias and preferred or nil
end

local function AddRecord(index, key, record)
    if type(record) ~= "table" or type(record.categories) ~= "table" then return end
    local alias, preferred = ns.PlayerIdentityAliases(key, record)
    local guid = ns.SafePlayerGUID(record.guid)
    local entry = {record = record, guid = guid, alias = alias, preferred = preferred}
    index.entries[key] = entry
    AddIndexKey(index.aliases, alias, key)
    AddIndexKey(index.aliases, entry.preferred, key)
    AddIndexKey(index.guids, guid, key)
end

function ns.CreatePlayerIdentityIndex(players)
    local index = setmetatable({entries = {}, aliases = {}, guids = {}}, IdentityIndex)
    for key, record in pairs(players) do AddRecord(index, key, record) end
    return index
end

local function GetLiveIndex()
    if dirty then
        liveIndex = ns.CreatePlayerIdentityIndex(KnownPlayersDB.players)
        dirty = false
    end
    return liveIndex
end

function IdentityIndex:Update(key, record)
    local old = self.entries[key]
    if old then
        RemoveIndexKey(self.aliases, old.alias, key)
        RemoveIndexKey(self.aliases, old.preferred, key)
        RemoveIndexKey(self.guids, old.guid, key)
        self.entries[key] = nil
    end
    AddRecord(self, key, record)
end

function ns.UpdateIdentityIndex(key, record)
    if not dirty then liveIndex:Update(key, record) end
    if ns.InvalidateBattleNetIndex then ns.InvalidateBattleNetIndex() end
end

-- Match only an unambiguous name on the same realm, without a conflicting GUID.
function IdentityIndex:FindKeyByName(name, guid, realm)
    name = ns.SafeString(name)
    if not name then return nil end
    guid = ns.SafePlayerGUID(guid)
    local candidates = self.aliases[Alias(name, realm)]
    if not candidates then
        local exact = self.entries[name]
        if exact and (not guid or not exact.guid or exact.guid == guid) then return name end
        return nil
    end
    local match
    for key in pairs(candidates) do
        local storedGUID = self.entries[key].guid
        if not guid or not storedGUID or storedGUID == guid then
            if match then return nil, true end
            match = key
        end
    end
    return match
end

function IdentityIndex:FindKeyByGUID(guid)
    guid = ns.SafePlayerGUID(guid)
    if not guid then return nil end
    local candidates = self.guids[guid]
    if not candidates then return nil end
    local match
    for key in pairs(candidates) do
        if not match or key < match then match = key end
    end
    return match
end

function ns.FindDirectKeyByName(name, guid, realm)
    if ns.SafeString(name) then return GetLiveIndex():FindKeyByName(name, guid, realm) end
end

function ns.FindDirectKeyByGUID(guid)
    if ns.SafePlayerGUID(guid) then return GetLiveIndex():FindKeyByGUID(guid) end
end

function ns.HasConflictingPlayerGUID(name, guid, realm)
    local index = GetLiveIndex()
    local candidates = index.aliases[Alias(name, realm)]
    for key in pairs(candidates or {}) do
        local existing = index.entries[key].guid
        if existing and existing ~= guid then return true end
    end
    return false
end

function ns.FindDirectRecord(name, guid)
    local key = ns.FindDirectKeyByGUID(guid) or ns.FindDirectKeyByName(name, guid)
    return key and liveIndex.entries[key].record or nil
end

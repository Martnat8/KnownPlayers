local addonName, ns = ...

local SECONDS_PER_DAY = 86400
local CATEGORIES = { "trade", "party", "raid", "guild", "whisper", "target", "inspect", "pvp" }
local function SecondsForDuration(duration)
    if type(duration) ~= "table" then return 30 * SECONDS_PER_DAY end
    return math.max(60, (tonumber(duration.days) or 0) * SECONDS_PER_DAY
        + (tonumber(duration.hours) or 0) * 3600
        + (tonumber(duration.minutes) or 0) * 60)
end

function ns.GetCategoryRetention(category)
    return KnownPlayersSettings.categoryRetention[category]
end

local DEFAULT_SETTINGS = {
    expirationEnabled = false,
    expirationDays = 30,
    categoryRetention = {},
    trackBattleNetAssociations = true,
    knownOnlyNameplates = false,
    namesOnlyNameplates = false,
    nameDisplayMode = "full",
    showGuildInNamesOnly = false,
    nameplateCategoryColors = {},
    nameplateColorOrder = {},
    trackGroup = { party = true, raid = true },
    trackWhispers = true,
    trackTrades = true,
    trackGuild = true,
    trackTargets = true,
    trackInspects = true,
    trackPvP = false,
    filterNPCNameplates = false,
    npcNameDisplayMode = "full",
    showNPCTitle = false,
    npcNamesOnlyNameplates = false,
}

local function CopyDefaults(source, destination)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(destination[key]) ~= "table" then
                destination[key] = {}
            end
            CopyDefaults(value, destination[key])
        elseif destination[key] == nil then
            destination[key] = value
        end
    end
end

function ns.InitializeDatabase()
    if type(KnownPlayersDB) ~= "table" then
        KnownPlayersDB = {}
    end
    if type(KnownPlayersDB.players) ~= "table" then
        KnownPlayersDB.players = {}
    end
    if type(KnownPlayersDB.npcs) ~= "table" then
        KnownPlayersDB.npcs = {}
    end
    if type(KnownPlayersSettings) ~= "table" then
        KnownPlayersSettings = {}
    end
    CopyDefaults(DEFAULT_SETTINGS, KnownPlayersSettings)
    if type(KnownPlayersDB.bnetCharacters) ~= "table" then KnownPlayersDB.bnetCharacters = {} end
    -- Upgrade previous global retention preference once. All categories
    -- initially inherit the same behavior, then become independent.
    for _, category in ipairs(CATEGORIES) do
        if category ~= "guild" and type(KnownPlayersSettings.categoryRetention[category]) ~= "table" then
            KnownPlayersSettings.categoryRetention[category] = {
                enabled = false,
                days = math.max(1, math.min(180, tonumber(KnownPlayersSettings.expirationDays) or 30)),
                hours = 0,
                minutes = 0,
            }
        end
    end
    -- NPC retention is separate from player interactions and off by default.
    if type(KnownPlayersSettings.categoryRetention.npc) ~= "table" then
        KnownPlayersSettings.categoryRetention.npc = {
            enabled = false, days = 30, hours = 0, minutes = 0,
        }
    end
    -- Guild membership is roster-based, not an inactivity-based relationship.
    KnownPlayersSettings.categoryRetention.guild = nil
end

-- Preserve existing SavedVariables keys. Identify players by GUID when available,
-- then by exact name + realm. Never merge solely on a similar-looking name.
local function ValidGUID(guid)
    return type(guid) == "string" and guid:match("^Player%-") ~= nil
end

local function SplitKnownRealm(key)
    if type(key) ~= "string" then return nil, nil end
    -- The Forever realm token is an internal identifier. The same character
    -- can also have hyphens in their *name*, so don't split on the first '-'.
    local name, realm = key:match("^(.-)%-(CAMWOW[%w]+)$")
    if name and name ~= "" then return name, realm end
    local localRealm = type(GetNormalizedRealmName) == "function" and GetNormalizedRealmName() or nil
    if type(localRealm) == "string" and localRealm ~= "" then
        local suffix = "-" .. localRealm
        if key:sub(-#suffix) == suffix then
            return key:sub(1, -#suffix - 1), localRealm
        end
    end
    return key, nil
end

function ns.GetDisplayName(key, record)
    if type(record) == "table" and type(record.displayName) == "string" and record.displayName ~= "" then
        return record.displayName
    end
    local name = SplitKnownRealm(key)
    return name or tostring(key)
end

function ns.MigratePlayerRecords()
    local changed = 0
    for key, record in pairs(KnownPlayersDB.players) do
        if type(record) == "table" then
            local name, realm = SplitKnownRealm(key)
            if not record.displayName and name then
                record.displayName = name
                changed = changed + 1
            end
            if not record.realm and realm then record.realm = realm end
            if type(record.categories) ~= "table" then record.categories = {} end
            if type(record.categoryLastSeen) ~= "table" then record.categoryLastSeen = {} end
            if type(record.categoryFirstSeen) ~= "table" then record.categoryFirstSeen = {} end
            -- Previous versions stored a single lastSeen value.
            for category, enabled in pairs(record.categories) do
                if enabled and type(record.categoryLastSeen[category]) ~= "number" then
                    record.categoryLastSeen[category] = record.lastSeen
                end
                if enabled and type(record.categoryFirstSeen[category]) ~= "number" then
                    -- Historical first encounter dates were not stored. Use the
                    -- oldest timestamp we still have for this category.
                    record.categoryFirstSeen[category] = record.categoryLastSeen[category] or record.lastSeen
                end
            end
        end
    end
    if ns.InvalidateIdentityIndex then ns.InvalidateIdentityIndex() end
    return changed
end

local function MergeInto(destination, source)
    destination.categories = type(destination.categories) == "table" and destination.categories or {}
    if type(source.categories) == "table" then
        for category, enabled in pairs(source.categories) do
            if enabled then destination.categories[category] = true end
        end
    end
    if type(source.lastSeen) == "number"
        and (type(destination.lastSeen) ~= "number" or source.lastSeen > destination.lastSeen) then
        destination.lastSeen = source.lastSeen
    end
    destination.categoryFirstSeen = destination.categoryFirstSeen or {}
    if type(source.categoryFirstSeen) == "table" then
        for category, stamp in pairs(source.categoryFirstSeen) do
            if type(stamp) == "number" and
                (type(destination.categoryFirstSeen[category]) ~= "number"
                    or stamp < destination.categoryFirstSeen[category]) then
                destination.categoryFirstSeen[category] = stamp
            end
        end
    end
    destination.categoryLastSeen = destination.categoryLastSeen or {}
    if type(source.categoryLastSeen) == "table" then
        for category, stamp in pairs(source.categoryLastSeen) do
            if type(stamp) == "number" and
                (type(destination.categoryLastSeen[category]) ~= "number"
                    or stamp > destination.categoryLastSeen[category]) then
                destination.categoryLastSeen[category] = stamp
            end
        end
    end
    destination.guid = destination.guid or source.guid
    destination.realm = destination.realm or source.realm
    destination.displayName = destination.displayName or source.displayName
end

-- Optional GUID lets another interaction recognize a character whose name
-- spelling / realm format differs. Identical names without a GUID are not
-- proof that two records belong to the same player.
function ns.RememberPlayer(name, category, seenAt, guid)
    if type(name) ~= "string" or name == "" then return nil end
    local players = KnownPlayersDB.players
    local displayName, realm = SplitKnownRealm(name)
    if not ValidGUID(guid) then guid = nil end

    local matchedKey = nil
    if guid then
        for key, record in pairs(players) do
            if type(record) == "table" and record.guid == guid then
                matchedKey = key
                break
            end
        end
    end

    local record = matchedKey and players[matchedKey] or nil
    local exact = players[name]
    if record and type(exact) == "table" and exact ~= record then
        -- Merge only if no GUID conflicts, and the exact entry has either
        -- the same GUID or no existing GUID of its own.
        if not exact.guid or exact.guid == guid then
            MergeInto(record, exact)
            players[name] = nil
        end
    elseif not record and type(exact) == "table" then
        if not (guid and exact.guid and exact.guid ~= guid) then
            record = exact
            matchedKey = name
        end
    end

    if not record then
        -- Different GUID for an already-occupied key: never overwrite it.
        local key = name
        if players[key] ~= nil and guid then key = "guid:" .. guid end
        record = { categories = {} }
        players[key] = record
        matchedKey = key
    end
    if type(record.categories) ~= "table" then record.categories = {} end
    local timestamp = seenAt or time()
    if type(record.categoryLastSeen) ~= "table" then record.categoryLastSeen = {} end
    if type(record.categoryFirstSeen) ~= "table" then record.categoryFirstSeen = {} end
    if type(category) == "string" and category ~= "" then
        if not record.categories[category] then
            -- A newly joined category starts its own known-since timer.
            record.categoryFirstSeen[category] = timestamp
        elseif type(record.categoryFirstSeen[category]) ~= "number" then
            record.categoryFirstSeen[category] = record.categoryLastSeen[category] or timestamp
        end
        record.categories[category] = true
        record.categoryLastSeen[category] = timestamp
    end
    record.lastSeen = timestamp
    record.guid = guid or record.guid
    -- Prefer the name supplied by the current API; don't replace a useful
    -- previous realm with a missing one.
    if displayName and displayName ~= "" then record.displayName = displayName end
    if realm then record.realm = realm end
    if ns.InvalidateIdentityIndex then ns.InvalidateIdentityIndex() end
    if ns.PromotePendingBattleNetObservations then ns.PromotePendingBattleNetObservations() end
    return record
end

function ns.GetPlayer(name)
    return KnownPlayersDB.players[name]
end

function ns.ForgetPlayer(name)
    if KnownPlayersDB.players[name] == nil then return false end
    KnownPlayersDB.players[name] = nil
    if ns.InvalidateIdentityIndex then ns.InvalidateIdentityIndex() end
    if ns.PruneUnlinkedBattleNetData then ns.PruneUnlinkedBattleNetData() end
    return true
end

function ns.PruneExpiredPlayers(now)
    local currentTime = now or time()
    local removed = 0
    for key, record in pairs(KnownPlayersDB.players) do
        if type(record) == "table" and type(record.categories) == "table" then
            for category, present in pairs(record.categories) do
                local retention = KnownPlayersSettings.categoryRetention[category]
                if present and type(retention) == "table" and retention.enabled then
                    local stamp = type(record.categoryLastSeen) == "table"
                        and record.categoryLastSeen[category] or record.lastSeen
                    if type(stamp) == "number"
                        and stamp < currentTime - SecondsForDuration(retention) then
                        record.categories[category] = nil
                        if record.categoryLastSeen then record.categoryLastSeen[category] = nil end
                        if record.categoryFirstSeen then record.categoryFirstSeen[category] = nil end
                        removed = removed + 1
                    end
                end
            end
            if not next(record.categories) then KnownPlayersDB.players[key] = nil end
        end
    end
    if removed > 0 then
        if ns.InvalidateIdentityIndex then ns.InvalidateIdentityIndex() end
        if ns.PruneUnlinkedBattleNetData then ns.PruneUnlinkedBattleNetData() end
    end
    return removed
end

function ns.PruneExpiredNPCs(now)
    if not KnownPlayersDB or type(KnownPlayersDB.npcs) ~= "table" then return 0 end
    local retention = KnownPlayersSettings and KnownPlayersSettings.categoryRetention
        and KnownPlayersSettings.categoryRetention.npc
    if type(retention) ~= "table" or not retention.enabled then return 0 end
    local cutoff = (now or time()) - SecondsForDuration(retention)
    local removed = 0
    for id, npc in pairs(KnownPlayersDB.npcs) do
        if type(npc) == "table" and type(npc.lastSeen) == "number" and npc.lastSeen < cutoff then
            KnownPlayersDB.npcs[id] = nil
            removed = removed + 1
        end
    end
    if removed > 0 then
        if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
        if ns.RefreshPlayerListWindows then ns.RefreshPlayerListWindows() end
    end
    return removed
end

function ns.CountPlayers()
    local count = 0
    for _ in pairs(KnownPlayersDB.players) do
        count = count + 1
    end
    return count
end

-- A player may belong to several tracking categories. Removing a category
-- never removes the others; an empty record is deleted altogether.
function ns.RemovePlayerCategory(key, category)
    local record = KnownPlayersDB.players[key]
    if type(record) ~= "table" or type(record.categories) ~= "table"
        or not record.categories[category] then
        return false
    end
    record.categories[category] = nil
    if type(record.categoryLastSeen) == "table" then record.categoryLastSeen[category] = nil end
    if type(record.categoryFirstSeen) == "table" then record.categoryFirstSeen[category] = nil end
    if not next(record.categories) then
        KnownPlayersDB.players[key] = nil
    end
    if ns.InvalidateIdentityIndex then ns.InvalidateIdentityIndex() end
    if ns.PruneUnlinkedBattleNetData then ns.PruneUnlinkedBattleNetData() end
    return true
end

function ns.ClearPlayerCategory(category)
    local removed = 0
    for key, record in pairs(KnownPlayersDB.players) do
        if type(record) == "table" and type(record.categories) == "table"
            and record.categories[category] then
            if ns.RemovePlayerCategory(key, category) then
                removed = removed + 1
            end
        end
    end
    return removed
end

function ns.GetCategoryPlayers(category)
    local results = {}
    for key, record in pairs(KnownPlayersDB.players) do
        if type(record) == "table" and type(record.categories) == "table"
            and record.categories[category] then
            results[#results + 1] = {
                key = key,
                name = ns.GetDisplayName(key, record),
                realm = record.realm or "",
                firstSeen = type(record.categoryFirstSeen) == "table"
                    and record.categoryFirstSeen[category] or nil,
            }
        end
    end
    table.sort(results, function(a, b)
        local aName, bName = a.name:lower(), b.name:lower()
        if aName ~= bName then return aName < bName end
        return a.key < b.key
    end)
    return results
end

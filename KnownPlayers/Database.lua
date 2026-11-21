local addonName, ns = ...

local SECONDS_PER_DAY = 86400
local CATEGORIES = { "trade", "party", "raid", "guild", "whisper", "target", "inspect", "manual" }
local supportedCategories = {}
for _, category in ipairs(CATEGORIES) do supportedCategories[category] = true end

function ns.IsPlayerCategory(category)
    return supportedCategories[category] == true
end

-- Keep older interaction history available in SavedVariables. Only currently
-- supported categories count as known players or supply Battle.net anchors.
function ns.HasPlayerCategory(record)
    if type(record) ~= "table" or type(record.categories) ~= "table" then return false end
    for category, present in pairs(record.categories) do
        if present and supportedCategories[category] then return true end
    end
    return false
end

local function TrimmedText(value)
    return ns.SafeString((ns.SafeString(value) or ""):match("^%s*(.-)%s*$"))
end

local function NormalizeTags(text)
    local tags, seen = {}, {}
    for value in text:gmatch("[^,]+") do
        local tag = TrimmedText(value)
        if tag and not seen[tag:lower()] then
            tags[#tags + 1] = tag
            seen[tag:lower()] = true
        end
    end
    return ns.SafeString(table.concat(tags, ", "))
end

function ns.SetPlayerFavorite(key, record, favorite)
    if KnownPlayersDB.players[key] ~= record or not ns.HasPlayerCategory(record) then return false end
    record.favorite = favorite and true or nil
    if ns.RefreshPlayerListWindows then ns.RefreshPlayerListWindows(true) end
    return true
end

function ns.SavePlayerDetails(key, record, note, tags)
    if KnownPlayersDB.players[key] ~= record or not ns.HasPlayerCategory(record) then return false end
    record.note = TrimmedText(note)
    record.tags = NormalizeTags(ns.SafeString(tags) or "")
    if ns.RefreshPlayerListWindows then ns.RefreshPlayerListWindows(true) end
    return true
end

local UNDO_SECONDS = 30
local lastRemoval

function ns.HasRemovalUndo()
    return lastRemoval ~= nil and time() < lastRemoval.expires
end

function ns.ClearRemovalUndo()
    lastRemoval = nil
    if ns.RefreshRemovalUndoButtons then ns.RefreshRemovalUndoButtons() end
end

function ns.OfferRemovalUndo(restore)
    local removal = {restore = restore, expires = time() + UNDO_SECONDS}
    lastRemoval = removal
    if ns.RefreshRemovalUndoButtons then ns.RefreshRemovalUndoButtons() end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(UNDO_SECONDS, function()
            if lastRemoval == removal then ns.ClearRemovalUndo() end
        end)
    end
    print("|cff33ff99KnownPlayers:|r Use /kp undo within " .. UNDO_SECONDS .. " seconds to restore this removal.")
end

function ns.UndoLastRemoval()
    local removal = ns.HasRemovalUndo() and lastRemoval
    ns.ClearRemovalUndo()
    if not removal then return false, "There is no recent removal to undo." end
    if not removal.restore() then return false, "Could not restore the removal because the record changed." end
    if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
    if ns.RefreshPlayerListWindows then ns.RefreshPlayerListWindows() end
    return true, "Restored the last removal."
end
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
    showMinimapButton = false,
    knownOnlyNameplates = false,
    namesOnlyNameplates = false, -- Legacy preference, retained for upgrades.
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
    trackManual = true,
    filterNPCNameplates = false,
    npcServiceCategories = {
        vendor = true, trainer = true, banker = true, auctioneer = true,
        flight = true, innkeeper = true, repair = true, quest = false,
        manual = true,
    },
    npcNameplateCategoryColors = {},
    npcNameplateColorOrder = {},
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
    -- User-specific visibility overrides are keyed by creature template ID.
    -- Do not duplicate QuestieDB classifications in SavedVariables.
    if type(KnownPlayersDB.npcOverrides) ~= "table" then
        KnownPlayersDB.npcOverrides = {}
    end
    if type(KnownPlayersSettings) ~= "table" then
        KnownPlayersSettings = {}
    end
    CopyDefaults(DEFAULT_SETTINGS, KnownPlayersSettings)
    -- Preserve the existing Show Health Bar preference on upgrade. A fresh
    -- install defaults to Always, while legacy Names Only maps to Never.
    if KnownPlayersSettings.playerHealthBarMode ~= "always"
        and KnownPlayersSettings.playerHealthBarMode ~= "combat"
        and KnownPlayersSettings.playerHealthBarMode ~= "never" then
        KnownPlayersSettings.playerHealthBarMode =
            KnownPlayersSettings.namesOnlyNameplates and "never" or "always"
    end
    -- Keep the legacy boolean coherent for older consumers of SavedVariables.
    KnownPlayersSettings.namesOnlyNameplates =
        KnownPlayersSettings.playerHealthBarMode == "never"
    if type(KnownPlayersDB.bnetCharacters) ~= "table" then KnownPlayersDB.bnetCharacters = {} end
    -- Upgrade previous global retention preference once. All categories
    -- initially inherit the same behavior, then become independent.
    for _, category in ipairs(CATEGORIES) do
        if category ~= "guild" and type(KnownPlayersSettings.categoryRetention[category]) ~= "table" then
            KnownPlayersSettings.categoryRetention[category] = {
                enabled = true,
                days = 30,
                hours = 0,
                minutes = 0,
            }
        end
    end
    -- NPC retention is separate from player interactions and off by default.
    if type(KnownPlayersSettings.categoryRetention.npc) ~= "table" then
        KnownPlayersSettings.categoryRetention.npc = {
            enabled = true, days = 30, hours = 0, minutes = 0,
        }
    end
    -- Guild membership is roster-based, not an inactivity-based relationship.
    KnownPlayersSettings.categoryRetention.guild = nil
end

-- Preserve existing SavedVariables keys. Identify players by GUID when available,
-- then by exact name + realm. Never merge solely on a similar-looking name.
local function ValidGUID(guid)
    return ns.SafePlayerGUID(guid) ~= nil
end

local function SplitKnownRealm(key, realmHint)
    if type(key) ~= "string" then return nil, nil end
    -- A separately supplied realm resolves cross-realm names without treating
    -- a hyphen within the character name as a realm separator.
    if type(realmHint) == "string" and realmHint ~= "" then
        local suffix = "-" .. realmHint
        if key:sub(-#suffix):lower() == suffix:lower() then
            return key:sub(1, -#suffix - 1), realmHint
        end
    end
    -- The Forever realm token is an internal identifier. The same character
    -- can also have hyphens in their *name*, so don't split on the first '-'.
    local name, realm = key:match("^(.-)%-(CAMWOW[%w]+)$")
    if name and name ~= "" then return name, realm end
    local ok, realmValue = pcall(GetNormalizedRealmName)
    local localRealm = ok and ns.SafeString(realmValue)
    if localRealm then
        local suffix = "-" .. localRealm
        if key:sub(-#suffix) == suffix then
            return key:sub(1, -#suffix - 1), localRealm
        end
    end
    return key, nil
end

-- WoW Forever may report a character as "First Second" on guild rosters and
-- "First-Second" in unit APIs. Normalize only the CHARACTER portion of a
-- realm-qualified key; never merge characters from different known realms.
function ns.NormalizePlayerKey(key, realmHint)
    key = ns.SafeString(key)
    if not key then return nil end
    local name, realm = SplitKnownRealm(key, realmHint)
    if not name or not realm then return nil end
    name = name:match("^%s*(.-)%s*$"):gsub("%s+", "-")
    if name == "" then return nil end
    return name .. "-" .. realm, name, realm
end

local function ReadableCharacterName(name)
    -- Display only: stored identities retain their canonical hyphens/realm.
    return name:gsub("%-", " "):gsub("%s+", " ")
end

function ns.GetDisplayName(key, record)
    if type(record) == "table" and type(record.displayName) == "string" and record.displayName ~= "" then
        return ReadableCharacterName(record.displayName)
    end
    local name = SplitKnownRealm(key, type(record) == "table" and record.realm or nil)
    return ReadableCharacterName(name or tostring(key))
end

local MergeInto

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
    -- Merge legacy space/hyphen variants on the SAME realm. A GUID conflict
    -- blocks the merge, even when the displayed names look identical.
    -- Choose an already-canonical key first, so roster refreshes and direct
    -- encounters continue writing to that one SavedVariables entry.
    local entries = {}
    for key, record in pairs(KnownPlayersDB.players) do
        if type(record) == "table" then
            local canonical, _, realm = ns.NormalizePlayerKey(key, record.realm)
            if canonical and realm then
                entries[#entries + 1] = {key = key, canonical = canonical,
                    group = canonical:lower(), record = record}
            end
        end
    end
    table.sort(entries, function(a, b)
        if a.group ~= b.group then return a.group < b.group end
        if (a.key == a.canonical) ~= (b.key == b.canonical) then
            return a.key == a.canonical
        end
        return a.key < b.key
    end)
    local leaders = {}
    for _, entry in ipairs(entries) do
        local record = KnownPlayersDB.players[entry.key]
        if record == entry.record then
            local leaderKey = leaders[entry.group]
            local leader = leaderKey and KnownPlayersDB.players[leaderKey]
            local oldGUID = ns.SafePlayerGUID(record.guid)
            local leaderGUID = leader and ns.SafePlayerGUID(leader.guid)
            if leader and (not oldGUID or not leaderGUID or oldGUID == leaderGUID) then
                if record ~= leader then
                    MergeInto(leader, record)
                    KnownPlayersDB.players[entry.key] = nil
                    changed = changed + 1
                end
            elseif not leader then
                -- Re-key to the familiar hyphenated spelling when unoccupied.
                local destination = entry.canonical
                if destination ~= entry.key and KnownPlayersDB.players[destination] == nil then
                    KnownPlayersDB.players[destination] = record
                    KnownPlayersDB.players[entry.key] = nil
                    changed = changed + 1
                    entry.key = destination
                end
                leaders[entry.group] = entry.key
            end
            -- A conflicting-GUID record remains separate and untouched.
        end
    end
    if ns.InvalidateIdentityIndex then ns.InvalidateIdentityIndex() end
    return changed
end

function ns.MergePlayerAppearance(destination, source)
    if not destination.class or destination.class == source.class then
        destination.classToken = destination.classToken or source.classToken
    end
    if not destination.race or destination.race == source.race then
        destination.raceAtlas = destination.raceAtlas or source.raceAtlas
    end
    destination.class = ns.SafeString(destination.class) or ns.SafeString(source.class)
    destination.race = ns.SafeString(destination.race) or ns.SafeString(source.race)
end

MergeInto = function(destination, source, keepDestinationDetails)
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
    ns.MergePlayerAppearance(destination, source)
    if keepDestinationDetails then return end
    destination.favorite = (destination.favorite or source.favorite) and true or nil
    local originalNote = ns.SafeString(destination.note)
    local sourceNote = ns.SafeString(source.note)
    if sourceNote and originalNote and sourceNote ~= originalNote then
        destination.note = originalNote .. "\n\n" .. sourceNote
    else
        destination.note = originalNote or sourceNote
    end
    local tags = ns.SafeString(source.tags)
    if tags then destination.tags = NormalizeTags((ns.SafeString(destination.tags) or "") .. "," .. tags) end
end

function ns.SetPlayerClass(record, class, token)
    class, token = ns.SafeString(class), ns.SafeString(token)
    if class and class ~= record.class then
        record.class = class
        record.classToken = nil
    end
    if token then record.classToken = token:lower():gsub("%s+", "") end
end

function ns.SetPlayerRace(record, race, token, sex)
    race, token = ns.SafeString(race), ns.SafeString(token)
    if race and race ~= record.race then
        record.race = race
        record.raceAtlas = nil
    end
    if not token or not ns.IsAccessibleValue(sex) then return end
    local variant = sex == 2 and "male" or sex == 3 and "female"
    if not variant then return end
    token = token:lower():gsub("%s+", "")
    if token == "scourge" then token = "undead" end
    record.raceAtlas = "raceicon128-" .. token .. "-" .. variant
end

function ns.RefreshPlayerAppearance(record, unit)
    if unit then
        local raceOK, race, raceToken = pcall(UnitRace, unit)
        local classOK, class, classToken = pcall(UnitClass, unit)
        local sexOK, sex = pcall(UnitSex, unit)
        if raceOK then ns.SetPlayerRace(record, race, raceToken, sexOK and sex) end
        if classOK then ns.SetPlayerClass(record, class, classToken) end
    end

    -- Cached GUID data can fill gaps for whispers and older saved records.
    if record.race and record.raceAtlas and record.class and record.classToken then return end
    local guid = ns.SafePlayerGUID(record.guid)
    if not guid then return end
    local ok, class, classToken, race, raceToken, sex = pcall(GetPlayerInfoByGUID, guid)
    if not ok then return end
    if not record.class or record.class == ns.SafeString(class) then
        ns.SetPlayerClass(record, class, record.classToken or classToken)
    end
    if not record.race or (not record.raceAtlas and record.race == ns.SafeString(race)) then
        ns.SetPlayerRace(record, race, raceToken, sex)
    end
end

-- Optional GUID lets another interaction recognize a character whose name
-- spelling / realm format differs. Identical names without a GUID are not
-- proof that two records belong to the same player.
function ns.RememberPlayer(name, category, seenAt, guid, realmHint, unit)
    name = ns.SafeString(name)
    if not name then return nil end
    local normalized, displayName, realm = ns.NormalizePlayerKey(name, realmHint)
    if normalized then name = normalized end
    if not displayName then displayName, realm = SplitKnownRealm(name, realmHint) end
    if not ValidGUID(guid) then guid = nil end
    local players = KnownPlayersDB.players

    local matchedKey = guid and ns.FindDirectKeyByGUID and ns.FindDirectKeyByGUID(guid) or nil
    if not matchedKey and ns.FindDirectKeyByName then
        matchedKey = ns.FindDirectKeyByName(name, guid)
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
    ns.RefreshPlayerAppearance(record, unit)
    if ns.InvalidateIdentityIndex then ns.InvalidateIdentityIndex() end
    if ns.PromotePendingBattleNetObservations then ns.PromotePendingBattleNetObservations() end
    return record
end

function ns.GetPlayer(name)
    return KnownPlayersDB.players[name]
end

local function RestorePlayer(key, saved, guildClubID, originalRecord)
    if saved.categories.guild and guildClubID ~= KnownPlayersDB.guildRosterClubID then
        saved.categories.guild = nil
        if saved.categoryFirstSeen then saved.categoryFirstSeen.guild = nil end
        if saved.categoryLastSeen then saved.categoryLastSeen.guild = nil end
        if not next(saved.categories) then return false end
    end
    local players = KnownPlayersDB.players
    local guid = ns.SafePlayerGUID(saved.guid)
    local match = guid and ns.FindDirectKeyByGUID and ns.FindDirectKeyByGUID(guid)
    if not match and ns.FindDirectKeyByName then
        match = ns.FindDirectKeyByName(key, guid)
    end
    if match then
        MergeInto(players[match], saved, players[match] == originalRecord)
    else
        if players[key] ~= nil then
            if not guid or players["guid:" .. guid] ~= nil then return false end
            key = "guid:" .. guid
        end
        players[key] = saved
    end
    if ns.InvalidateIdentityIndex then ns.InvalidateIdentityIndex() end
    if ns.PromotePendingBattleNetObservations then ns.PromotePendingBattleNetObservations() end
    return true
end

function ns.ForgetPlayer(name, undoable)
    local record = KnownPlayersDB.players[name]
    if record == nil then return false end
    KnownPlayersDB.players[name] = nil
    if ns.InvalidateIdentityIndex then ns.InvalidateIdentityIndex() end
    if ns.PruneUnlinkedBattleNetData then ns.PruneUnlinkedBattleNetData() end
    if undoable and type(record) == "table" and type(record.categories) == "table" then
        local guildClubID = KnownPlayersDB.guildRosterClubID
        ns.OfferRemovalUndo(function() return RestorePlayer(name, record, guildClubID) end)
    end
    return true
end

function ns.PruneExpiredPlayers(now)
    local currentTime = now or time()
    local cutoffs = {}
    for category in pairs(supportedCategories) do
        local retention = KnownPlayersSettings.categoryRetention[category]
        if category ~= "guild" and type(retention) == "table" and retention.enabled then
            cutoffs[category] = currentTime - SecondsForDuration(retention)
        end
    end
    if not next(cutoffs) then return 0 end

    local removed = 0
    for key, record in pairs(KnownPlayersDB.players) do
        if type(record) == "table" and type(record.categories) == "table" and not record.favorite then
            local categoryLastSeen = type(record.categoryLastSeen) == "table" and record.categoryLastSeen
            local categoryFirstSeen = type(record.categoryFirstSeen) == "table" and record.categoryFirstSeen
            for category, present in pairs(record.categories) do
                local cutoff = cutoffs[category]
                if present and cutoff then
                    local stamp = (categoryLastSeen and categoryLastSeen[category]) or record.lastSeen
                    if type(stamp) == "number" and stamp <= cutoff then
                        record.categories[category] = nil
                        if categoryLastSeen then categoryLastSeen[category] = nil end
                        if categoryFirstSeen then categoryFirstSeen[category] = nil end
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
        if type(npc) == "table" and not npc.favorite and type(npc.lastSeen) == "number"
            and npc.lastSeen <= cutoff then
            KnownPlayersDB.npcs[id] = nil
            removed = removed + 1
        end
    end
    return removed
end

function ns.CountPlayers()
    local count = 0
    for _, record in pairs(KnownPlayersDB.players) do
        if ns.HasPlayerCategory(record) then count = count + 1 end
    end
    return count
end

-- A player may belong to several tracking categories. Removing a category
-- never removes the others; an empty record is deleted altogether.
local function RemovePlayerCategory(key, category, preserveFavorites)
    local record = KnownPlayersDB.players[key]
    if type(record) ~= "table" or type(record.categories) ~= "table"
        or not record.categories[category] then
        return false
    end
    record.categories[category] = nil
    if type(record.categoryLastSeen) == "table" then record.categoryLastSeen[category] = nil end
    if type(record.categoryFirstSeen) == "table" then record.categoryFirstSeen[category] = nil end
    if preserveFavorites and record.favorite and not ns.HasPlayerCategory(record) then
        record.categories.manual = true
        record.categoryFirstSeen = record.categoryFirstSeen or {}
        record.categoryLastSeen = record.categoryLastSeen or {}
        local stamp = record.lastSeen or time()
        record.categoryFirstSeen.manual, record.categoryLastSeen.manual = stamp, stamp
    end
    if not next(record.categories) then
        KnownPlayersDB.players[key] = nil
    end
    return true
end

local function RefreshAfterCategoryRemoval()
    if ns.InvalidateIdentityIndex then ns.InvalidateIdentityIndex() end
    if ns.PruneUnlinkedBattleNetData then ns.PruneUnlinkedBattleNetData() end
end

function ns.RemovePlayerCategory(key, category, undoable)
    local record = KnownPlayersDB.players[key]
    local saved
    if undoable and type(record) == "table" and type(record.categories) == "table"
        and record.categories[category] then
        saved = {
            displayName = record.displayName, realm = record.realm, guid = record.guid,
            race = record.race, raceAtlas = record.raceAtlas,
            class = record.class, classToken = record.classToken,
            note = record.note, tags = record.tags, favorite = record.favorite, lastSeen = record.lastSeen,
            categories = {[category] = true},
            categoryFirstSeen = {[category] = type(record.categoryFirstSeen) == "table" and record.categoryFirstSeen[category] or nil},
            categoryLastSeen = {[category] = type(record.categoryLastSeen) == "table" and record.categoryLastSeen[category] or nil},
        }
    end
    if not RemovePlayerCategory(key, category) then return false end
    RefreshAfterCategoryRemoval()
    if saved then
        local guildClubID = KnownPlayersDB.guildRosterClubID
        ns.OfferRemovalUndo(function() return RestorePlayer(key, saved, guildClubID, record) end)
    end
    return true
end

function ns.ClearPlayerCategory(category, keep, preserveFavorites)
    local removed = 0
    for key in pairs(KnownPlayersDB.players) do
        if (not keep or not keep[key]) and RemovePlayerCategory(key, category, preserveFavorites) then
            removed = removed + 1
        end
    end
    if removed > 0 then RefreshAfterCategoryRemoval() end
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
                appearance = record,
                firstSeen = type(record.categoryFirstSeen) == "table"
                    and record.categoryFirstSeen[category] or nil,
            }
        end
    end
    return results
end

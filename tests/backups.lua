-- Run from the repository root with Lua 5.1. The client codec is stubbed.
local NOW = 1000000
time = function() return NOW end
GetNormalizedRealmName = function() return "CAMWOW1" end
StaticPopupDialogs = {}
CreateFrame = function()
    return {RegisterEvent = function() end, SetScript = function() end}
end

local payloads, serial = {}, 0
C_EncodingUtil = {
    SerializeCBOR = function(value)
        serial = serial + 1
        local key = "Payload" .. serial
        payloads[key] = value
        return key
    end,
    DeserializeCBOR = function(value) return payloads[value] end,
    EncodeBase64 = function(value) return value end,
    DecodeBase64 = function(value) return value end,
}

local ns = {
    RefreshMinimapButton = function() end, RefreshKnownNameplates = function() end,
}
for _, module in ipairs({"Safety", "Categories", "Database", "Identity", "NPC", "Backups",
    "BattleNet", "Colors", "Settings", "Windows", "PlayerList", "Tracking"}) do
    assert(loadfile("KnownPlayers/" .. module .. ".lua"))("KnownPlayers", ns)
end
ns.InitializeDatabase()
ns.InitializeNameplateColors()

local key = "Synthetic-Friend-CAMWOW1"
local guid = "Player-Test-1"
local record = ns.RememberPlayer(key, "manual", NOW - 10, guid)
record.note, record.tags, record.favorite = "Original note", "Trader", true
ns.SetActiveGuild(42)
ns.RememberPlayer(key, "guild", NOW - 5, guid)
KnownPlayersDB.npcs["42"] = {name = "Example Vendor", firstSeen = NOW - 100, lastSeen = NOW}
KnownPlayersDB.npcOverrides["42"] = {name = "Example Vendor", mode = "show", firstSeen = NOW}
KnownPlayersDB.bnetCharacters["Example#0000"] = {[key] = {name = "Synthetic-Friend", realm = "CAMWOW1", guid = guid}}
KnownPlayersSettings.showMinimapButton = false
KnownPlayersSettings.overheadNameCVarsBackup = {UnitNameFriendlyPlayerName = "1"}

local manual = assert(ns.CreateRestorePoint("manual", "Manual backup"))
assert(manual.created == NOW and manual.sections.players.records[key].note == "Original note")
assert(manual.sections.players.bnet["Example#0000"] and not manual.sections.settings.overheadNameCVarsBackup)

local settingsOnly = assert(ns.ReadBackup(assert(ns.ExportBackup({settings = true}))))
assert(settingsOnly.sections.settings.showMinimapButton == false)
assert(not settingsOnly.sections.players and not settingsOnly.sections.npcs)
assert(not settingsOnly.sections.settings.overheadNameCVarsBackup)
local export = assert(ns.ExportBackup({settings = true, players = true, npcs = true}))
local portable = assert(ns.ReadBackup("\n" .. export .. "\n"))
assert(portable.sections.players.records[key].favorite and not portable.sections.players.bnet)
assert(portable.sections.players.records[key].guildMemberships["42"].firstSeen == NOW - 5)
assert(portable.sections.npcs.overrides["42"].mode == "show")
assert(ns.DescribeBackup(portable, {players = true, npcs = true}) == "1 player record, 1 saved NPC, 1 NPC override")

local oldCodec = C_EncodingUtil
C_EncodingUtil = nil
assert(not ns.ExportBackup({settings = true}) and not ns.ReadBackup(export))
assert(ns.GetRestorePoint("manual") == manual)
C_EncodingUtil = oldCodec

-- Settings reset and the real clear-list action create automatic checkpoints.
StaticPopupDialogs.KNOWNPLAYERS_RESET_SETTINGS.OnAccept()
assert(KnownPlayersSettings.showMinimapButton == true and KnownPlayersDB.players[key] == record)
assert(ns.GetRestorePoint("automatic").sections.settings.showMinimapButton == false)
assert(not ns.GetRestorePoint("automatic").sections.players and not ns.GetRestorePoint("automatic").sections.npcs)
assert(ns.ApplyBackup(ns.GetRestorePoint("automatic"), {settings = true}, "replace", true))
assert(KnownPlayersSettings.showMinimapButton == false and KnownPlayersSettings.overheadNameCVarsBackup)
StaticPopupDialogs.KNOWNPLAYERS_CLEAR_CATEGORY_WINDOW.OnAccept(nil, "manual")
assert(not ns.PlayerHasCategory(record, "manual"))
assert(ns.GetRestorePoint("automatic").sections.players.records[key].categories.manual)
assert(not ns.GetRestorePoint("automatic").sections.settings and not ns.GetRestorePoint("automatic").sections.npcs)
assert(ns.GetRestorePoint("manual") == manual)

-- Import into an existing record with the same GUID after a rename.
local renamed = "Renamed-Friend-CAMWOW1"
KnownPlayersDB.players = {}
ns.InvalidateIdentityIndex()
local current = ns.RememberPlayer(renamed, "trade", NOW, guid)
current.note, current.tags = "Current note", "Guild"
KnownPlayersDB.npcs["42"].firstSeen = NOW - 10
KnownPlayersDB.npcOverrides["42"].mode = "hide"
local applied, skipped = ns.ApplyBackup(portable, {players = true, npcs = true}, "merge", false)
assert(applied and skipped == 0)
local merged = ns.FindDirectRecord(renamed, guid)
assert(merged.note == "Current note" and merged.tags == "Guild, Trader" and merged.favorite)
assert(ns.PlayerHasCategory(merged, "manual") and ns.PlayerHasCategory(merged, "trade") and ns.PlayerHasCategory(merged, "guild"))
assert(KnownPlayersDB.npcs["42"].firstSeen == NOW - 100 and KnownPlayersDB.npcOverrides["42"].mode == "hide")
assert(KnownPlayersDB.players[key] == nil and KnownPlayersDB.players[renamed] == merged)

assert(ns.ApplyBackup(manual, {players = true}, "replace", true))
assert(KnownPlayersDB.players[key].note == "Original note" and KnownPlayersDB.players[renamed] == nil)
assert(KnownPlayersDB.bnetCharacters["Example#0000"])
assert(KnownPlayersDB.npcOverrides["42"].mode == "hide")
assert(ns.GetRestorePoint("automatic").sections.players.records[renamed].note == "Current note")

local original = KnownPlayersDB.players
local automatic = ns.GetRestorePoint("automatic")
assert(not ns.ReadBackup("KnownPlayers:2:Bad") and not ns.ReadBackup("return { data = true }"))
payloads.Invalid = {version = 1, created = NOW, sections = {players = {records = {[key] = {favorite = "true"}}}}}
assert(not ns.ReadBackup("KnownPlayers:1:Invalid"))
assert(not ns.ApplyBackup(portable, {}, "replace", false))
assert(not ns.ApplyBackup(settingsOnly, {players = true}, "replace", false))
assert(original == KnownPlayersDB.players and automatic == ns.GetRestorePoint("automatic"))

local noGUID = {version = 1, created = NOW, sections = {players = {records = {
    [key] = {displayName = "Synthetic-Friend", realm = "CAMWOW1", categories = {party = true}},
}}}}
ns.RememberPlayer(key, "raid", NOW, "Player-Test-2")
applied, skipped = ns.ApplyBackup(noGUID, {players = true}, "merge", false)
assert(applied and skipped == 1)
assert(not ns.PlayerHasCategory(ns.FindDirectRecord(key, guid), "party"))

local livePlayers = KnownPlayersDB.players
local liveRecord = ns.FindDirectRecord(key, guid)
local invalidateBattleNet = ns.InvalidateBattleNetIndex
ns.InvalidateBattleNetIndex = function() error("Staging invalidated the live Battle.net index") end
local staged = {[key] = {guid = guid, note = "Staged note", categories = {manual = true}}}
assert(ns.MergeBackupPlayers(staged, {[renamed] = {guid = guid, categories = {trade = true}}}) == 0)
assert(staged[key].categories.trade and staged[key].note == "Staged note" and not staged[renamed])
assert(KnownPlayersDB.players == livePlayers and ns.FindDirectRecord(key, guid) == liveRecord)
ns.InvalidateBattleNetIndex = invalidateBattleNet

-- An incoming GUID-less alias sorts before the incoming conflicting GUID.
local shared = "Backup-Player-CAMWOW1"
ns.RememberPlayer(shared, "manual", NOW, "Player-Backup-1")
local competing = {version = 1, created = NOW, sections = {players = {records = {
    ["Backup Player-CAMWOW1"] = {favorite = true, categories = {trade = true}},
    [shared] = {guid = "Player-Backup-2", categories = {target = true}},
}}}}
applied, skipped = ns.ApplyBackup(competing, {players = true}, "merge", false)
assert(applied and skipped == 1)
local preserved = ns.FindDirectRecord(shared, "Player-Backup-1")
assert(preserved and not preserved.favorite and not ns.PlayerHasCategory(preserved, "trade"))
assert(ns.PlayerHasCategory(ns.FindDirectRecord(shared, "Player-Backup-2"), "target"))

-- Individually unique aliases can still disagree on which player owns a row.
local firstKey, secondKey = "First-Player-CAMWOW1", "Second-Player-CAMWOW1"
ns.RememberPlayer(firstKey, "manual", NOW, "Player-Backup-3")
ns.RememberPlayer(secondKey, "manual", NOW, "Player-Backup-4")
local mismatched = {version = 1, created = NOW, sections = {players = {records = {
    [firstKey] = {displayName = "Second Player", realm = "CAMWOW1", favorite = true, categories = {trade = true}},
}}}}
applied, skipped = ns.ApplyBackup(mismatched, {players = true}, "merge", false)
assert(applied and skipped == 1)
for _, alias in ipairs({firstKey, secondKey}) do
    local saved = ns.GetPlayer(alias)
    assert(saved and not saved.favorite and not ns.PlayerHasCategory(saved, "trade"))
end

-- An incoming GUID cannot claim a staged GUID-less row with a disputed preferred name.
local disputedKey = "Disputed-Backup-CAMWOW1"
KnownPlayersDB.players[disputedKey] = {
    displayName = "Second Player", realm = "CAMWOW1", note = "Disputed backup note", categories = {trade = true},
}
ns.InvalidateIdentityIndex()
local disputedImport = {version = 1, created = NOW, sections = {players = {records = {
    [disputedKey] = {guid = "Player-Backup-5", categories = {target = true}},
}}}}
applied, skipped = ns.ApplyBackup(disputedImport, {players = true}, "merge", false)
assert(applied and skipped == 0)
local unresolved = ns.GetPlayer(disputedKey)
local imported = ns.GetPlayer("guid:Player-Backup-5")
assert(unresolved and not unresolved.guid and unresolved.note == "Disputed backup note")
assert(ns.PlayerHasCategory(unresolved, "trade") and not ns.PlayerHasCategory(unresolved, "target"))
assert(imported and not imported.note and imported.displayName ~= "Second Player"
    and not ns.PlayerHasCategory(imported, "trade"))
assert(ns.PlayerHasCategory(imported, "target") and ns.FindDirectRecord(secondKey, "Player-Backup-4"))

-- Reject a merge beyond the portable limit before changing history or checkpoints.
local extraNPC = {version = 1, created = NOW, sections = {npcs = {
    records = {["10001"] = {name = "Extra NPC"}}, overrides = {},
}}}
local npcs = {}
for id = 1, 10000 do npcs[tostring(id)] = {name = "Synthetic NPC"} end
KnownPlayersDB.npcs = npcs
automatic = ns.GetRestorePoint("automatic")
local ok, message = ns.ApplyBackup(extraNPC, {npcs = true}, "merge", false)
assert(not ok and message:find("10000 saved NPCs", 1, true))
assert(KnownPlayersDB.npcs == npcs and not npcs["10001"] and ns.GetRestorePoint("automatic") == automatic)

-- Existing oversized histories remain eligible for local checkpoints and replacement.
npcs["10001"] = {name = "Existing NPC"}
local oversized = assert(ns.CreateRestorePoint("manual", "Oversized history"))
assert(oversized.sections.npcs.records["10001"] and not ns.ExportBackup({npcs = true}))
KnownPlayersSettings.showMinimapButton = false
StaticPopupDialogs.KNOWNPLAYERS_RESET_SETTINGS.OnAccept()
assert(KnownPlayersSettings.showMinimapButton and KnownPlayersDB.npcs == npcs)
assert(ns.ApplyBackup(extraNPC, {npcs = true}, "replace", false))
assert(ns.ApplyBackup(oversized, {npcs = true}, "replace", true))
assert(KnownPlayersDB.npcs["10001"].name == "Existing NPC" and KnownPlayersDB.npcs["1"])

local nested = ns.RememberPlayer("Nested-History-CAMWOW1", "manual", NOW)
nested.guildMemberships = {}
for clubID = 1, 201 do nested.guildMemberships[tostring(clubID)] = {firstSeen = NOW} end
assert(not ns.ExportBackup({players = true}))
nested.guildMemberships["201"] = nil
local longNote = string.rep("x", 65537)
assert(ns.SavePlayerDetails("Nested-History-CAMWOW1", nested, longNote, ""))
assert(not ns.ExportBackup({players = true}))
nested.guildMemberships["201"] = {firstSeen = NOW}
local nestedPoint = assert(ns.CreateRestorePoint("manual", "Nested history"))
nested.note, nested.guildMemberships = nil, nil
assert(ns.ApplyBackup(nestedPoint, {players = true}, "replace", true))
local restored = ns.GetPlayer("Nested-History-CAMWOW1")
assert(restored.note == longNote and restored.guildMemberships["201"].firstSeen == NOW)
-- A malformed unrelated history row must not block a settings-only action.
restored.favorite = "invalid"
KnownPlayersSettings.showMinimapButton = false
StaticPopupDialogs.KNOWNPLAYERS_RESET_SETTINGS.OnAccept()
assert(KnownPlayersSettings.showMinimapButton and ns.GetPlayer("Nested-History-CAMWOW1") == restored)
assert(ns.ApplyBackup(ns.GetRestorePoint("automatic"), {settings = true}, "replace", true))
assert(KnownPlayersSettings.showMinimapButton == false and restored.favorite == "invalid")
assert(ns.ApplyBackup({version = 1, created = NOW, sections = {settings = {}, players = "invalid"}},
    {settings = true}, "replace", true))
assert(KnownPlayersSettings.showMinimapButton)
restored.favorite = nil

-- The real scanner writes a new player during any of these settings actions.
local partyMember = "New-Party-Member-CAMWOW1"
GetNumGroupMembers = function() return 2 end
IsInRaid = function() return false end
UnitExists = function(unit) return unit == "party1" end
UnitIsPlayer = UnitExists
UnitIsUnit = function(first, second) return first == second end
UnitFullName = function() return "New Party Member", "CAMWOW1" end
UnitGUID = function() return "Player-Party-1" end
local function VerifyTrackingRollback(apply)
    ns.ApplyKnownPlayersSettings({trackGroup = {party = false}})
    assert(not ns.GetPlayer(partyMember))
    apply()
    assert(ns.CategoryTrackingEnabled("party") and ns.PlayerHasCategory(ns.GetPlayer(partyMember), "party"))
    local point = ns.GetRestorePoint("automatic")
    assert(point.sections.settings and point.sections.players.bnet and not point.sections.npcs)
    assert(not point.sections.players.records[partyMember])
    assert(ns.ApplyBackup(point, {settings = true, players = true}, "replace", true))
    assert(not ns.CategoryTrackingEnabled("party") and not ns.GetPlayer(partyMember) and ns.GetPlayer(key))
end
VerifyTrackingRollback(StaticPopupDialogs.KNOWNPLAYERS_RESET_SETTINGS.OnAccept)
local enableParty = {version = 1, created = NOW, sections = {settings = {trackGroup = {party = true}}}}
VerifyTrackingRollback(function() assert(ns.ApplyBackup(enableParty, {settings = true}, "merge", false)) end)
VerifyTrackingRollback(function() assert(ns.ApplyBackup(enableParty, {settings = true}, "replace", true)) end)

GetNumGroupMembers = function() return 0 end
ns.ApplyKnownPlayersSettings({})
local scans = {}
ns.ScanGroupRoster = function() scans[#scans + 1] = "group" end
ns.RequestGuildRoster = function() scans[#scans + 1] = "guild request" end
ns.ScanGuildRoster = function() scans[#scans + 1] = "guild scan" end
ns.ScanBattleNetFriends = function() scans[#scans + 1] = "Battle.net" end
local disabled = {trackGroup = {party = false, raid = false}, trackGuild = false, trackBattleNetAssociations = false}
local enabledBackup = assert(ns.CreateRestorePoint("manual", "Enabled tracking"))
ns.ApplyKnownPlayersSettings(disabled)
assert(#scans == 0)
assert(ns.ApplyBackup(enabledBackup, {settings = true}, "replace", true))
assert(table.concat(scans, ", ") == "group, guild request, guild scan, Battle.net")
scans = {}
assert(ns.ApplyBackup(enabledBackup, {settings = true}, "replace", true))
assert(#scans == 0)
ns.ApplyKnownPlayersSettings(disabled)
StaticPopupDialogs.KNOWNPLAYERS_RESET_SETTINGS.OnAccept()
assert(table.concat(scans, ", ") == "group, guild request, guild scan, Battle.net")

KnownPlayersSettings = {
    namesOnlyNameplates = true, npcNamesOnlyNameplates = true,
    nameplateColorOrder = {"trade", "manual"}, npcNameplateColorOrder = {"trainer", "vendor"},
}
ns.InitializeDatabase()
ns.InitializeNameplateColors()
assert(KnownPlayersSettings.playerHealthBarMode == "never" and KnownPlayersSettings.npcHealthBarMode == "never")
assert(table.concat(KnownPlayersSettings.nameplateColorOrder, ",", 1, 2) == "trade,manual")
assert(table.concat(ns.GetNPCNameplateColorOrder(), ",", 1, 2) == "trainer,vendor")

io.write("Backup and restore checkpoints, portable sections, merge conflicts, and invalid imports passed.\n")

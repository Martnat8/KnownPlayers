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
KnownPlayersSettings.nameplatesClickable = false
KnownPlayersSettings.nameplateClickInsetsBackup = {[0] = {original = {1, 2, 3, 4}, applied = {1000, 1000, 1000, 1000}}}
KnownPlayersSettings.nameplateFilterMethod = "alpha"
KnownPlayersSettings.playerNameplateFilterMethod = "alpha"
ns.InitializeDatabase()
assert(KnownPlayersSettings.nameplateFilterMethod == nil and KnownPlayersSettings.playerNameplateFilterMethod == nil)
KnownPlayersSettings.overheadNameCVarsBackup = {UnitNameFriendlyPlayerName = "1"}

local manual = assert(ns.CreateRestorePoint("manual", "Manual backup"))
assert(manual.created == NOW and manual.sections.players.records[key].note == "Original note")
assert(manual.sections.players.bnet["Example#0000"] and not manual.sections.settings.overheadNameCVarsBackup)

local settingsOnly = assert(ns.ReadBackup(assert(ns.ExportBackup({settings = true}))))
assert(settingsOnly.sections.settings.showMinimapButton == false)
assert(settingsOnly.sections.settings.nameplatesClickable == false)
assert(settingsOnly.sections.settings.nameplateClickInsetsBackup == nil)
assert(not settingsOnly.sections.settings.nameplateFilterMethod)
assert(not settingsOnly.sections.players and not settingsOnly.sections.npcs)
assert(not settingsOnly.sections.settings.overheadNameCVarsBackup)
local legacyPayload = C_EncodingUtil.SerializeCBOR({version = settingsOnly.version, created = NOW,
    sections = {settings = {nameplateFilterMethod = "alpha", playerNameplateFilterMethod = "alpha",
        showMinimapButton = false}}})
local legacy = assert(ns.ReadBackup("KnownPlayers:" .. settingsOnly.version .. ":" .. legacyPayload))
assert(not legacy.sections.settings.nameplateFilterMethod and not legacy.sections.settings.playerNameplateFilterMethod)
assert(legacy.sections.settings.showMinimapButton == false)
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
assert(KnownPlayersSettings.nameplatesClickable == true and KnownPlayersSettings.nameplateClickInsetsBackup)
assert(ns.GetRestorePoint("automatic").sections.settings.showMinimapButton == false)
assert(not ns.GetRestorePoint("automatic").sections.players and not ns.GetRestorePoint("automatic").sections.npcs)
assert(ns.ApplyBackup(ns.GetRestorePoint("automatic"), {settings = true}, "replace", true))
assert(KnownPlayersSettings.showMinimapButton == false and KnownPlayersSettings.overheadNameCVarsBackup)
assert(KnownPlayersSettings.nameplatesClickable == false and KnownPlayersSettings.nameplateClickInsetsBackup)
local favoriteOnly = ns.RememberPlayer("Pinned-Example-CAMWOW1", "manual", NOW)
favoriteOnly.favorite = true
local ordinaryKey = "Ordinary-Example-CAMWOW1"
ns.RememberPlayer(ordinaryKey, "manual", NOW)
StaticPopupDialogs.KNOWNPLAYERS_CLEAR_CATEGORY_WINDOW.OnAccept(nil, "manual")
assert(ns.PlayerHasCategory(record, "manual") and ns.PlayerHasCategory(record, "guild"))
assert(ns.PlayerHasCategory(favoriteOnly, "manual") and ns.GetPlayer("Pinned-Example-CAMWOW1") == favoriteOnly)
assert(ns.GetPlayer(ordinaryKey) == nil)
assert(ns.GetRestorePoint("automatic").sections.players.records[key].categories.manual)
assert(ns.GetRestorePoint("automatic").sections.players.records[ordinaryKey].categories.manual)
assert(not ns.GetRestorePoint("automatic").sections.settings and not ns.GetRestorePoint("automatic").sections.npcs)
assert(ns.GetRestorePoint("manual") == manual)
local beforeRedundantClear = ns.GetRestorePoint("automatic")
StaticPopupDialogs.KNOWNPLAYERS_CLEAR_CATEGORY_WINDOW.OnAccept(nil, "manual")
assert(ns.GetRestorePoint("automatic") == beforeRedundantClear)

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

-- Forget removes the live note and link while leaving local recovery copies intact.
local tag = "Example#0000"
assert(ns.ForgetPlayer(key))
assert(not ns.GetPlayer(key) and not KnownPlayersDB.bnetCharacters[tag])
assert(manual.sections.players.records[key].note == "Original note" and manual.sections.players.bnet[tag])
KnownPlayersSettings.trackBattleNetAssociations = false
assert(ns.ApplyBackup(manual, {players = true}, "replace", true))
assert(not ns.CategoryTrackingEnabled("associated") and KnownPlayersDB.bnetCharacters[tag])
KnownPlayersSettings.trackBattleNetAssociations = true
local undoPoint = ns.GetRestorePoint("automatic")
assert(not ns.DeleteRestorePoint("manual", undoPoint), "Deletion must confirm the same snapshot")
assert(ns.DeleteRestorePoint("manual", manual))
assert(not ns.GetRestorePoint("manual") and ns.GetRestorePoint("automatic") == undoPoint)
manual = assert(ns.CreateRestorePoint("manual", "Manual backup"))
assert(ns.DeleteRestorePoint("automatic", undoPoint))
assert(not ns.GetRestorePoint("automatic") and ns.GetRestorePoint("manual") == manual)
assert(ns.GetPlayer(key).note == "Original note" and KnownPlayersDB.bnetCharacters[tag])

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

-- A partial import preserves omitted tracking fields. Explicit Battle.net enable
-- scans the synthetic friend roster and captures those writes in the checkpoint.
GetNumGroupMembers = function() return 0 end
IsInGuild = function() return false end
local friendKey, altKey, friendTag = "Backup-Anchor-CAMWOW1", "Backup-Alt-CAMWOW1", "Example#0010"
local friend = {battleTag = friendTag, gameAccountInfo = {
    clientProgram = "WoW", characterName = "Backup Anchor", realmName = "CAMWOW1", playerGuid = "Player-Backup-10",
}}
BNConnected = function() return true end
BNGetNumFriends = function() return 1 end
C_BattleNet = {
    GetFriendAccountInfo = function() return friend end,
    GetFriendNumGameAccounts = function() return 1 end,
    GetFriendGameAccountInfo = function() return {
        clientProgram = "WoW", characterName = "Backup Alt", realmName = "CAMWOW1", playerGuid = "Player-Backup-11",
    } end,
}
assert(ns.ScanBattleNetFriends() == 1 and not KnownPlayersDB.bnetCharacters[friendTag])
ns.ApplyKnownPlayersSettings({trackBattleNetAssociations = false})
BNConnected = function() return false end
ns.ApplyKnownPlayersSettings({trackBattleNetAssociations = true})
ns.RememberPlayer(friendKey, "manual", NOW, "Player-Backup-10")
assert(not KnownPlayersDB.bnetCharacters[friendTag], "Disabling tracking must discard pending observations immediately")
BNConnected = function() return true end
local partial = {version = 1, created = NOW, sections = {settings = {
    showMinimapButton = false, trackGroup = {raid = false},
}}}
ns.ApplyKnownPlayersSettings({trackBattleNetAssociations = false, trackGuild = false, trackGroup = {party = false}})
assert(ns.ApplyBackup(partial, {settings = true}, "merge", false))
assert(not ns.CategoryTrackingEnabled("associated"), "Partial import enabled Battle.net tracking")
assert(not ns.CategoryTrackingEnabled("guild") and not ns.CategoryTrackingEnabled("party")
    and not ns.CategoryTrackingEnabled("raid") and not KnownPlayersSettings.showMinimapButton)
assert(not KnownPlayersDB.bnetCharacters[friendTag] and not ns.GetRestorePoint("automatic").sections.players)
assert(ns.DescribeBackup(partial, {settings = true}) == "Settings")
partial.sections.settings.trackTrades = false
assert(ns.DescribeBackup(partial, {settings = true}):find("Disable: Trade", 1, true))
partial.sections.settings.trackBattleNetAssociations = true
assert(ns.DescribeBackup(partial, {settings = true}):find("Enable: Known Battle.net Alts", 1, true))
assert(ns.DescribeBackup(partial, {}) == "")
assert(ns.ApplyBackup(partial, {settings = true}, "replace", false))
assert(ns.IsAssociatedCharacter(altKey, "Player-Backup-11"))
local beforeScan = ns.GetRestorePoint("automatic")
assert(not beforeScan.sections.settings.trackBattleNetAssociations and beforeScan.sections.players.bnet
    and not beforeScan.sections.players.bnet[friendTag])
assert(ns.ApplyBackup(beforeScan, {settings = true, players = true}, "replace", true))
assert(not ns.CategoryTrackingEnabled("associated") and not KnownPlayersDB.bnetCharacters[friendTag])
assert(ns.GetPlayer(friendKey))

-- A failed UI refresh must leave the restore committed and report a warning.
KnownPlayersDB.npcs = {["42"] = {name = "Previous NPC"}}
local refreshNameplates = ns.RefreshKnownNameplates
ns.RefreshKnownNameplates = function() error("Synthetic nameplate refresh failure") end
local refreshLists = ns.RefreshPlayerListWindows
local refreshedLists = false
ns.RefreshPlayerListWindows = function() refreshedLists = true end
local restoredWithWarning, skippedWithWarning, warning = ns.ApplyBackup(extraNPC, {npcs = true}, "replace", false)
assert(restoredWithWarning and skippedWithWarning == 0 and warning and refreshedLists)
assert(KnownPlayersDB.npcs["10001"].name == "Extra NPC" and not KnownPlayersDB.npcs["42"])
assert(ns.GetRestorePoint("automatic").sections.npcs.records["42"].name == "Previous NPC")
local refreshMinimap = ns.RefreshMinimapButton
ns.RefreshMinimapButton = function() error("Synthetic minimap refresh failure") end
refreshedLists = false
restoredWithWarning, skippedWithWarning, warning = ns.ApplyBackup(partial, {settings = true}, "merge", false)
assert(restoredWithWarning and skippedWithWarning == 0 and warning and refreshedLists)
assert(KnownPlayersSettings.trackBattleNetAssociations and ns.IsAssociatedCharacter(altKey, "Player-Backup-11"))
ns.RefreshKnownNameplates, ns.RefreshPlayerListWindows, ns.RefreshMinimapButton =
    refreshNameplates, refreshLists, refreshMinimap

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
    npcNameplateCategoryColors = {vendor = {0.94, 0.81, 0.34}, trainer = {0.33, 0.44, 0.55}},
}
ns.InitializeDatabase()
ns.InitializeNameplateColors()
assert(KnownPlayersSettings.playerHealthBarMode == "never" and KnownPlayersSettings.npcHealthBarMode == "never")
assert(table.concat(KnownPlayersSettings.nameplateColorOrder, ",", 1, 3) == "avoid,trade,manual")
assert(table.concat(ns.GetNPCNameplateColorOrder(), ",", 1, 2) == "trainer,vendor")
local vendorColor, trainerColor = ns.GetNPCNameplateCategoryColor("vendor"), ns.GetNPCNameplateCategoryColor("trainer")
assert(vendorColor[1] == 0xC7 / 255 and vendorColor[2] == 0xF0 / 255 and vendorColor[3] == 0)
assert(trainerColor[1] == 0.33 and trainerColor[2] == 0.44 and trainerColor[3] == 0.55)
assert(ns.GetNameplateCategoryColor("trade")[1] == 1 and ns.GetNameplateCategoryColor("trade")[2] == 0.82)

-- A player can still choose the old shade after migration and restore it from a backup.
KnownPlayersSettings.npcNameplateCategoryColors.vendor = {0.94, 0.81, 0.34}
local paletteBackup = assert(ns.ReadBackup(assert(ns.ExportBackup({settings = true}))))
assert(ns.ApplyBackup(paletteBackup, {settings = true}, "merge", false))
assert(ns.GetNPCNameplateCategoryColor("vendor")[1] == 0.94)

local avoidedKey = "Synthetic-Avoid-CAMWOW1"
KnownPlayersDB = nil
ns.InitializeDatabase()
ns.InvalidateIdentityIndex()
local avoided = ns.RememberPlayer(avoidedKey, "avoid", NOW, "Player-Avoid-1")
avoided.note = "Synthetic Avoid note"
local avoidBackup = assert(ns.ReadBackup(assert(ns.ExportBackup({players = true, settings = true}))))
assert(avoidBackup.sections.players.records[avoidedKey].categories.avoid)
assert(avoidBackup.sections.settings.trackAvoid)
assert(ns.SetPlayerAvoided(avoidedKey, avoided, false) and not ns.GetPlayer(avoidedKey))
assert(ns.ApplyBackup(avoidBackup, {players = true}, "merge", false))
assert(ns.PlayerHasCategory(ns.GetPlayer(avoidedKey), "avoid") and ns.GetPlayer(avoidedKey).note == "Synthetic Avoid note")

KnownPlayersSettings.useAlternateAvoidName = true
local renamedListBackup = assert(ns.ReadBackup(assert(ns.ExportBackup({settings = true}))))
KnownPlayersSettings.useAlternateAvoidName = false
assert(ns.ApplyBackup(renamedListBackup, {settings = true}, "merge", false))
assert(ns.GetPlayerCategoryLabel("avoid") == "Shitbags")
local olderSettings = {version = 1, created = NOW, sections = {settings = {showMinimapButton = false}}}
assert(ns.ApplyBackup(olderSettings, {settings = true}, "merge", false))
assert(ns.GetPlayerCategoryLabel("avoid") == "Shitbags" and ns.PlayerHasCategory(ns.GetPlayer(avoidedKey), "avoid"))

-- Upgrade the first-name/realm layout written for Forever before surnames were stored explicitly.
local legacyKey, transportKey, disputedKey = "Example-Surname", "Preserved-Player-CAMWOW1", "guid:Player-Convert-3"
local convertedGUID = "Player-Convert-1"
KnownPlayersDB.players = {
    [legacyKey] = {displayName = "Example", realm = "Surname", guid = convertedGUID, note = "Synthetic note",
        tags = "Synthetic tags", favorite = true, categories = {manual = true}, lastSeen = NOW,
        categoryFirstSeen = {manual = NOW - 10}, categoryLastSeen = {manual = NOW}},
    [transportKey] = {displayName = "Preserved-Player", realm = "CAMWOW1", categories = {party = true}},
    [disputedKey] = {displayName = "Example", realm = "Surname", guid = "Player-Convert-3",
        note = "Unverified name", categories = {whisper = true}},
}
KnownPlayersDB.bnetCharacters = {
    ["Synthetic#0000"] = {[legacyKey] = {name = "Example", realm = "Surname", guid = convertedGUID}},
}
ns.InvalidateIdentityIndex()
local oldSnapshot = assert(ns.CreateRestorePoint("manual", "Manual backup", {players = true}))
local original = KnownPlayersDB.players[legacyKey]
original.note = false
assert(ns.ConvertPlayerNames() == nil and original.displayName == "Example" and original.realm == "Surname")
original.note = "Synthetic note"

local converted, skipped = ns.ConvertPlayerNames()
assert(converted == 2 and skipped == 1)
local checkpoint = assert(ns.GetRestorePoint("automatic"))
assert(ns.GetRestorePoint("manual") == oldSnapshot and checkpoint.sections.players.records[legacyKey].realm == "Surname")
assert(ns.CountPlayers() == 3 and ns.GetPlayer(legacyKey) == original and not original.realm)
assert(original.displayName == "Example Surname" and original.surname == "Surname")
assert(original.note == "Synthetic note" and original.tags == "Synthetic tags" and original.favorite == true)
assert(original.guid == convertedGUID and original.categoryFirstSeen.manual == NOW - 10 and original.categoryLastSeen.manual == NOW)
assert(ns.GetPlayer(disputedKey).realm == "Surname" and ns.GetPlayer(disputedKey).note == "Unverified name")
assert(ns.FindDirectKeyByName("Preserved Player") == transportKey)
assert(KnownPlayersDB.bnetCharacters["Synthetic#0000"][legacyKey].guid == convertedGUID)
assert(ns.ConvertPlayerNames() == 0 and ns.GetRestorePoint("automatic") == checkpoint)

ns.MigratePlayerRecords()
assert(not ns.GetPlayer(transportKey).realm and ns.FindDirectKeyByName("Preserved Player") == transportKey)
local convertedBackup = assert(ns.ReadBackup(assert(ns.ExportBackup({players = true}))))
assert(convertedBackup.sections.players.records[legacyKey].surname == "Surname")
assert(convertedBackup.sections.players.records[transportKey].displayName == "Preserved Player")
assert(ns.ApplyBackup(checkpoint, {players = true}, "replace", true))
local restored = ns.GetPlayer(legacyKey)
assert(restored.displayName == "Example" and restored.realm == "Surname" and not restored.surname)
assert(restored.guid == convertedGUID and restored.note == "Synthetic note" and restored.tags == "Synthetic tags" and restored.favorite)
assert(ns.PlayerHasCategory(restored, "manual") and restored.categoryFirstSeen.manual == NOW - 10)
assert(ns.GetPlayer(transportKey).realm == "CAMWOW1" and ns.GetPlayer(disputedKey).note == "Unverified name")
assert(KnownPlayersDB.bnetCharacters["Synthetic#0000"][legacyKey].guid == convertedGUID)

io.write("Backup and restore checkpoints, portable sections, merge conflicts, and invalid imports passed.\n")

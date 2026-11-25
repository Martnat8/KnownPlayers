-- Run from the repository root with Lua 5.1.
local NOW = 1000000
local REALM = "CAMWOW1"
local SELF = "Test-Self-" .. REALM
local MEMBER = "Test-Member-" .. REALM

local function StartSession(saved, settings)
    local state = {events = {}, timers = {}, messages = {}, roster = {}, friends = {}, connected = true}
    KnownPlayersDB, KnownPlayersSettings = saved, settings
    SlashCmdList, StaticPopupDialogs = {}, {}
    print = function(message) state.messages[#state.messages + 1] = message end
    time = function() return NOW end
    CreateFrame = function()
        local frame = {events = {}}
        state.events[#state.events + 1] = frame
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:SetScript(key, handler) self[key] = handler end
        return frame
    end
    C_Timer = {After = function(_, fn) state.timers[#state.timers + 1] = fn end, NewTicker = function() end}
    C_Club = {GetGuildClubId = function() return state.club end}
    C_GuildInfo = {GuildRoster = function() end}
    GetNormalizedRealmName = function() return REALM end
    IsInGuild = function() return state.club ~= nil end
    GetNumGuildMembers = function() return #state.roster end
    GetGuildRosterInfo = function(index) return state.roster[index], nil, nil, nil, "Mage" end
    GetNumGroupMembers = function() return 0 end
    UnitExists = function() return true end
    UnitIsPlayer = function() return true end
    UnitIsUnit = function(first, second) return first == second end
    UnitFullName = function(unit) return unit == "player" and "Test-Self" or "Other-Target", REALM end
    BNConnected = function() return state.connected end
    BNGetNumFriends = function() return #state.friends end
    C_BattleNet = {
        GetFriendAccountInfo = function(index)
            if index ~= state.failedFriendIndex then return state.friends[index] end
        end,
        GetFriendNumGameAccounts = function(index) return #(state.friends[index].games or {}) end,
        GetFriendGameAccountInfo = function(index, game) return state.friends[index].games[game] end,
    }
    Menu = {ModifyMenu = function(tag, callback) state[tag] = callback end}

    function state:Fire(event, ...)
        for _, frame in ipairs(self.events) do
            if frame.events[event] then frame:OnEvent(event, ...) end
        end
    end

    function state:ConfirmRoster()
        self:Fire("GUILD_ROSTER_UPDATE")
        local pending = self.timers
        self.timers = {}
        for _, callback in ipairs(pending) do callback() end
    end

    local ns = {
        CreateSettingsPanel = function() end, RefreshMinimapButton = function() end,
        RefreshKnownNameplates = function() end, RefreshPlayerListWindows = function() end,
        CountNPCs = function() return 0 end,
    }
    for _, module in ipairs({"Safety", "Categories", "Database", "Identity", "PlayerMenu", "Tracking", "BattleNet", "Core"}) do
        assert(loadfile("KnownPlayers/" .. module .. ".lua"))("KnownPlayers", ns)
    end
    state:Fire("ADDON_LOADED", "KnownPlayers")
    return ns, state
end

local ns, state = StartSession()
local original = ns.RememberPlayer(MEMBER, "party", NOW - 2 * 86400)
original.note = "Synthetic note"
SlashCmdList.KNOWNPLAYERS("dbtest")
assert(ns.GetPlayer(MEMBER) == original and original.note == "Synthetic note")
assert(KnownPlayersSettings.categoryRetention.party.enabled == false)
assert(state.messages[#state.messages]:find("PASS", 1, true))

-- Migrate and revisit a guild, then verify a later departure on that roster.
ns, state = StartSession({guildRosterClubID = 42, players = {
    [MEMBER] = {categories = {guild = true}, lastSeen = NOW - 50, note = "Migrated note", tags = "Test"},
}})
state.club, state.roster = 42, {SELF, MEMBER}
state:ConfirmRoster()
local migrated = ns.GetPlayer(MEMBER)
assert(ns.PlayerHasCategory(migrated, "guild"))
assert(ns.PlayerCategoryTime(migrated, "guild", "firstSeen") == NOW - 50)

local saved, settings = KnownPlayersDB, KnownPlayersSettings
ns, state = StartSession(saved, settings)
state:Fire("PLAYER_ENTERING_WORLD")
assert(ns.GetPlayer(MEMBER) == migrated and migrated.note == "Migrated note")
assert(#ns.GetCategoryPlayers("guild") == 0)
state.club, state.roster = 43, {SELF, "Different-Member-" .. REALM}
state:ConfirmRoster()
assert(#ns.GetCategoryPlayers("guild") == 1 and not ns.PlayerHasCategory(migrated, "guild"))
state.club, state.roster = 42, {SELF, MEMBER}
state:ConfirmRoster()
assert(ns.PlayerHasCategory(migrated, "guild"))

state.roster = {SELF}
state:ConfirmRoster()
assert(#ns.GetCategoryPlayers("guild") == 0 and ns.GetPlayer(MEMBER) == migrated)
assert(migrated.note == "Migrated note" and migrated.tags == "Test")
ns.PruneExpiredPlayers(NOW)
assert(ns.RememberPlayer(MEMBER, "target") == migrated)
assert(ns.PlayerHasCategory(migrated, "target"))

-- A partial roster must not bulk-delete memberships. Confirmed removals
-- preserve favorites and leave memberships from other guilds intact.
ns, state = StartSession()
state.club, state.roster = 44, {SELF, MEMBER, "Second-" .. REALM, "Third-" .. REALM, "Fourth-" .. REALM}
state:ConfirmRoster()
local favorite = ns.GetPlayer(MEMBER)
assert(ns.SetPlayerFavorite(MEMBER, favorite, true))
state.roster = {SELF}
state:ConfirmRoster()
assert(#ns.GetCategoryPlayers("guild") == 4)
C_Club.GetClubMembers = function() return {1} end
C_Club.GetMemberInfo = function() return {name = SELF} end
state:ConfirmRoster()
assert(#ns.GetCategoryPlayers("guild") == 0)
assert(ns.GetPlayer(MEMBER) == favorite and ns.PlayerHasCategory(favorite, "manual"))

ns, state = StartSession()
local old = ns.RememberPlayer(MEMBER, "manual", nil, "Player-Test-1")
local current = ns.RememberPlayer(MEMBER, "target", nil, "Player-Test-2")
assert(old ~= current and ns.FindDirectRecord(MEMBER, "Player-Test-2") == current)
assert(ns.FindDirectRecord(MEMBER) == nil and ns.RememberPlayer(MEMBER, "whisper") == nil)
assert(ns.ForgetPlayer(MEMBER, true) and ns.FindDirectRecord(MEMBER) == current)
assert(ns.UndoLastRemoval() and ns.FindDirectRecord(MEMBER) == nil)

local target = "Other-Target-" .. REALM
ns.RememberPlayer(target, "manual")
local buttons = {}
local menu = {CreateDivider = function() end, CreateTitle = function() end,
    CreateButton = function(_, label, callback) buttons[label] = callback end}
state.MENU_UNIT_FRIEND(nil, menu, {name = MEMBER, guid = "Player-Test-2"})
assert(next(buttons) == nil and ns.GetPlayer(target))
state.MENU_UNIT_TARGET(nil, menu, {unit = "target"})
assert(buttons["Forget Player"])
buttons["Forget Player"]()
assert(ns.GetPlayer(target) == nil and ns.GetPlayer(MEMBER))

-- Preserve GUID-less history through startup and later GUID-confirmed tracking.
local sharedKey = "Shared-Player-" .. REALM
local firstAlias, secondAlias = "Shared Player-" .. REALM, "shared-player-" .. REALM
ns, state = StartSession({players = {
    [sharedKey] = {note = "Ambiguous history", categories = {trade = true}, lastSeen = NOW},
    [firstAlias] = {guid = "Player-Migrate-1", categories = {manual = true}},
    [secondAlias] = {guid = "Player-Migrate-2", categories = {manual = true}},
}})
local ambiguousHistory = ns.GetPlayer(sharedKey)
assert(ambiguousHistory and ambiguousHistory.note == "Ambiguous history")
local confirmed = ns.RememberPlayer(sharedKey, "whisper", NOW, "Player-Migrate-1")
assert(confirmed and not confirmed.note and not ns.PlayerHasCategory(confirmed, "trade"))
assert(ns.GetPlayer(sharedKey) == ambiguousHistory and ns.CountPlayers() == 3)
local newcomer = ns.RememberPlayer(sharedKey, "party", NOW, "Player-Migrate-3")
assert(newcomer and newcomer ~= ambiguousHistory and not ns.PlayerHasCategory(newcomer, "trade"))
assert(ns.GetPlayer(sharedKey) == ambiguousHistory and ns.CountPlayers() == 4)

-- A preferred alias from a GUID-keyed record also claims the name.
local guidKey = "guid:Player-Migrate-2"
ns, state = StartSession({players = {
    [sharedKey] = {note = "Unassigned note", categories = {trade = true}, lastSeen = NOW},
    [firstAlias] = {guid = "Player-Migrate-1", categories = {manual = true}},
    [guidKey] = {guid = "Player-Migrate-2", displayName = "Shared Player", realm = REALM,
        categories = {manual = true}},
}})
assert(ns.GetPlayer(sharedKey).note == "Unassigned note" and ns.CountPlayers() == 3)
assert(not ns.GetPlayer(firstAlias).note and not ns.GetPlayer(guidKey).note)
assert(not ns.PlayerHasCategory(ns.GetPlayer(firstAlias), "trade"))

-- A confirmed whisper must not absorb a GUID-less row claimed by another alias.
local disputedKey = "Disputed-Player-" .. REALM
local confirmedKey, preferredKey = "guid:Player-Disputed-1", "Preferred-Player-" .. REALM
ns, state = StartSession({players = {
    [disputedKey] = {displayName = "Preferred Player", realm = REALM, note = "Disputed note",
        categories = {trade = true}},
    [confirmedKey] = {guid = "Player-Disputed-1", displayName = "Disputed Player", realm = REALM,
        categories = {manual = true}},
    [preferredKey] = {guid = "Player-Disputed-2", categories = {manual = true}},
}})
local disputed = ns.GetPlayer(disputedKey)
assert(disputed and ns.CountPlayers() == 3)
local confirmedEvent = {"Synthetic message", disputedKey, [12] = "Player-Disputed-1"}
state:Fire("CHAT_MSG_WHISPER", unpack(confirmedEvent, 1, 12))
local whisperOwner = ns.GetPlayer(confirmedKey)
assert(ns.GetPlayer(disputedKey) == disputed and disputed.note == "Disputed note")
assert(ns.PlayerHasCategory(disputed, "trade") and not ns.PlayerHasCategory(disputed, "whisper"))
assert(ns.PlayerHasCategory(whisperOwner, "whisper") and not ns.PlayerHasCategory(whisperOwner, "trade"))
assert(not whisperOwner.note and ns.CountPlayers() == 3)

ns, state = StartSession(nil, {trackWhispers = true})
local localMember = ns.RememberPlayer(MEMBER, "manual")
state:Fire("CHAT_MSG_WHISPER", "Synthetic message", "Test-Member")
assert(ns.PlayerHasCategory(localMember, "whisper") and ns.CountPlayers() == 1)
local remote = "Test-Member-CAMWOW2"
state:Fire("CHAT_MSG_WHISPER", "Synthetic message", remote)
assert(ns.PlayerHasCategory(ns.GetPlayer(remote), "whisper"))
state:Fire("CHAT_MSG_WHISPER_INFORM", "Synthetic message", "Test-Self")
assert(ns.CountPlayers() == 2 and not ns.GetPlayer(SELF))
local remoteRealm = "LegacyRealm"
local qualified = "Test-Member-" .. remoteRealm
local remoteMember = ns.RememberPlayer(qualified, "manual", NOW, nil, remoteRealm)
state:Fire("CHAT_MSG_WHISPER", "Synthetic message", qualified)
assert(ns.PlayerHasCategory(remoteMember, "whisper") and ns.CountPlayers() == 3)
local conflict = ns.RememberPlayer(qualified, "manual", NOW, "Player-Whisper-1", remoteRealm)
local another = ns.RememberPlayer(qualified, "manual", NOW, "Player-Whisper-2", remoteRealm)
state:Fire("CHAT_MSG_WHISPER", "Synthetic message", qualified)
assert(conflict ~= another and not ns.PlayerHasCategory(another, "whisper") and ns.CountPlayers() == 4)

local sender = "Qualified-Player-" .. remoteRealm
local existing = ns.RememberPlayer(sender, "manual", NOW, "Player-Qualified-1", remoteRealm)
local event = {"Synthetic message", sender, [12] = "Player-Qualified-2"}
state:Fire("CHAT_MSG_WHISPER", unpack(event, 1, 12))
local qualifiedWhisper = ns.FindDirectRecord(nil, "Player-Qualified-2")
assert(qualifiedWhisper and qualifiedWhisper.realm == remoteRealm and qualifiedWhisper.displayName == "Qualified-Player")
assert(ns.PlayerHasCategory(qualifiedWhisper, "whisper") and not ns.PlayerHasCategory(existing, "whisper"))
assert(ns.GetPlayer("guid:Player-Qualified-2") == qualifiedWhisper and not ns.GetPlayer(sender .. "-" .. REALM))

-- Full and partial Battle.net snapshots exercise persisted and transient links.
ns, state = StartSession()
local function Game(name, guid)
    return {clientProgram = "WoW", characterName = name, realmName = REALM, playerGuid = guid}
end
ns.RememberPlayer(MEMBER, "manual", nil, "Player-Test-1")
local friend = {battleTag = "Example#0000", gameAccountInfo = Game("Test-Member", "Player-Test-1"),
    games = {Game("Test-Alt", "Player-Test-2")}}
state.friends = {friend}
state:Fire("BN_FRIEND_LIST_SIZE_CHANGED")
assert(ns.IsAssociatedCharacter("Test-Alt-" .. REALM, "Player-Test-2"))
state.failedFriendIndex = 1
state:Fire("BN_FRIEND_LIST_SIZE_CHANGED")
assert(#ns.GetAssociatedCharacters() == 1)
state.failedFriendIndex, state.connected, state.friends = nil, false, {}
state:Fire("BN_DISCONNECTED")
state:Fire("BN_FRIEND_LIST_SIZE_CHANGED")
assert(#ns.GetAssociatedCharacters() == 1)
state.connected = true
state:Fire("BN_CONNECTED")
assert(#ns.GetAssociatedCharacters() == 1)
state:Fire("BN_FRIEND_LIST_SIZE_CHANGED")
assert(#ns.GetAssociatedCharacters() == 0 and next(KnownPlayersDB.bnetCharacters) == nil)
assert(ns.GetPlayer(MEMBER))

-- Two linked groups can report the same name while each GUID remains valid.
ns, state = StartSession()
local altKey = "Shared-Alt-" .. REALM
local secondAnchor = "Second-Anchor-" .. REALM
ns.RememberPlayer(MEMBER, "manual", NOW, "Player-Anchor-1")
ns.RememberPlayer(secondAnchor, "manual", NOW, "Player-Anchor-2")
KnownPlayersDB.bnetCharacters = {
    ["Example#0001"] = {
        [MEMBER] = {guid = "Player-Anchor-1"},
        [altKey] = {guid = "Player-Alt-1"},
    },
    ["Example#0002"] = {
        [secondAnchor] = {guid = "Player-Anchor-2"},
        ["shared alt-" .. REALM] = {guid = "Player-Alt-2"},
    },
}
ns.InvalidateBattleNetIndex()
assert(ns.IsAssociatedCharacter(altKey, "Player-Alt-1") and ns.IsAssociatedCharacter(altKey, "Player-Alt-2"))
assert(not ns.IsKnownOrAssociated(altKey) and not ns.IsAssociatedCharacter(altKey, "Player-Alt-3"))
KnownPlayersDB.bnetCharacters["Example#0002"] = nil
ns.InvalidateBattleNetIndex()
assert(ns.IsAssociatedCharacter(altKey) and not ns.IsAssociatedCharacter(altKey, "Player-Alt-2"))

-- New and existing roster imports must grow linearly in identity lookups.
ns, state = StartSession()
state.club, state.roster = 45, {SELF}
for index = 1, 500 do state.roster[index + 1] = "Synthetic" .. index .. "-" .. REALM end
local normalizations, normalize = 0, ns.NormalizePlayerKey
ns.NormalizePlayerKey = function(...)
    normalizations = normalizations + 1
    return normalize(...)
end
state:ConfirmRoster()
assert(ns.ScanGuildRoster() == 500)
assert(normalizations < 5000, "roster import rebuilt its identity index per member")

UnitIsUnit = function() error("unit comparison restricted") end
state:Fire("PLAYER_TARGET_CHANGED")
assert(ns.GetPlayer(target) == nil)
io.write("Persistence, guild, identity, menu, and Battle.net checks passed.\n")

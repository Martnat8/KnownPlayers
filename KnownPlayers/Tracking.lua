local addonName, ns = ...

-- Identity keys include the realm so identically named characters on
-- different realms cannot overwrite one another.
local function GetPlayerKey(unit)
    if not UnitExists(unit) or not UnitIsPlayer(unit) or ns.CompareUnits(unit, "player") ~= false then
        return nil
    end

    local ok, name, realm = pcall(UnitFullName, unit)
    local key = ok and ns.PlayerKeyFromName(name, realm)
    if key then return key, ns.SafePlayerGUID(ns.SafeUnitGUID(unit)) end
end

function ns.ScanGroupRoster()
    local total = GetNumGroupMembers()
    if not total or total <= 1 then
        return 0
    end

    local raid = IsInRaid()
    local category = raid and "raid" or "party"
    if not KnownPlayersSettings.trackGroup[category] then
        return 0
    end

    local prefix = raid and "raid" or "party"
    local finalIndex = raid and total or (total - 1)
    local updated = 0
    local now = time()

    for i = 1, finalIndex do
        local unit = prefix .. i
        local key, guid = GetPlayerKey(unit)
        if key then
            ns.RememberPlayer(key, category, now, guid, nil, unit)
            updated = updated + 1
        end
    end

    return updated
end

local rosterFrame = CreateFrame("Frame")
rosterFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
rosterFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
rosterFrame:SetScript("OnEvent", function()
    -- The database is initialized during ADDON_LOADED.
    if KnownPlayersDB and KnownPlayersSettings and KnownPlayersSettings.trackGroup then
        ns.ScanGroupRoster()
    end
end)

-- Chat events supply the other player's name as their second argument.
-- Normalize names to the same Name-Realm keys used by roster tracking.
local function NormalizeWhisperName(sender, guid)
    sender = ns.SafeString(sender)
    if not sender or sender == UNKNOWNOBJECT then
        return nil
    end

    local key, _, realm = ns.NormalizePlayerKey(sender)
    if key then return key, realm end

    -- A less common realm suffix can still be resolved from an exact saved key.
    local saved = ns.GetPlayer(sender)
    if saved then
        realm = ns.SafeString(saved.realm)
        -- A different event GUID rules out the saved player, but the exact
        -- key still identifies the realm that the client supplied.
        local qualified, _, qualifiedRealm = ns.NormalizePlayerKey(sender, realm)
        if guid and qualified then return qualified, qualifiedRealm end
        local matched, ambiguous = ns.FindDirectKeyByName(sender, guid, realm)
        if ambiguous then return nil end
        if matched == sender then return sender, realm end
    end
    key, _, realm = ns.PlayerKeyFromName(sender)
    return key, realm
end

local whisperFrame = CreateFrame("Frame")
whisperFrame:RegisterEvent("CHAT_MSG_WHISPER")
whisperFrame:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
whisperFrame:SetScript("OnEvent", function(_, _, ...)
    local sender = select(2, ...)
    local guid = ns.SafePlayerGUID(select(12, ...))
    if not KnownPlayersDB or not KnownPlayersSettings
        or not KnownPlayersSettings.trackWhispers then
        return
    end

    local key, realm = NormalizeWhisperName(sender, guid)
    if not key then
        return
    end

    -- Do not retain your own character if the client reports a self-whisper.
    local ok, selfName, selfRealm = pcall(UnitFullName, "player")
    local selfKey = ok and ns.PlayerKeyFromName(selfName, selfRealm)
    local comparableKey = realm and key or ns.PlayerKeyFromName(key)
    if (selfKey and comparableKey and comparableKey:lower() == selfKey:lower())
        or (guid and guid == ns.SafeUnitGUID("player")) then
        return
    end

    ns.RememberPlayer(key, "whisper", nil, guid, realm)
end)

-- Opening a trade window constitutes an encounter, even if the trade
-- is later cancelled. The "npc" unit identifies the other trading party
-- while the trade window is open (it is not necessarily a literal NPC).
local tradeFrame = CreateFrame("Frame")
tradeFrame:RegisterEvent("TRADE_SHOW")
tradeFrame:SetScript("OnEvent", function()
    if not KnownPlayersDB or not KnownPlayersSettings
        or not KnownPlayersSettings.trackTrades then
        return
    end

    -- Use the trade partner, not the player's current target, which could
    -- be a different character. Skip the event if the name is unavailable.
    local key, guid = GetPlayerKey("npc")
    if key then
        ns.RememberPlayer(key, "trade", nil, guid, nil, "npc")
    end
end)

-- Guild mode: remember everyone listed on the roster, including offline
-- members. A future option may restrict this to directly met guildmates.
local function NormalizeGuildName(name)
    name = ns.SafeString(name)
    if not name or name == UNKNOWNOBJECT then
        return nil
    end

    local playerName, realm = name:match("^([^%-]+)%-(.+)$")
    if not playerName then
        playerName = name
    end
    if not realm or realm == "" then
        realm = ns.SafeString(GetNormalizedRealmName())
    end
    if not realm or realm == "" then
        return nil
    end
    local key = playerName .. "-" .. realm
    return ns.NormalizePlayerKey(key) or key
end

local function GuildClubID()
    if not C_Club or type(C_Club.GetGuildClubId) ~= "function" then return nil end
    local ok, id = pcall(C_Club.GetGuildClubId)
    if not ok or not ns.IsAccessibleValue(id) then return nil end
    if type(id) == "number" and id > 0 then return id end
    return ns.SafeString(id)
end

local function GuildSelfKey()
    local ok, name, realm = pcall(UnitFullName, "player")
    if not ok or not ns.IsAccessibleValue(realm) then return nil end
    name = ns.SafeString(name)
    if not name or name == UNKNOWNOBJECT then return nil end
    realm = ns.SafeString(realm) or ns.SafeString(GetNormalizedRealmName())
    return realm and ns.NormalizePlayerKey(name .. "-" .. realm, realm) or nil
end

local function TrackGuildRoster()
    return KnownPlayersDB and KnownPlayersSettings and KnownPlayersSettings.trackGuild
        and IsInGuild()
end

local currentClub, confirmedRoster, pendingRoster

local function ReadGuildSnapshot()
    if not TrackGuildRoster() then return nil end
    local total = GetNumGuildMembers()
    local selfKey = GuildSelfKey()
    if not selfKey or not ns.IsAccessibleValue(total) or type(total) ~= "number"
        or total < 1 then return nil end
    local members = {}
    for i = 1, total do
        local name, _, _, _, class = GetGuildRosterInfo(i)
        local key = NormalizeGuildName(name)
        if not key or members[key] then return nil end
        members[key] = {class = ns.SafeString(class)}
    end
    if members[selfKey] then return {members = members, count = total, selfKey = selfKey} end
end

local function SameSnapshot(a, b)
    if not a or not b or a.count ~= b.count or a.selfKey ~= b.selfKey then return false end
    for key in pairs(a.members) do if not b.members[key] then return false end end
    return true
end

local function RefreshGuildViews()
    if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
    if ns.RefreshPlayerListWindows then ns.RefreshPlayerListWindows() end
end

local function ClubRosterMatches(clubID, members, count)
    if type(C_Club.GetClubMembers) ~= "function" or type(C_Club.GetMemberInfo) ~= "function" then
        return false
    end
    local ok, ids = pcall(C_Club.GetClubMembers, clubID)
    if not ok or not ns.IsAccessibleValue(ids) or type(ids) ~= "table" or #ids ~= count then return false end
    local seen = {}
    for _, id in ipairs(ids) do
        local read, info = pcall(C_Club.GetMemberInfo, clubID, id)
        if not read or not ns.IsAccessibleValue(info) or type(info) ~= "table" then return false end
        local key = NormalizeGuildName(info.name)
        if not key or not members[key] or seen[key] then return false end
        seen[key] = true
    end
    return true
end

local function ReconcileGuildMembership(clubID, snapshot)
    local missing, savedGuildCount, keep = 0, 0, {}
    for key, record in pairs(KnownPlayersDB.players) do
        if ns.PlayerHasCategory(record, "guild") then
            savedGuildCount = savedGuildCount + 1
            local name = ns.SafeString(record.displayName)
            local realm = ns.SafeString(record.realm)
            local canonical = name and realm and ns.NormalizePlayerKey(name .. "-" .. realm, realm)
            if snapshot.members[key] or (canonical and snapshot.members[canonical]) then
                keep[key] = true
            else
                missing = missing + 1
            end
        end
    end
    -- A truncated roster must not erase a guild's history. For a large
    -- removal, require the current club's member list to corroborate the roster.
    if missing > math.max(2, math.floor(savedGuildCount * 0.1))
        and not ClubRosterMatches(clubID, snapshot.members, snapshot.count) then return false end
    if missing > 0 then ns.ClearPlayerCategory("guild", keep, true) end
    return true
end

local function SelectCurrentGuild()
    local clubID = IsInGuild() and GuildClubID() or nil
    if currentClub ~= clubID then
        currentClub, confirmedRoster, pendingRoster = clubID, nil, nil
        if ns.SetActiveGuild(clubID) then RefreshGuildViews() end
    end
    return clubID
end

local function ImportGuildRoster(snapshot)
    local updated, now = 0, time()
    for key, member in pairs(snapshot.members) do
        if key ~= snapshot.selfKey then
            local record = ns.RememberPlayer(key, "guild", now)
            if record then
                ns.SetPlayerClass(record, member.class)
                updated = updated + 1
            end
        end
    end
    return updated
end

function ns.ScanGuildRoster()
    if not TrackGuildRoster() or not confirmedRoster or GuildClubID() ~= currentClub then return 0 end
    return ImportGuildRoster(confirmedRoster)
end

function ns.RequestGuildRoster()
    if not KnownPlayersSettings or not KnownPlayersSettings.trackGuild or not IsInGuild() then return end
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
end

function ns.RefreshGuildList()
    if not TrackGuildRoster() then return false end
    ns.RequestGuildRoster()
    ns.ScanGuildRoster()
    return true
end

local guildFrame = CreateFrame("Frame")
guildFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
guildFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
guildFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
guildFrame:RegisterEvent("INITIAL_CLUBS_LOADED")
guildFrame:SetScript("OnEvent", function(_, event, unit)
    if not KnownPlayersDB or not KnownPlayersSettings then return end
    if event == "PLAYER_GUILD_UPDATE" and ns.SafeString(unit) ~= "player" then return end
    local clubID = SelectCurrentGuild()
    if not clubID or not TrackGuildRoster() then return end
    if event ~= "GUILD_ROSTER_UPDATE" then
        ns.RequestGuildRoster()
        return
    end
    local snapshot = ReadGuildSnapshot()
    if not snapshot or SameSnapshot(snapshot, pendingRoster) then return end
    if SameSnapshot(snapshot, confirmedRoster) then
        pendingRoster = nil
        return
    end
    pendingRoster = snapshot
    C_Timer.After(2, function()
        if pendingRoster ~= snapshot then return end
        pendingRoster = nil
        if GuildClubID() ~= clubID then return end
        local confirmed = ReadGuildSnapshot()
        if not SameSnapshot(snapshot, confirmed) then return end
        local reconciled = ReconcileGuildMembership(clubID, confirmed)
        ImportGuildRoster(confirmed)
        if reconciled then confirmedRoster = confirmed end
        RefreshGuildViews()
    end)
end)


-- Targeting and inspecting are separate encounters. Neither action is
-- inferred from the other; a player may legitimately have both categories.
local targetFrame = CreateFrame("Frame")
targetFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
targetFrame:SetScript("OnEvent", function()
    if KnownPlayersDB and KnownPlayersSettings and KnownPlayersSettings.trackTargets then
        local key, guid = GetPlayerKey("target")
        if key then ns.RememberPlayer(key, "target", nil, guid, nil, "target") end
    end
    -- Recognize the new encounter before the filter decides which plates to hide.
    if ns.OnNameplateTargetChanged then ns.OnNameplateTargetChanged() end
end)

-- InspectUnit is the Blizzard UI entry point for a player-initiated
-- inspection. Hooking it, rather than INSPECT_READY, avoids recording
-- background inspect-data requests from unrelated addons.
if type(InspectUnit) == "function" and type(hooksecurefunc) == "function" then
    hooksecurefunc("InspectUnit", function(unit)
        if not KnownPlayersDB or not KnownPlayersSettings
            or not KnownPlayersSettings.trackInspects then
            return
        end
        local key, guid
        if type(unit) == "string" then key, guid = GetPlayerKey(unit) end
        if key then
            ns.RememberPlayer(key, "inspect", nil, guid, nil, unit)
        end
    end)
end

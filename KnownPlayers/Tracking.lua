local addonName, ns = ...

-- Identity keys include the realm so identically named characters on
-- different realms cannot overwrite one another.
local function GetPlayerKey(unit)
    if not UnitExists(unit) or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then
        return nil
    end

    local name, realm = UnitFullName(unit)
    name, realm = ns.SafeString(name), ns.SafeString(realm)
    if not name or name == UNKNOWNOBJECT then
        return nil
    end

    if not realm or realm == "" then
        realm = GetNormalizedRealmName()
    end
    if not realm or realm == "" then
        return nil
    end

    return name .. "-" .. realm, ns.SafePlayerGUID(ns.SafeUnitGUID(unit))
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
        local key, guid = GetPlayerKey(prefix .. i)
        if key then
            ns.RememberPlayer(key, category, now, guid)
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
local function NormalizeWhisperName(sender)
    sender = ns.SafeString(sender)
    if not sender then
        return nil
    end

    local name, realm = sender:match("^([^%-]+)%-(.+)$")
    if not name then
        name = sender
    end
    if name == "" then
        return nil
    end

    if not realm or realm == "" then
        realm = GetNormalizedRealmName()
    end
    if not realm or realm == "" then
        return nil
    end

    return name .. "-" .. realm
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

    local key = NormalizeWhisperName(sender)
    if not key then
        return
    end

    -- Do not retain your own character if the client reports a self-whisper.
    local selfName, selfRealm = UnitFullName("player")
    if selfName and (not selfRealm or selfRealm == "") then
        selfRealm = GetNormalizedRealmName()
    end
    if selfName and selfRealm and key == selfName .. "-" .. selfRealm then
        return
    end

    ns.RememberPlayer(key, "whisper", nil, guid)
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
        ns.RememberPlayer(key, "trade", nil, guid)
    end
end)

-- Guild mode: remember everyone listed on the roster, including offline
-- members. A future option may restrict this to directly met guildmates.
local function NormalizeGuildName(name)
    name = ns.SafeString(name)
    if not name then
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

function ns.ScanGuildRoster()
    if not TrackGuildRoster() then return 0 end
    local clubID = GuildClubID()
    if not clubID or KnownPlayersDB.guildRosterClubID ~= clubID then return 0 end
    local selfKey = GuildSelfKey()
    local total = GetNumGuildMembers()
    if not selfKey or not ns.IsAccessibleValue(total) or type(total) ~= "number" then return 0 end
    local now = time()
    local updated = 0

    for i = 1, total do
        local name = GetGuildRosterInfo(i)
        local key = NormalizeGuildName(name)
        if key and key ~= selfKey then
            ns.RememberPlayer(key, "guild", now)
            updated = updated + 1
        end
    end
    return updated
end

local reconcileGuildOnNextUpdate = true
local guildReconcileGeneration = 0

local function ReadGuildSnapshot()
    if not TrackGuildRoster() then return nil end
    local total = GetNumGuildMembers()
    local selfKey = GuildSelfKey()
    if not selfKey or not ns.IsAccessibleValue(total) or type(total) ~= "number"
        or total < 1 then return nil end
    local current = {}
    for i = 1, total do
        local key = NormalizeGuildName(GetGuildRosterInfo(i))
        if not key or current[key] then return nil end
        current[key] = true
    end
    if current[selfKey] then return current, total end
end

local function SameSnapshot(a, b)
    if not a or not b then return false end
    for key in pairs(a) do if not b[key] then return false end end
    for key in pairs(b) do if not a[key] then return false end end
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

local function ReconcileGuildMembership(clubID, members, count)
    local missing, savedGuildCount = 0, 0
    for key, record in pairs(KnownPlayersDB.players) do
        if type(record) == "table" and type(record.categories) == "table" and record.categories.guild then
            savedGuildCount = savedGuildCount + 1
            if not members[key] then missing = missing + 1 end
        end
    end
    -- A truncated roster must not erase a guild's history. For a large
    -- removal, require the current club's member list to corroborate the roster.
    if missing > math.max(2, math.floor(savedGuildCount * 0.1))
        and not ClubRosterMatches(clubID, members, count) then return false end
    ns.ClearPlayerCategory("guild", members)
    return true
end

local function ClearOldGuild()
    guildReconcileGeneration = guildReconcileGeneration + 1
    reconcileGuildOnNextUpdate = true
    -- Wait for a fresh roster for the new guild before reading cached entries.
    KnownPlayersDB.guildRosterClubID = nil
    if ns.ClearPlayerCategory("guild") > 0 then RefreshGuildViews() end
end

local function CheckGuildSwitch(clubID)
    local previous = KnownPlayersDB.guildRosterClubID
    if previous and clubID and previous ~= clubID then ClearOldGuild() end
end

function ns.RefreshGuildList()
    if not TrackGuildRoster() then return false end
    guildReconcileGeneration = guildReconcileGeneration + 1
    reconcileGuildOnNextUpdate = true
    ns.RequestGuildRoster()
    ns.ScanGuildRoster()
    return true
end

function ns.RequestGuildRoster()
    if not KnownPlayersSettings or not KnownPlayersSettings.trackGuild or not IsInGuild() then return end
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
end

local guildFrame = CreateFrame("Frame")
guildFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
guildFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
guildFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
guildFrame:RegisterEvent("INITIAL_CLUBS_LOADED")
guildFrame:SetScript("OnEvent", function(_, event, unit)
    if not KnownPlayersDB or not KnownPlayersSettings then return end
    if event == "PLAYER_GUILD_UPDATE" and ns.SafeString(unit) ~= "player" then return end
    if event == "INITIAL_CLUBS_LOADED" and not IsInGuild() then return end
    local canConfirm = C_Timer and type(C_Timer.After) == "function"
    if event ~= "GUILD_ROSTER_UPDATE" then
        guildReconcileGeneration = guildReconcileGeneration + 1
        reconcileGuildOnNextUpdate = true
        if IsInGuild() then
            CheckGuildSwitch(GuildClubID())
            ns.RequestGuildRoster()
            ns.ScanGuildRoster()
        elseif canConfirm then
            -- Guild APIs can briefly be uninitialized on login or during a switch.
            local generation = guildReconcileGeneration
            C_Timer.After(2, function()
                if generation == guildReconcileGeneration and IsInGuild() == false and not GuildClubID() then
                    ClearOldGuild()
                end
            end)
        end
        return
    end
    if not IsInGuild() then return end
    local clubID = GuildClubID()
    if not clubID then return end
    CheckGuildSwitch(clubID)
    if not TrackGuildRoster() then return end
    if KnownPlayersDB.guildRosterClubID == clubID then
        ns.ScanGuildRoster()
        if ns.RefreshPlayerListWindows then ns.RefreshPlayerListWindows() end
    end
    -- Only reconcile after a roster update and a second matching snapshot.
    if not reconcileGuildOnNextUpdate or not canConfirm then return end
    local snapshot = ReadGuildSnapshot()
    if not snapshot then return end
    local generation = guildReconcileGeneration
    C_Timer.After(2, function()
        if generation ~= guildReconcileGeneration or not reconcileGuildOnNextUpdate
            or GuildClubID() ~= clubID then return end
        local confirmed, count = ReadGuildSnapshot()
        if not SameSnapshot(snapshot, confirmed) then return end
        reconcileGuildOnNextUpdate = not ReconcileGuildMembership(clubID, confirmed, count)
        KnownPlayersDB.guildRosterClubID = clubID
        ns.ScanGuildRoster()
        RefreshGuildViews()
    end)
end)


-- Targeting and inspecting are separate encounters. Neither action is
-- inferred from the other; a player may legitimately have both categories.
local targetFrame = CreateFrame("Frame")
targetFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
targetFrame:SetScript("OnEvent", function()
    if not KnownPlayersDB or not KnownPlayersSettings
        or not KnownPlayersSettings.trackTargets then
        return
    end

    local key, guid = GetPlayerKey("target")
    if key then
        ns.RememberPlayer(key, "target", nil, guid)
    end
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
            ns.RememberPlayer(key, "inspect", nil, guid)
        end
    end)
end

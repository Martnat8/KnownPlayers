local addonName, ns = ...

-- Identity keys include the realm so identically named characters on
-- different realms cannot overwrite one another.
local function GetPlayerKey(unit)
    if not UnitExists(unit) or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then
        return nil
    end

    local name, realm = UnitFullName(unit)
    if not name or name == "" or name == UNKNOWNOBJECT then
        return nil
    end

    if not realm or realm == "" then
        realm = GetNormalizedRealmName()
    end
    if not realm or realm == "" then
        return nil
    end

    return name .. "-" .. realm, UnitGUID(unit)
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
    if type(sender) ~= "string" or sender == "" then
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
    local guid = select(12, ...)
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
    if type(name) ~= "string" or name == "" then
        return nil
    end

    local playerName, realm = name:match("^([^%-]+)%-(.+)$")
    if not playerName then
        playerName = name
    end
    if not realm or realm == "" then
        realm = GetNormalizedRealmName()
    end
    if not realm or realm == "" then
        return nil
    end
    return playerName .. "-" .. realm
end

function ns.ScanGuildRoster()
    if not KnownPlayersDB or not KnownPlayersSettings or not KnownPlayersSettings.trackGuild
        or not IsInGuild() then
        return 0
    end

    local total = GetNumGuildMembers() or 0
    local selfName, selfRealm = UnitFullName("player")
    if selfName and (not selfRealm or selfRealm == "") then
        selfRealm = GetNormalizedRealmName()
    end
    local selfKey = selfName and selfRealm and (selfName .. "-" .. selfRealm) or nil
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

function ns.RequestGuildRoster()
    if not KnownPlayersSettings or not KnownPlayersSettings.trackGuild or not IsInGuild() then
        return
    end
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    end
end

local guildFrame = CreateFrame("Frame")
guildFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
guildFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
guildFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
guildFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_GUILD_UPDATE" and unit and unit ~= "player" then
        return
    end
    if event == "GUILD_ROSTER_UPDATE" then
        ns.ScanGuildRoster()
    else
        -- Ask the server for the full roster. The resulting event handles
        -- asynchronous delivery; an immediate scan also accepts cached data.
        ns.RequestGuildRoster()
        ns.ScanGuildRoster()
    end
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

local addonName, ns = ...

-- Record only hostile player-initiated attacks directed at this character.
-- The combat-log GUID is preferred over textual names for identity matching.
local ATTACK_EVENTS = {
    SWING_DAMAGE = true, SWING_MISSED = true,
    RANGE_DAMAGE = true, RANGE_MISSED = true,
    SPELL_DAMAGE = true, SPELL_MISSED = true,
    SPELL_PERIODIC_DAMAGE = true,
    DAMAGE_SHIELD = true,
}

local function FullKey(name)
    name = ns.SafeString(name)
    if not name then return nil end
    -- Combat log names normally include the realm for cross-realm players.
    if name:find("-", 1, true) then return name end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if type(realm) ~= "string" or realm == "" then return nil end
    return name .. "-" .. realm
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function()
    if not KnownPlayersDB or not KnownPlayersSettings or not KnownPlayersSettings.trackPvP then return end
    if type(CombatLogGetCurrentEventInfo) ~= "function" then return end

    local _, subevent, _, sourceGUID, sourceName, _, _, destGUID = CombatLogGetCurrentEventInfo()
    subevent = ns.SafeString(subevent)
    sourceGUID = ns.SafePlayerGUID(sourceGUID)
    destGUID = ns.SafeString(destGUID)
    local myGUID = ns.SafeUnitGUID("player")
    if not subevent or not ATTACK_EVENTS[subevent] or not sourceGUID
        or not destGUID or not myGUID then return end
    if destGUID ~= myGUID or sourceGUID == destGUID then return end

    local key = FullKey(sourceName)
    if not key then return end
    ns.RememberPlayer(key, "pvp", nil, sourceGUID)
end)

-- Guard registration for client variants that restrict combat-log access.
if type(CombatLogGetCurrentEventInfo) == "function" then
    pcall(frame.RegisterEvent, frame, "COMBAT_LOG_EVENT_UNFILTERED")
end

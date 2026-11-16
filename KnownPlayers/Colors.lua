local addonName, ns = ...

local DEFAULT_ORDER = { "pvp", "guild", "associated", "raid", "party", "trade", "whisper", "inspect", "target" }
local DEFAULT_COLORS = {
    pvp = {1.0, 0.20, 0.20},
    trade = {1.0, 0.82, 0.40}, guild = {0.40, 0.85, 0.55},
    associated = {0.40, 0.67, 1.0}, whisper = {0.72, 0.55, 1.0},
    raid = {1.0, 0.53, 0.30}, party = {0.34, 0.85, 0.82},
    inspect = {0.72, 0.72, 0.72}, target = {1.0, 1.0, 1.0},
}
local TRACK_KEY = {
    pvp = "trackPvP", trade = "trackTrades", guild = "trackGuild", whisper = "trackWhispers",
    target = "trackTargets", inspect = "trackInspects", associated = "trackBattleNetAssociations",
}

function ns.InitializeNameplateColors()
    local settings = KnownPlayersSettings
    settings.nameplateCategoryColors = type(settings.nameplateCategoryColors) == "table" and settings.nameplateCategoryColors or {}
    settings.nameplateColorOrder = type(settings.nameplateColorOrder) == "table" and settings.nameplateColorOrder or {}
    for key, rgb in pairs(DEFAULT_COLORS) do
        local saved = settings.nameplateCategoryColors[key]
        if type(saved) ~= "table" or type(saved[1]) ~= "number" or type(saved[2]) ~= "number" or type(saved[3]) ~= "number" then
            settings.nameplateCategoryColors[key] = {rgb[1], rgb[2], rgb[3]}
        end
    end
    local clean, seen = {}, {}
    for _, key in ipairs(settings.nameplateColorOrder) do
        if DEFAULT_COLORS[key] and not seen[key] then clean[#clean+1] = key; seen[key] = true end
    end
    for _, key in ipairs(DEFAULT_ORDER) do
        if not seen[key] then
            if key == "pvp" then table.insert(clean, 1, key)
            else clean[#clean+1] = key end
            seen[key] = true
        end
    end
    settings.nameplateColorOrder = clean
end

function ns.CategoryTrackingEnabled(category)
    local settings = KnownPlayersSettings
    if category == "party" or category == "raid" then
        return type(settings.trackGroup) == "table" and settings.trackGroup[category] == true
    end
    return settings[TRACK_KEY[category]] == true
end

-- Share the indexed identity/association lookups with the visibility filter.
local function DirectRecord(name, guid)
    return ns.FindDirectRecord and ns.FindDirectRecord(name, guid) or nil
end

local function IsAssociatedAlt(name, guid)
    return ns.CategoryTrackingEnabled("associated")
        and ns.IsAssociatedCharacter and ns.IsAssociatedCharacter(name, guid) or false
end

-- Return first enabled interaction in the user-specified priority order.
-- Alts inherit recognition, not an invented direct interaction history.
function ns.GetNameplateCategory(name, guid)
    if not KnownPlayersDB or not KnownPlayersSettings then return nil end
    local record = DirectRecord(name, guid)
    local associated = IsAssociatedAlt(name, guid)
    for _, category in ipairs(KnownPlayersSettings.nameplateColorOrder or DEFAULT_ORDER) do
        if category == "associated" then
            if associated then return category end
        elseif record and record.categories[category] and ns.CategoryTrackingEnabled(category) then
            return category
        end
    end
    return nil
end

function ns.GetNameplateCategoryColor(category)
    return KnownPlayersSettings.nameplateCategoryColors[category]
        or DEFAULT_COLORS[category] or {1, 1, 1}
end

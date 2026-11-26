local addonName, ns = ...

local DEFAULT_ORDER = { "avoid", "manual", "guild", "associated", "raid", "party", "trade", "whisper", "inspect", "target" }
local DEFAULT_COLORS = {
    trade = {1.0, 0.82, 0.40}, guild = {0.40, 0.85, 0.55},
    associated = {0.40, 0.67, 1.0}, whisper = {0.72, 0.55, 1.0},
    raid = {1.0, 0.53, 0.30}, party = {0.34, 0.85, 0.82},
    inspect = {0.72, 0.72, 0.72}, target = {1.0, 1.0, 1.0},
    manual = {1.0, 0.38, 0.65},
    avoid = {1.0, 0.20, 0.20},
}
-- Independent NPC name colors. No NPC identities or classifications are
-- bundled; the color mapping only applies to QuestieDB's service categories
-- and the user's manually saved NPC types.
local NPC_DEFAULT_COLORS = {
    vendor = {0xC7 / 255, 0xF0 / 255, 0},
    trainer = {0x38 / 255, 0x68 / 255, 0xEF / 255},
    banker = {0x8F / 255, 0xA6 / 255, 0x32 / 255},
    auctioneer = {1, 0xA9 / 255, 0},
    flight = {0, 1, 0xF5 / 255},
    innkeeper = {0xED / 255, 0, 0xDE / 255},
    repair = {0xB8 / 255, 0x79 / 255, 0x2E / 255},
    quest = {0xF8 / 255, 1, 0x9B / 255},
    manual = {0xAC / 255, 0x4A / 255, 1},
}

local NPC_LEGACY_COLORS = {
    vendor = {0.94, 0.81, 0.34},
    trainer = {0.55, 0.73, 1.00},
    banker = {0.40, 0.84, 0.57},
    auctioneer = {1.00, 0.65, 0.33},
    flight = {0.48, 0.85, 0.95},
    innkeeper = {0.88, 0.69, 1.00},
    repair = {1.00, 0.48, 0.40},
    quest = {1.00, 0.95, 0.48},
    manual = {1.00, 0.39, 0.70},
}

-- Existing saved orders take precedence over these defaults.
local NPC_DEFAULT_ORDER = {
    "manual", "flight", "trainer", "banker", "vendor",
    "repair", "innkeeper", "auctioneer", "quest",
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
    if not seen.avoid then
        table.insert(clean, 1, "avoid")
        seen.avoid = true
    end
    for _, key in ipairs(DEFAULT_ORDER) do
        if not seen[key] then
            clean[#clean+1] = key
            seen[key] = true
        end
    end
    settings.nameplateColorOrder = clean
    settings.npcNameplateCategoryColors =
        type(settings.npcNameplateCategoryColors) == "table" and settings.npcNameplateCategoryColors or {}
    local migrateNPCColors = not settings.npcNameplatePaletteVersion
    for key, rgb in pairs(NPC_DEFAULT_COLORS) do
        local saved = settings.npcNameplateCategoryColors[key]
        local legacy = NPC_LEGACY_COLORS[key]
        if type(saved) ~= "table" or type(saved[1]) ~= "number"
            or type(saved[2]) ~= "number" or type(saved[3]) ~= "number"
            or (migrateNPCColors and saved[1] == legacy[1] and saved[2] == legacy[2] and saved[3] == legacy[3]) then
            settings.npcNameplateCategoryColors[key] = {rgb[1], rgb[2], rgb[3]}
        end
    end
    settings.npcNameplatePaletteVersion = settings.npcNameplatePaletteVersion or 1
    -- Validate and migrate the NPC category order: discard unknown/duplicate
    -- keys, then append any categories added by a future addon version.
    local order = type(settings.npcNameplateColorOrder) == "table"
        and settings.npcNameplateColorOrder or {}
    local npcClean, npcSeen = {}, {}
    for _, key in ipairs(order) do
        if NPC_DEFAULT_COLORS[key] and not npcSeen[key] then
            npcClean[#npcClean + 1] = key
            npcSeen[key] = true
        end
    end
    for _, key in ipairs(NPC_DEFAULT_ORDER) do
        if not npcSeen[key] then
            npcClean[#npcClean + 1] = key
            npcSeen[key] = true
        end
    end
    settings.npcNameplateColorOrder = npcClean
end

function ns.GetNPCNameplateCategoryColor(category)
    local saved = KnownPlayersSettings and KnownPlayersSettings.npcNameplateCategoryColors
    return (type(saved) == "table" and saved[category])
        or NPC_DEFAULT_COLORS[category] or {1, 1, 1}
end

function ns.GetNPCNameplateColorOrder()
    local saved = KnownPlayersSettings and KnownPlayersSettings.npcNameplateColorOrder
    return type(saved) == "table" and next(saved) and saved or NPC_DEFAULT_ORDER
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
        elseif ns.PlayerHasCategory(record, category) and ns.CategoryTrackingEnabled(category) then
            return category
        end
    end
    return nil
end

function ns.GetNameplateCategoryColor(category)
    return KnownPlayersSettings.nameplateCategoryColors[category]
        or DEFAULT_COLORS[category] or {1, 1, 1}
end

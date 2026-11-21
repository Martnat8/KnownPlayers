local addonName, ns = ...

-- NPC records are separate from player histories. A Creature GUID includes a
-- stable NPC template ID; its full spawn GUID is not stable across encounters.
-- These are explicitly remembered NPC TYPES, not individual spawned entities.
local function NPCFromUnit(unit)
    if not unit or not UnitExists(unit) or UnitIsPlayer(unit) then return nil end
    local guid = ns.SafeUnitGUID(unit)
    if not guid then return nil end
    local npcID = guid:match("^Creature%-[^%-]+%-[^%-]+%-[^%-]+%-[^%-]+%-(%d+)%-")
    if not npcID then return nil end
    local name = UnitName(unit)
    name = ns.SafeString(name)
    if not name or (ns.IsAccessibleValue(UNKNOWNOBJECT) and name == UNKNOWNOBJECT) then return nil end
    return npcID, name
end

function ns.GetNPCFromUnit(unit)
    return NPCFromUnit(unit)
end

-- QuestieDB supplies automatic NPC classifications; manually remembered NPCs
-- remain an independent, user-maintained list.
local NPC_CATEGORIES = {
    {key="vendor", label="Vendors"},
    {key="trainer", label="Trainers"},
    {key="banker", label="Bankers"},
    {key="auctioneer", label="Auctioneers"},
    {key="flight", label="Flight Masters"},
    {key="innkeeper", label="Innkeepers"},
    {key="repair", label="Repair NPCs"},
    {key="quest", label="Quest NPCs"},
    {key="manual", label="Manually Added"},
}

-- Default precedence matches 0.4.2 for existing users; the saved order
-- overrides it after initialization.
local NPC_COLOR_PRIORITY = {
    "manual", "flight", "banker", "auctioneer", "repair",
    "trainer", "innkeeper", "vendor", "quest",
}

function ns.GetNPCServiceCategories()
    return NPC_CATEGORIES
end

function ns.GetNPCNameplateCategory(id)
    id = tostring(id or "")
    if not id:match("^%d+$") or not KnownPlayersSettings then return nil end
    local enabled = KnownPlayersSettings.npcServiceCategories
    if type(enabled) ~= "table" then return nil end
    local remembered = KnownPlayersDB and type(KnownPlayersDB.npcs) == "table"
        and type(KnownPlayersDB.npcs[id]) == "table"
    -- Manually remembered NPCs still work without QuestieDB or automatic
    -- filtering. QuestieDB roles participate only when filtering is enabled.
    local services
    if KnownPlayersSettings.filterNPCNameplates and ns.GetNPCServiceInfo then
        services = ns.GetNPCServiceInfo(id)
    end
    if not remembered and type(services) ~= "table" then return nil end
    for _, category in ipairs(KnownPlayersSettings.npcNameplateColorOrder or NPC_COLOR_PRIORITY) do
        if enabled[category] then
            if category == "manual" and remembered then return "manual", services ~= nil end
            if category ~= "manual" and type(services) == "table"
                and services[category] then return category, true end
        end
    end
    return nil, services ~= nil
end

-- Overrides are explicit user decisions and supersede automatic category
-- filtering. They do not duplicate or alter QuestieDB's NPC classifications.
function ns.GetNPCVisibilityOverride(id)
    id = tostring(id or "")
    local entry = KnownPlayersDB and type(KnownPlayersDB.npcOverrides) == "table"
        and KnownPlayersDB.npcOverrides[id]
    if type(entry) == "table" and (entry.mode == "show" or entry.mode == "hide") then
        return entry.mode
    end
    return "auto"
end

function ns.SetNPCVisibilityOverride(id, name, mode)
    id = tostring(id or "")
    if not id:match("^%d+$") or (mode ~= "auto" and mode ~= "show" and mode ~= "hide")
        or not KnownPlayersDB or type(KnownPlayersDB.npcOverrides) ~= "table" then return false end
    if mode == "auto" then
        local previous = KnownPlayersDB.npcOverrides[id]
        KnownPlayersDB.npcOverrides[id] = nil
        if type(previous) == "table" then
            ns.OfferRemovalUndo(function()
                if KnownPlayersDB.npcOverrides[id] then return false end
                KnownPlayersDB.npcOverrides[id] = previous
                return true
            end)
        end
    else
        local old = KnownPlayersDB.npcOverrides[id]
        KnownPlayersDB.npcOverrides[id] = {
            name = (type(name) == "string" and name ~= "" and name)
                or (type(old) == "table" and old.name) or ("NPC " .. id),
            mode = mode,
            firstSeen = type(old) == "table" and old.firstSeen or time(),
        }
    end
    if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
    if ns.RefreshPlayerListWindows then ns.RefreshPlayerListWindows() end
    return true
end

function ns.IsKnownNPC(unit, resolvedID)
    local id = resolvedID or NPCFromUnit(unit)
    if not id or ns.GetNPCVisibilityOverride(id) == "hide" then return false end
    return ns.GetNPCVisibilityOverride(id) == "show"
        or ns.GetNPCNameplateCategory(id) ~= nil
end

function ns.RememberNPC(id, name, favorite)
    if type(id) ~= "string" or not id:match("^%d+$")
        or type(name) ~= "string" or name == "" then return false end
    local store = KnownPlayersDB.npcs
    local entry = store[id]
    if type(entry) ~= "table" then
        entry = { firstSeen = time() }
        store[id] = entry
    end
    entry.name = name
    entry.lastSeen = time()
    if favorite then entry.favorite = true end
    if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
    if ns.RefreshPlayerListWindows then ns.RefreshPlayerListWindows() end
    return true
end

function ns.ToggleNPCFavorite(id, name)
    local entry = KnownPlayersDB.npcs[id]
    if type(entry) ~= "table" then return ns.RememberNPC(id, name, true) end
    entry.favorite = not entry.favorite or nil
    if ns.RefreshPlayerListWindows then ns.RefreshPlayerListWindows() end
    return true
end

-- Visiting a remembered NPC again refreshes its inactivity timer; no list
-- changes or UI refreshes are needed when only the timestamp changes.
local recentTargetGUID
local npcTargetFrame = CreateFrame("Frame")
npcTargetFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
npcTargetFrame:SetScript("OnEvent", function()
    local guid = UnitExists("target") and ns.SafeUnitGUID("target")
    if guid and guid == recentTargetGUID then return end
    recentTargetGUID = guid
    local id = NPCFromUnit("target")
    local record = id and KnownPlayersDB and KnownPlayersDB.npcs and KnownPlayersDB.npcs[id]
    if type(record) == "table" then record.lastSeen = time() end
end)

function ns.ForgetNPC(id)
    local entry = KnownPlayersDB.npcs[id]
    if type(entry) ~= "table" then return false end
    KnownPlayersDB.npcs[id] = nil
    ns.OfferRemovalUndo(function()
        local current = KnownPlayersDB.npcs[id]
        if type(current) == "table" then
            current.favorite = (current.favorite or entry.favorite) and true or nil
            if type(entry.firstSeen) == "number" then
                current.firstSeen = math.min(tonumber(current.firstSeen) or entry.firstSeen, entry.firstSeen)
            end
        else
            KnownPlayersDB.npcs[id] = entry
        end
        return true
    end)
    if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
    if ns.RefreshPlayerListWindows then ns.RefreshPlayerListWindows() end
    return true
end

function ns.ClearNPCs()
    local count = ns.CountNPCs()
    ns.ClearRemovalUndo()
    KnownPlayersDB.npcs = {}
    if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
    if ns.RefreshPlayerListWindows then ns.RefreshPlayerListWindows() end
    return count
end

function ns.ClearNPCManagement()
    local seen, count = {}, 0
    for id in pairs(KnownPlayersDB.npcs or {}) do
        seen[id], count = true, count + 1
    end
    for id in pairs(KnownPlayersDB.npcOverrides or {}) do
        if not seen[id] then count = count + 1 end
    end
    ns.ClearRemovalUndo()
    KnownPlayersDB.npcs = {}
    KnownPlayersDB.npcOverrides = {}
    if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
    if ns.RefreshPlayerListWindows then ns.RefreshPlayerListWindows() end
    return count
end

function ns.CountNPCs()
    local count = 0
    for _ in pairs(KnownPlayersDB.npcs or {}) do count = count + 1 end
    return count
end

-- The browser contains saved records only: manual saves and explicit
-- overrides. QuestieDB NPCs are classified on demand, never bulk-copied.
function ns.GetNPCList()
    local entries = {}
    for id, entry in pairs(KnownPlayersDB.npcs or {}) do
        if type(entry) == "table" then
            entries[id] = {
                key = id, name = entry.name or ("NPC " .. id),
                firstSeen = entry.firstSeen, manual = true, favorite = entry.favorite == true,
            }
        end
    end
    for id, entry in pairs(KnownPlayersDB.npcOverrides or {}) do
        if type(entry) == "table" and (entry.mode == "show" or entry.mode == "hide") then
            local result = entries[id]
            if not result then
                result = {key = id, name = entry.name or ("NPC " .. id),
                    firstSeen = entry.firstSeen, manual = false, favorite = false}
                entries[id] = result
            end
        end
    end
    local list = {}
    for id, entry in pairs(entries) do
        entry.override = ns.GetNPCVisibilityOverride(id)
        entry.services = ns.GetNPCServiceInfo and ns.GetNPCServiceInfo(id) or nil
        entry.realm = "" -- Compatibility with generic list/search helpers.
        list[#list + 1] = entry
    end
    return list
end

-- Target-frame right-click customization via Blizzard's tagged menu API.
-- No replacement of secure unit frames or right-click handlers.
local menuRegistered = false
local function AddNPCMenu(_, rootDescription, contextData)
    local unit = contextData and contextData.unit
    if type(unit) ~= "string" or not UnitExists(unit) then unit = "target" end
    local id, name = NPCFromUnit(unit)
    if not id then return end
    rootDescription:CreateDivider()
    rootDescription:CreateTitle("KnownPlayers")
    local saved = KnownPlayersDB.npcs[id]
    if saved then
        rootDescription:CreateButton("Forget NPC", function()
            ns.ForgetNPC(id)
        end)
    else
        rootDescription:CreateButton("Remember NPC", function()
            ns.RememberNPC(id, name)
        end)
    end
    rootDescription:CreateButton(saved and saved.favorite and "Remove from Favorites" or "Add to Favorites", function()
        ns.ToggleNPCFavorite(id, name)
    end)
    local mode = ns.GetNPCVisibilityOverride(id)
    rootDescription:CreateTitle("NPC visibility override")
    for _, choice in ipairs({
        {"auto", "Automatic"}, {"show", "Always Show"}, {"hide", "Always Hide"},
    }) do
        local selectedMode, label = choice[1], choice[2]
        rootDescription:CreateButton((mode == selectedMode and "|cff33ff99[Selected]|r " or "") .. label,
            function() ns.SetNPCVisibilityOverride(id, name, selectedMode) end)
    end
end

function ns.InitializeNPCMenu()
    if menuRegistered then return end
    if type(Menu) ~= "table" or type(Menu.ModifyMenu) ~= "function" then return end
    local ok = pcall(Menu.ModifyMenu, "MENU_UNIT_TARGET", AddNPCMenu)
    if ok then menuRegistered = true end
end

-- The Blizzard menu system may become available after KnownPlayers loads.
local menuEvents = CreateFrame("Frame")
menuEvents:RegisterEvent("PLAYER_LOGIN")
menuEvents:RegisterEvent("ADDON_LOADED")
menuEvents:SetScript("OnEvent", function(_, event, loadedAddon)
    if event == "PLAYER_LOGIN" or loadedAddon == "Blizzard_Menu" then
        ns.InitializeNPCMenu()
    end
end)

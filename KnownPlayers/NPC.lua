local addonName, ns = ...

-- NPC records are separate from player histories. A Creature GUID includes a
-- stable NPC template ID; its full spawn GUID is not stable across encounters.
-- These are explicitly remembered NPC TYPES, not individual spawned entities.
local function NPCFromUnit(unit)
    if not unit or not UnitExists(unit) or UnitIsPlayer(unit) then return nil end
    local guid = UnitGUID(unit)
    if type(guid) ~= "string" then return nil end
    local npcID = guid:match("^Creature%-[^%-]+%-[^%-]+%-[^%-]+%-[^%-]+%-(%d+)%-")
    if not npcID then return nil end
    local name = UnitName(unit)
    if type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT then return nil end
    return npcID, name
end

function ns.GetNPCFromUnit(unit)
    return NPCFromUnit(unit)
end

function ns.IsKnownNPC(unit)
    local id = NPCFromUnit(unit)
    return id ~= nil and type(KnownPlayersDB.npcs[id]) == "table"
end

function ns.RememberNPC(id, name)
    if type(id) ~= "string" or not id:match("^%d+$")
        or type(name) ~= "string" or name == "" then return false end
    local store = KnownPlayersDB.npcs
    local entry = store[id]
    if not entry then
        entry = { firstSeen = time() }
        store[id] = entry
    end
    entry.name = name
    entry.lastSeen = time()
    if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
    if ns.RefreshPlayerListWindows then ns.RefreshPlayerListWindows() end
    return true
end

-- Visiting a remembered NPC again refreshes its inactivity timer; no list
-- changes or UI refreshes are needed when only the timestamp changes.
local recentTargetGUID
local npcTargetFrame = CreateFrame("Frame")
npcTargetFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
npcTargetFrame:SetScript("OnEvent", function()
    local guid = UnitExists("target") and UnitGUID("target")
    if guid and guid == recentTargetGUID then return end
    recentTargetGUID = guid
    local id = NPCFromUnit("target")
    local record = id and KnownPlayersDB and KnownPlayersDB.npcs and KnownPlayersDB.npcs[id]
    if type(record) == "table" then record.lastSeen = time() end
end)

function ns.ForgetNPC(id)
    if type(KnownPlayersDB.npcs[id]) ~= "table" then return false end
    KnownPlayersDB.npcs[id] = nil
    if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
    if ns.RefreshPlayerListWindows then ns.RefreshPlayerListWindows() end
    return true
end

function ns.ClearNPCs()
    local count = ns.CountNPCs()
    KnownPlayersDB.npcs = {}
    if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
    if ns.RefreshPlayerListWindows then ns.RefreshPlayerListWindows() end
    return count
end

function ns.CountNPCs()
    local count = 0
    for _ in pairs(KnownPlayersDB.npcs or {}) do count = count + 1 end
    return count
end

function ns.GetNPCList()
    local list = {}
    for id, entry in pairs(KnownPlayersDB.npcs or {}) do
        if type(entry) == "table" then
            list[#list + 1] = {
                key = id, name = entry.name or ("NPC " .. id),
                realm = "", firstSeen = entry.firstSeen,
            }
        end
    end
    table.sort(list, function(a, b)
        local x, y = a.name:lower(), b.name:lower()
        if x ~= y then return x < y end
        return tonumber(a.key) < tonumber(b.key)
    end)
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
    if KnownPlayersDB.npcs[id] then
        rootDescription:CreateButton("Remove NPC from KnownPlayers", function()
            ns.ForgetNPC(id)
        end)
    else
        rootDescription:CreateButton("Remember NPC", function()
            ns.RememberNPC(id, name)
        end)
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

local addonName, ns = ...

-- Add manual player recognition to Blizzard's unit-portrait context menus.
-- This uses the same Menu.ModifyMenu mechanism as KnownPlayers' NPC menu.
-- Manual additions have their own category, separate from automatic targeting.
local menuRegistered = {}

function ns.GetPlayerFromUnit(unit)
    if not ns.SafeString(unit) or not UnitExists(unit) or not UnitIsPlayer(unit) then
        return nil, "Target another player first."
    end
    local unidentified = "Could not identify the targeted player."
    local isSelf = ns.CompareUnits(unit, "player")
    if isSelf == nil then
        return nil, unidentified
    end
    if isSelf then return nil, "Target another player first." end

    local ok, name, realm = pcall(UnitFullName, unit)
    if not ok or not ns.IsAccessibleValue(realm) then
        return nil, unidentified
    end
    name = ns.SafeString(name)
    if not name or name == UNKNOWNOBJECT then
        return nil, unidentified
    end
    if realm == nil or realm == "" then
        local readRealm, localRealm = pcall(GetNormalizedRealmName)
        if readRealm then realm = localRealm end
    end
    realm = ns.SafeString(realm)
    if not realm then return nil, "Could not identify the player's realm." end
    return name .. "-" .. realm, ns.SafePlayerGUID(ns.SafeUnitGUID(unit)), name, realm
end

local function FindSavedKey(name, guid)
    local key = ns.FindDirectKeyByGUID(guid) or ns.FindDirectKeyByName(name, guid)
    local record = key and ns.GetPlayer(key)
    if ns.HasPlayerCategory(record) then return key, record end
end

local function Refresh()
    if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
    if ns.RefreshPlayerListWindows then ns.RefreshPlayerListWindows() end
end

local function AddPlayerMenu(menuTag, rootDescription, contextData)
    if not KnownPlayersDB or not KnownPlayersSettings then return end
    -- Blizzard uses MENU_UNIT_PLAYER for player portraits on some builds,
    -- rather than MENU_UNIT_TARGET (which works for NPCs). Menu context can
    -- also omit the unit token on the target portrait.
    local unit = ns.SafeString(contextData and contextData.unit)
    if not unit then
        -- Friends and chat menus can omit a unit and refer to someone else.
        if menuTag ~= "MENU_UNIT_TARGET" then return end
        unit = "target"
    end
    local key, guid, _, realm = ns.GetPlayerFromUnit(unit)
    if not key then return end

    local function CurrentUnit()
        local currentKey, currentGUID = ns.GetPlayerFromUnit(unit)
        if currentKey == key and (not guid or guid == currentGUID) then return unit end
    end

    local savedKey, savedRecord = FindSavedKey(key, guid)
    rootDescription:CreateDivider()
    rootDescription:CreateTitle("KnownPlayers")
    if savedKey then
        rootDescription:CreateButton("Why do I know this player?", function()
            if ns.GetPlayer(savedKey) == savedRecord then ns.OpenPlayerHistory(savedKey, CurrentUnit()) end
        end)
        rootDescription:CreateButton("Forget Player", function()
            if ns.GetPlayer(savedKey) == savedRecord and ns.ForgetPlayer(savedKey, true) then
                Refresh()
            end
        end)
    else
        rootDescription:CreateButton("Remember Player", function()
            ns.RememberPlayer(key, "manual", nil, guid, realm, CurrentUnit())
            Refresh()
            if not KnownPlayersSettings.trackManual then
                print("|cff33ff99KnownPlayers:|r Player saved. Enable Manually Added tracking to display its nameplate.")
            end
        end)
    end
end

function ns.InitializePlayerMenu()
    if type(Menu) ~= "table" or type(Menu.ModifyMenu) ~= "function" then return end
    -- NPC portraits use MENU_UNIT_TARGET, but player portraits commonly use
    -- MENU_UNIT_PLAYER. Group and raid portraits have their own menu tags.
    for _, tag in ipairs({
        "MENU_UNIT_TARGET", "MENU_UNIT_PLAYER", "MENU_UNIT_FRIEND",
        "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER",
    }) do
        if not menuRegistered[tag] then
            local ok = pcall(Menu.ModifyMenu, tag, function(_, root, context)
                AddPlayerMenu(tag, root, context)
            end)
            if ok then menuRegistered[tag] = true end
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, loadedAddon)
    if event == "PLAYER_LOGIN" or loadedAddon == "Blizzard_Menu" then
        ns.InitializePlayerMenu()
    end
end)

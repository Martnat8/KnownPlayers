local addonName, ns = ...

-- Add manual player recognition to Blizzard's unit-portrait context menus.
-- This uses the same Menu.ModifyMenu mechanism as KnownPlayers' NPC menu.
-- Manual additions have their own category, separate from automatic targeting.
local menuRegistered = {}

local function PlayerFromUnit(unit)
    if type(unit) ~= "string" or not UnitExists(unit)
        or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then
        return nil
    end
    local name, realm = UnitFullName(unit)
    name = ns.SafeString(name)
    realm = ns.SafeString(realm)
    if not name or name == UNKNOWNOBJECT then
        return nil
    end
    if type(realm) ~= "string" or realm == "" then
        realm = GetNormalizedRealmName()
    end
    if type(realm) ~= "string" or realm == "" then return nil end
    return name .. "-" .. realm, ns.SafePlayerGUID(ns.SafeUnitGUID(unit)), name
end

local function FindSavedKey(name, guid)
    local records = KnownPlayersDB and KnownPlayersDB.players
    if type(records) ~= "table" then return nil end
    if guid and ns.FindDirectKeyByGUID then
        local matched = ns.FindDirectKeyByGUID(guid)
        if matched then return matched end
    end
    local record = records[name]
    if type(record) == "table"
        and (not guid or not record.guid or record.guid == guid) then
        return name
    end
    return nil
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
    local unit = contextData and contextData.unit
    if not ns.SafeString(unit) or not UnitExists(unit) then
        -- For the target portrait, accept either target-menu tag. Never
        -- substitute our target for a party/raid/friend context menu.
        if menuTag ~= "MENU_UNIT_TARGET" and menuTag ~= "MENU_UNIT_PLAYER"
            and menuTag ~= "MENU_UNIT_FRIEND" and menuTag ~= "MENU_UNIT_ENEMY_PLAYER" then
            return
        end
        unit = "target"
    end
    local key, guid, displayName = PlayerFromUnit(unit)
    if not key then return end

    local savedKey = FindSavedKey(key, guid)
    rootDescription:CreateDivider()
    rootDescription:CreateTitle("KnownPlayers")
    if savedKey then
        rootDescription:CreateButton("Forget Player", function()
            if ns.ForgetPlayer(savedKey) then
                Refresh()
            end
        end)
    else
        rootDescription:CreateButton("Remember Player", function()
            ns.RememberPlayer(key, "manual", nil, guid)
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

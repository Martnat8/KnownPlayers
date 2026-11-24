local _, ns = ...

-- Native overhead names cannot be filtered per owner. Suppress those labels
-- while Known Only is active so player and minion names use the nameplate filter.
local nativePlayerNameCVars = {
    "UnitNameFriendlyPlayerName",
    "UnitNameEnemyPlayerName",
    "UnitNameEnemyMinionName",
    "UnitNameEnemyPetName",
    "UnitNameEnemyGuardianName",
    "UnitNameEnemyTotemName",
}
local friendlyMinionCVars = {
    "UnitNameFriendlyMinionName",
    "UnitNameFriendlyPetName",
    "UnitNameFriendlyGuardianName",
    "UnitNameFriendlyTotemName",
}
for _, name in ipairs(friendlyMinionCVars) do
    nativePlayerNameCVars[#nativePlayerNameCVars + 1] = name
end
local firstFriendlyMinionPlateIndex = #friendlyMinionCVars + 1
for _, name in ipairs({
    "nameplateShowFriendlyPlayerMinions",
    "nameplateShowFriendlyPlayerPets",
    "nameplateShowFriendlyPlayerGuardians",
    "nameplateShowFriendlyPlayerTotems",
}) do
    friendlyMinionCVars[#friendlyMinionCVars + 1] = name
end
local nativeNamesShuttingDown = false
local syncingNativeNames = false

local function ReadNativeNameCVar(name)
    local getter = C_CVar and C_CVar.GetCVar or GetCVar
    if type(getter) ~= "function" then return nil end
    local ok, value = pcall(getter, name)
    if ok then return ns.SafeString(value) end
end

local function WriteNativeNameCVar(name, value)
    local setter = C_CVar and C_CVar.SetCVar or SetCVar
    if type(setter) ~= "function" then return false end
    local ok = pcall(setter, name, value)
    return ok and ReadNativeNameCVar(name) == value
end

local function RestoreManagedCVar(key, prior, forced)
    if type(prior) ~= "string" then return true end
    local current = ReadNativeNameCVar(key)
    if current == nil then return false end
    -- Respect any newer value written by WoW, the user, or another addon.
    return current ~= forced or prior == forced or WriteNativeNameCVar(key, prior)
end

local function BackUpNativeNames(keys, backup)
    for _, key in ipairs(keys) do
        if backup[key] == nil then backup[key] = ReadNativeNameCVar(key) end
    end
    return next(backup) and backup or nil
end

local function SuppressNativeNames(keys, onlyEnabled)
    for _, key in ipairs(keys) do
        local current = ReadNativeNameCVar(key)
        if current == "1" or (not onlyEnabled and current ~= nil and current ~= "0") then
            WriteNativeNameCVar(key, "0")
        end
    end
end

local nameplateSettings = {
    player = "nameplateShowFriendlyPlayers",
    npc = "nameplateShowFriendlyNpcs",
    always = "nameplateShowAll",
}

function ns.GetNameplateSetting(key)
    local cvar = nameplateSettings[key]
    local value = cvar and ReadNativeNameCVar(cvar)
    if value == "1" then return true end
    if value == "0" then return false end
end

function ns.EnableNameplateSettings(keys)
    if InCombatLockdown() then return false end
    local applied, changed = true, false
    for _, key in ipairs(keys) do
        local cvar = nameplateSettings[key]
        if cvar and ns.GetNameplateSetting(key) == false then
            if WriteNativeNameCVar(cvar, "1") then
                changed = true
                if key == "npc" and KnownPlayersSettings and type(KnownPlayersSettings.npcCVarBackup) == "table" then
                    KnownPlayersSettings.npcCVarBackup[cvar] = nil
                end
            else
                applied = false
            end
        end
    end
    if changed then ns.RefreshKnownNameplates() end
    return applied
end

function ns.RestoreNativeOverheadNames()
    if not KnownPlayersSettings then return end
    local old = KnownPlayersSettings.overheadNameCVarsBackup
    if type(old) ~= "table" then return end
    local allRestored = true
    for _, name in ipairs(nativePlayerNameCVars) do
        if not RestoreManagedCVar(name, old[name], "0") then allRestored = false end
    end
    if allRestored then KnownPlayersSettings.overheadNameCVarsBackup = nil end
end

function ns.SyncNativeOverheadNames()
    if not KnownPlayersSettings or nativeNamesShuttingDown or syncingNativeNames then return end
    syncingNativeNames = true
    if KnownPlayersSettings.knownOnlyNameplates then
        local old = KnownPlayersSettings.overheadNameCVarsBackup
        if type(old) ~= "table" then old = {} end
        local backup = BackUpNativeNames(nativePlayerNameCVars, old)
        if backup then KnownPlayersSettings.overheadNameCVarsBackup = backup end
        SuppressNativeNames(nativePlayerNameCVars, false)
    else
        ns.RestoreNativeOverheadNames()
    end
    syncingNativeNames = false
end

function ns.GetFriendlyMinionVisibility()
    -- During filtering, only the plate CVars determine what can be shown.
    local first = KnownPlayersSettings.knownOnlyNameplates and firstFriendlyMinionPlateIndex or 1
    local available, visible = false, false
    for i = first, #friendlyMinionCVars do
        local value = ReadNativeNameCVar(friendlyMinionCVars[i])
        available = available or value ~= nil
        visible = visible or value == "1"
    end
    local setter = C_CVar and C_CVar.SetCVar or SetCVar
    return visible, available and type(setter) == "function"
end

function ns.SetFriendlyMinionVisibility(visible)
    if InCombatLockdown() then return false end
    ns.SyncNativeOverheadNames()
    local old = KnownPlayersSettings.knownOnlyNameplates and KnownPlayersSettings.overheadNameCVarsBackup
    local desired, applied = visible and "1" or "0", true
    for _, name in ipairs(friendlyMinionCVars) do
        local current = ReadNativeNameCVar(name)
        if type(old) == "table" and old[name] then
            -- The native labels stay suppressed while filtering. Remember
            -- the user's new choice for when the nameplate filter turns off.
            old[name] = desired
        elseif current and current ~= desired and not WriteNativeNameCVar(name, desired) then
            applied = false
        end
    end
    return applied
end

-- The NPC filter is independent from the player Known Only filter.
-- When active, suppress native overhead labels that would otherwise bypass
-- the per-NPC filter. Friendly NPC plates are enabled explicitly in Settings.
-- Leave the client's dedicated hostile NPC name setting alone.
local npcNameCVars = {
    "UnitNameNPC", "UnitNameInteractiveNPC", "UnitNameFriendlySpecialNPCName",
}
local legacyNPCNameplateCVars = {nameplateSettings.npc, "UnitNameHostleNPC"}
local npcCVarsShuttingDown = false
local npcSyncing = false

function ns.HasUnfilteredOverheadNames(key)
    local cvars = key == "npc" and npcNameCVars or nativePlayerNameCVars
    for _, name in ipairs(cvars) do
        if ReadNativeNameCVar(name) == "1" then return true end
    end
    return false
end

local function RestoreNPCNameplateCVar(key, prior)
    local forced = key == nameplateSettings.npc and "1" or "0"
    return RestoreManagedCVar(key, prior, forced)
end

function ns.RestoreNPCNameplateCVars()
    if not KnownPlayersSettings then return end
    local backup = KnownPlayersSettings.npcCVarBackup
    if type(backup) ~= "table" then return end
    local complete = true
    for key, prior in pairs(backup) do
        if not RestoreNPCNameplateCVar(key, prior) then complete = false end
    end
    if complete then KnownPlayersSettings.npcCVarBackup = nil end
end

function ns.SyncNPCNameplateCVars()
    if not KnownPlayersSettings or npcCVarsShuttingDown or npcSyncing then return end
    npcSyncing = true
    if KnownPlayersSettings.filterNPCNameplates and ns.IsQuestieDBConnected() then
        local backup = KnownPlayersSettings.npcCVarBackup
        if type(backup) ~= "table" then backup = {} end
        -- Restore CVars that older versions forced and retire their backups.
        for _, key in ipairs(legacyNPCNameplateCVars) do
            if backup[key] ~= nil and RestoreNPCNameplateCVar(key, backup[key]) then
                backup[key] = nil
            end
        end
        KnownPlayersSettings.npcCVarBackup = BackUpNativeNames(npcNameCVars, backup)
        SuppressNativeNames(npcNameCVars, true)
    else
        ns.RestoreNPCNameplateCVars()
    end
    npcSyncing = false
end

function ns.OnNameplateCVarUpdate(key)
    key = ns.SafeString(key)
    if not key then return end
    key = key:lower()
    for _, name in ipairs(nativePlayerNameCVars) do
        if key == name:lower() then
            ns.SyncNativeOverheadNames()
            return
        end
    end
    for _, name in ipairs(npcNameCVars) do
        if key == name:lower() then
            ns.SyncNPCNameplateCVars()
            return
        end
    end
end

function ns.ShutdownNameplateCVars()
    nativeNamesShuttingDown, npcCVarsShuttingDown = true, true
    ns.RestoreNativeOverheadNames()
    ns.RestoreNPCNameplateCVars()
end

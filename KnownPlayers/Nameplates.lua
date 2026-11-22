local addonName, ns = ...

-- Experimental player-only nameplate visibility. Never hide the UnitFrame;
-- alpha-zero preserves the frame for click-targeting where the client allows it.
local changedFrames = setmetatable({}, { __mode = "k" })
local plateUnits = {} -- unit token -> frame, needed when the plate is recycled.
local namesOnlyLabels = setmetatable({}, { __mode = "k" })
local namesOnlyGuildLabels = setmetatable({}, { __mode = "k" })
local originalNameColors = setmetatable({}, { __mode = "k" })
local originalVertexColors = setmetatable({}, { __mode = "k" })
local originalNativeNameAlpha = setmetatable({}, { __mode = "k" })
local hoverHooked = setmetatable({}, { __mode = "k" })
local elapsed = 0
local function PlayerHealthBarMode()
    return KnownPlayersSettings and KnownPlayersSettings.playerHealthBarMode or "always"
end

local function NPCHealthBarMode()
    return KnownPlayersSettings and KnownPlayersSettings.npcHealthBarMode or "always"
end

local function HealthBarVisible(mode)
    if mode == "never" then return false end
    if mode == "always" then return true end
    -- "In Combat" refers to this character entering/leaving combat.
    return type(InCombatLockdown) == "function" and InCombatLockdown() or false
end

local function PlayerHealthBarVisible()
    return HealthBarVisible(PlayerHealthBarMode())
end

local CategoryColorForUnit

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
local nativeNameCheckElapsed = 0
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
        local previous = old[name]
        if type(previous) == "string" then
            local current = ReadNativeNameCVar(name)
            -- If something else already changed the setting while we managed
            -- it, do not overwrite that newer user/addon choice on restoration.
            if current == "0" and previous ~= "0" then
                if not WriteNativeNameCVar(name, previous) then
                    allRestored = false
                end
            elseif current == nil then
                allRestored = false
            end
        end
    end
    if allRestored then KnownPlayersSettings.overheadNameCVarsBackup = nil end
end

function ns.SyncNativeOverheadNames()
    if not KnownPlayersSettings or nativeNamesShuttingDown or syncingNativeNames then return end
    syncingNativeNames = true
    if KnownPlayersSettings.knownOnlyNameplates then
        local old = KnownPlayersSettings.overheadNameCVarsBackup
        if type(old) ~= "table" then old = {} end
        for _, name in ipairs(nativePlayerNameCVars) do
            if old[name] == nil then old[name] = ReadNativeNameCVar(name) end
        end
        if next(old) then KnownPlayersSettings.overheadNameCVarsBackup = old end
        for _, name in ipairs(nativePlayerNameCVars) do
            local current = ReadNativeNameCVar(name)
            if current ~= nil and current ~= "0" then
                WriteNativeNameCVar(name, "0")
            end
        end
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
    if type(prior) ~= "string" then return true end
    local current = ReadNativeNameCVar(key)
    if current == nil then return false end
    local forced = key == nameplateSettings.npc and "1" or "0"
    return current ~= forced or prior == forced or WriteNativeNameCVar(key, prior)
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
        for _, key in ipairs(npcNameCVars) do
            if backup[key] == nil then backup[key] = ReadNativeNameCVar(key) end
        end
        KnownPlayersSettings.npcCVarBackup = next(backup) and backup or nil
        for _, key in ipairs(npcNameCVars) do
            if ReadNativeNameCVar(key) == "1" then WriteNativeNameCVar(key, "0") end
        end
    else
        ns.RestoreNPCNameplateCVars()
    end
    npcSyncing = false
end

local function Print(message)
    print("|cff33ff99KnownPlayers:|r " .. message)
end

local function IsProtected(frame)
    return not frame or (frame.IsForbidden and frame:IsForbidden())
end

local function RestoreFrame(frame, allowCombat)
    local alpha = changedFrames[frame]
    if alpha == nil or IsProtected(frame) then return false end
    -- Protected nameplate changes can be blocked while fighting. In the
    -- Combat-only mode we try the alpha restoration safely, keeping the
    -- original alpha for a later retry if the client rejects the call.
    if InCombatLockdown and InCombatLockdown() and not allowCombat then return false end
    local ok = pcall(frame.SetAlpha, frame, alpha)
    if ok then changedFrames[frame] = nil end
    return ok
end

local function RestoreAll()
    for frame in pairs(changedFrames) do RestoreFrame(frame) end
end

local function MakeTransparent(frame)
    if IsProtected(frame) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if changedFrames[frame] == nil then
        local ok, alpha = pcall(frame.GetAlpha, frame)
        if not ok or type(alpha) ~= "number" then return end
        changedFrames[frame] = alpha
    end
    pcall(frame.SetAlpha, frame, 0)
end

-- With health bars visible, use the same custom text layer to support
-- Full/First Name and Guild Name. Only the native name FONT STRING is faded;
-- the health bar and clickable frame remain untouched.
local function RestoreNativeNameAlpha(frame)
    local name = frame and frame.name
    if not name then return end
    local alpha = originalNativeNameAlpha[name]
    if alpha ~= nil then
        pcall(name.SetAlpha, name, alpha)
        originalNativeNameAlpha[name] = nil
    end
end

local function SuppressNativeName(frame)
    local name = frame and frame.name
    if not name or type(name.SetAlpha) ~= "function" then return end
    if originalNativeNameAlpha[name] == nil then
        local ok, alpha = pcall(name.GetAlpha, name)
        if not ok or type(alpha) ~= "number" then return end
        originalNativeNameAlpha[name] = alpha
    end
    pcall(name.SetAlpha, name, 0)
end

-- NPCs have optional role/title text rather than player guild memberships.
-- Only read a tooltip subtitle when the client exposes one safely.
local function GetNPCTitle(unit)
    if not C_TooltipInfo or type(C_TooltipInfo.GetUnit) ~= "function" then return nil end
    local ok, tooltip = pcall(C_TooltipInfo.GetUnit, unit)
    if not ok or type(tooltip) ~= "table" or type(tooltip.lines) ~= "table" then return nil end
    local offset = tonumber(type(GetCVar) == "function" and GetCVar("colorblindMode")) or 0
    local line = tooltip.lines[2 + offset]
    local value = line and line.leftText
    value = ns.SafeString(value)
    if not value then return nil end
    -- Do not mistake level information for an NPC title.
    local levelText = (UNIT_LEVEL_TEMPLATE or "Level %d"):lower()
    local pattern = "^" .. levelText:gsub("%%d", ".+"):gsub("%%s", ".+")
    if value:lower():match(pattern) then return nil end
    return value
end

-- Render names outside the faded UnitFrame so the original plate remains
-- present for targeting. This deliberately avoids hiding protected children.
local function HideNameOnlyLabel(frame)
    RestoreNativeNameAlpha(frame)
    local label = namesOnlyLabels[frame]
    if label then label:Hide() end
    local guild = namesOnlyGuildLabels[frame]
    if guild then guild:Hide() end
end

local function HideAllNameOnlyLabels()
    for frame in pairs(namesOnlyLabels) do HideNameOnlyLabel(frame) end
end

local function MirrorNativeNameFont(label, native, plate, relativeSize)
    local font, size, flags
    if native and type(native.GetFont) == "function" then
        local ok, currentFont, currentSize, currentFlags = pcall(native.GetFont, native)
        if ok then font, size, flags = currentFont, currentSize, currentFlags end
    end
    if font and type(size) == "number" and size > 0 then
        local desiredSize = size * (relativeSize or 1)
        local ok, currentFont, currentSize, currentFlags = pcall(label.GetFont, label)
        if not ok or currentFont ~= font or currentSize ~= desiredSize or currentFlags ~= flags then
            pcall(label.SetFont, label, font, desiredSize, flags)
        end
    end
    -- The native font may be under a separately scaled UnitFrame. The custom
    -- text lives on the outer nameplate, so match effective scale explicitly.
    if native and type(native.GetEffectiveScale) == "function"
        and type(plate.GetEffectiveScale) == "function" then
        local ok1, nativeScale = pcall(native.GetEffectiveScale, native)
        local ok2, plateScale = pcall(plate.GetEffectiveScale, plate)
        if ok1 and ok2 and type(nativeScale) == "number"
            and type(plateScale) == "number" and plateScale > 0 then
            local targetScale = nativeScale / plateScale
            if targetScale > 0 and type(label.GetScale) == "function" then
                local ok3, oldScale = pcall(label.GetScale, label)
                if ok3 and type(oldScale) == "number"
                    and math.abs(oldScale - targetScale) > 0.001 then
                    pcall(label.SetScale, label, targetScale)
                end
            end
        end
    end
end

local function ShowNameOnly(plate, frame, unit, keepHealthBar, isNPC, npcColor)
    if not frame.name then return false end
    -- Blizzard's original label can contain more of the character's
    -- display name than UnitName() on Forever. Read it before fading the frame.
    local name
    if type(frame.name.GetText) == "function" then
        local ok, text = pcall(frame.name.GetText, frame.name)
        if ok then name = ns.SafeString(text) end
    end
    if not name then
        local ok, unitName = pcall(UnitName, unit)
        if ok then name = ns.SafeString(unitName) end
    end
    if not name then return false end
    if KnownPlayersSettings and (isNPC and KnownPlayersSettings.npcNameDisplayMode == "first"
        or not isNPC and KnownPlayersSettings.nameDisplayMode == "first") then
        name = name:match("^(%S+)") or name
    end
    local label = namesOnlyLabels[frame]
    if not label then
        label = plate:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetJustifyH("CENTER")
        -- Anchor to Blizzard's existing name position, but keep the label
        -- outside the transparent UnitFrame so it remains visible.
        label:SetPoint("CENTER", frame.name, "CENTER", 0, 0)
        namesOnlyLabels[frame] = label
    end
    MirrorNativeNameFont(label, frame.name, plate)
    label:SetText(name)
    local displayColor
    if isNPC then
        displayColor = npcColor
        if not displayColor and frame.name and type(frame.name.GetTextColor) == "function" then
            local ok, r, g, b = pcall(frame.name.GetTextColor, frame.name)
            if ok and type(r) == "number" then displayColor = {r, g, b} end
        end
    else
        displayColor = CategoryColorForUnit(unit)
    end
    displayColor = displayColor or {1, 1, 1}
    label:SetTextColor(displayColor[1], displayColor[2], displayColor[3], 1)
    label:Show()

    local guildLabel = namesOnlyGuildLabels[frame]
    local guildName
    if isNPC then
        if KnownPlayersSettings and KnownPlayersSettings.showNPCTitle then
            guildName = GetNPCTitle(unit)
        end
    elseif KnownPlayersSettings and KnownPlayersSettings.showGuildInNamesOnly
        and type(GetGuildInfo) == "function" then
        local ok, result = pcall(GetGuildInfo, unit)
        if ok and ns.SafeString(result) then
            guildName = result
        end
    end
    if guildName then
        if not guildLabel then
            guildLabel = plate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            guildLabel:SetJustifyH("CENTER")
            namesOnlyGuildLabels[frame] = guildLabel
        end
        -- Titles and guild lines inherit the current native name font
        -- at a slightly smaller relative size; no independent fixed font size.
        MirrorNativeNameFont(guildLabel, frame.name, plate, 0.85)
        -- Keep the character and guild labels together, above the health bar.
        -- Anchoring the text (rather than moving the protected health bar) also
        -- preserves Blizzard's normal nameplate hit area.
        guildLabel:ClearAllPoints()
        label:ClearAllPoints()
        if keepHealthBar then
            local healthBar = frame.healthBar or frame.HealthBar
            if healthBar and not IsProtected(healthBar)
                and type(healthBar.IsShown) == "function" and healthBar:IsShown() then
                guildLabel:SetPoint("BOTTOM", healthBar, "TOP", 0, 2)
            else
                -- Fallback if this client's bar isn't exposed on UnitFrame.
                guildLabel:SetPoint("BOTTOM", frame.name, "BOTTOM", 0, 2)
            end
            label:SetPoint("BOTTOM", guildLabel, "TOP", 0, 2)
        else
            label:SetPoint("CENTER", frame.name, "CENTER", 0, 0)
            guildLabel:SetPoint("TOP", label, "BOTTOM", 0, -2)
        end
        guildLabel:SetText("<" .. guildName .. ">")
        guildLabel:SetTextColor(displayColor[1], displayColor[2], displayColor[3], 1)
        guildLabel:SetAlpha(1)
        guildLabel:Show()
    else
        if guildLabel then guildLabel:Hide() end
        -- A recycled plate may have been positioned above a guild line.
        -- Restore the normal name position when the guild line is absent.
        label:ClearAllPoints()
        label:SetPoint("CENTER", frame.name, "CENTER", 0, 0)
    end
    if keepHealthBar then
        local mode = isNPC and NPCHealthBarMode() or PlayerHealthBarMode()
        RestoreFrame(frame, mode == "combat")
        SuppressNativeName(frame)
    else
        RestoreNativeNameAlpha(frame)
        MakeTransparent(frame)
    end
    return true
end

-- Recolor Blizzard's visible character name as well as our names-only label.
-- Preserve the original font color so disabling KnownPlayers restores it.
local function RestoreNameColor(frame)
    if not frame or not frame.name then return end
    local saved = originalNameColors[frame.name]
    if saved then
        pcall(frame.name.SetTextColor, frame.name, saved[1], saved[2], saved[3], saved[4])
        originalNameColors[frame.name] = nil
    end
    local vertex = originalVertexColors[frame.name]
    if vertex and type(frame.name.SetVertexColor) == "function" then
        pcall(frame.name.SetVertexColor, frame.name, vertex[1], vertex[2], vertex[3], vertex[4])
        originalVertexColors[frame.name] = nil
    end
end

local function SetNameColor(frame, color)
    if not frame or not frame.name or type(frame.name.SetTextColor) ~= "function" then return end
    local label = frame.name
    if not originalNameColors[label] and type(label.GetTextColor) == "function" then
        local ok, r, g, b, a = pcall(label.GetTextColor, label)
        if ok and type(r) == "number" then
            originalNameColors[label] = {r, g, b, type(a) == "number" and a or 1}
        end
    end
    if not originalVertexColors[label] and type(label.GetVertexColor) == "function" then
        local ok, r, g, b, a = pcall(label.GetVertexColor, label)
        if ok and type(r) == "number" then
            originalVertexColors[label] = {r, g, b, type(a) == "number" and a or 1}
        end
    end
    pcall(label.SetTextColor, label, color[1], color[2], color[3], 1)
    -- Blizzard may override vertex color on hover, independently of text color.
    if type(label.SetVertexColor) == "function" then
        pcall(label.SetVertexColor, label, color[1], color[2], color[3], 1)
    end
end

CategoryColorForUnit = function(unit)
    if not ns.GetNameplateCategory then return nil end
    local n, r = UnitFullName(unit)
    n, r = ns.SafeString(n), ns.SafeString(r)
    if not n then return nil end
    if type(r) ~= "string" or r == "" then
        r = type(GetNormalizedRealmName) == "function" and GetNormalizedRealmName() or nil
    end
    if type(r) ~= "string" or r == "" then return nil end
    local category = ns.GetNameplateCategory(n .. "-" .. r, ns.SafePlayerGUID(ns.SafeUnitGUID(unit)))
    if category then return ns.GetNameplateCategoryColor(category) end
end

local function RestoreAllNameColors()
    for label, color in pairs(originalNameColors) do
        if label and type(label.SetTextColor) == "function" then
            pcall(label.SetTextColor, label, color[1], color[2], color[3], color[4])
        end
        originalNameColors[label] = nil
    end
    for label, color in pairs(originalVertexColors) do
        if label and type(label.SetVertexColor) == "function" then
            pcall(label.SetVertexColor, label, color[1], color[2], color[3], color[4])
        end
        originalVertexColors[label] = nil
    end
end

-- Reapply just the name color after Blizzard's mouseover/name-update processing.
-- Do not change visibility or interact with protected nameplate frames here.
local function ReapplyNormalNameColor(frame, unit)
    if not KnownPlayersSettings or not PlayerHealthBarVisible() then return end
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit)
        or UnitIsUnit(unit, "player") or IsProtected(frame) then return end
    local color = CategoryColorForUnit(unit)
    if color then SetNameColor(frame, color) end
    if namesOnlyLabels[frame] and namesOnlyLabels[frame]:IsShown() then
        SuppressNativeName(frame)
    end
end

local function HookPlateHover(plate, frame)
    if not hoverHooked[frame] and type(frame.HookScript) == "function" then
        local ok = pcall(frame.HookScript, frame, "OnEnter", function(self)
            local unit = plate.unitToken or self.unit
            ReapplyNormalNameColor(self, unit)
        end)
        if ok then hoverHooked[frame] = true end
    end
    if not hoverHooked[plate] and type(plate.HookScript) == "function" then
        local ok = pcall(plate.HookScript, plate, "OnEnter", function(self)
            local current = self.UnitFrame
            if current then ReapplyNormalNameColor(current, self.unitToken) end
        end)
        if ok then hoverHooked[plate] = true end
    end
end

local function GetPlateList()
    if C_NamePlate and type(C_NamePlate.GetNamePlates) == "function" then
        return C_NamePlate.GetNamePlates() or {}
    end
    return {}
end

local function FindTargetPlate()
    if not UnitExists("target") or not UnitIsPlayer("target") then
        return nil, "Target another player first."
    end
    for _, plate in ipairs(GetPlateList()) do
        local unit = plate.unitToken
        if unit and UnitExists(unit) and UnitIsUnit(unit, "target") then return plate end
    end
    return nil, "Target has no visible nameplate. Enable player nameplates and move closer."
end

local function PlayerKey(name, realm)
    name, realm = ns.SafeString(name), ns.SafeString(realm)
    if not name or name == UNKNOWNOBJECT then return nil end
    if not realm and type(GetNormalizedRealmName) == "function" then
        realm = ns.SafeString(GetNormalizedRealmName())
    end
    return realm and name .. "-" .. realm
end

local function IsRecognized(unit)
    -- Leave the plate visible when the game can't identify the player.
    local key = PlayerKey(UnitFullName(unit))
    if not key then return true end
    local guid = ns.SafePlayerGUID(ns.SafeUnitGUID(unit))
    return ns.IsKnownOrAssociated(key, guid)
end

local function IsRecognizedMinion(unit)
    if type(UnitOwnerGUID) ~= "function" then return true end
    local ok, guid = pcall(UnitOwnerGUID, unit)
    local owner = ok and ns.SafePlayerGUID(guid)
    if not owner or owner == ns.SafeUnitGUID("player") then return true end
    if ns.IsKnownOrAssociated(nil, owner) then return true end

    -- Older player records may only have a name and realm.
    if type(UnitNameFromGUID) ~= "function" then return false end
    local found, name, realm = pcall(UnitNameFromGUID, owner)
    local key = found and PlayerKey(name, realm)
    return key and ns.IsKnownOrAssociated(key, owner) or false
end

local function IsNonAttackableNPC(unit)
    local ok, attackable = pcall(UnitCanAttack, "player", unit)
    return ok and ns.IsAccessibleValue(attackable) and attackable == false
end

function ns.RefreshKnownNameplates()
    if not KnownPlayersSettings then return end
    local knownOnly = KnownPlayersSettings.knownOnlyNameplates
    local playerMode, npcMode = PlayerHealthBarMode(), NPCHealthBarMode()
    local namesOnly, npcShowBar = not HealthBarVisible(playerMode), HealthBarVisible(npcMode)
    -- Even with full nameplates and no visibility filter, refresh the
    -- original Blizzard name text colors for recognized characters.

    local inCombat = InCombatLockdown and InCombatLockdown()
    if inCombat and playerMode ~= "combat" and npcMode ~= "combat" then return end
    for _, plate in ipairs(GetPlateList()) do
        local unit = plate.unitToken
        local frame = plate.UnitFrame
        local accessible = unit and frame and not IsProtected(frame)
            and not (inCombat and frame.IsProtected and frame:IsProtected())
        local exists = accessible and UnitExists(unit)
        local player = exists and UnitIsPlayer(unit)
        local minion = exists and not player and ns.IsPlayerMinion(unit)
        local allowCombat = exists and (player and playerMode == "combat"
            or not player and not minion and npcMode == "combat")
        if accessible and (not inCombat or allowCombat) then
            -- If a frame was recycled from an unknown to a known player,
            -- restore its original alpha before evaluating the new occupant.
            local lastFrame = plateUnits[unit]
            if lastFrame and lastFrame ~= frame then
                HideNameOnlyLabel(lastFrame)
                RestoreFrame(lastFrame)
                RestoreNameColor(lastFrame)
            end
            plateUnits[unit] = frame
            HookPlateHover(plate, frame)
            if player and not UnitIsUnit(unit, "player") then
                local visible = not knownOnly or IsRecognized(unit)
                if not visible then
                    HideNameOnlyLabel(frame)
                    RestoreNameColor(frame)
                    MakeTransparent(frame)
                elseif namesOnly then
                    RestoreNameColor(frame)
                    if not ShowNameOnly(plate, frame, unit) then
                        -- Fail open if the name cannot be displayed.
                        HideNameOnlyLabel(frame)
                        RestoreFrame(frame)
                    end
                else
                    -- Keep the normal health bar, but render the same custom
                    -- character/guild labels used by Names Only mode.
                    RestoreFrame(frame, allowCombat)
                    local color = CategoryColorForUnit(unit)
                    if color then SetNameColor(frame, color)
                    else RestoreNameColor(frame) end
                    -- Preserve Blizzard's actual font/scale/placement when
                    -- neither first-name mode nor a guild line is requested.
                    if KnownPlayersSettings.nameDisplayMode ~= "first"
                        and not KnownPlayersSettings.showGuildInNamesOnly then
                        HideNameOnlyLabel(frame)
                    elseif not ShowNameOnly(plate, frame, unit, true) then
                        HideNameOnlyLabel(frame)
                    end
                end
            elseif minion then
                HideNameOnlyLabel(frame)
                RestoreNameColor(frame)
                if knownOnly and not IsRecognizedMinion(unit) then MakeTransparent(frame)
                else RestoreFrame(frame) end
            elseif exists and not player then
                -- Creature identity is read only once per plate per refresh.
                -- Protected or unrecognized GUIDs are left visible (fail open).
                local npcID = ns.GetNPCFromUnit and ns.GetNPCFromUnit(unit)
                local category, classified
                if npcID then
                    category, classified = ns.GetNPCNameplateCategory(npcID)
                end
                local override = npcID and ns.GetNPCVisibilityOverride
                    and ns.GetNPCVisibilityOverride(npcID) or "auto"
                RestoreNameColor(frame)
                if npcID and (override == "hide"
                    or (override ~= "show" and classified and not category
                        and IsNonAttackableNPC(unit))) then
                    HideNameOnlyLabel(frame)
                    MakeTransparent(frame)
                elseif npcID and (category or override == "show") then
                    local color = category and ns.GetNPCNameplateCategoryColor(category)
                    if npcShowBar and KnownPlayersSettings.npcNameDisplayMode ~= "first"
                        and not KnownPlayersSettings.showNPCTitle then
                        -- Standard text uses Blizzard's own label. Only name
                        -- color changes; original font and layout remain native.
                        HideNameOnlyLabel(frame)
                        RestoreFrame(frame, allowCombat)
                        if color then SetNameColor(frame, color) end
                    elseif not ShowNameOnly(plate, frame, unit, npcShowBar, true, color) then
                        HideNameOnlyLabel(frame)
                        RestoreFrame(frame)
                    end
                else
                    HideNameOnlyLabel(frame)
                    RestoreFrame(frame)
                end
            else
                HideNameOnlyLabel(frame)
                RestoreFrame(frame)
                RestoreNameColor(frame) -- Unfiltered NPCs, pets, and other units.
            end
        end
    end
end

function ns.SetKnownOnlyNameplates(enabled)
    if not KnownPlayersSettings then return end
    KnownPlayersSettings.knownOnlyNameplates = enabled and true or false
    ns.SyncNativeOverheadNames()
    ns.RefreshKnownNameplates()
end

function ns.SetPlayerHealthBarMode(mode)
    if not KnownPlayersSettings or (mode ~= "always" and mode ~= "combat" and mode ~= "never") then
        return
    end
    KnownPlayersSettings.playerHealthBarMode = mode
    KnownPlayersSettings.namesOnlyNameplates = mode == "never"
    ns.RefreshKnownNameplates()
end

function ns.SetNPCHealthBarMode(mode)
    if not KnownPlayersSettings or (mode ~= "always" and mode ~= "combat" and mode ~= "never") then
        return
    end
    KnownPlayersSettings.npcHealthBarMode = mode
    KnownPlayersSettings.npcNamesOnlyNameplates = mode == "never"
    ns.RefreshKnownNameplates()
end

-- Legacy entry point retained for compatibility with previously shipped code.
function ns.SetNamesOnlyNameplates(enabled)
    ns.SetPlayerHealthBarMode(enabled and "never" or "always")
end

function ns.TestTargetNameplate(hide)
    if InCombatLockdown and InCombatLockdown() then
        Print("Nameplate test is disabled during combat.")
        return
    end
    if KnownPlayersSettings and (KnownPlayersSettings.knownOnlyNameplates
        or not PlayerHealthBarVisible()) then
        Print("Disable both nameplate display options before the manual test.")
        return
    end
    local plate, err = FindTargetPlate()
    if not plate then Print(err); return end
    local frame = plate.UnitFrame
    if not frame or type(frame.SetAlpha) ~= "function" then
        Print("Could not access the target nameplate UnitFrame.")
        return
    end
    if IsProtected(frame) then Print("Target nameplate is restricted by the client."); return end
    if hide then
        MakeTransparent(frame)
        Print("Applied transparency to target nameplate (test only).")
    else
        if RestoreFrame(frame) then Print("Restored target nameplate appearance.")
        else Print("This target nameplate was not changed by the test.") end
    end
end

-- The client may redraw the native name after the category color is applied.
-- Hook the normal Blizzard update when it is available; leave a periodic
-- refresh as fallback for Forever-specific frame updates.
if type(hooksecurefunc) == "function" and type(CompactUnitFrame_UpdateName) == "function" then
    hooksecurefunc("CompactUnitFrame_UpdateName", function(updatedFrame)
        if not updatedFrame then return end
        local unit = updatedFrame.unit
        if not ns.SafeString(unit) or not unit:match("^nameplate") then return end
        ReapplyNormalNameColor(updatedFrame, unit)
    end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CVAR_UPDATE")
frame:SetScript("OnEvent", function(_, event, unit)
    if event == "ADDON_LOADED" then
        if unit == "QuestieDB" then
            ns.SyncNPCNameplateCVars()
            ns.RefreshKnownNameplates()
        end
        return
    end
    if event == "PLAYER_LOGOUT" then
        nativeNamesShuttingDown = true
        ns.RestoreNativeOverheadNames()
        npcCVarsShuttingDown = true
        ns.RestoreNPCNameplateCVars()
        HideAllNameOnlyLabels()
        RestoreAll()
        RestoreAllNameColors()
        return
    end
    if event == "CVAR_UPDATE" then
        -- If the native names are turned back on in WoW's settings, keep the
        -- active filter consistent. Do not change unrelated CVars.
        if type(unit) == "string" then
            for _, name in ipairs(nativePlayerNameCVars) do
                if unit:lower() == name:lower() then
                    ns.SyncNativeOverheadNames()
                    break
                end
            end
            for _, name in ipairs(npcNameCVars) do
                if unit:lower() == name:lower() then
                    ns.SyncNPCNameplateCVars()
                    break
                end
            end
        end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        -- Re-evaluate health-bar mode on combat transitions. Protected
        -- nameplates may require deferred updates until combat ends.
        ns.RefreshKnownNameplates()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        ns.SyncNativeOverheadNames()
        ns.SyncNPCNameplateCVars()
    end
    if event == "NAME_PLATE_UNIT_REMOVED" then
        -- Forever may clear the unit-to-nameplate mapping before this event.
        local previous = plateUnits[unit]
        if previous then
            HideNameOnlyLabel(previous)
            RestoreFrame(previous)
            RestoreNameColor(previous)
        end
        plateUnits[unit] = nil
    end
    ns.RefreshKnownNameplates()
end)
frame:SetScript("OnUpdate", function(_, delta)
    if not KnownPlayersSettings then return end
    nativeNameCheckElapsed = nativeNameCheckElapsed + delta
    if nativeNameCheckElapsed >= 5 then
        nativeNameCheckElapsed = 0
        ns.SyncNativeOverheadNames()
        ns.SyncNPCNameplateCVars()
    end
    elapsed = elapsed + delta
    if elapsed >= 0.75 then
        elapsed = 0
        ns.RefreshKnownNameplates()
    end
end)

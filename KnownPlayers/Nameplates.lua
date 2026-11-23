local addonName, ns = ...

-- Alpha-zero leaves the UnitFrame available for click-targeting where allowed.
local changedFrames = setmetatable({}, { __mode = "k" })
local plateUnits = {} -- unit token -> outer plate and its current pooled UnitFrame
local nameLabels = setmetatable({}, { __mode = "k" }) -- owned by the outer plate
local activeNameLabels = {}
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

local function IsCombatRestricted(frame)
    return InCombatLockdown and InCombatLockdown() and frame.IsProtected and frame:IsProtected()
end

local function ReadAppearanceValue(getter, object, ...)
    if type(getter) ~= "function" then return nil end
    local ok, value = pcall(getter, object, ...)
    if ok and ns.IsAccessibleValue(value) then return value end
end

local function RestoreFrame(frame, allowCombat)
    local alpha = changedFrames[frame]
    if alpha == nil or IsProtected(frame) then return false end
    -- Protected nameplate changes can be blocked while fighting. In the
    -- Combat-only mode we try the alpha restoration safely, keeping the
    -- original alpha for a later retry if the client rejects the call.
    if InCombatLockdown and InCombatLockdown() and not allowCombat then return false end
    local current = ReadAppearanceValue(frame.GetAlpha, frame)
    if type(current) == "number" and current ~= 0 then
        changedFrames[frame] = nil
        return false -- Blizzard already set the alpha for this plate.
    end
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
    local alpha = ReadAppearanceValue(frame.GetAlpha, frame)
    if type(alpha) ~= "number" or alpha == 0 then return end
    if pcall(frame.SetAlpha, frame, 0) then changedFrames[frame] = alpha end
end

-- With health bars visible, use the same custom text layer to support
-- Full/First Name and Guild Name. Only the native name FONT STRING is faded;
-- the health bar and clickable frame remain untouched.
local function RestoreNativeNameAlpha(frame)
    local name = not IsProtected(frame) and not IsCombatRestricted(frame) and frame.name
    if not name then return end
    local alpha = originalNativeNameAlpha[name]
    if alpha == nil then return end
    local current = ReadAppearanceValue(name.GetAlpha, name)
    if (type(current) == "number" and current ~= 0) or pcall(name.SetAlpha, name, alpha) then
        originalNativeNameAlpha[name] = nil
    end
end

local function SuppressNativeName(frame)
    local name = frame and frame.name
    if not name or type(name.SetAlpha) ~= "function" then return end
    local alpha = ReadAppearanceValue(name.GetAlpha, name)
    if type(alpha) ~= "number" or alpha == 0 then return end
    if pcall(name.SetAlpha, name, 0) then originalNativeNameAlpha[name] = alpha end
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

local function HideNameLabels(plate, frame)
    RestoreNativeNameAlpha(frame)
    local labels = activeNameLabels[plate]
    if not labels or labels.frame ~= frame then return end
    labels.name:Hide()
    labels.name:ClearAllPoints()
    if labels.subtitle then
        labels.subtitle:Hide()
        labels.subtitle:ClearAllPoints()
    end
    labels.unit, labels.frame = nil, nil
    activeNameLabels[plate] = nil
end

local function CreateNameLabel(plate, fontObject)
    local label = plate:CreateFontString(nil, "OVERLAY", fontObject)
    label:SetJustifyH("CENTER")
    if label.SetSmoothScaling then label:SetSmoothScaling(true) end
    label:Hide()
    return label
end

local function MirrorNativeNameFont(label, native, relativeSize)
    if type(native.GetFont) ~= "function" then return end
    local ok, font, size, flags = pcall(native.GetFont, native)
    if not ok or not ns.IsAccessibleValue(font) or not ns.IsAccessibleValue(size)
        or not ns.IsAccessibleValue(flags) then return end
    -- Forever can set the actual text height independently of the font asset.
    local height = ReadAppearanceValue(native.GetFontHeight, native, false)
    if type(height) == "number" and height > 0 then size = height end
    if font and type(size) == "number" and size > 0 then
        local desiredSize = size * (relativeSize or 1)
        local currentFont, currentSize, currentFlags = label:GetFont()
        if currentFont ~= font or currentSize ~= desiredSize or currentFlags ~= flags then
            pcall(label.SetFont, label, font, desiredSize, flags)
        end
    end
end

local function ApplyLabelAppearance(label, scale, textScale, alpha)
    if label.GetScale and label.SetScale and math.abs(label:GetScale() - scale) > 0.001 then
        label:SetScale(scale)
    end
    if label.GetTextScale and label.SetTextScale and math.abs(label:GetTextScale() - textScale) > 0.001 then
        label:SetTextScale(textScale)
    end
    if math.abs(label:GetAlpha() - alpha) > 0.001 then label:SetAlpha(alpha) end
end

local function UpdateNameLabelAppearance(plate, labels)
    local frame = labels.frame
    local current = not IsProtected(plate) and plate.UnitFrame == frame
        and ns.SafeString(plate.unitToken) == labels.unit and not IsProtected(frame)
    local native = current and frame.name
    local visible = native and not labels.behindCamera
        and ReadAppearanceValue(frame.IsVisible, frame) ~= false
    labels.name:SetShown(visible == true)
    if labels.subtitle then labels.subtitle:SetShown(visible == true and labels.hasSubtitle) end
    if not visible then return end

    -- The outer plate supplies the distance fade and scale. Match any extra
    -- scale or opacity that Blizzard applies to the UnitFrame or its name.
    local nativeScale = ReadAppearanceValue(native.GetEffectiveScale, native)
    local plateScale = ReadAppearanceValue(plate.GetEffectiveScale, plate)
    local scale = nativeScale and nativeScale > 0 and plateScale and plateScale > 0
        and nativeScale / plateScale or 1
    local textScale = ReadAppearanceValue(native.GetTextScale, native) or 1
    local frameAlpha = changedFrames[frame] or ReadAppearanceValue(frame.GetAlpha, frame) or 1
    local nameAlpha = originalNativeNameAlpha[native] or ReadAppearanceValue(native.GetAlpha, native) or 1
    local alpha = frameAlpha * nameAlpha
    ApplyLabelAppearance(labels.name, scale, textScale, alpha)
    if labels.hasSubtitle then ApplyLabelAppearance(labels.subtitle, scale, textScale, alpha) end
end

local function GetNameSubtitle(unit, isNPC)
    if isNPC then
        if KnownPlayersSettings.showNPCTitle then return GetNPCTitle(unit) end
    elseif KnownPlayersSettings.showGuildInNamesOnly then
        return ns.SafeString(ReadAppearanceValue(GetGuildInfo, unit))
    end
end

local function ShowNameOnly(plate, frame, unit, keepHealthBar, isNPC, npcColor)
    if not frame.name then return false end
    local firstName = isNPC and KnownPlayersSettings.npcNameDisplayMode == "first"
        or not isNPC and KnownPlayersSettings.nameDisplayMode == "first"
    local subtitle = GetNameSubtitle(unit, isNPC)
    if keepHealthBar and not firstName and not subtitle then return false end

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
    if firstName then name = name:match("^(%S+)") or name end
    -- The UnitFrame can move between outer plates. Keep the text outside the
    -- faded UnitFrame and allocate it once per outer plate.
    local labels = nameLabels[plate]
    if not labels then
        labels = {name = CreateNameLabel(plate, "GameFontNormal")}
        nameLabels[plate] = labels
    end
    local plateManager = C_NamePlateManager
    local behindCamera = ReadAppearanceValue(plateManager and plateManager.IsNamePlateUnitBehindCamera, unit)
    if behindCamera ~= nil or labels.unit ~= unit or labels.frame ~= frame then
        labels.behindCamera = behindCamera == true
    end
    labels.unit, labels.frame = unit, frame
    activeNameLabels[plate] = labels
    local label = labels.name
    MirrorNativeNameFont(label, frame.name)
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
    local subtitleLabel = labels.subtitle
    labels.hasSubtitle = subtitle ~= nil
    label:ClearAllPoints()
    if subtitle then
        if not subtitleLabel then
            subtitleLabel = CreateNameLabel(plate, "GameFontNormalSmall")
            labels.subtitle = subtitleLabel
        end
        -- Titles and guild lines inherit the current native name font
        -- at a slightly smaller relative size; no independent fixed font size.
        MirrorNativeNameFont(subtitleLabel, frame.name, 0.85)
        -- Keep the name and subtitle together, above the health bar.
        -- Anchoring the text (rather than moving the protected health bar) also
        -- preserves Blizzard's normal nameplate hit area.
        subtitleLabel:ClearAllPoints()
        if keepHealthBar then
            local healthBar = frame.healthBar or frame.HealthBar
            if healthBar and not IsProtected(healthBar)
                and type(healthBar.IsShown) == "function" and healthBar:IsShown() then
                subtitleLabel:SetPoint("BOTTOM", healthBar, "TOP", 0, 2)
            else
                -- Fallback if this client's bar isn't exposed on UnitFrame.
                subtitleLabel:SetPoint("BOTTOM", frame.name, "BOTTOM", 0, 2)
            end
            label:SetPoint("BOTTOM", subtitleLabel, "TOP", 0, 2)
        else
            label:SetPoint("CENTER", frame.name, "CENTER", 0, 0)
            subtitleLabel:SetPoint("TOP", label, "BOTTOM", 0, -2)
        end
        subtitleLabel:SetText("<" .. subtitle .. ">")
        subtitleLabel:SetTextColor(displayColor[1], displayColor[2], displayColor[3], 1)
    else
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
    labels.replacesNativeName = keepHealthBar
    UpdateNameLabelAppearance(plate, labels)
    return true
end

-- Recolor Blizzard's visible character name as well as our names-only label.
-- Preserve the original font color so disabling KnownPlayers restores it.
local function RestoreNameColor(frame)
    if IsProtected(frame) or IsCombatRestricted(frame) or not frame.name then return end
    local saved = originalNameColors[frame.name]
    if saved and pcall(frame.name.SetTextColor, frame.name, saved[1], saved[2], saved[3], saved[4]) then
        originalNameColors[frame.name] = nil
    end
    local vertex = originalVertexColors[frame.name]
    if vertex and pcall(frame.name.SetVertexColor, frame.name, vertex[1], vertex[2], vertex[3], vertex[4]) then
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
    local ok, n, r = pcall(UnitFullName, unit)
    if not ok or not ns.IsAccessibleValue(r) then return nil end
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

-- Blizzard can redraw the native label during mouseover and name updates.
local function ReapplyNormalNameColor(frame, unit)
    if not KnownPlayersSettings or not unit or IsProtected(frame) or IsCombatRestricted(frame) then return end
    local binding = plateUnits[unit]
    local plate = binding and binding.plate
    local labels = plate and activeNameLabels[plate]
    if labels and labels.frame == frame and not IsProtected(plate)
        and plate.UnitFrame == frame and ns.SafeString(plate.unitToken) == unit
        and labels.replacesNativeName then
        SuppressNativeName(frame)
    end
    if PlayerHealthBarVisible() and UnitExists(unit) and UnitIsPlayer(unit) and ns.CompareUnits(unit, "player") == false then
        local color = CategoryColorForUnit(unit)
        if color then SetNameColor(frame, color) end
    end
end

local function HookPlateHover(plate, frame)
    if not hoverHooked[frame] and type(frame.HookScript) == "function" then
        local ok = pcall(frame.HookScript, frame, "OnEnter", function(self)
            ReapplyNormalNameColor(self, ns.SafeString(self.unit))
        end)
        if ok then hoverHooked[frame] = true end
    end
    if not hoverHooked[plate] and type(plate.HookScript) == "function" then
        local ok = pcall(plate.HookScript, plate, "OnEnter", function(self)
            local current = self.UnitFrame
            if current then ReapplyNormalNameColor(current, ns.SafeString(self.unitToken)) end
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
        local unit = not IsProtected(plate) and ns.SafeString(plate.unitToken)
        if unit and UnitExists(unit) and ns.CompareUnits(unit, "target") == true then return plate end
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
    local ok, name, realm = pcall(UnitFullName, unit)
    local key = ok and ns.IsAccessibleValue(realm) and PlayerKey(name, realm)
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

local function ReleasePlate(unit, binding)
    local plate, frame = binding.plate, binding.frame
    HideNameLabels(plate, frame)
    RestoreFrame(frame)
    RestoreNameColor(frame)
    plateUnits[unit] = nil
end

function ns.RefreshKnownNameplates()
    if not KnownPlayersSettings then return end
    local knownOnly = KnownPlayersSettings.knownOnlyNameplates
    local playerMode, npcMode = PlayerHealthBarMode(), NPCHealthBarMode()
    local namesOnly, npcShowBar = not HealthBarVisible(playerMode), HealthBarVisible(npcMode)
    -- Even with full nameplates and no visibility filter, refresh the
    -- original Blizzard name text colors for recognized characters.

    local platesByUnit = {}
    for _, plate in ipairs(GetPlateList()) do
        local unit = not IsProtected(plate) and ns.SafeString(plate.unitToken)
        if unit then platesByUnit[unit] = plate end
    end
    -- Clear stale bindings before rendering any newly assigned pooled frame.
    -- This also catches plates that disappear between the add/remove events.
    for unit, binding in pairs(plateUnits) do
        if platesByUnit[unit] ~= binding.plate or binding.plate.UnitFrame ~= binding.frame
            or not UnitExists(unit) then
            ReleasePlate(unit, binding)
        end
    end

    local inCombat = InCombatLockdown and InCombatLockdown()
    if inCombat and playerMode ~= "combat" and npcMode ~= "combat" then return end
    for unit, plate in pairs(platesByUnit) do
        local frame = plate.UnitFrame
        local accessible = not IsProtected(frame)
            and not (inCombat and frame.IsProtected and frame:IsProtected())
        local exists = accessible and UnitExists(unit)
        local player = exists and UnitIsPlayer(unit)
        local minion = exists and not player and ns.IsPlayerMinion(unit)
        local allowCombat = exists and (player and playerMode == "combat"
            or not player and not minion and npcMode == "combat")
        if exists and (not inCombat or allowCombat) then
            if not plateUnits[unit] then plateUnits[unit] = {plate = plate, frame = frame} end
            HookPlateHover(plate, frame)
            if player and ns.CompareUnits(unit, "player") == false then
                local visible = not knownOnly or IsRecognized(unit)
                if not visible then
                    HideNameLabels(plate, frame)
                    RestoreNameColor(frame)
                    MakeTransparent(frame)
                elseif namesOnly then
                    RestoreNameColor(frame)
                    if not ShowNameOnly(plate, frame, unit) then
                        -- Fail open if the name cannot be displayed.
                        HideNameLabels(plate, frame)
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
                    if not ShowNameOnly(plate, frame, unit, true) then
                        HideNameLabels(plate, frame)
                    end
                end
            elseif minion then
                HideNameLabels(plate, frame)
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
                    HideNameLabels(plate, frame)
                    MakeTransparent(frame)
                elseif npcID and (category or override == "show") then
                    local color = category and ns.GetNPCNameplateCategoryColor(category)
                    if not ShowNameOnly(plate, frame, unit, npcShowBar, true, color) then
                        -- Standard text uses Blizzard's own label. Only name
                        -- color changes; original font and layout remain native.
                        HideNameLabels(plate, frame)
                        RestoreFrame(frame, allowCombat)
                        if color then SetNameColor(frame, color) end
                    end
                else
                    HideNameLabels(plate, frame)
                    RestoreFrame(frame)
                end
            else
                HideNameLabels(plate, frame)
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
frame:RegisterEvent("NAME_PLATE_UNIT_BEHIND_CAMERA_CHANGED")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CVAR_UPDATE")
frame:SetScript("OnEvent", function(_, event, unit, isBehindCamera)
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
        for token, binding in pairs(plateUnits) do ReleasePlate(token, binding) end
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
    if event == "NAME_PLATE_UNIT_BEHIND_CAMERA_CHANGED" then
        local binding = plateUnits[ns.SafeString(unit)]
        local plate = binding and binding.plate
        local labels = plate and activeNameLabels[plate]
        if labels and ns.IsAccessibleValue(isBehindCamera) and type(isBehindCamera) == "boolean" then
            labels.behindCamera = isBehindCamera
            UpdateNameLabelAppearance(plate, labels)
        end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        -- Re-evaluate health-bar mode on combat transitions. Protected
        -- nameplates may require deferred updates until combat ends.
        if event == "PLAYER_REGEN_ENABLED" then
            ns.SyncNativeOverheadNames()
            ns.SyncNPCNameplateCVars()
        end
        ns.RefreshKnownNameplates()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        ns.SyncNativeOverheadNames()
        ns.SyncNPCNameplateCVars()
    end
    if event == "NAME_PLATE_UNIT_REMOVED" then
        -- Forever may clear the unit-to-nameplate mapping before this event.
        unit = ns.SafeString(unit)
        local binding = plateUnits[unit]
        if binding then ReleasePlate(unit, binding) end
        return
    end
    ns.RefreshKnownNameplates()
end)
frame:SetScript("OnUpdate", function(_, delta)
    if not KnownPlayersSettings then return end
    for plate, labels in pairs(activeNameLabels) do UpdateNameLabelAppearance(plate, labels) end
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

local addonName, ns = ...

-- The names-only appearance fades the UnitFrame and draws its own labels.
local changedFrames = setmetatable({}, { __mode = "k" })
local combatFades = setmetatable({}, { __mode = "k" })
local COMBAT_FADE_SECONDS = 0.25
local PLATE_RETRY_TIMES = {0, 0.1, 0.35}
local SELECTED_PLATE_WAIT = 0.75
local plateUnits = {} -- unit token -> outer plate and its current pooled UnitFrame
local nameLabels = setmetatable({}, { __mode = "k" }) -- owned by the outer plate
local activeNameLabels = {}
local originalNameColors = setmetatable({}, { __mode = "k" })
local originalVertexColors = setmetatable({}, { __mode = "k" })
local originalNativeNameAlpha = setmetatable({}, { __mode = "k" })
local elapsed = 0
local plateRetryStep, plateRetryElapsed
local selectedPlateWait = 0
local hiddenOuterPlates = setmetatable({}, { __mode = "k" })
local unlistedOuterPlates = setmetatable({}, { __mode = "k" })
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

local nativeNameCheckElapsed = 0

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
    if alpha == nil or IsProtected(frame) or IsCombatRestricted(frame) then return false end
    -- Keep the saved alpha for a later retry if the client rejects the call.
    if InCombatLockdown and InCombatLockdown() and not allowCombat then return false end
    local current = ReadAppearanceValue(frame.GetAlpha, frame)
    local fade = combatFades[frame]
    if type(current) == "number" and current ~= 0 and (not fade or current ~= fade.alpha) then
        changedFrames[frame], combatFades[frame] = nil, nil
        return false -- Blizzard already set the alpha for this plate.
    end
    local ok = pcall(frame.SetAlpha, frame, alpha)
    if ok then changedFrames[frame], combatFades[frame] = nil, nil end
    return ok
end

local function RestoreAll()
    for frame in pairs(changedFrames) do RestoreFrame(frame) end
end

local function MakeTransparent(frame, allowCombat)
    if IsProtected(frame) or IsCombatRestricted(frame) then return false end
    if not allowCombat and InCombatLockdown and InCombatLockdown() then return false end
    local alpha = ReadAppearanceValue(frame.GetAlpha, frame)
    if type(alpha) ~= "number" then return false end
    if alpha ~= 0 then
        if not pcall(frame.SetAlpha, frame, 0) then return false end
        if not combatFades[frame] then changedFrames[frame] = alpha end
    end
    combatFades[frame] = nil
    return true
end

local function StartCombatFade(frame)
    if IsProtected(frame) or IsCombatRestricted(frame) then return end
    local alpha = ReadAppearanceValue(frame.GetAlpha, frame)
    if type(alpha) ~= "number" or alpha <= 0 then return end
    changedFrames[frame] = alpha
    combatFades[frame] = { elapsed = 0, alpha = alpha }
end

-- With health bars visible, use the same custom text layer to support
-- Full/First Name and Guild Name. Only the native name FONT STRING is faded;
-- the health bar and clickable frame remain untouched.
local function RestoreNativeNameAlpha(frame)
    local name = not IsProtected(frame) and not IsCombatRestricted(frame) and frame.name
    if IsProtected(name) or IsCombatRestricted(name) then return end
    local alpha = originalNativeNameAlpha[name]
    if alpha == nil then return end
    local current = ReadAppearanceValue(name.GetAlpha, name)
    if (type(current) == "number" and current ~= 0) or pcall(name.SetAlpha, name, alpha) then
        originalNativeNameAlpha[name] = nil
    end
end

local function SuppressNativeName(frame)
    if IsProtected(frame) then return false end
    local name = frame.name
    if IsProtected(name) or type(name.SetAlpha) ~= "function" then return false end
    local alpha = ReadAppearanceValue(name.GetAlpha, name)
    if type(alpha) ~= "number" then return false end
    if alpha == 0 then return true end
    if IsCombatRestricted(frame) or IsCombatRestricted(name) or not pcall(name.SetAlpha, name, 0) then return false end
    originalNativeNameAlpha[name] = alpha
    return true
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
    if labels.interactionIcon then labels.interactionIcon:Hide() end
    labels.interactionIconReady = nil
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

local function UpdateInteractionIcon(plate, labels, visible, scale, alpha)
    local icon = labels.interactionIcon
    local frame = labels.frame
    local softTarget = visible and labels.isNPC and not labels.replacesNativeName
        and not combatFades[frame] and frame.SoftTargetFrame
    local native = softTarget and not IsProtected(softTarget) and softTarget.Icon
    -- The native texture can be shown even while its UnitFrame has zero alpha.
    if IsProtected(native) or ReadAppearanceValue(native.IsShown, native) ~= true
        or type(SetUnitCursorTexture) ~= "function" then
        if icon then icon:Hide() end
        labels.interactionIconReady = nil
        return
    end

    if not icon then
        icon = plate:CreateTexture(nil, "OVERLAY")
        icon:SetPoint("RIGHT", labels.name, "LEFT", -4, 0)
        labels.interactionIcon = icon
    end
    if labels.interactionIconReady == nil then
        labels.interactionIconReady = ReadAppearanceValue(SetUnitCursorTexture, icon, labels.unit, nil, nil, true) == true
    end
    if labels.interactionIconScale ~= scale then
        icon:SetSize(20 * scale, 20 * scale)
        labels.interactionIconScale = scale
    end
    if icon:GetAlpha() ~= alpha then icon:SetAlpha(alpha) end
    icon:SetShown(labels.interactionIconReady)
end

local function UpdateNameLabelAppearance(plate, labels, delta)
    local frame = labels.frame
    local current = not IsProtected(plate) and plate.UnitFrame == frame
        and ns.SafeString(plate.unitToken) == labels.unit and not IsProtected(frame)
    local native = current and frame.name
    local visible = native and not labels.behindCamera
        and ReadAppearanceValue(frame.IsVisible, frame) ~= false
    if visible and delta and (labels.replacesNativeName or combatFades[frame]) and not SuppressNativeName(frame) then
        RestoreFrame(frame, true)
        HideNameLabels(plate, frame)
        return
    end
    if current and delta and not labels.replacesNativeName then
        local mode = labels.isNPC and NPCHealthBarMode() or PlayerHealthBarMode()
        local fade = combatFades[frame]
        if fade and mode == "combat" and not HealthBarVisible(mode) then
            fade.elapsed = math.min(COMBAT_FADE_SECONDS, fade.elapsed + delta)
            local alpha = changedFrames[frame] * (1 - fade.elapsed / COMBAT_FADE_SECONDS)
            if IsCombatRestricted(frame) or not pcall(frame.SetAlpha, frame, alpha) then
                RestoreFrame(frame, true)
                HideNameLabels(plate, frame)
                return
            end
            fade.alpha = ReadAppearanceValue(frame.GetAlpha, frame) or alpha
            if fade.elapsed == COMBAT_FADE_SECONDS then
                combatFades[frame] = nil
                RestoreNativeNameAlpha(frame)
            end
        -- Blizzard can change the native alpha without rebinding the plate.
        elseif visible and not HealthBarVisible(mode) and not MakeTransparent(frame, mode == "never") then
            HideNameLabels(plate, frame)
            return
        end
    end
    labels.name:SetShown(visible == true)
    if labels.subtitle then labels.subtitle:SetShown(visible == true and labels.hasSubtitle) end
    if not visible then
        UpdateInteractionIcon(plate, labels, false)
        return
    end

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
    UpdateInteractionIcon(plate, labels, true, scale, alpha)
end

local function GetNameSubtitle(unit, isNPC)
    if isNPC then
        if KnownPlayersSettings.showNPCTitle then return GetNPCTitle(unit) end
    elseif KnownPlayersSettings.showGuildInNamesOnly then
        return ns.SafeString(ReadAppearanceValue(GetGuildInfo, unit))
    end
end

local function ShowNameOnly(plate, frame, unit, keepHealthBar, kind, displayColor, fadeOnCombatEnd)
    if not frame.name then return false end
    local isNPC, isMinion = kind == "npc", kind == "minion"
    local firstName, subtitle
    if not isMinion then
        firstName = isNPC and KnownPlayersSettings.npcNameDisplayMode == "first"
            or not isNPC and KnownPlayersSettings.nameDisplayMode == "first"
        subtitle = GetNameSubtitle(unit, isNPC)
    end
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
    local mode = isNPC and NPCHealthBarMode() or PlayerHealthBarMode()
    if not keepHealthBar then
        if fadeOnCombatEnd and mode == "combat" and not combatFades[frame] then StartCombatFade(frame) end
        if not (mode == "combat" and combatFades[frame]) and not MakeTransparent(frame, mode == "never") then
            return false
        end
    else
        RestoreFrame(frame, mode == "combat")
    end
    if keepHealthBar or combatFades[frame] then
        if not SuppressNativeName(frame) then
            RestoreFrame(frame, true)
            return false
        end
    else
        RestoreNativeNameAlpha(frame)
    end
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
    if (isNPC or isMinion) and not displayColor and type(frame.name.GetTextColor) == "function" then
        local ok, r, g, b = pcall(frame.name.GetTextColor, frame.name)
        if ok and type(r) == "number" then displayColor = {r, g, b} end
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
    labels.replacesNativeName = keepHealthBar
    labels.isNPC = isNPC
    labels.isMinion = isMinion
    labels.interactionIconReady = nil
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

local function CategoryColorForUnit(unit)
    if not ns.GetNameplateCategory then return nil end
    local key = ns.PlayerKeyFromUnit(unit)
    if not key then return nil end
    local category = ns.GetNameplateCategory(key, ns.SafePlayerGUID(ns.SafeUnitGUID(unit)))
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

-- Reapply styling after Blizzard redraws the native name.
local function ReapplyNormalNameColor(frame, unit)
    if not KnownPlayersSettings or not unit or IsProtected(frame) or IsCombatRestricted(frame)
        or not UnitExists(unit) then return end
    local player = ReadAppearanceValue(UnitIsPlayer, unit) == true
    if not KnownPlayersSettings.knownOnlyNameplates and (player or ns.IsPlayerMinion(unit)) then return end
    local binding = plateUnits[unit]
    local plate = binding and binding.plate
    local labels = plate and activeNameLabels[plate]
    if labels and labels.frame == frame and not IsProtected(plate)
        and plate.UnitFrame == frame and ns.SafeString(plate.unitToken) == unit
        and labels.replacesNativeName then
        SuppressNativeName(frame)
    end
    if player and PlayerHealthBarVisible() and ns.CompareUnits(unit, "player") == false then
        local color = CategoryColorForUnit(unit)
        if color then SetNameColor(frame, color) end
    end
end

local function GetPlateList()
    if C_NamePlate and type(C_NamePlate.GetNamePlates) == "function" then
        return C_NamePlate.GetNamePlates() or {}
    end
    return {}
end

local function IsNPCUnit(unit)
    return unit and ReadAppearanceValue(UnitExists, unit) == true
        and ns.GetNPCFromUnit and ns.GetNPCFromUnit(unit) ~= nil
end

local function CanRefreshSelectedPlate()
    if ReadAppearanceValue(UnitExists, "target") ~= true then return false end
    if ReadAppearanceValue(UnitIsPlayer, "target") == true then
        return KnownPlayersSettings and KnownPlayersSettings.knownOnlyNameplates
            and ns.CompareUnits("target", "player") == false
    end
    return IsNPCUnit("target")
end

local function GetSelectedPlate()
    local plate = ReadAppearanceValue(C_NamePlate and C_NamePlate.GetNamePlateForUnit, "target")
    local unit = not IsProtected(plate) and ns.SafeString(plate.unitToken)
    if unit and ns.CompareUnits(unit, "target") == true then return plate, unit end
end

local function GetUnlistedSelectedPlate(platesByUnit)
    -- Restoring an outer frame can leave it outside both client lookups.
    for plate, binding in pairs(unlistedOuterPlates) do
        local unit = not IsProtected(plate) and ns.SafeString(plate.unitToken)
        if unit == binding.unit and not platesByUnit[unit] and plate.UnitFrame == binding.frame
            and ReadAppearanceValue(plate.IsShown, plate) == true and ns.CompareUnits(unit, "target") == true then
            return plate, unit
        end
    end
end

local function AddSelectedPlate(platesByUnit)
    if not CanRefreshSelectedPlate() then return end
    local plate, unit = GetSelectedPlate()
    if not plate then plate, unit = GetUnlistedSelectedPlate(platesByUnit) end
    if unit and not platesByUnit[unit] then
        platesByUnit[unit] = plate
        return plate
    end
end

local function IsRecognized(unit)
    -- Leave the plate visible when the game can't identify the player.
    local key = ns.PlayerKeyFromUnit(unit)
    if not key then return true end
    local guid = ns.SafePlayerGUID(ns.SafeUnitGUID(unit))
    return ns.IsKnownOrAssociated(key, guid)
end

local function RestoreOuterPlate(plate)
    if IsProtected(plate) or IsCombatRestricted(plate) then return end
    if ReadAppearanceValue(plate.IsShown, plate) ~= true then pcall(plate.Show, plate) end
    if ReadAppearanceValue(plate.IsShown, plate) == true then hiddenOuterPlates[plate] = nil end
end

local function HideOuterPlate(plate, unit, frame)
    local unlisted = unlistedOuterPlates[plate]
    if unlisted and unlisted.unit == unit and unlisted.frame == frame then return end
    if ReadAppearanceValue(plate.IsShown, plate) ~= true
        or type(plate.Hide) ~= "function" or type(plate.Show) ~= "function" then
        return
    end
    pcall(plate.Hide, plate)
    if ReadAppearanceValue(plate.IsShown, plate) == false then
        hiddenOuterPlates[plate] = {unit = unit, frame = frame}
        unlistedOuterPlates[plate] = nil
    end
end

local function UpdateHiddenOuterPlates(platesByUnit)
    for plate, binding in pairs(hiddenOuterPlates) do
        local unit = not IsProtected(plate) and ns.SafeString(plate.unitToken)
        if unit and UnitExists(unit) then
            if platesByUnit[unit] == plate then
                if binding.released or unit ~= binding.unit or plate.UnitFrame ~= binding.frame
                    or IsProtected(plate.UnitFrame) then
                    RestoreOuterPlate(plate)
                end
            elseif unit == binding.unit and not binding.released and not platesByUnit[unit] then
                -- Leave only this binding visible if hiding it removed it from enumeration.
                if ReadAppearanceValue(plate.IsShown, plate) == false then unlistedOuterPlates[plate] = binding end
                RestoreOuterPlate(plate)
            end
        end
    end
end

local function IsRecognizedMinion(unit)
    if type(UnitOwnerGUID) ~= "function" then return true end
    local ok, guid = pcall(UnitOwnerGUID, unit)
    local owner = ok and ns.SafePlayerGUID(guid)
    if not owner or owner == ns.SafeUnitGUID("player") then return true end
    if ns.IsKnownOrAssociated(nil, owner) then return true end

    -- The owner may only be saved by name.
    if type(UnitNameFromGUID) ~= "function" then return false end
    local found, name, surname = pcall(UnitNameFromGUID, owner)
    local key = found and ns.PlayerKeyFromName(name, surname)
    return key and ns.IsKnownOrAssociated(key, owner) or false
end

local function IsNonAttackableNPC(unit)
    local ok, attackable = pcall(UnitCanAttack, "player", unit)
    return ok and ns.IsAccessibleValue(attackable) and attackable == false
end

local function RestorePlateAppearance(plate, frame)
    HideNameLabels(plate, frame)
    RestoreFrame(frame, true)
    RestoreNameColor(frame)
end

local function ReleasePlate(unit, binding)
    -- A recycled frame can carry our zero alpha into the next unit's binding.
    RestorePlateAppearance(binding.plate, binding.frame)
    plateUnits[unit] = nil
end

function ns.RefreshKnownNameplates(fadeOnCombatEnd)
    if not KnownPlayersSettings then return end
    local knownOnly = KnownPlayersSettings.knownOnlyNameplates
    local playerMode, npcMode = PlayerHealthBarMode(), NPCHealthBarMode()
    local namesOnly, npcShowBar = not HealthBarVisible(playerMode), HealthBarVisible(npcMode)
    local platesByUnit = {}
    for _, plate in ipairs(GetPlateList()) do
        local unit = not IsProtected(plate) and ns.SafeString(plate.unitToken)
        if unit then platesByUnit[unit] = plate end
    end
    local inCombat = InCombatLockdown and InCombatLockdown()
    UpdateHiddenOuterPlates(platesByUnit)
    local selectedOnlyPlate = AddSelectedPlate(platesByUnit)
    -- Clear stale bindings before rendering any newly assigned pooled frame.
    -- This also catches plates that disappear between the add/remove events.
    for unit, binding in pairs(plateUnits) do
        if platesByUnit[unit] ~= binding.plate or binding.plate.UnitFrame ~= binding.frame
            or not UnitExists(unit) then
            ReleasePlate(unit, binding)
        end
    end

    if inCombat and knownOnly and playerMode == "always" and npcMode == "always"
        and not next(activeNameLabels) and not next(hiddenOuterPlates) then return end
    local showFriendlyMinions = knownOnly and ns.GetFriendlyMinionVisibility()
    for unit, plate in pairs(platesByUnit) do
        local frame = plate.UnitFrame
        local accessible = not IsProtected(frame) and not IsCombatRestricted(frame)
        local exists = accessible and UnitExists(unit)
        local player = exists and UnitIsPlayer(unit)
        local minion = exists and not player and ns.IsPlayerMinion(unit)
        local friendlyMinion = minion and showFriendlyMinions and ReadAppearanceValue(UnitIsFriend, "player", unit) == true
        local labels = activeNameLabels[plate]
        local restoreMinionBar = minion and labels and labels.isMinion and labels.frame == frame and not namesOnly
        local allowCombat = exists and (player and playerMode ~= "always"
            or friendlyMinion and playerMode ~= "always" or restoreMinionBar
            or not player and not minion and npcMode ~= "always")
        local canStyle = not inCombat or allowCombat
        if not knownOnly and (player or minion) then
            if hiddenOuterPlates[plate] then RestoreOuterPlate(plate) end
            RestorePlateAppearance(plate, frame)
            plateUnits[unit] = nil
        elseif exists and (canStyle or hiddenOuterPlates[plate]) then
            if not plateUnits[unit] then plateUnits[unit] = {plate = plate, frame = frame} end
            local otherPlayer = player and ns.CompareUnits(unit, "player") == false
            local filteredPlayer = otherPlayer and knownOnly and not IsRecognized(unit)
            local filteredMinion = minion and knownOnly and not IsRecognizedMinion(unit)
            local npcID, category, classified, override
            if not player and not minion then
                -- Read creature identity once. Unavailable GUIDs are left visible.
                npcID = ns.GetNPCFromUnit and ns.GetNPCFromUnit(unit)
                if npcID then
                    category, classified = ns.GetNPCNameplateCategory(npcID)
                    override = ns.GetNPCVisibilityOverride and ns.GetNPCVisibilityOverride(npcID) or "auto"
                end
            end
            local filteredNPC = npcID and (override == "hide"
                or (override ~= "show" and classified and not category and IsNonAttackableNPC(unit)))
            local filtered = filteredPlayer or filteredMinion or filteredNPC
            -- A target lookup alone cannot reliably track a hidden plate after deselection.
            local hideOuter = filtered and plate ~= selectedOnlyPlate
            if not hideOuter and hiddenOuterPlates[plate] then RestoreOuterPlate(plate) end

            if filtered then
                RestorePlateAppearance(plate, frame)
                if hideOuter and not inCombat then HideOuterPlate(plate, unit, frame) end
            elseif canStyle and otherPlayer then
                if namesOnly then
                    RestoreNameColor(frame)
                    if not ShowNameOnly(plate, frame, unit, false, "player", CategoryColorForUnit(unit), fadeOnCombatEnd) then
                        -- Fail open if the name cannot be displayed.
                        HideNameLabels(plate, frame)
                        RestoreFrame(frame, allowCombat)
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
                    if not ShowNameOnly(plate, frame, unit, true, "player", color) then
                        HideNameLabels(plate, frame)
                    end
                end
            elseif canStyle and minion then
                RestoreNameColor(frame)
                if not (friendlyMinion and namesOnly
                    and ShowNameOnly(plate, frame, unit, false, "minion", nil, fadeOnCombatEnd)) then
                    HideNameLabels(plate, frame)
                    RestoreFrame(frame, allowCombat)
                end
            elseif canStyle and not player then
                RestoreNameColor(frame)
                if npcID and (category or override == "show") then
                    local color = category and ns.GetNPCNameplateCategoryColor(category)
                    if not ShowNameOnly(plate, frame, unit, npcShowBar, "npc", color, fadeOnCombatEnd) then
                        -- Standard text uses Blizzard's own label. Only name
                        -- color changes; original font and layout remain native.
                        HideNameLabels(plate, frame)
                        RestoreFrame(frame, allowCombat)
                        if color then SetNameColor(frame, color) end
                    end
                else
                    HideNameLabels(plate, frame)
                    RestoreFrame(frame, npcMode == "never")
                end
            elseif canStyle then
                HideNameLabels(plate, frame)
                RestoreFrame(frame)
                RestoreNameColor(frame) -- Unfiltered NPCs, pets, and other units.
            end
        end
    end
end

function ns.OnNameplateTargetChanged()
    local refreshTarget = CanRefreshSelectedPlate()
    plateRetryStep = refreshTarget and 1 or nil
    plateRetryElapsed = 0
    selectedPlateWait = refreshTarget and SELECTED_PLATE_WAIT or 0
    ns.RefreshKnownNameplates()
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
frame:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED")
frame:RegisterEvent("PLAYER_SOFT_FRIEND_CHANGED")
frame:RegisterEvent("PLAYER_SOFT_ENEMY_CHANGED")
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
        for plate in pairs(hiddenOuterPlates) do
            local token = not IsProtected(plate) and ns.SafeString(plate.unitToken)
            if token and UnitExists(token) then RestoreOuterPlate(plate) end
        end
        ns.ShutdownNameplateCVars()
        for token, binding in pairs(plateUnits) do ReleasePlate(token, binding) end
        RestoreAll()
        RestoreAllNameColors()
        return
    end
    if event == "CVAR_UPDATE" then
        -- If the native names are turned back on in WoW's settings, keep the
        -- active filter consistent. Do not change unrelated CVars.
        ns.OnNameplateCVarUpdate(unit)
        return
    end
    if event == "PLAYER_SOFT_INTERACT_CHANGED" or event == "PLAYER_SOFT_FRIEND_CHANGED"
        or event == "PLAYER_SOFT_ENEMY_CHANGED" then
        -- The native driver also handles these events. Read its texture state
        -- on the next display update, after its event handler has run.
        for _, labels in pairs(activeNameLabels) do labels.interactionIconReady = nil end
        return
    end
    if event == "NAME_PLATE_UNIT_BEHIND_CAMERA_CHANGED" then
        if not ns.IsAccessibleValue(isBehindCamera) or type(isBehindCamera) ~= "boolean" then return end
        unit = ns.SafeString(unit)
        local binding = plateUnits[unit]
        local plate = binding and binding.plate
        local labels = plate and activeNameLabels[plate]
        if labels then
            labels.behindCamera = isBehindCamera
            UpdateNameLabelAppearance(plate, labels)
        end
        -- The camera event can arrive before the client reattaches the plate.
        if not isBehindCamera and (IsNPCUnit(unit) or IsNPCUnit("target")) then
            plateRetryStep, plateRetryElapsed = 1, 0
        end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        -- Re-evaluate health-bar mode on combat transitions. Protected
        -- nameplates may require deferred updates until combat ends.
        if event == "PLAYER_REGEN_ENABLED" then
            ns.SyncNativeOverheadNames()
            ns.SyncNPCNameplateCVars()
            ns.SyncNameplateClicks()
        end
        ns.RefreshKnownNameplates(event == "PLAYER_REGEN_ENABLED")
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        ns.SyncNativeOverheadNames()
        ns.SyncNPCNameplateCVars()
        ns.SyncNameplateClicks()
    end
    if event == "NAME_PLATE_UNIT_REMOVED" then
        -- Forever may clear the unit-to-nameplate mapping before this event.
        unit = ns.SafeString(unit)
        local binding = plateUnits[unit]
        local hidden = binding and hiddenOuterPlates[binding.plate]
        if hidden then hidden.released = true end
        for plate, unlisted in pairs(unlistedOuterPlates) do
            if unlisted.unit == unit then unlistedOuterPlates[plate] = nil end
        end
        if binding then ReleasePlate(unit, binding) end
        return
    end
    ns.RefreshKnownNameplates()
end)
frame:SetScript("OnUpdate", function(_, delta)
    if not KnownPlayersSettings then return end
    for plate, labels in pairs(activeNameLabels) do UpdateNameLabelAppearance(plate, labels, delta) end
    nativeNameCheckElapsed = nativeNameCheckElapsed + delta
    if nativeNameCheckElapsed >= 5 then
        nativeNameCheckElapsed = 0
        ns.SyncNativeOverheadNames()
        ns.SyncNPCNameplateCVars()
    end
    elapsed = elapsed + delta
    local retryPlate = false
    if plateRetryStep then
        plateRetryElapsed = plateRetryElapsed + delta
        if plateRetryElapsed >= PLATE_RETRY_TIMES[plateRetryStep] then
            retryPlate = true
            local nextStep = plateRetryStep + 1
            plateRetryStep = PLATE_RETRY_TIMES[nextStep] and nextStep or nil
        end
    end
    if selectedPlateWait > 0 then
        selectedPlateWait = selectedPlateWait - delta
        -- Wait for this target's frame without scanning every other nameplate.
        local plate = GetSelectedPlate()
        local unitFrame = plate and plate.UnitFrame
        if not IsProtected(unitFrame) and not IsCombatRestricted(unitFrame) and not IsProtected(unitFrame.name)
            and ReadAppearanceValue(unitFrame.IsVisible, unitFrame) ~= false then
            selectedPlateWait = 0
            retryPlate = true
        end
    end
    if retryPlate or elapsed >= 0.75 then
        elapsed = 0
        ns.RefreshKnownNameplates()
    end
end)

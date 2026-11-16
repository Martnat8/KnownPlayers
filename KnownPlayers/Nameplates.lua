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
local CategoryColorForUnit

local function Print(message)
    print("|cff33ff99KnownPlayers:|r " .. message)
end

local function IsProtected(frame)
    return not frame or (frame.IsForbidden and frame:IsForbidden())
end

local function RestoreFrame(frame)
    local alpha = changedFrames[frame]
    if alpha == nil or IsProtected(frame) then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
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

local function ShowNameOnly(plate, frame, unit, keepHealthBar)
    if not frame.name then return false end
    -- Blizzard's original label can contain more of the character's
    -- display name than UnitName() on Forever. Read it before fading the frame.
    local name
    if type(frame.name.GetText) == "function" then
        local ok, text = pcall(frame.name.GetText, frame.name)
        if ok and type(text) == "string" and text ~= "" then name = text end
    end
    if not name then
        local ok, unitName = pcall(UnitName, unit)
        if ok and type(unitName) == "string" and unitName ~= "" then name = unitName end
    end
    if not name then return false end
    if KnownPlayersSettings and KnownPlayersSettings.nameDisplayMode == "first" then
        name = name:match("^(%S+)") or name
    end
    local label = namesOnlyLabels[frame]
    if not label then
        label = plate:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetJustifyH("CENTER")
        -- Anchor to Blizzard's existing name position, but keep the label
        -- outside the transparent UnitFrame so it remains visible.
        label:SetPoint("CENTER", frame.name, "CENTER", 0, 0)
        if type(frame.name.GetFont) == "function" then
            local fontOk, font, size, flags = pcall(frame.name.GetFont, frame.name)
            if fontOk and font and type(size) == "number" then
                pcall(label.SetFont, label, font, size, flags)
            end
        end
        namesOnlyLabels[frame] = label
    end
    label:SetText(name)
    local displayColor = CategoryColorForUnit(unit) or {1, 1, 1}
    label:SetTextColor(displayColor[1], displayColor[2], displayColor[3], 1)
    label:Show()

    local guildLabel = namesOnlyGuildLabels[frame]
    local guildName
    if KnownPlayersSettings and KnownPlayersSettings.showGuildInNamesOnly
        and type(GetGuildInfo) == "function" then
        local ok, result = pcall(GetGuildInfo, unit)
        if ok and type(result) == "string" and result ~= "" then
            guildName = result
        end
    end
    if guildName then
        if not guildLabel then
            guildLabel = plate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            guildLabel:SetJustifyH("CENTER")
            namesOnlyGuildLabels[frame] = guildLabel
        end
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
        RestoreFrame(frame)
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
    if type(n) ~= "string" or n == "" then return nil end
    if type(r) ~= "string" or r == "" then
        r = type(GetNormalizedRealmName) == "function" and GetNormalizedRealmName() or nil
    end
    if type(r) ~= "string" or r == "" then return nil end
    local category = ns.GetNameplateCategory(n .. "-" .. r, UnitGUID(unit))
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
    if not KnownPlayersSettings or KnownPlayersSettings.namesOnlyNameplates then return end
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

local function IsRecognized(unit)
    -- Fail open if the identity is unavailable: don't hide unidentified units.
    local name, realm = UnitFullName(unit)
    if type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT then return true end
    if type(realm) ~= "string" or realm == "" then
        realm = type(GetNormalizedRealmName) == "function" and GetNormalizedRealmName() or nil
    end
    if type(realm) ~= "string" or realm == "" then return true end
    local guid = UnitGUID(unit)
    return ns.IsKnownOrAssociated and ns.IsKnownOrAssociated(name .. "-" .. realm, guid) or false
end

function ns.RefreshKnownNameplates()
    if not KnownPlayersSettings then return end
    local knownOnly = KnownPlayersSettings.knownOnlyNameplates
    local namesOnly = KnownPlayersSettings.namesOnlyNameplates
    -- Even with full nameplates and no visibility filter, refresh the
    -- original Blizzard name text colors for recognized characters.

    if InCombatLockdown and InCombatLockdown() then return end
    for _, plate in ipairs(GetPlateList()) do
        local unit = plate.unitToken
        local frame = plate.UnitFrame
        if unit and frame and not IsProtected(frame) then
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
            if UnitExists(unit) and UnitIsPlayer(unit) and not UnitIsUnit(unit, "player") then
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
                    RestoreFrame(frame)
                    local color = CategoryColorForUnit(unit)
                    if color then SetNameColor(frame, color)
                    else RestoreNameColor(frame) end
                    if not ShowNameOnly(plate, frame, unit, true) then
                        HideNameOnlyLabel(frame)
                    end
                end
            else
                HideNameOnlyLabel(frame)
                RestoreFrame(frame)
                RestoreNameColor(frame) -- NPCs / pets / other units are unaffected.
            end
        end
    end
end

function ns.SetKnownOnlyNameplates(enabled)
    if not KnownPlayersSettings then return end
    KnownPlayersSettings.knownOnlyNameplates = enabled and true or false
    ns.RefreshKnownNameplates()
end

function ns.SetNamesOnlyNameplates(enabled)
    if not KnownPlayersSettings then return end
    KnownPlayersSettings.namesOnlyNameplates = enabled and true or false
    ns.RefreshKnownNameplates()
end

function ns.TestTargetNameplate(hide)
    if InCombatLockdown and InCombatLockdown() then
        Print("Nameplate test is disabled during combat.")
        return
    end
    if KnownPlayersSettings and (KnownPlayersSettings.knownOnlyNameplates
        or KnownPlayersSettings.namesOnlyNameplates) then
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
        if type(unit) ~= "string" or not unit:match("^nameplate") then return end
        ReapplyNormalNameColor(updatedFrame, unit)
    end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGOUT" then
        HideAllNameOnlyLabels()
        RestoreAll()
        RestoreAllNameColors()
        return
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
    elapsed = elapsed + delta
    if elapsed >= 0.75 then
        elapsed = 0
        ns.RefreshKnownNameplates()
    end
end)

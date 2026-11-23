-- Run from the repository root with Lua 5.1.
local function Approx(actual, expected, message)
    assert(math.abs(actual - expected) < 0.001, message .. " (" .. actual .. ")")
end

local units, behind, plates = {}, {}, {}
local scripts, registered = {}, {}
local combat = false
local inaccessible = {}
function canaccessvalue(value) return value ~= inaccessible end
function InCombatLockdown() return combat end
function UnitExists(unit) return units[unit] ~= nil end
function UnitName(unit) return units[unit] and units[unit].name end
function UnitIsPlayer(unit) return units[unit].player == true end
function UnitIsUnit(first, second) return first == second end
function UnitFullName(unit) return UnitName(unit), "Example" end
function UnitCanAttack(_, unit) return units[unit].attackable == true end
function UnitGUID(unit) return units[unit] and units[unit].guid end
function GetGuildInfo(unit) return units[unit].subtitle end
C_TooltipInfo = {GetUnit = function(unit)
    return {lines = {{leftText = UnitName(unit)}, {leftText = units[unit].subtitle}}}
end}
C_NamePlate = {GetNamePlates = function() return plates end}
C_NamePlateManager = {IsNamePlateUnitBehindCamera = function(unit)
    return behind[unit] == true
end}
function CreateFrame()
    return {
        RegisterEvent = function(_, event) registered[event] = true end,
        SetScript = function(_, script, fn) scripts[script] = fn end,
    }
end

local function Label()
    local label = {alpha = 1, scale = 1, textScale = 1, shown = true,
        color = {0.3, 0.4, 0.5, 1}, font = "mock.ttf", size = 12, flags = "OUTLINE"}
    function label:GetAlpha() return self.alpha end
    function label:SetAlpha(value)
        assert(not self.forbidden and not (combat and self.protected), "restricted alpha write")
        self.alpha = value
    end
    function label:GetScale() return self.scale end
    function label:SetScale(value) self.scale = value end
    function label:GetTextScale() return self.textScale end
    function label:SetTextScale(value) self.textScale = value end
    function label:GetEffectiveScale() return self.engineScale or self.scale end
    function label:GetFont() return self.font, self.size, self.flags end
    function label:SetFont(font, size, flags) self.font, self.size, self.flags = font, size, flags end
    function label:GetFontHeight() return self.height or self.size end
    function label:SetSmoothScaling(enabled) self.smoothScaling = enabled end
    function label:GetText() return self.text end
    function label:SetText(text) self.text = text end
    function label:SetJustifyH() end
    function label:Hide() self.shown = false end
    function label:IsShown() return self.shown end
    function label:IsVisible() return self.shown end
    function label:SetShown(shown) self.shown = shown end
    function label:SetPoint(position, anchor) self.point, self.anchor = position, anchor end
    function label:ClearAllPoints() self.point, self.anchor = nil, nil end
    function label:SetTextColor(...) self.color = {...} end
    function label:GetTextColor() return unpack(self.color) end
    function label:IsForbidden() return self.forbidden == true end
    function label:IsProtected() return self.protected == true end
    function label:HookScript(script, fn) self[script] = fn end
    return label
end

local function UnitFrame()
    local frame = Label()
    frame.name, frame.healthBar = Label(), Label()
    return frame
end
local function Plate()
    local plate = Label()
    plate.labels = {}
    function plate:CreateFontString()
        local label = Label()
        label.owner = self
        self.labels[#self.labels + 1] = label
        return label
    end
    return plate
end
local function Bind(plate, unitFrame, token, info)
    plate.UnitFrame, plate.unitToken = unitFrame, token
    unitFrame.unit, unitFrame.name.text = token, info.name
    units[token] = info
end

local ns = {
    IsKnownOrAssociated = function(key) return key == "Familiar Player-Example" end,
    GetNameplateCategory = function(key) return key == "Familiar Player-Example" and "guild" or nil end,
    GetNameplateCategoryColor = function() return {0.2, 0.7, 0.8} end,
    GetNPCFromUnit = function(unit) return units[unit].npc and unit end,
    GetNPCNameplateCategory = function(unit) return units[unit].category, units[unit].classified end,
    GetNPCVisibilityOverride = function(unit) return units[unit].override or "auto" end,
    GetNPCNameplateCategoryColor = function() return {0.8, 0.4, 0.2} end,
    IsQuestieDBConnected = function() return true end,
}
assert(loadfile("KnownPlayers/Safety.lua"))("KnownPlayers", ns)
assert(loadfile("KnownPlayers/Nameplates.lua"))("KnownPlayers", ns)
local function Event(event, ...) assert(registered[event], "unregistered event: " .. event); scripts.OnEvent(nil, event, ...) end
local function Tick() scripts.OnUpdate(nil, 0.016) end

KnownPlayersSettings = {npcHealthBarMode = "never", npcNameDisplayMode = "first",
    showNPCTitle = true, playerHealthBarMode = "never", knownOnlyNameplates = true}
local pooled = UnitFrame()
pooled.alpha, pooled.name.alpha = 0.8, 0.5
pooled.name.height = 18
local first, second = Plate(), Plate()
local one = {name = "First Auctioneer", npc = true, category = "auctioneer", classified = true, subtitle = "Auctioneer"}
local two = {name = "Second Banker", npc = true, category = "banker", classified = true}
Bind(first, pooled, "nameplate1", one)
plates = {first}
Event("NAME_PLATE_UNIT_ADDED", "nameplate1")
local firstName, firstTitle = unpack(first.labels)
assert(firstName.text == "First" and firstTitle.text == "<Auctioneer>")
assert(firstName.shown and firstTitle.shown and firstName.smoothScaling and firstTitle.smoothScaling)
assert(firstName.owner == first and firstName.anchor == pooled.name)
assert(pooled.alpha == 0)
Approx(firstName.size, 18, "native font height")
Approx(firstTitle.size, 15.3, "title font height")
Approx(firstName.alpha, 0.4, "native local fade while bar is suppressed")
first.engineScale, pooled.name.engineScale, pooled.name.textScale = 0.7, 0.56, 0.9
Tick()
Approx(firstName.scale, 0.8, "effective scale updated during the display frame")
Approx(firstTitle.scale, 0.8, "title scale updated during the display frame")
Approx(firstTitle.textScale, 0.9, "text scale updated during the display frame")
pooled.name.engineScale = inaccessible
Tick()
Approx(firstName.scale, 1, "unreadable scale falls back safely")
pooled.name.engineScale = 0.56
behind.nameplate1 = true
Event("NAME_PLATE_UNIT_BEHIND_CAMERA_CHANGED", "nameplate1", true)
assert(not firstName.shown and not firstTitle.shown and pooled.alpha == 0)
ns.RefreshKnownNameplates()
assert(not firstName.shown)
behind.nameplate1 = false
Event("NAME_PLATE_UNIT_BEHIND_CAMERA_CHANGED", "nameplate1", false)
assert(firstName.shown and firstTitle.shown)
pooled.shown = false
Tick()
assert(not firstName.shown)
pooled.shown = true

-- A removal notification can arrive before the client clears the binding.
Event("NAME_PLATE_UNIT_REMOVED", "nameplate1")
assert(not firstName.shown and not firstTitle.shown and firstName.anchor == nil)
Approx(pooled.alpha, 0.8, "native frame restored on removal")
first.unitToken, first.UnitFrame = nil, nil
Bind(second, pooled, "nameplate2", two)
plates = {second}
Event("NAME_PLATE_UNIT_ADDED", "nameplate2")
local secondName = second.labels[1]
assert(secondName.owner == second and secondName.shown and secondName.text == "Second")
assert(not firstName.shown and #second.labels == 1)

-- Moving straight to a new outer plate without remove also restores and rebinds.
second.unitToken, second.UnitFrame = nil, nil
Bind(first, pooled, "nameplate3", one)
plates = {first}
Tick()
assert(not secondName.shown)
ns.RefreshKnownNameplates()
assert(firstName.shown and firstTitle.shown and firstName.anchor == pooled.name and #first.labels == 2)
assert(secondName.anchor == nil)

-- A title requests custom text with bars, but missing title falls back to native.
KnownPlayersSettings.npcHealthBarMode = "always"
KnownPlayersSettings.npcNameDisplayMode = "full"
ns.RefreshKnownNameplates()
assert(firstName.shown and firstName.text == one.name and pooled.name.alpha == 0)
assert(firstTitle.anchor == pooled.healthBar)
Approx(pooled.alpha, 0.8, "health bar still at native opacity")
pooled.alpha = 0.6
Tick()
Approx(firstTitle.alpha, 0.3, "live UnitFrame opacity is mirrored with a visible bar")
one.subtitle = nil
ns.RefreshKnownNameplates()
assert(not firstName.shown and not firstTitle.shown)
Approx(pooled.name.alpha, 0.5, "normal name alpha restored")
Approx(pooled.name.color[1], 0.8, "native label retains NPC category color")
one.subtitle = "Auctioneer"
ns.RefreshKnownNameplates()
assert(firstName.shown and pooled.name.alpha == 0)

-- A disappearance without an event also prunes overlay state under lockdown.
combat, pooled.protected, pooled.name.protected = true, true, true
plates = {}
ns.RefreshKnownNameplates()
assert(not firstName.shown and firstName.anchor == nil and pooled.name.alpha == 0)
combat, pooled.protected, pooled.name.protected = false, false, false
local unknown = {name = "Unclassified NPC", npc = true}
Bind(second, pooled, "nameplate4", unknown)
plates = {second}
Event("PLAYER_REGEN_ENABLED")
assert(not secondName.shown)
Approx(pooled.name.alpha, 0.5, "pending native label restoration is retried on pooled reuse")

-- Classified hide, attackable fail-open, explicit overrides, and player filtering.
unknown.classified = true
ns.RefreshKnownNameplates()
assert(pooled.alpha == 0 and not secondName.shown)
unknown.attackable = true
ns.RefreshKnownNameplates()
Approx(pooled.alpha, 0.6, "unselected attackable NPC stays native")
unknown.override = "show"
KnownPlayersSettings.npcHealthBarMode = "never"
ns.RefreshKnownNameplates()
assert(secondName.shown and pooled.alpha == 0)
unknown.override = "hide"
ns.RefreshKnownNameplates()
assert(not secondName.shown and pooled.alpha == 0)

local playerPlate = Plate()
local playerFrame = UnitFrame()
local player = {name = "Familiar Player", player = true, guid = "Player-1-ABC", subtitle = "Example Guild"}
Bind(playerPlate, playerFrame, "nameplate5", player)
KnownPlayersSettings.showGuildInNamesOnly = true
plates = {playerPlate}
Event("NAME_PLATE_UNIT_ADDED", "nameplate5")
assert(playerPlate.labels[1].shown and playerPlate.labels[2].text == "<Example Guild>" and playerFrame.alpha == 0)
player.name = "Unknown Player"
playerFrame.name.text = player.name
ns.RefreshKnownNameplates()
assert(not playerPlate.labels[1].shown and playerFrame.alpha == 0)
KnownPlayersSettings.knownOnlyNameplates = false
ns.RefreshKnownNameplates()
assert(playerPlate.labels[1].shown)
playerPlate.forbidden = true
Tick()
assert(not playerPlate.labels[1].shown)

-- A same-token replacement updates native anchors without reallocating the text.
playerPlate.forbidden = false
local replacement = UnitFrame()
replacement.name.height = 22
Bind(playerPlate, replacement, "nameplate5", player)
ns.RefreshKnownNameplates()
assert(playerPlate.labels[1].anchor == replacement.name and #playerPlate.labels == 2)
Approx(playerFrame.alpha, 1, "previous UnitFrame alpha restored before replacement")
Approx(playerPlate.labels[1].size, 22, "replacement native font height")
replacement.alpha = 0.45 -- Blizzard changed alpha before its removal event.
Event("NAME_PLATE_UNIT_REMOVED", "nameplate5")
Approx(replacement.alpha, 0.45, "removal respects freshly assigned game alpha")
assert(not playerPlate.labels[1].shown and playerPlate.labels[1].anchor == nil)


-- A comparison restriction on one player must not prevent processing NPC plates.
local restrictedPlate = Plate()
local restrictedFrame = UnitFrame()
Bind(restrictedPlate, restrictedFrame, "nameplate6", {name = "Restricted", player = true})
local normalComparison = UnitIsUnit
UnitIsUnit = function(first, second)
    if first == "nameplate6" then error("unit comparison restricted") end
    return normalComparison(first, second)
end
unknown.override = "show"
plates = {restrictedPlate, second}
ns.RefreshKnownNameplates()
assert(not restrictedPlate.labels[1] and secondName.shown)

-- Reset settings while WoW refuses CVar writes. Retry the saved values afterward.
local cvars = {UnitNameFriendlyPlayerName = "1", UnitNameNPC = "1"}
local reject = false
C_CVar = {
    GetCVar = function(name) return cvars[name] end,
    SetCVar = function(name, value)
        if reject then return false end
        cvars[name] = value
        return true
    end,
}
StaticPopupDialogs = {}
KnownPlayersDB = {}
assert(loadfile("KnownPlayers/Categories.lua"))("KnownPlayers", ns)
assert(loadfile("KnownPlayers/Database.lua"))("KnownPlayers", ns)
assert(loadfile("KnownPlayers/Settings.lua"))("KnownPlayers", ns)
ns.RefreshMinimapButton = function() end
ns.InitializeDatabase()
KnownPlayersSettings.knownOnlyNameplates = true
KnownPlayersSettings.filterNPCNameplates = true
ns.SyncNativeOverheadNames()
ns.SyncNPCNameplateCVars()
assert(cvars.UnitNameFriendlyPlayerName == "0" and cvars.UnitNameNPC == "0")
reject = true
StaticPopupDialogs.KNOWNPLAYERS_RESET_SETTINGS.OnAccept()
assert(KnownPlayersSettings.overheadNameCVarsBackup.UnitNameFriendlyPlayerName == "1")
assert(KnownPlayersSettings.npcCVarBackup.UnitNameNPC == "1")
reject = false
Event("PLAYER_REGEN_ENABLED")
assert(cvars.UnitNameFriendlyPlayerName == "1" and cvars.UnitNameNPC == "1")
assert(not KnownPlayersSettings.overheadNameCVarsBackup and not KnownPlayersSettings.npcCVarBackup)
print("Nameplate lifecycle, filtering, scaling, and settings restoration checks passed.")

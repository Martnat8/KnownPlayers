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
function SetUnitCursorTexture(texture, unit)
    texture.cursor = units[unit] and units[unit].cursor
    return texture.cursor ~= nil
end
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
    function label:SetPoint(position, anchor, relativePoint, x, y)
        self.point, self.anchor, self.relativePoint, self.x, self.y = position, anchor, relativePoint, x, y
    end
    function label:SetSize(width, height) self.width, self.textureHeight = width, height end
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
    function plate:CreateTexture()
        assert(not self.interactionIcon, "interaction texture should be reused")
        self.interactionIcon = Label()
        return self.interactionIcon
    end
    return plate
end
local function Bind(plate, unitFrame, token, info)
    plate.UnitFrame, plate.unitToken = unitFrame, token
    unitFrame.unit, unitFrame.name.text = token, info.name
    units[token] = info
end

local ns = {
    IsKnownOrAssociated = function(key) return key == "Familiar-Player-Example" end,
    GetNameplateCategory = function(key) return key == "Familiar-Player-Example" and "guild" or nil end,
    GetNameplateCategoryColor = function() return {0.2, 0.7, 0.8} end,
    GetNPCFromUnit = function(unit) return units[unit].npc and unit end,
    GetNPCNameplateCategory = function(unit) return units[unit].category, units[unit].classified end,
    GetNPCVisibilityOverride = function(unit) return units[unit].override or "auto" end,
    GetNPCNameplateCategoryColor = function() return {0.8, 0.4, 0.2} end,
    IsQuestieDBConnected = function() return true end,
}
assert(loadfile("KnownPlayers/Safety.lua"))("KnownPlayers", ns)
assert(loadfile("KnownPlayers/Categories.lua"))("KnownPlayers", ns)
assert(loadfile("KnownPlayers/Database.lua"))("KnownPlayers", ns)
assert(loadfile("KnownPlayers/NameplateCVars.lua"))("KnownPlayers", ns)
assert(loadfile("KnownPlayers/Nameplates.lua"))("KnownPlayers", ns)
local function Event(event, ...) assert(registered[event], "unregistered event: " .. event); scripts.OnEvent(nil, event, ...) end
local function Tick(delta) scripts.OnUpdate(nil, delta or 0.016) end

KnownPlayersSettings = {npcHealthBarMode = "never", npcNameDisplayMode = "first",
    showNPCTitle = true, playerHealthBarMode = "never", knownOnlyNameplates = true}
local pooled = UnitFrame()
pooled.alpha, pooled.name.alpha = 0.8, 0.5
pooled.name.height = 18
local nativeIcon = Label()
pooled.SoftTargetFrame = {Icon = nativeIcon}
local first, second = Plate(), Plate()
local one = {name = "First Auctioneer", npc = true, category = "auctioneer", classified = true,
    subtitle = "Auctioneer", cursor = "loot"}
local two = {name = "Second Banker", npc = true, category = "banker", classified = true}
Bind(first, pooled, "nameplate1", one)
plates = {first}
Event("NAME_PLATE_UNIT_ADDED", "nameplate1")
local firstName, firstTitle = unpack(first.labels)
assert(firstName.text == "First" and firstTitle.text == "<Auctioneer>")
assert(firstName.shown and firstTitle.shown and firstName.smoothScaling and firstTitle.smoothScaling)
assert(firstName.owner == first and firstName.anchor == pooled.name)
assert(pooled.alpha == 0)
local interactionIcon = assert(first.interactionIcon, "hidden health bar lost the NPC's interaction icon")
assert(interactionIcon.shown and interactionIcon.cursor == "loot" and nativeIcon.shown)
assert(interactionIcon.anchor == firstName and interactionIcon.point == "RIGHT"
    and interactionIcon.relativePoint == "LEFT" and interactionIcon.x < 0 and interactionIcon.y == 0)
nativeIcon:Hide()
Tick()
assert(not interactionIcon.shown)
nativeIcon:SetShown(true)
Tick()
assert(interactionIcon.shown and interactionIcon.cursor == "loot")
one.cursor = "talk"
Event("PLAYER_SOFT_INTERACT_CHANGED")
Tick()
assert(interactionIcon.shown and interactionIcon.cursor == "talk")
Approx(firstName.size, 18, "native font height")
Approx(firstTitle.size, 15.3, "title font height")
Approx(firstName.alpha, 0.4, "native local fade while bar is suppressed")
first.engineScale, pooled.name.engineScale, pooled.name.textScale = 0.7, 0.56, 0.9
Tick()
Approx(firstName.scale, 0.8, "effective scale updated during the display frame")
Approx(interactionIcon.width, 16, "interaction icon follows the nameplate scale")
Approx(interactionIcon.alpha, firstName.alpha, "interaction icon follows the name opacity")
Approx(firstTitle.scale, 0.8, "title scale updated during the display frame")
Approx(firstTitle.textScale, 0.9, "text scale updated during the display frame")
pooled.name.engineScale = inaccessible
Tick()
Approx(firstName.scale, 1, "unreadable scale falls back safely")
pooled.name.engineScale = 0.56
behind.nameplate1 = true
Event("NAME_PLATE_UNIT_BEHIND_CAMERA_CHANGED", "nameplate1", true)
assert(not firstName.shown and not firstTitle.shown and not interactionIcon.shown and pooled.alpha == 0)
ns.RefreshKnownNameplates()
assert(not firstName.shown)
behind.nameplate1 = false
Event("NAME_PLATE_UNIT_BEHIND_CAMERA_CHANGED", "nameplate1", false)
assert(firstName.shown and firstTitle.shown and interactionIcon.shown)
pooled.shown = false
Tick()
assert(not firstName.shown)
pooled.shown = true

-- A removal notification can arrive before the client clears the binding.
Event("NAME_PLATE_UNIT_REMOVED", "nameplate1")
assert(not firstName.shown and not firstTitle.shown and firstName.anchor == nil and not interactionIcon.shown)
Approx(pooled.alpha, 0.8, "native frame restored on removal")
first.unitToken, first.UnitFrame = nil, nil
nativeIcon:Hide()
Bind(second, pooled, "nameplate2", two)
plates = {second}
Event("NAME_PLATE_UNIT_ADDED", "nameplate2")
local secondName = second.labels[1]
assert(secondName.owner == second and secondName.shown and secondName.text == "Second")
assert(not firstName.shown and #second.labels == 1 and not second.interactionIcon)

-- Moving straight to a new outer plate without remove also restores and rebinds.
second.unitToken, second.UnitFrame = nil, nil
Bind(first, pooled, "nameplate3", one)
nativeIcon:SetShown(true)
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
assert(not interactionIcon.shown and nativeIcon.shown, "native icon stays in place with bars visible")
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

-- Release a filtered plate in combat before WoW reuses the frame's alpha.
local recycledPlate, recycledFrame = Plate(), UnitFrame()
plates = {recycledPlate}
KnownPlayersSettings.knownOnlyNameplates = true
KnownPlayersSettings.playerHealthBarMode, KnownPlayersSettings.npcHealthBarMode = "always", "always"
for _, protected in ipairs({false, true}) do
    Bind(recycledPlate, recycledFrame, "nameplate7", {name = "Unrecognized Player", player = true})
    Event("NAME_PLATE_UNIT_ADDED", "nameplate7")
    assert(recycledFrame.alpha == 0)
    combat, recycledFrame.protected = true, protected
    Event("NAME_PLATE_UNIT_REMOVED", "nameplate7")
    Bind(recycledPlate, recycledFrame, "nameplate8", {name = "Familiar Player", player = true})
    Event("NAME_PLATE_UNIT_ADDED", "nameplate8")
    assert(recycledFrame.alpha == (protected and 0 or 1))
    combat = false
    Event("PLAYER_REGEN_ENABLED")
    assert(recycledFrame.alpha == 1)
    Event("NAME_PLATE_UNIT_REMOVED", "nameplate8")
    recycledFrame.protected = false
end

-- Never applies to new and recycled plates during combat when WoW permits alpha writes.
KnownPlayersSettings.playerHealthBarMode, KnownPlayersSettings.npcHealthBarMode = "never", "never"
combat = true
local combatPlayer, combatNPC, protectedNPC, rejectedNPC = Plate(), Plate(), Plate(), Plate()
local playerFrame, npcFrame, protectedFrame, rejectedFrame = UnitFrame(), UnitFrame(), UnitFrame(), UnitFrame()
protectedFrame.protected = true
local setRejectedAlpha = rejectedFrame.SetAlpha
function rejectedFrame:SetAlpha(alpha)
    if combat then error("synthetic client alpha rejection") end
    setRejectedAlpha(self, alpha)
end
Bind(combatPlayer, playerFrame, "nameplate9", {name = "Familiar Player", player = true})
Bind(combatNPC, npcFrame, "nameplate10", one)
Bind(protectedNPC, protectedFrame, "nameplate11", one)
Bind(rejectedNPC, rejectedFrame, "nameplate12", one)
plates = {combatPlayer, combatNPC, protectedNPC, rejectedNPC}
Event("NAME_PLATE_UNIT_ADDED", "nameplate9")
assert(playerFrame.alpha == 0 and combatPlayer.labels[1].shown, "Never missed a new player plate during combat")
assert(npcFrame.alpha == 0 and combatNPC.labels[1].shown, "Never missed a new NPC plate during combat")
assert(protectedFrame.alpha == 1 and not protectedNPC.labels[1])
assert(rejectedFrame.alpha == 1 and not rejectedNPC.labels[1])
-- Blizzard can restore the alpha on a plate without changing its unit binding.
playerFrame.alpha, npcFrame.alpha = 0.55, 0.8
Tick()
assert(playerFrame.alpha == 0 and npcFrame.alpha == 0, "A native combat alpha reset showed a health bar until the next refresh")
Approx(combatPlayer.labels[1].alpha, 0.55, "player label follows the updated fade")
Approx(combatNPC.labels[1].alpha, 0.8, "NPC label follows the updated fade")
Event("NAME_PLATE_UNIT_REMOVED", "nameplate10")
assert(npcFrame.alpha == 0.8 and not combatNPC.labels[1].shown)
Bind(combatNPC, npcFrame, "nameplate13", two)
Event("NAME_PLATE_UNIT_ADDED", "nameplate13")
assert(npcFrame.alpha == 0 and combatNPC.labels[1].shown and combatNPC.labels[1].text == two.name)
npcFrame.protected, npcFrame.alpha = true, 0.7
Tick()
assert(npcFrame.alpha == 0.7 and not combatNPC.labels[1].shown)
combat = false
Event("PLAYER_REGEN_ENABLED")
assert(protectedFrame.alpha == 0 and rejectedFrame.alpha == 0 and npcFrame.alpha == 0)
-- A native redraw can arrive after the combat-end event and its refresh.
playerFrame.alpha, npcFrame.alpha = 0.65, 0.9
Tick()
assert(playerFrame.alpha == 0 and npcFrame.alpha == 0, "Never missed a native alpha reset after combat ended")
Approx(combatPlayer.labels[1].alpha, 0.65, "player label follows the post-combat fade")
Approx(combatNPC.labels[1].alpha, 0.9, "NPC label follows the post-combat fade")

-- In Combat eases the bars out without fading the names or leaking alpha on reuse.
KnownPlayersSettings.playerHealthBarMode, KnownPlayersSettings.npcHealthBarMode = "combat", "combat"
npcFrame.protected = false
npcFrame.SoftTargetFrame = {Icon = Label()}
two.cursor = "loot"
plates = {combatPlayer, combatNPC}
units.nameplate9.subtitle = "Example Guild"
combat = true
Event("PLAYER_REGEN_DISABLED")
Approx(playerFrame.alpha, 0.65, "player bar visible at the start of combat")
Approx(npcFrame.alpha, 0.9, "NPC bar visible at the start of combat")
assert(not combatNPC.interactionIcon, "visible bars keep the native interaction icon")
assert(playerFrame.name.alpha == 0 and combatPlayer.labels[2].shown)
playerFrame.name.alpha = 0.8
Tick()
assert(playerFrame.name.alpha == 0 and combatPlayer.labels[2].shown, "Native name returned over the guild line")
assert(combatPlayer.labels[2].text == "<Example Guild>")
playerFrame.name.protected, playerFrame.name.alpha = true, 0.8
Tick()
assert(playerFrame.name.alpha == 0.8 and not combatPlayer.labels[2].shown)
playerFrame.name.protected = false
Event("NAME_PLATE_UNIT_ADDED", "nameplate9")
assert(playerFrame.name.alpha == 0 and combatPlayer.labels[2].shown)
combat = false
Event("PLAYER_REGEN_ENABLED")
Approx(playerFrame.alpha, 0.65, "bar does not jump to transparent on combat exit")
playerFrame.name.alpha = 1
Tick(0.125)
assert(playerFrame.name.alpha == 0 and combatPlayer.labels[2].shown)
Approx(playerFrame.alpha, 0.325, "player bar halfway through the fade")
Approx(npcFrame.alpha, 0.45, "NPC bar halfway through the fade")
Approx(combatPlayer.labels[1].alpha, 0.65, "player name stays visible through the fade")
Approx(combatNPC.labels[1].alpha, 0.9, "NPC name stays visible through the fade")
assert(not combatNPC.interactionIcon, "the interaction icon stays native while the bar fades")
Tick(0.125)
assert(playerFrame.alpha == 0 and npcFrame.alpha == 0)
assert(combatNPC.interactionIcon.shown and combatNPC.interactionIcon.cursor == "loot")

combat = true
Event("PLAYER_REGEN_DISABLED")
assert(not combatNPC.interactionIcon.shown, "combat restores the native interaction icon with the bar")
combat = false
Event("PLAYER_REGEN_ENABLED")
Tick(0.125)
Event("NAME_PLATE_UNIT_REMOVED", "nameplate13")
Approx(npcFrame.alpha, 0.9, "releasing a fading plate restores native alpha")
assert(not combatNPC.labels[1].shown)
combat = true
Event("PLAYER_REGEN_DISABLED")
Approx(playerFrame.alpha, 0.65, "reentering combat cancels the fade")
combat = false

-- Enabled friendly player minions follow the player health-bar mode.
do
    local originalIsMinion, originalIsFriend, originalCVars = UnitIsMinion, UnitIsFriend, C_CVar
    local minionsCVar = "1"
    C_CVar = {GetCVar = function(name)
        if name == "nameplateShowFriendlyPlayerMinions" then return minionsCVar end
    end}
    UnitIsMinion = function(unit) return units[unit].minion == true end
    UnitIsFriend = function(_, unit) return units[unit].friendly == true end
    local friendlyPlate, hostilePlate = Plate(), Plate()
    local friendlyFrame, hostileFrame = UnitFrame(), UnitFrame()
    Bind(friendlyPlate, friendlyFrame, "nameplateFriendlyPet", {name = "Synthetic Pet", minion = true, friendly = true})
    Bind(hostilePlate, hostileFrame, "nameplateHostilePet", {name = "Hostile Pet", minion = true})
    plates = {friendlyPlate, hostilePlate}
    KnownPlayersSettings.nameDisplayMode = "first"
    ns.SetPlayerHealthBarMode("never")
    assert(friendlyFrame.alpha == 0 and friendlyPlate.labels[1].shown
        and friendlyPlate.labels[1].text == "Synthetic Pet" and not friendlyPlate.labels[2],
        "Never kept a health bar on an enabled friendly minion")
    assert(hostileFrame.alpha == 1 and not hostilePlate.labels[1])
    ns.SetPlayerHealthBarMode("always")
    assert(friendlyFrame.alpha == 1 and not friendlyPlate.labels[1].shown)
    combat = true
    ns.SetPlayerHealthBarMode("combat")
    assert(friendlyFrame.alpha == 1)
    combat = false
    Event("PLAYER_REGEN_ENABLED")
    Tick(0.125)
    Approx(friendlyFrame.alpha, 0.5, "minion health bar fades on combat exit")
    Tick(0.125)
    assert(friendlyFrame.alpha == 0 and friendlyPlate.labels[1].shown)
    combat = true
    Event("PLAYER_REGEN_DISABLED")
    assert(friendlyFrame.alpha == 1 and not friendlyPlate.labels[1].shown)
    ns.SetPlayerHealthBarMode("never")
    assert(friendlyFrame.alpha == 0 and friendlyPlate.labels[1].shown)
    ns.SetNPCHealthBarMode("always")
    ns.SetPlayerHealthBarMode("always")
    assert(friendlyFrame.alpha == 1 and not friendlyPlate.labels[1].shown,
        "Always did not restore a friendly minion health bar during combat")
    ns.SetPlayerHealthBarMode("never")
    combat = false
    minionsCVar = "0"
    ns.RefreshKnownNameplates()
    assert(friendlyFrame.alpha == 1 and not friendlyPlate.labels[1].shown)
    KnownPlayersSettings.nameDisplayMode = nil
    UnitIsMinion, UnitIsFriend, C_CVar = originalIsMinion, originalIsFriend, originalCVars
end

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
time = function() return 1000000 end
assert(loadfile("KnownPlayers/Backups.lua"))("KnownPlayers", ns)
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
-- A partially successful restore must forget resolved keys before later retries.
for _, config in ipairs({
    {"knownOnlyNameplates", "overheadNameCVarsBackup", ns.SyncNativeOverheadNames,
        "UnitNameFriendlyPlayerName", "UnitNameEnemyPlayerName"},
    {"filterNPCNameplates", "npcCVarBackup", ns.SyncNPCNameplateCVars,
        "UnitNameNPC", "UnitNameInteractiveNPC"},
}) do
    local toggle, backupKey, sync, first, second = unpack(config)
    cvars[first], cvars[second] = "1", "1"
    KnownPlayersSettings[toggle] = true
    sync()
    assert(cvars[first] == "0" and cvars[second] == "0")
    C_CVar.SetCVar = function(name, value)
        if name == second then return false end
        cvars[name] = value
        return true
    end
    KnownPlayersSettings[toggle] = false
    sync()
    local pending = KnownPlayersSettings[backupKey]
    assert(cvars[first] == "1" and cvars[second] == "0" and not pending[first] and pending[second] == "1")
    cvars[first] = "0"
    C_CVar.SetCVar = function(name, value) cvars[name] = value; return true end
    Event("PLAYER_REGEN_ENABLED")
    assert(cvars[first] == "0" and cvars[second] == "1" and not KnownPlayersSettings[backupKey])
end
-- The default method keeps hidden players available for recognition.
do
    local selected, nearby = Plate(), Plate()
    local selectedFrame, nearbyFrame = UnitFrame(), UnitFrame()
    local unfamiliar = {name = "Unfamiliar Player", player = true, friendly = true}
    local familiar = {name = "Familiar Player", player = true, friendly = true}
    Bind(selected, selectedFrame, "nameplateTest", unfamiliar)
    Bind(nearby, nearbyFrame, "nameplateNearby", unfamiliar)
    plates = {selected, nearby}
    function UnitIsFriend(_, unit) return units[unit].friendly == true end
    KnownPlayersSettings.knownOnlyNameplates = true
    ns.FillKnownPlayersSettingsDefaults(KnownPlayersSettings)
    KnownPlayersSettings.playerHealthBarMode, KnownPlayersSettings.npcHealthBarMode = "always", "always"

    local messages, originalPrint = {}, print
    print = function(message) messages[#messages + 1] = message end
    function selected:Show() self.shown = true end
    function nearby:Show() self.shown = true end
    ns.RefreshKnownNameplates()
    assert(not selected.shown and not nearby.shown and selectedFrame.alpha == 0 and nearbyFrame.alpha == 0)
    KnownPlayersSettings.playerNameplateFilterMethod = "alpha"
    ns.RefreshKnownNameplates()
    assert(selected.shown and nearby.shown and selectedFrame.alpha == 0 and nearbyFrame.alpha == 0)

    KnownPlayersSettings.playerNameplateFilterMethod = "hide"
    ns.RefreshKnownNameplates()
    assert(not selected.shown and not nearby.shown)
    ns.SetKnownOnlyNameplates(false)
    assert(selected.shown and nearby.shown and selectedFrame.alpha == 1 and nearbyFrame.alpha == 1)
    ns.SetKnownOnlyNameplates(true)
    assert(not selected.shown and not nearby.shown)

    local originalIsKnown = ns.IsKnownOrAssociated
    ns.IsKnownOrAssociated = function() return true end
    ns.RefreshKnownNameplates()
    assert(selected.shown and nearby.shown and selectedFrame.alpha == 1 and nearbyFrame.alpha == 1)
    ns.IsKnownOrAssociated = originalIsKnown
    ns.RefreshKnownNameplates()
    assert(not selected.shown and not nearby.shown)

    combat = true
    Event("PLAYER_REGEN_DISABLED")
    assert(selected.shown and selectedFrame.alpha == 0)
    combat = false
    Event("PLAYER_REGEN_ENABLED")
    assert(not selected.shown)

    selected.unitToken, units.nameplateTest = nil, nil
    plates = {nearby}
    Event("NAME_PLATE_UNIT_REMOVED", "nameplateTest")
    ns.RefreshKnownNameplates()
    assert(not selected.shown, "an unbound frame must stay under the client's control")
    Bind(selected, selectedFrame, "nameplateReused", familiar)
    plates = {selected, nearby}
    Event("NAME_PLATE_UNIT_ADDED", "nameplateReused")
    assert(selected.shown and selectedFrame.alpha == 1, "a recognized player must not inherit the outer hide")

    Bind(selected, selectedFrame, "nameplateReused", unfamiliar)
    local hide = selected.Hide
    selected.Hide = function() error("Restricted mock frame") end
    ns.RefreshKnownNameplates()
    assert(selected.shown and selectedFrame.alpha == 0)

    plates = {selected} -- Simulate a client dropping a still-bound hidden plate from enumeration.
    ns.RefreshKnownNameplates()
    assert(nearby.shown and messages[#messages]:find("Using transparency for this session", 1, true))
    assert(KnownPlayersSettings.playerNameplateFilterMethod == "hide")
    selected.Hide = hide
    ns.RefreshKnownNameplates()
    assert(selected.shown and selectedFrame.alpha == 0, "session fallback must prevent subsequent outer hides")
    print = originalPrint
end

print("Nameplate lifecycle, filtering methods, scaling, and settings restoration checks passed.")

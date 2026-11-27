-- Run from the repository root with all shipped Lua paths as arguments.
local addon = "KnownPlayers"
local toc = addon .. "/" .. addon .. ".toc"
local manifest = assert(io.open(toc))
local entries, listed = {}, {}
for line in manifest:lines() do
    local path = line:match("^%s*(.-)%s*$")
    if path ~= "" and path:sub(1, 1) ~= "#" then
        path = addon .. "/" .. path:gsub("\\", "/")
        assert(not listed[path], toc .. " lists " .. path .. " twice")
        listed[path] = true
        local file = assert(io.open(path))
        file:close()
        entries[#entries + 1] = path
    end
end
manifest:close()
assert(#arg > 0, "Pass the shipped Lua paths to compare with the TOC")
for _, path in ipairs(arg) do
    assert(listed[path:gsub("\\", "/")], path .. " is missing from " .. toc)
end

local frames = {}
local attachedMinimapMask
local function Noop() end
local widget = setmetatable({
    ClearAllPoints = Noop, Update = Noop, RegisterForClicks = Noop, Disable = Noop,
    EnableMouse = Noop,
}, {__index = function(_, name)
    if name:match("^Set") then return Noop end
end})
function widget:RegisterEvent(event) self.events[event] = true end
function widget:UnregisterEvent(event) self.events[event] = nil end
function widget:SetScript(script, handler) self[script] = handler end
function widget:SetupMenu(callback) self.menuSetup = callback end
function widget:SetSelectionText(callback) self.selectionText = callback end
function widget:HookScript(script, handler)
    local previous = rawget(self, script)
    self[script] = function(...)
        if previous then previous(...) end
        handler(...)
    end
end
function widget:SetSize(width, height) self.width, self.height = width, height end
function widget:SetPoint(point, _, _, x, y)
    if point == "TOPLEFT" then self.leftOffset, self.topOffset = x, y end
end
function widget:SetText(text) self.text = text end
function widget:GetText() return self.text end
function widget:SetChecked(checked) self.checked = checked end
function widget:GetChecked() return self.checked end
function widget:SetAllPoints(target) self.allPointsTarget = target end
function widget:AddMaskTexture(mask) attachedMinimapMask = mask end
function widget:HasFocus() return self.focused end
function widget:ClearFocus()
    if not self.focused then return end
    self.focused = false
    if self.OnEditFocusLost then self:OnEditFocusLost() end
end
function widget:EnableMouseWheel(enabled) self.mouseWheelEnabled = enabled end
function widget:SetWidth(width) self.width = width end
function widget:SetHeight(height) self.height = height end
function widget:GetWidth() return self.width or 0 end
function widget:GetHeight() return self.height or 0 end
function widget:GetStringHeight() return 12 end
function widget:GetStringWidth() return 40 end
function widget:GetFrameLevel() return 0 end
function widget:IsShown() return self.shown end
widget.IsVisible = widget.IsShown
function widget:SetShown(shown)
    if self.shown == shown then return end
    self.shown = shown
    if shown and self.OnShow then self:OnShow() end
end
function widget:Hide() self:SetShown(false) end
function widget:Show() self:SetShown(true) end
local function NewWidget()
    return setmetatable({shown = true, events = {}}, {__index = widget})
end
widget.CreateFontString, widget.CreateTexture, widget.GetFontString = NewWidget, NewWidget, NewWidget
widget.CreateMaskTexture = NewWidget

function CreateFrame(_, _, parent, template)
    local frame = NewWidget()
    frame.parent = parent
    if template == "InterfaceOptionsCheckButtonTemplate" then frame.Text = NewWidget() end
    if template == "UIPanelScrollFrameTemplate" then frame.ScrollBar = NewWidget() end
    frames[#frames + 1] = frame
    return frame
end

StaticPopupDialogs, SlashCmdList = {}, {}
Minimap = NewWidget()
PanelTemplates_TabResize, PanelTemplates_ResizeTabsToFit = Noop, Noop
PanelTemplates_SetTab, PanelTemplates_SetNumTabs = Noop, Noop
local settingsRegistered = false
function InterfaceOptions_AddCategory() settingsRegistered = true end
time = os.time
function InCombatLockdown() return false end
function GetNumGroupMembers() return 0 end
function IsInGuild() return false end
function BNConnected() return false end
local tickerStarted = false
C_Timer = {NewTicker = function() tickerStarted = true end}

local npcDistance, distanceWrites = "45.25", 0
C_CVar = {
    GetCVar = function(key) if key == "nameplateMaxDistance" then return npcDistance end end,
    SetCVar = function(key, value)
        assert(key == "nameplateMaxDistance")
        npcDistance = tonumber(value) > 100 and "100" or value
        distanceWrites = distanceWrites + 1
        return true
    end,
}

local hitTestInsets = {[0] = {1, 2, 3, 4}, [1] = {5, 6, 7, 8}}
Enum = {NamePlateType = {Friendly = 0, Enemy = 1}}
C_NamePlateManager = {
    GetNamePlateHitTestInsets = function(plateType) return unpack(hitTestInsets[plateType]) end,
    SetNamePlateHitTestInsets = function(plateType, ...) hitTestInsets[plateType] = {...} end,
}

local ns = {}
for _, path in ipairs(entries) do
    if path:match("%.lua$") then
        local ok, message = pcall(assert(loadfile(path)), addon, ns)
        assert(ok, "Loading " .. path .. " in TOC order failed: " .. tostring(message))
    end
end

for i = 1, #frames do
    local frame = frames[i]
    if frame.events.ADDON_LOADED then frame:OnEvent("ADDON_LOADED", addon) end
end
assert(settingsRegistered and tickerStarted and type(SlashCmdList.KNOWNPLAYERS) == "function",
    "KnownPlayers did not finish ADDON_LOADED startup")
assert(attachedMinimapMask and attachedMinimapMask.allPointsTarget.width == 20,
    "the minimap icon should fill its circular mask")
local centeredScroller = false
for _, frame in ipairs(frames) do
    if frame.scrollBarHideable then
        assert(not frame.ScrollBar:IsShown() and frame.mouseWheelEnabled == false)
        local leftOffset = frame.leftOffset
        frame:OnScrollRangeChanged(0, 50)
        assert(frame.mouseWheelEnabled)
        assert(frame.leftOffset <= leftOffset)
        centeredScroller = centeredScroller or frame.leftOffset < leftOffset
        frame:OnScrollRangeChanged(0, 0)
        assert(not frame.mouseWheelEnabled)
        assert(frame.leftOffset == leftOffset)
    end
end
assert(centeredScroller, "Appearance should make room for the scrollbar when content overflows")

local playerFilter, npcFilter, clickToggle
for _, frame in ipairs(frames) do
    if frame.Text and frame.Text.text == "Enable player nameplate filtering" then
        playerFilter = frame
    elseif frame.Text and frame.Text.text == "Enable NPC nameplate filtering" then
        npcFilter = frame
    elseif frame.Text and frame.Text.text == "Clickable nameplates" then
        clickToggle = frame
    end
end
assert(playerFilter and npcFilter and playerFilter.topOffset > npcFilter.topOffset,
    "Both nameplate filtering toggles must be available on the main page")
assert(clickToggle and clickToggle.parent == npcFilter.parent and clickToggle.topOffset < npcFilter.topOffset)
assert(clickToggle:GetChecked() and hitTestInsets[0][1] == 1 and hitTestInsets[1][4] == 8)
clickToggle:SetChecked(false)
clickToggle:OnClick()
assert(not KnownPlayersSettings.nameplatesClickable and hitTestInsets[0][1] > 100 and hitTestInsets[1][4] > 100)
clickToggle:SetChecked(true)
clickToggle:OnClick()
assert(KnownPlayersSettings.nameplatesClickable and hitTestInsets[0][1] == 1 and hitTestInsets[1][4] == 8)

local npcDistanceInput, appearanceEvents
for _, frame in ipairs(frames) do
    if frame.OnEnterPressed and frame:GetText() == "45.25" then npcDistanceInput = frame end
    if frame.events.CVAR_UPDATE and frame.parent and frame.parent.fitHeightContent then appearanceEvents = frame end
end
assert(npcDistanceInput and appearanceEvents and distanceWrites == 0)
appearanceEvents.parent.shown = true
npcDistance = "75"
appearanceEvents:OnEvent("CVAR_UPDATE", "nameplateMaxDistance")
assert(npcDistanceInput:GetText() == "75" and distanceWrites == 0, "refresh must preserve a console change")
npcDistanceInput.focused = true
npcDistanceInput:SetText("90.5")
npcDistanceInput:OnEnterPressed()
assert(npcDistance == "90.5" and distanceWrites == 1, "the NPC distance editor must send the submitted value")
npcDistanceInput.focused = true
npcDistanceInput:SetText("100")
npcDistanceInput:OnEscapePressed()
assert(npcDistanceInput:GetText() == "90.5" and distanceWrites == 1, "cancel must discard the draft")
npcDistanceInput.focused = true
npcDistanceInput:SetText("not a distance")
npcDistanceInput:OnEnterPressed()
assert(distanceWrites == 1, "invalid input must not write the CVar")
npcDistanceInput.focused = true
npcDistanceInput:SetText("120")
npcDistanceInput:OnEnterPressed()
assert(npcDistanceInput:GetText() == "100" and distanceWrites == 2, "show the value the client actually accepted")

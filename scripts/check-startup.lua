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
function widget:SetPoint(point, _, _, x)
    if point == "TOPLEFT" then self.leftOffset = x end
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

function CreateFrame(_, _, _, template)
    local frame = NewWidget()
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

local filterMethodDropdown
for _, frame in ipairs(frames) do
    if frame.selectionText and frame.selectionText() == "Hide nameplate frame" then
        filterMethodDropdown = frame
        break
    end
end
assert(filterMethodDropdown, "The player filtering dropdown must show the default")
local filterChoices = {}
filterMethodDropdown.menuSetup(filterMethodDropdown, {CreateRadio = function(_, label, selected, choose, value)
    filterChoices[label] = {selected = selected, choose = choose, value = value}
end})
local alpha = assert(filterChoices["Transparency only"])
assert(not alpha.selected(alpha.value))
alpha.choose(alpha.value)
assert(KnownPlayersSettings.playerNameplateFilterMethod == "alpha" and alpha.selected(alpha.value))
assert(filterMethodDropdown.selectionText() == "Transparency only")

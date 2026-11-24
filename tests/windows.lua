-- Exercise list opening and Escape through the same frame scripts WoW calls.
local named, edits, labels = {}, {}, {}
local function Noop() end
local frameMethods = setmetatable({}, {__index = function(_, key)
    if key:match("^Set") or key:match("^Register") or key == "EnableMouse" or key == "EnableKeyboard"
        or key == "UnregisterEvent" or key == "Raise" or key == "SetupMenu" or key == "ClearFocus" then
        return Noop
    end
end})

function frameMethods:SetScript(script, callback) self.scripts[script] = callback end
function frameMethods:HookScript(script, callback)
    local previous = self.scripts[script]
    self.scripts[script] = function(frame, ...)
        if previous then previous(frame, ...) end
        callback(frame, ...)
    end
end
function frameMethods:IsShown() return self.shown end
function frameMethods:IsMenuOpen() return false end
function frameMethods:SetShown(shown)
    if self.shown == shown then return end
    self.shown = shown
    local callback = self.scripts[shown and "OnShow" or "OnHide"]
    if callback then callback(self) end
end
function frameMethods:Show() self:SetShown(true) end
function frameMethods:Hide() self:SetShown(false) end
function frameMethods:SetText(text)
    self.text = text
    if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end
end
function frameMethods:GetText() return self.text or "" end
function frameMethods:CreateFontString()
    local label = CreateFrame("FontString")
    labels[#labels + 1] = label
    return label
end
function frameMethods:CreateTexture() return CreateFrame("Texture") end

function CreateFrame(kind, name)
    local frame = setmetatable({shown = true, scripts = {}}, {__index = frameMethods})
    if name then named[name] = frame end
    if kind == "EditBox" then edits[#edits + 1] = frame end
    return frame
end

StaticPopupDialogs = {}
local refreshes = 0
local ns = {
    HasRemovalUndo = function() return false end,
    GetCategoryPlayers = function()
        refreshes = refreshes + 1
        return {{key = "Sample-Player-CAMWOW1", name = "Sample Player", realm = "CAMWOW1", appearance = {}}}
    end,
}
for _, module in ipairs({"Safety", "Categories", "Windows", "PlayerList"}) do
    assert(loadfile("KnownPlayers/" .. module .. ".lua"))("KnownPlayers", ns)
end

local settingsPage = {}
ns.OpenPlayerList("party", settingsPage)
local list = assert(named.KnownPlayersPartyListWindow)
assert(refreshes == 1 and list:IsShown())
ns.OpenPlayerList("party", settingsPage)
assert(refreshes == 2)
edits[1]:SetText(" sample-player ")
assert(labels[2]:GetText() == "1 players (1 shown)")
edits[1]:SetText("other-player")
assert(labels[2]:GetText() == "1 players (0 shown)")

local parent = CreateFrame("Frame")
parent.hideOtherWindows = true
ns.EnableWindowEscape(parent)
ns.ShowWindow(parent)
assert(parent:IsShown() and not list:IsShown())
ns.OpenPlayerList("party", settingsPage)
assert(list:IsShown() and not parent:IsShown() and refreshes == 5)
edits[1].scripts.OnEscapePressed(edits[1])
assert(parent:IsShown() and not list:IsShown())
ns.OpenPlayerList("party", settingsPage)
ns.CloseWindowsFromSettingsPage(settingsPage)
assert(parent:IsShown() and not list:IsShown())

print("Player list refresh, name search, Escape, and settings ownership checks passed.")

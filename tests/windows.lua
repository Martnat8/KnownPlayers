-- Exercise list opening and Escape through the same frame scripts WoW calls.
local named, edits, labels, buttons = {}, {}, {}, {}
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
function frameMethods:IsVisible()
    return self.shown and (not self.parent or self.parent:IsVisible())
end
function frameMethods:IsMenuOpen() return false end
function frameMethods:SetShown(shown)
    if self.shown == shown then return end
    self.shown = shown
    local callback = self.scripts[shown and "OnShow" or "OnHide"]
    if callback then callback(self) end
end
function frameMethods:Show() self:SetShown(true) end
function frameMethods:Hide() self:SetShown(false) end
function frameMethods:SetText(text, userInput)
    self.text = text
    self.selectedText = nil
    if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, userInput) end
end
function frameMethods:GetText() return self.text or "" end
function frameMethods:SetAlpha(alpha) self.alpha = alpha end
function frameMethods:GetAlpha() return self.alpha or 1 end
function frameMethods:SetHighlightColor(...) self.highlightColor = {...} end
function frameMethods:GetHighlightColor() return unpack(self.highlightColor or {0.8, 0.7, 0.6, 0.5}) end
function frameMethods:SetFocus() self.focused = true end
function frameMethods:ClearFocus() self.focused = false end
function frameMethods:HighlightText() self.selectedText = self:GetText() end
function frameMethods:SetEnabled(enabled) self.enabled = enabled end
function frameMethods:SetPoint(...) self.point = {...} end
function frameMethods:SetTexture(texture) self.texturePath = texture end
function frameMethods:SetChecked(checked) self.checked = checked end
function frameMethods:GetChecked() return self.checked end
function frameMethods:SetSelectionText(callback) self.selectionText = callback end
function frameMethods:GenerateMenu() end
function frameMethods:Update() end
function frameMethods:StopMovingOrSizing() end
function frameMethods:GetStringHeight() return 12 end
function frameMethods:CreateFontString()
    local label = CreateFrame("FontString")
    labels[#labels + 1] = label
    return label
end
function frameMethods:CreateTexture() return CreateFrame("Texture") end

function CreateFrame(kind, name, parent, template)
    local frame = setmetatable({shown = true, scripts = {}, parent = parent}, {__index = frameMethods})
    if name then named[name] = frame end
    if kind == "EditBox" then edits[#edits + 1] = frame end
    if kind == "Button" or kind == "CheckButton" then buttons[#buttons + 1] = frame end
    if kind == "CheckButton" then frame.Text = CreateFrame("FontString") end
    if template == "BasicFrameTemplateWithInset" then
        frame.TitleText = CreateFrame("FontString")
        frame.CloseButton = CreateFrame("Button", nil, frame)
    end
    if template == "UIPanelInputScrollFrameTemplate" then frame.EditBox = CreateFrame("EditBox", nil, frame) end
    return frame
end

StaticPopupDialogs = {}
UISpecialFrames = {}
local refreshes = 0
local appearance = {categories = {}}
local ns = {
    HasRemovalUndo = function() return false end,
    PlayerHasCategory = function(record, key) return record.categories[key] == true end,
    SetPlayerAvoided = function(key, record, avoided)
        assert(key == "Sample-Player-CAMWOW1" and record == appearance)
        record.categories.avoid = avoided
    end,
    GetCategoryPlayers = function()
        refreshes = refreshes + 1
        return {{key = "Sample-Player-CAMWOW1", name = "Sample Player", realm = "CAMWOW1", appearance = appearance}}
    end,
}
for _, module in ipairs({"Safety", "Categories", "Windows", "PlayerList"}) do
    assert(loadfile("KnownPlayers/" .. module .. ".lua"))("KnownPlayers", ns)
end

local settingsPage = {}
ns.OpenPlayerList("party", settingsPage)
local list = assert(named.KnownPlayersPartyListWindow)
assert(refreshes == 1 and list:IsShown())
local avoidAction
for _, button in ipairs(buttons) do
    if button.tooltip == "Add to Avoid" then avoidAction = button; break end
end
assert(avoidAction and avoidAction.point[2] == avoidAction.parent.favoriteButton)
assert(avoidAction.icon.texturePath == "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01")
assert(avoidAction.parent.removeButton.point[2] == avoidAction)
avoidAction.scripts.OnClick()
assert(appearance.categories.avoid)
ns.OpenPlayerList("party", settingsPage)
assert(refreshes == 2 and avoidAction.tooltip == "Remove from Avoid")
edits[1]:SetText(" sample-player ")
assert(labels[1]:GetText() == "1 players (1 shown)")
edits[1]:SetText("other-player")
assert(labels[1]:GetText() == "1 players (0 shown)")

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

local escapeFrame = assert(named[UISpecialFrames[1]])
assert(#UISpecialFrames == 1 and escapeFrame:IsShown())
ns.OpenPlayerList("party", settingsPage)
list.classFilter.IsMenuOpen = function() return true end
list.classFilter.CloseMenu = function(self) self.IsMenuOpen = function() return false end end
escapeFrame:Hide()
assert(list:IsShown() and not list.classFilter:IsMenuOpen())
escapeFrame:Hide()
assert(parent:IsShown() and not list:IsShown())
ns.OpenPlayerList("party", settingsPage)
list.CloseButton.scripts.OnClick(list.CloseButton)
assert(parent:IsShown() and not list:IsShown())
escapeFrame:Hide()
assert(not parent:IsShown() and not escapeFrame:IsShown())

-- Exercise the backup window's confirmation buttons and status through its frame scripts.
time, date = os.time, os.date
KnownPlayersDB = {players = {}, npcs = {["42"] = {name = "Synthetic NPC"}}, npcOverrides = {}}
KnownPlayersSettings = {trackBattleNetAssociations = false}
for _, module in ipairs({"Backups", "BackupWindow"}) do
    assert(loadfile("KnownPlayers/" .. module .. ".lua"))("KnownPlayers", ns)
end
local popup, popupAction
function StaticPopup_Show(dialog, _, _, action)
    popup, popupAction = dialog, action
end
local function Confirm()
    StaticPopupDialogs[popup].OnAccept(nil, popupAction)
end
local function Button(text)
    for _, button in ipairs(buttons) do
        if button:IsVisible() and (button:GetText() == text or (button.Text and button.Text:GetText() == text)) then
            return button
        end
    end
    error("Missing button " .. text)
end
local function Click(text)
    local button = Button(text)
    assert(button.enabled ~= false)
    button.scripts.OnClick(button)
end
local function HasLabel(text)
    for _, label in ipairs(labels) do
        if label:GetText():find(text, 1, true) then return true end
    end
    return false
end

-- All Players should explain empty results and keep History tied to the current row.
assert(loadfile("KnownPlayers/Database.lua"))("KnownPlayers", ns)
ns.OpenPlayerList("players", settingsPage)
local allPlayers = assert(named.KnownPlayersAllPlayersWindow)
local playerSearch = edits[#edits]
assert(allPlayers.classFilter.selectionText() == "All classes")
assert(HasLabel("No saved players yet"))

local name = "Synthetic Long Player Display Name"
local firstKey, secondKey = "synthetic-1", "synthetic-2"
KnownPlayersDB.players = {
    [firstKey] = {displayName = name, realm = "Synthetic Glade", categories = {trade = true}, lastSeen = 1},
    [secondKey] = {displayName = name, realm = "Synthetic Vale", categories = {party = true}, lastSeen = 2},
}
allPlayers.Refresh()
Click("None")
assert(HasLabel("Select at least one reason"))
Click("All")
playerSearch:SetText("Unmatched Realm")
assert(HasLabel("No matching players"))
playerSearch:SetText("")

local historyKey
local openHistory = ns.OpenPlayerHistory
ns.OpenPlayerHistory = function(key) historyKey = key end
local history = Button("History")
GameTooltip = {
    SetOwner = function(self, owner) self.owner = owner end,
    IsOwned = function(self, owner) return self.owner == owner end,
    SetText = function(self, text) self.text = text end,
    Show = Noop,
    Hide = function(self) self.owner = nil end,
}
history.scripts.OnEnter(history)
assert(GameTooltip.text == name .. "\nSynthetic Glade")
Click("History")
assert(historyKey == firstKey)

local mostRecent = Button("Most recent first")
mostRecent:SetChecked(true)
Click("Most recent first")
assert(GameTooltip.text == name .. "\nSynthetic Vale")
Click("History")
assert(historyKey == secondKey)
playerSearch:SetText("Synthetic Glade")
assert(HasLabel("2 players (1 shown)"))
assert(GameTooltip.text == name .. "\nSynthetic Glade")
Click("History")
assert(historyKey == firstKey)
history.scripts.OnLeave(history)
assert(not GameTooltip:IsOwned(history))
GameTooltip = nil
ns.OpenPlayerHistory = openHistory
allPlayers:Hide()

local historyRecord = KnownPlayersDB.players[firstKey]
ns.OpenPlayerHistory(firstKey)
local editor = assert(named.KnownPlayersPlayerHistoryWindow)
local note = edits[#edits - 1]
note:SetText("Synthetic draft")
KnownPlayersDB.players[firstKey] = nil
Click("Save")
assert(editor:IsShown() and note:GetText() == "Synthetic draft")
assert(HasLabel("This player record is no longer available"))
KnownPlayersDB.players[firstKey] = historyRecord
Click("Save")
assert(not editor:IsShown() and historyRecord.note == "Synthetic draft")
KnownPlayersDB.players = {}

local manual = assert(ns.CreateRestorePoint("manual", "Manual backup", {npcs = true}))
local automatic = assert(ns.CreateRestorePoint("automatic", "Automatic backup", {npcs = true}))
ns.OpenBackupWindow()
Click("Delete Restore Point")
assert(ns.GetRestorePoint("manual") == manual)
Confirm()
assert(not ns.GetRestorePoint("manual") and ns.GetRestorePoint("automatic") == automatic)
Click("Restore Selected")
ns.ClearRemovalUndo = function() end
ns.RefreshKnownNameplates = function() error("Synthetic refresh failure") end
ns.RefreshPlayerListWindows = function() end
KnownPlayersDB.npcs = {["43"] = {name = "Previous NPC"}}
Confirm()
assert(KnownPlayersDB.npcs["42"] and ns.GetRestorePoint("automatic").sections.npcs.records["43"])
assert(HasLabel("Backup restored. Some views could not refresh."))
Click("Delete Restore Point")
Confirm()
assert(not ns.GetRestorePoint("automatic") and Button("Delete Restore Point").enabled == false)

-- Run both transfer pages with the same payload, including the reveal fallback.
local serialized
local payload = string.rep("A", 4 * 1024 * 1024 - 256)
C_EncodingUtil = {
    SerializeCBOR = function(snapshot) serialized = snapshot; return payload end,
    DeserializeCBOR = function(text) if text == payload then return serialized end end,
    EncodeBase64 = function(text) return text end,
    DecodeBase64 = function(text) return text end,
}
local exportEdit, importEdit = edits[#edits - 1], edits[#edits]
KnownPlayersSettings.trackBattleNetAssociations = true
KnownPlayersDB.players["Synthetic-CAMWOW1"] = {note = "Synthetic note", categories = {manual = true}}
Click("Export")
assert(exportEdit.parent:GetAlpha() == 0 and Button("Show Backup Text").enabled == false)
assert(Button("Settings"):GetChecked() and Button("Player history"):GetChecked() and Button("Saved NPCs"):GetChecked())
Click("Prepare to Copy")
assert(serialized.sections.players.records["Synthetic-CAMWOW1"].note == "Synthetic note")
local copied = "KnownPlayers:1:" .. payload
assert(exportEdit.focused and exportEdit:GetText() == copied and exportEdit.selectedText == copied)
assert(exportEdit.parent:GetAlpha() == 0)
assert(select(4, exportEdit:GetHighlightColor()) == 0, "Masked export still renders a text selection")
assert(HasLabel("Backup ready. Press Ctrl+C") and HasLabel("Settings, 1 player record, 1 saved NPC"))
Click("Show Backup Text")
assert(exportEdit.parent:GetAlpha() == 1 and exportEdit:GetText() == copied)
assert(table.concat({exportEdit:GetHighlightColor()}, ",") == "0.8,0.7,0.6,0.5")
Click("Hide Backup Text")
assert(exportEdit.parent:GetAlpha() == 0 and select(4, exportEdit:GetHighlightColor()) == 0)

KnownPlayersSettings.trackBattleNetAssociations = false
Click("Import")
assert(exportEdit:GetText() == "" and not exportEdit.focused)
Click("Paste Backup")
assert(importEdit.focused and importEdit.parent:GetAlpha() == 0)
importEdit:SetText(copied, true)
assert(not importEdit.focused and importEdit.parent:GetAlpha() == 0)
assert(HasLabel("Settings, 1 player record, 1 saved NPC") and HasLabel("Enable: Known Battle.net Alts"))
assert(not KnownPlayersSettings.trackBattleNetAssociations and Button("Merge").enabled)
Click("Show Backup Text")
assert(importEdit.parent:GetAlpha() == 1 and importEdit:GetText() == copied)
Click("Hide Backup Text")
local importSettings = Button("Settings")
importSettings:SetChecked(false)
importSettings.scripts.OnClick(importSettings)
assert(not HasLabel("Enable: Known Battle.net Alts") and Button("Merge").enabled)
Click("Paste Backup")
assert(importEdit.selectedText == copied)
assert(select(4, importEdit:GetHighlightColor()) == 0)
importEdit:SetText(copied:sub(1, 50), true)
assert(HasLabel("Could not read this backup") and Button("Replace Selected").enabled == false)
assert(Button("Import Settings").enabled == false and KnownPlayersDB.npcs["42"])
Click("Paste Backup")
importEdit:SetText(copied, true)
for _, label in ipairs({"Settings", "Player history"}) do
    local checkbox = Button(label)
    checkbox:SetChecked(false)
    checkbox.scripts.OnClick(checkbox)
end
Click("Merge")
assert(HasLabel("Import complete.") and importEdit:GetText() == "" and not importEdit.focused)
assert(Button("Import Settings").enabled == false and not KnownPlayersSettings.trackBattleNetAssociations)

Click("Export")
for _, label in ipairs({"Player history", "Saved NPCs"}) do
    local checkbox = Button(label)
    checkbox:SetChecked(false)
    checkbox.scripts.OnClick(checkbox)
end
Click("Prepare to Copy")
assert(serialized.sections.settings and not serialized.sections.players and not serialized.sections.npcs)

print("Player list and backup window behavior checks passed.")

local addonName, ns = ...
local panel, settingsWindow
local settingsRefreshers = {}

local TABLE_LEFT, ROW_HEIGHT = 18, 31
local TRACKING_CONTROLS = {
    durationX = 164, duration = 123, priorityX = 298, arrow = 25, arrowGap = 3,
    manage = 70, gap = 8, color = 72,
}
local CONTENT_RIGHT_PADDING = 18
local SCROLL_LEFT, SCROLL_RIGHT = 3, 28
local SCROLL_TOP, SCROLL_BOTTOM = 4, 6
local PAGE_PADDING, WINDOW_PADDING = 6, 10
local MIN_SETTINGS_HEIGHT = 340
local CONTENT_WIDTH = TABLE_LEFT + TRACKING_CONTROLS.priorityX + 2 * TRACKING_CONTROLS.arrow
    + TRACKING_CONTROLS.arrowGap + TRACKING_CONTROLS.gap + TRACKING_CONTROLS.manage + CONTENT_RIGHT_PADDING
local INSET_WIDTH = CONTENT_WIDTH + SCROLL_LEFT + SCROLL_RIGHT + 2 * PAGE_PADDING
local function RegisterSettingsRefresher(callback)
    settingsRefreshers[#settingsRefreshers + 1] = callback
end
local function RefreshSettingsControls()
    for _, callback in ipairs(settingsRefreshers) do callback() end
end

function ns.ApplyKnownPlayersSettings(settings)
    -- The CVar backups describe this client and travel with its live settings.
    local previous = KnownPlayersSettings or {}
    previous.knownOnlyNameplates = false
    previous.filterNPCNameplates = false
    if ns.RestoreNativeOverheadNames then ns.RestoreNativeOverheadNames() end
    if ns.RestoreNPCNameplateCVars then ns.RestoreNPCNameplateCVars() end
    settings.overheadNameCVarsBackup = previous.overheadNameCVarsBackup
    settings.npcCVarBackup = previous.npcCVarBackup
    KnownPlayersSettings = settings
    ns.InitializeDatabase()
    if ns.InitializeNameplateColors then ns.InitializeNameplateColors() end
    RefreshSettingsControls()
    ns.RefreshMinimapButton()
    if ns.InvalidateBattleNetIndex then ns.InvalidateBattleNetIndex() end
    if ns.SyncNativeOverheadNames then ns.SyncNativeOverheadNames() end
    if ns.SyncNPCNameplateCVars then ns.SyncNPCNameplateCVars() end
    if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
    if ns.RefreshPlayerListWindows then ns.RefreshPlayerListWindows() end
end

StaticPopupDialogs["KNOWNPLAYERS_RESET_SETTINGS"] = {
    text = "Reset all KnownPlayers settings to their defaults?\n\nA restore point will be saved in Backup & Restore.",
    button1 = "Reset Settings",
    button2 = CANCEL,
    OnAccept = function()
        if not ns.BackupBeforeChange("Before resetting settings") then return end
        ns.ApplyKnownPlayersSettings({})
        print("|cff33ff99KnownPlayers:|r Settings restored to defaults.")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function Label(parent, value, x, y, font)
    local label = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetText(value)
    return label
end

local function Button(parent, value, width, click)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 115, 25)
    button:SetText(value)
    button:SetScript("OnClick", click)
    return button
end

local function ColorButton(parent, click)
    local button = Button(parent, "Color", TRACKING_CONTROLS.color, click)
    local swatch = button:CreateTexture(nil, "OVERLAY")
    swatch:SetSize(12, 12)
    swatch:SetPoint("LEFT", button, "LEFT", 10, 0)
    local text = button:GetFontString()
    text:ClearAllPoints()
    text:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
    return button, swatch
end

local function PriorityButton(parent, direction, click)
    local button = Button(parent, "", TRACKING_CONTROLS.arrow, click)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAtlas("minimal-scrollbar-arrow-" .. direction)
    icon:SetSize(17, 11)
    icon:SetPoint("CENTER")
    button:HookScript("OnEnable", function() icon:SetAlpha(1) end)
    button:HookScript("OnDisable", function() icon:SetAlpha(0.4) end)
    return button
end

local function ShowAbout(parent)
    if parent.aboutWindow then
        ns.ShowWindow(parent.aboutWindow)
        return
    end

    local standalone = settingsWindow and parent:GetParent() == settingsWindow
    local name = standalone and "KnownPlayersStandaloneAboutWindow" or "KnownPlayersAboutWindow"
    local frame = CreateFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset")
    frame:SetWidth(520)
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    if frame.TitleText then frame.TitleText:SetText("About KnownPlayers") end
    frame:Hide()
    ns.EnableWindowEscape(frame)
    if not standalone then parent:HookScript("OnHide", function() frame:Hide() end) end

    Label(frame, "Version " .. ns.AddonVersion, 22, -38)
    local y = -62
    for _, section in ipairs({
        {"Remembering players",
            "Choose which interactions to track on Player Nameplates. Use a portrait menu or /kp remember to save someone manually. Open Player History to see why you know them and add a note, tags, or a favorite."},
        {"NPC filtering and overrides",
            "Automatic NPC categories use QuestieDB. The filter leaves attackable monsters and unclassified NPCs visible. In the NPC Manager, Overrides lists NPCs set to Always Show or Always Hide. Automatic clears the override."},
        {"Nameplate distance and opacity",
            "The sliders show the values WoW accepts. The game controls which nameplates exist and can cap their visible range. Always Show applies to nameplates the game supplies."},
        {"Saved lists",
            "History and notes stay on this computer. Favorites stay saved when inactive. Use Undo or /kp undo within 30 seconds of an individual removal. Reset Settings to Defaults keeps your lists."},
    }) do
        Label(frame, section[1], 22, y, "GameFontNormal")
        local details = Label(frame, section[2], 22, y - 19, "GameFontHighlight")
        details:SetWidth(476)
        details:SetJustifyH("LEFT")
        y = y - 19 - details:GetStringHeight() - 14
    end
    frame:SetHeight(-y + 8)

    parent.aboutWindow = frame
    ns.ShowWindow(frame)
end

local function Checkbox(parent, x, y, title, current, onClick, getCurrent)
    local button = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button.Text:SetText(title)
    button:SetChecked(current)
    button:SetScript("OnClick", function(self)
        onClick(self:GetChecked() and true or false)
    end)
    if getCurrent then
        RegisterSettingsRefresher(function() button:SetChecked(getCurrent() and true or false) end)
    end
    return button
end

local function AddFriendlyMinionVisibility(parent, x, y)
    local toggle
    local function Refresh()
        local visible, available = ns.GetFriendlyMinionVisibility()
        toggle:SetChecked(visible)
        toggle:SetEnabled(available and not InCombatLockdown())
    end

    toggle = Checkbox(parent, x, y, "Show friendly player minions", false, function(checked)
        if not InCombatLockdown() and not ns.SetFriendlyMinionVisibility(checked) then
            print("|cff33ff99KnownPlayers:|r WoW could not change some friendly minion visibility settings.")
        end
        Refresh()
    end)
    toggle:RegisterEvent("CVAR_UPDATE")
    toggle:RegisterEvent("PLAYER_REGEN_DISABLED")
    toggle:RegisterEvent("PLAYER_REGEN_ENABLED")
    toggle:SetScript("OnEvent", Refresh)
    RegisterSettingsRefresher(Refresh)
    Refresh()
end

local function NewScrollingPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    local scroller = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroller:SetPoint("TOPLEFT", page, "TOPLEFT", SCROLL_LEFT, -SCROLL_TOP)
    scroller:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -SCROLL_RIGHT, SCROLL_BOTTOM)
    local content = CreateFrame("Frame", nil, scroller)
    content:SetSize(CONTENT_WIDTH, 600)
    scroller:SetScrollChild(content)
    scroller:SetScript("OnSizeChanged", function(self)
        local width = self:GetWidth()
        if width > 0 then content:SetWidth(math.min(CONTENT_WIDTH, width)) end
    end)
    return page, content
end

local function SetCategoryTracking(key, checked)
    local category = key == "associated" and ns.AssociatedCategory or ns.PlayerCategoryByKey[key]
    if category.group then
        KnownPlayersSettings.trackGroup[category.group] = checked
        if checked and ns.ScanGroupRoster then ns.ScanGroupRoster() end
    else
        KnownPlayersSettings[category.tracking] = checked
        if checked and key == "guild" and ns.RequestGuildRoster then
            ns.RequestGuildRoster()
            if ns.ScanGuildRoster then ns.ScanGuildRoster() end
        elseif checked and key == "associated" and ns.ScanBattleNetFriends then
            ns.ScanBattleNetFriends()
        end
    end
    if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
end

local RETENTION_PRESETS = {
    {"1 minute", 0, 0, 1}, {"5 minutes", 0, 0, 5},
    {"1 hour", 0, 1, 0}, {"6 hours", 0, 6, 0},
    {"12 hours", 0, 12, 0}, {"1 day", 1, 0, 0},
    {"3 days", 3, 0, 0}, {"7 days", 7, 0, 0},
    {"14 days", 14, 0, 0}, {"30 days", 30, 0, 0},
    {"90 days", 90, 0, 0},
}

local function Dropdown(parent, x, y, width)
    local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dropdown:SetSize(width, 24)
    dropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    return dropdown
end

local function AddRetentionDropdown(row, key, x, relayout)
    local dropdown = Dropdown(row, x, -2, TRACKING_CONTROLS.duration)
    if not ns.GetCategoryRetention(key) then
        dropdown:SetText("Forever")
        dropdown:Disable()
        return
    end

    local fields = {}
    local units = {"days", "hours", "minutes"}
    local limits = {days = 180, hours = 23, minutes = 59}
    local shortLabels = {days = "d", hours = "h", minutes = "m"}
    local custom = CreateFrame("Frame", nil, row)
    custom:SetSize(240, 24)
    custom:SetPoint("TOPLEFT", row, "TOPLEFT", x, -32)
    local customSelected = false
    local forever, customOption = {"Forever"}, {"Custom..."}

    local function GetSelection()
        local duration = ns.GetCategoryRetention(key)
        if not duration.enabled then return forever end
        if not customSelected then
            for _, preset in ipairs(RETENTION_PRESETS) do
                if duration.days == preset[2] and duration.hours == preset[3]
                    and duration.minutes == preset[4] then return preset end
            end
        end
        return customOption
    end

    local function Refresh()
        local duration = ns.GetCategoryRetention(key)
        local showCustom = GetSelection() == customOption
        custom:SetShown(showCustom)
        for _, unit in ipairs(units) do
            fields[unit]:SetText(tostring(duration[unit] or 0))
        end
        dropdown:Update()
        local height = showCustom and ROW_HEIGHT + 29 or ROW_HEIGHT
        if row:GetHeight() ~= height then
            row:SetHeight(height)
            relayout()
        end
    end

    local function SaveDuration()
        if GetSelection() ~= customOption then return end
        local duration = ns.GetCategoryRetention(key)
        for _, unit in ipairs(units) do
            local value = math.floor(tonumber(fields[unit]:GetText()) or 0)
            duration[unit] = math.max(0, math.min(limits[unit], value))
        end
        if duration.days + duration.hours + duration.minutes == 0 then duration.minutes = 1 end
        Refresh()
    end

    for i, unit in ipairs(units) do
        local field = CreateFrame("EditBox", nil, custom, "InputBoxTemplate")
        field:SetSize(38, 22)
        field:SetPoint("TOPLEFT", custom, "TOPLEFT", (i - 1) * 72 + 4, 0)
        field:SetAutoFocus(false)
        field:SetNumeric(true)
        field:SetMaxLetters(3)
        field:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        field:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        field:SetScript("OnEditFocusLost", SaveDuration)
        local caption = field:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        caption:SetPoint("LEFT", field, "RIGHT", 5, 0)
        caption:SetText(shortLabels[unit])
        fields[unit] = field
    end

    local function IsSelected(option)
        return GetSelection() == option
    end
    local function Select(option)
        local duration = ns.GetCategoryRetention(key)
        duration.enabled = option ~= forever
        customSelected = option == customOption
        if option[2] then
            duration.days, duration.hours, duration.minutes = option[2], option[3], option[4]
        end
        Refresh()
    end

    dropdown:SetSelectionText(function() return GetSelection()[1] end)
    dropdown:SetupMenu(function(_, menu)
        menu:CreateRadio(forever[1], IsSelected, Select, forever)
        for _, option in ipairs(RETENTION_PRESETS) do
            menu:CreateRadio(option[1], IsSelected, Select, option)
        end
        menu:CreateRadio(customOption[1], IsSelected, Select, customOption)
    end)
    RegisterSettingsRefresher(function()
        customSelected = false
        Refresh()
    end)
    Refresh()
end

local function NameplateSliderRow(parent, anchor, option)
    local rowWidth = CONTENT_WIDTH - 2 * TABLE_LEFT
    local labelWidth, valueWidth, buttonWidth, columnGap = 174, 46, 74, 10
    local sliderX = labelWidth + columnGap
    local valueX = rowWidth - buttonWidth - columnGap - valueWidth
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
    row:SetSize(rowWidth, 44)
    local label = Label(row, option.label, 0, -7, "GameFontHighlight")
    label:SetWidth(labelWidth)
    label:SetJustifyH("LEFT")
    local slider = CreateFrame("Slider", nil, row, "UISliderTemplate")
    slider:SetPoint("TOPLEFT", row, "TOPLEFT", sliderX, -4)
    slider:SetSize(valueX - sliderX - columnGap, 17)
    slider:SetMinMaxValues(option.min, option.max)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    local valueLabel = Label(row, "", valueX, -7)
    valueLabel:SetWidth(valueWidth)
    valueLabel:SetJustifyH("RIGHT")
    local status = Label(row, "", sliderX, -28)

    local function ReadNumber(getter)
        local ok, value = pcall(getter, option.cvar)
        if ok and ns.IsAccessibleValue(value) then return tonumber(value) end
    end

    local function Availability(current)
        if current == nil then return "Unavailable on this client" end
        if InCombatLockdown() then return "Unavailable in combat" end
        if not C_CVar or type(C_CVar.SetCVar) ~= "function" then
            return "Unavailable on this client"
        end
        if type(C_CVar.GetCVarInfo) == "function" then
            local ok, _, _, _, _, locked, secure, readOnly = pcall(C_CVar.GetCVarInfo, option.cvar)
            if ok then
                if locked or readOnly then return "Restricted by WoW" end
                return nil, secure
            end
        end
    end

    local refreshing = false
    local defaultButton
    local function Refresh(message)
        local current = ReadNumber(C_CVar and C_CVar.GetCVar)
        local unavailable = Availability(current)
        refreshing = true
        slider:SetValue(current and math.max(option.min, math.min(option.max,
            current * option.scale)) or option.min)
        slider:SetEnabled(not unavailable)
        defaultButton:SetEnabled(not unavailable and ReadNumber(C_CVar.GetCVarDefault) ~= nil)
        valueLabel:SetText(current and string.format("%g%s", current * option.scale, option.suffix) or "N/A")
        status:SetText(unavailable or message or "")
        refreshing = false
    end

    local function Apply(value)
        local current = ReadNumber(C_CVar and C_CVar.GetCVar)
        local unavailable, secure = Availability(current)
        if unavailable then Refresh(); return end
        -- Even out of combat, WoW can reject protected values or clamp the range.
        -- Use the normal client setter and always show the value read back.
        local ok, applied = pcall(C_CVar.SetCVar, option.cvar, tostring(value))
        local actual = ReadNumber(C_CVar.GetCVar)
        if not ok or applied ~= true or actual == nil then
            Refresh(secure and "Restricted by WoW" or "WoW rejected the change")
        elseif math.abs(actual - value) > 0.00001 then
            Refresh("WoW kept the displayed value")
        else
            Refresh()
        end
    end

    defaultButton = Button(row, "Default", buttonWidth, function()
        local defaultValue = ReadNumber(C_CVar and C_CVar.GetCVarDefault)
        if defaultValue then Apply(defaultValue) end
    end)
    defaultButton:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    slider:SetScript("OnValueChanged", function(_, value)
        if not refreshing then Apply(math.floor(value + 0.5) / option.scale) end
    end)
    Refresh()
    return row, Refresh
end

local function PlaceAt(control, parent, x, y)
    control:ClearAllPoints()
    control:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
end

local NAMEPLATE_SETUP_OPTIONS = {
    {key = "player", label = "Friendly Player Nameplates", detail = "See players you know nearby."},
    {key = "npc", label = "Friendly NPC Nameplates", detail = "See vendors and remembered NPCs."},
    {key = "always", label = "Always Show Nameplates", detail = "See nameplates outside combat."},
}

local function AddNameplateSetup(content, refresh)
    local inset, width = 18, CONTENT_WIDTH - 36
    local padding, detailX = 12, 201
    local card = CreateFrame("Frame", nil, content, "InsetFrameTemplate")
    card:SetWidth(width)
    Label(card, "Nameplate setup", padding, -12, "GameFontNormal")

    local function Text(value, x)
        local text = Label(card, value, x, 0)
        text:SetWidth(width - x - padding)
        text:SetJustifyH("LEFT")
        return text
    end
    local function PlaceText(text, y, x, value)
        text:SetShown(value ~= nil)
        if not value then return y end
        text:SetText(value)
        PlaceAt(text, card, x, y)
        return y - text:GetStringHeight() - 6
    end

    local intro = Text("", padding)
    local rows = {}
    for _, option in ipairs(NAMEPLATE_SETUP_OPTIONS) do
        local label = Text(option.label, padding)
        label:SetWidth(detailX - padding - 8)
        local detail = Text(option.detail, detailX)
        detail:SetTextColor(0.76, 0.76, 0.76)
        rows[option.key] = {label = label, detail = detail}
    end
    local status = Text("", padding)
    status:SetTextColor(1, 0.78, 0.26)
    local otherChecks = Label(card, "Other checks", padding, 0, "GameFontNormalSmall")
    local notes = {Text("", padding), Text("", padding), Text("", padding)}
    local pending, applying, failed = {}, false, false
    local apply = Button(card, "Enable nameplate settings", 188, function()
        if InCombatLockdown() then return end
        applying = true
        failed = not ns.EnableNameplateSettings(pending)
        applying = false
        refresh()
    end)

    return function(needed, messages, top)
        if applying then return top - card:GetHeight() - 12 end
        pending = {}
        local y = -33
        for _, option in ipairs(NAMEPLATE_SETUP_OPTIONS) do
            local key = option.key
            local missing = needed[key] and ns.GetNameplateSetting(key) == false
            rows[key].label:SetShown(missing)
            rows[key].detail:SetShown(missing)
            if missing then pending[#pending + 1] = key end
        end
        local hasSettings, hasNotes = #pending > 0, #messages > 0
        if not hasSettings then failed = false end
        card:SetShown(hasSettings or hasNotes)
        if not hasSettings and not hasNotes then return top end
        PlaceAt(card, content, inset, top)

        y = PlaceText(intro, y, padding, hasSettings and "Turn on these WoW settings to show the nameplates you’ve configured." or nil)
        for _, key in ipairs(pending) do
            local row = rows[key]
            PlaceAt(row.label, card, padding, y)
            PlaceAt(row.detail, card, detailX, y)
            y = y - math.max(row.label:GetStringHeight(), row.detail:GetStringHeight()) - 6
        end
        apply:SetShown(hasSettings)
        local inCombat = InCombatLockdown()
        if hasSettings then
            apply:SetEnabled(not inCombat)
            PlaceAt(apply, card, padding, y - 3)
            y = y - 34
        end
        local feedback
        if hasSettings and inCombat then
            feedback = "Leave combat to apply these WoW settings."
        elseif hasSettings and failed then
            feedback = "WoW kept some settings off. You can change them in WoW’s Nameplates options."
        end
        y = PlaceText(status, y, padding, feedback)

        otherChecks:SetShown(hasSettings and hasNotes)
        if hasSettings and hasNotes then
            PlaceAt(otherChecks, card, padding, y - 3)
            y = y - otherChecks:GetStringHeight() - 9
        end
        for index, note in ipairs(notes) do y = PlaceText(note, y, padding, messages[index]) end
        local height = -y + 6
        card:SetHeight(height)
        return top - height - 12
    end
end

local function AnyPlayerTrackingEnabled()
    for _, category in ipairs(ns.PlayerCategories) do
        if ns.CategoryTrackingEnabled(category.key) then return true end
    end
    return false
end

local function NeedsFriendlyNPCPlates()
    if KnownPlayersSettings.filterNPCNameplates
        or KnownPlayersSettings.npcServiceCategories.manual and next(KnownPlayersDB.npcs) then return true end
    for _, override in pairs(KnownPlayersDB.npcOverrides) do
        if type(override) == "table" and override.mode == "show" then return true end
    end
    return false
end

local function BuildHomePage(parent)
    local page, content = NewScrollingPage(parent)
    local about = Button(page, "About", 80, function() ShowAbout(page) end)
    about:SetPoint("TOPRIGHT", page, "TOPRIGHT", -SCROLL_RIGHT - CONTENT_RIGHT_PADDING, -12)

    local intro = Label(content,
        "KnownPlayers reveals familiar nameplates as you meet and interact with players.", 18, -16, "GameFontHighlight")
    intro:SetWidth(320)
    intro:SetJustifyH("LEFT")
    Label(content, "Nameplate filtering", 18, -68, "GameFontNormal")
    local playerFilter = Checkbox(content, 17, -92, "Enable player nameplate filtering",
        KnownPlayersSettings.knownOnlyNameplates, ns.SetKnownOnlyNameplates,
        function() return KnownPlayersSettings.knownOnlyNameplates end)
    local npcFilter = Checkbox(content, 17, -121, "Enable NPC nameplate filtering",
        KnownPlayersSettings.filterNPCNameplates, function(checked)
            KnownPlayersSettings.filterNPCNameplates = checked
            ns.SyncNPCNameplateCVars()
            ns.RefreshKnownNameplates()
        end, function() return KnownPlayersSettings.filterNPCNameplates end)

    local Layout
    local function Refresh() Layout() end
    local layoutSetup = AddNameplateSetup(content, Refresh)

    local minimap = Checkbox(content, 17, 0, "Show minimap button",
        KnownPlayersSettings.showMinimapButton, function(checked)
            KnownPlayersSettings.showMinimapButton = checked
            ns.RefreshMinimapButton()
        end, function() return KnownPlayersSettings.showMinimapButton end)
    local reset = Button(content, "Reset Settings to Defaults", 205, function()
        StaticPopup_Show("KNOWNPLAYERS_RESET_SETTINGS")
    end)
    local backups = Button(content, "Backup & Restore", 135, function() ns.OpenBackupWindow(page) end)
    backups:SetPoint("LEFT", reset, "RIGHT", 9, 0)
    local version = Label(content, "Version " .. ns.AddonVersion, 0, 0)
    local repository = Label(content, "https://github.com/Martnat8/KnownPlayers", 0, 0)

    Layout = function()
        local players = KnownPlayersSettings.knownOnlyNameplates
        local npcs = KnownPlayersSettings.filterNPCNameplates
        local npcPlates = NeedsFriendlyNPCPlates()
        local questieReady = npcs and ns.IsQuestieDBConnected()
        local messages = {}
        if players and not AnyPlayerTrackingEnabled() then
            messages[#messages + 1] = "Enable a tracking category in Player Nameplates so KnownPlayers can learn who you know."
        end
        if npcs then
            if not questieReady then
                messages[#messages + 1] = "Enable QuestieDB with API contract 4 for automatic NPC roles. Remembered NPCs and overrides can work without it."
            else
                local hasRole = false
                for key, enabled in pairs(KnownPlayersSettings.npcServiceCategories) do
                    if key ~= "manual" and enabled then hasRole = true; break end
                end
                if not hasRole then
                    messages[#messages + 1] = "Enable the automatic roles you want to see in NPC Nameplates."
                end
            end
        end
        if (players and ns.HasUnfilteredOverheadNames("player"))
            or (questieReady and ns.HasUnfilteredOverheadNames("npc")) then
            messages[#messages + 1] = "WoW is still showing some overhead names outside the filter. Check WoW’s Names settings."
        end
        local footer = layoutSetup({player = players, npc = npcPlates, always = players or npcPlates},
            messages, -154) - 18
        PlaceAt(minimap, content, 17, footer)
        PlaceAt(reset, content, 18, footer - 39)
        PlaceAt(version, content, 18, footer - 81)
        PlaceAt(repository, content, 18, footer - 100)
        content:SetHeight(-footer + 128)
    end
    playerFilter:HookScript("OnClick", Refresh)
    npcFilter:HookScript("OnClick", Refresh)
    RegisterSettingsRefresher(Refresh)
    Refresh()

    local events = CreateFrame("Frame", nil, page)
    events:RegisterEvent("ADDON_LOADED")
    events:RegisterEvent("CVAR_UPDATE")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function(_, event, key)
        if page:IsVisible() and (event ~= "ADDON_LOADED" or key == "QuestieDB") then Refresh() end
    end)
    return page
end

local function AddPriorityTable(body, top, options)
    local orderKey = options.orderKey
    local priorityX = options.player and TRACKING_CONTROLS.priorityX or 225
    Label(body, options.player and "Track category" or "Show category", TABLE_LEFT + 6, top, "GameFontNormalSmall")
    if options.player then
        Label(body, "Remember for", TABLE_LEFT + TRACKING_CONTROLS.durationX + 3, top, "GameFontNormalSmall")
    end
    Label(body, "Priority", TABLE_LEFT + priorityX + 4, top, "GameFontNormalSmall")

    local rows = {}
    local function Layout()
        local order = KnownPlayersSettings[orderKey]
        local y = top - 22
        for index, key in ipairs(order) do
            local row = rows[key]
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", body, "TOPLEFT", TABLE_LEFT, y)
            row.tracking:SetChecked(options.enabled(key))
            row.up:SetEnabled(index > 1)
            row.down:SetEnabled(index < #order)
            y = y - row:GetHeight()
        end
        if options.afterRows then options.afterRows(y)
        else body:SetHeight(-y + 16) end
    end

    local function Move(key, delta)
        local order = KnownPlayersSettings[orderKey]
        for index, current in ipairs(order) do
            if current == key and order[index + delta] then
                order[index], order[index + delta] = order[index + delta], current
                Layout()
                ns.RefreshKnownNameplates()
                return
            end
        end
    end

    local ready = false
    for _, key in ipairs(KnownPlayersSettings[orderKey]) do
        local row = CreateFrame("Frame", nil, body)
        row:SetSize(CONTENT_WIDTH - TABLE_LEFT - CONTENT_RIGHT_PADDING, options.rowHeight or ROW_HEIGHT)
        rows[key] = row
        row.tracking = Checkbox(row, 0, -1, options.labels[key], options.enabled(key), function(checked)
            options.setEnabled(key, checked)
        end)
        row.up = PriorityButton(row, "top", function() Move(key, -1) end)
        row.up:SetPoint("TOPLEFT", row, "TOPLEFT", priorityX, -1)
        row.down = PriorityButton(row, "bottom", function() Move(key, 1) end)
        row.down:SetPoint("LEFT", row.up, "RIGHT", TRACKING_CONTROLS.arrowGap, 0)
        if options.player then
            AddRetentionDropdown(row, key, TRACKING_CONTROLS.durationX, function()
                if ready then Layout() end
            end)
            local manage = Button(row, "Manage", TRACKING_CONTROLS.manage, function()
                ns.OpenPlayerList(key, options.page)
            end)
            manage:SetPoint("LEFT", row.down, "RIGHT", TRACKING_CONTROLS.gap, 0)
        end
    end
    ready = true
    Layout()
    RegisterSettingsRefresher(Layout)
end

local PLAYER_LABELS = {associated = ns.AssociatedCategory.label}
for _, category in ipairs(ns.PlayerCategories) do PLAYER_LABELS[category.key] = category.label end

local function NPCLabels()
    local labels = {}
    for _, category in ipairs(ns.GetNPCServiceCategories()) do labels[category.key] = category.label end
    return labels
end

local function BuildPlayerPage(parent)
    local page, body = NewScrollingPage(parent)
    Label(body, "Higher categories take priority when a player belongs to several lists.", 21, -14)
    AddPriorityTable(body, -44, {
        player = true,
        page = page,
        orderKey = "nameplateColorOrder",
        labels = PLAYER_LABELS,
        enabled = ns.CategoryTrackingEnabled,
        setEnabled = SetCategoryTracking,
    })
    return page
end

local function BuildNPCPage(parent)
    local page, body = NewScrollingPage(parent)

    local sourceHeading = Label(body, "", 21, -12, "GameFontNormal")
    sourceHeading:SetWidth(CONTENT_WIDTH - 42)
    sourceHeading:SetJustifyH("LEFT")
    Label(body, "Automatic NPC roles come from the separately installed QuestieDB addon.", 21, -36)
    Label(body, "Higher categories take priority for NPCs with several roles.", 21, -56)
    local function RefreshSourceStatus()
        local status = ns.GetNPCDataSourceStatus():gsub(" %- automatic NPC categories unavailable$", "")
        local color = ns.IsQuestieDBConnected() and "ff59ff73" or "ffff5454"
        sourceHeading:SetText("NPC database - |c" .. color .. status .. "|r")
    end
    RegisterSettingsRefresher(RefreshSourceStatus)
    local sourceEvents = CreateFrame("Frame", nil, page)
    sourceEvents:RegisterEvent("ADDON_LOADED")
    sourceEvents:SetScript("OnEvent", function(_, _, addon)
        if addon == "QuestieDB" then RefreshSourceStatus() end
    end)
    RefreshSourceStatus()

    local management = CreateFrame("Frame", nil, body)
    management:SetWidth(CONTENT_WIDTH - 42)
    Label(management, "Forget manually remembered NPCs over time", 0, -4, "GameFontNormal")
    local retentionOffset = 25
    local retention = CreateFrame("Frame", nil, management)
    retention:SetSize(management:GetWidth(), ROW_HEIGHT)
    retention:SetPoint("TOPLEFT", management, "TOPLEFT", 0, -retentionOffset)
    Label(retention, "Remember for", 0, -8)
    local manager = Button(retention, "NPC Manager", 118, function() ns.OpenPlayerList("npc", page) end)
    local managerX = TRACKING_CONTROLS.durationX + TRACKING_CONTROLS.duration + TRACKING_CONTROLS.gap
    manager:SetPoint("TOPLEFT", retention, "TOPLEFT", managerX, -2)
    local managementY
    local function LayoutManagement()
        management:SetHeight(retentionOffset + retention:GetHeight() + 6)
        if managementY then body:SetHeight(-managementY + management:GetHeight()) end
    end
    AddRetentionDropdown(retention, "npc", TRACKING_CONTROLS.durationX, LayoutManagement)
    LayoutManagement()

    AddPriorityTable(body, -76, {
        orderKey = "npcNameplateColorOrder",
        rowHeight = 28,
        labels = NPCLabels(),
        enabled = function(key) return KnownPlayersSettings.npcServiceCategories[key] == true end,
        setEnabled = function(key, checked)
            KnownPlayersSettings.npcServiceCategories[key] = checked
            ns.RefreshKnownNameplates()
        end,
        afterRows = function(y)
            managementY = y - 12
            management:ClearAllPoints()
            management:SetPoint("TOPLEFT", body, "TOPLEFT", 21, managementY)
            LayoutManagement()
        end,
    })
    return page
end

local function AddChoiceDropdown(body, x, y, width, title, choices, get, set)
    Label(body, title, x + 3, y + 19, "GameFontNormalSmall")
    local dropdown = Dropdown(body, x, y, width)
    local function IsSelected(value) return get() == value end
    dropdown:SetSelectionText(function()
        for _, choice in ipairs(choices) do
            if IsSelected(choice[1]) then return choice[2] end
        end
    end)
    dropdown:SetupMenu(function(_, menu)
        for _, choice in ipairs(choices) do menu:CreateRadio(choice[2], IsSelected, set, choice[1]) end
    end)
    RegisterSettingsRefresher(function() dropdown:Update() end)
end

local NAME_CHOICES = {{"full", "Full name"}, {"first", "First name"}}
local HEALTH_CHOICES = {{"always", "Always"}, {"combat", "In combat"}, {"never", "Never"}}

local function AddAppearanceControls(box, isNPC)
    local padding = 12
    local width = box:GetWidth() - 2 * padding
    Label(box, isNPC and "NPC nameplates" or "Player nameplates", padding, -12, "GameFontNormal")
    local nameKey = isNPC and "npcNameDisplayMode" or "nameDisplayMode"
    local healthKey = isNPC and "npcHealthBarMode" or "playerHealthBarMode"
    local setHealth = isNPC and ns.SetNPCHealthBarMode or ns.SetPlayerHealthBarMode
    AddChoiceDropdown(box, padding, -53, width, isNPC and "NPC name" or "Character name",
        NAME_CHOICES, function() return KnownPlayersSettings[nameKey] end, function(mode)
            KnownPlayersSettings[nameKey] = mode
            ns.RefreshKnownNameplates()
        end)
    local label = isNPC and "Show NPC title" or "Show guild name"
    local extraKey = isNPC and "showNPCTitle" or "showGuildInNamesOnly"
    Checkbox(box, padding, -82, label, KnownPlayersSettings[extraKey], function(checked)
        KnownPlayersSettings[extraKey] = checked
        ns.RefreshKnownNameplates()
    end, function() return KnownPlayersSettings[extraKey] end)
    if not isNPC then AddFriendlyMinionVisibility(box, padding, -107) end
    AddChoiceDropdown(box, padding, -165, width, "Health bar", HEALTH_CHOICES,
        function() return KnownPlayersSettings[healthKey] end, setHealth)
end

local function AddNameplateSliders(page, body, anchor)
    local row = anchor
    local height = 0
    local refreshByCVar = {}
    for _, option in ipairs({
        {label = "Player distance", cvar = "nameplatePlayerMaxDistance",
            min = 20, max = 60, scale = 1, suffix = " yd"},
        {label = "NPC distance", cvar = "nameplateMaxDistance",
            min = 20, max = 60, scale = 1, suffix = " yd"},
        {label = "Minimum opacity", cvar = "nameplateMinAlpha",
            min = 0, max = 100, scale = 100, suffix = "%"},
    }) do
        row, refreshByCVar[option.cvar:lower()] = NameplateSliderRow(body, row, option)
        height = height + row:GetHeight() + 6
    end
    local function Refresh()
        for _, callback in pairs(refreshByCVar) do callback() end
    end
    RegisterSettingsRefresher(Refresh)
    local events = CreateFrame("Frame", nil, page)
    events:RegisterEvent("CVAR_UPDATE")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:SetScript("OnEvent", function(_, event, key)
        if not page:IsVisible() then return end
        if event ~= "CVAR_UPDATE" then
            Refresh()
        elseif type(key) == "string" and ns.IsAccessibleValue(key) then
            local callback = refreshByCVar[key:lower()]
            if callback then callback() end
        end
    end)
    return row, height
end

local function AddColorTable(box, title, orderKey, labels, getColor, colorKey)
    Label(box, title, 10, -11, "GameFontNormal")
    local rows = {}

    local function Refresh()
        for index, key in ipairs(KnownPlayersSettings[orderKey]) do
            local row = rows[key]
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -32 - (index - 1) * ROW_HEIGHT)
            local rgb = getColor(key)
            row.swatch:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
        end
    end

    local function PickColor(key)
        local picker = ColorPickerFrame
        if not picker then return end
        local color = getColor(key)
        local function Save(r, g, b)
            KnownPlayersSettings[colorKey][key] = {r, g, b}
            Refresh()
            ns.RefreshKnownNameplates()
        end
        local function Apply()
            Save(picker:GetColorRGB())
        end
        if type(picker.SetupColorPickerAndShow) == "function" then
            picker:SetupColorPickerAndShow({
                r = color[1], g = color[2], b = color[3], hasOpacity = false,
                swatchFunc = Apply,
                cancelFunc = function() Save(color[1], color[2], color[3]) end,
            })
        else
            picker.func = Apply
            picker.hasOpacity = false
            picker:SetColorRGB(color[1], color[2], color[3])
            picker:Show()
        end
    end

    for _, key in ipairs(KnownPlayersSettings[orderKey]) do
        local row = CreateFrame("Frame", nil, box)
        row:SetSize(box:GetWidth() - 16, ROW_HEIGHT)
        rows[key] = row
        local label = Label(row, labels[key], 0, -7, "GameFontHighlightSmall")
        label:SetWidth(row:GetWidth() - TRACKING_CONTROLS.color - 6)
        label:SetMaxLines(1)
        label:SetJustifyH("LEFT")
        local button
        button, row.swatch = ColorButton(row, function() PickColor(key) end)
        button:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -1)
    end
    Refresh()
    RegisterSettingsRefresher(Refresh)
end

local function AddAppearanceBoxes(body, anchor, anchorPoint, x, y, height)
    local gap = 12
    local width = math.floor((CONTENT_WIDTH - 2 * TABLE_LEFT - gap) / 2)
    local left = CreateFrame("Frame", nil, body, "InsetFrameTemplate")
    left:SetSize(width, height)
    left:SetPoint("TOPLEFT", anchor, anchorPoint, x, y)
    local right = CreateFrame("Frame", nil, body, "InsetFrameTemplate")
    right:SetSize(width, height)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", gap, 0)
    return left, right
end

local function BuildAppearancePage(parent)
    local page, body = NewScrollingPage(parent)
    local appearanceTop, appearanceHeight = -14, 204
    local playerAppearance, npcAppearance =
        AddAppearanceBoxes(body, body, "TOPLEFT", TABLE_LEFT, appearanceTop, appearanceHeight)
    AddAppearanceControls(playerAppearance, false)
    AddAppearanceControls(npcAppearance, true)
    local sliderTop = appearanceTop - appearanceHeight - 21
    local heading = Label(body, "Distance and opacity", TABLE_LEFT, sliderTop, "GameFontNormal")
    local last, sliderHeight = AddNameplateSliders(page, body, heading)
    local colorHeight = 40 + math.max(#KnownPlayersSettings.nameplateColorOrder,
        #KnownPlayersSettings.npcNameplateColorOrder) * ROW_HEIGHT
    local playerColors, npcColors = AddAppearanceBoxes(body, last, "BOTTOMLEFT", 0, -19, colorHeight)
    AddColorTable(playerColors, "Player category colors", "nameplateColorOrder",
        PLAYER_LABELS, ns.GetNameplateCategoryColor, "nameplateCategoryColors")
    AddColorTable(npcColors, "NPC category colors", "npcNameplateColorOrder",
        NPCLabels(), ns.GetNPCNameplateCategoryColor, "npcNameplateCategoryColors")
    body:SetHeight(-sliderTop + heading:GetStringHeight() + sliderHeight + 19 + colorHeight + 20)
    page.fitHeightContent = body
    return page
end

local SETTINGS_PAGES = {
    {title = "KnownPlayers", build = BuildHomePage},
    {title = "Player Nameplates", build = BuildPlayerPage},
    {title = "NPC Nameplates", build = BuildNPCPage},
    {title = "Appearance", build = BuildAppearancePage},
}

local function CreateSettingsPage(definition, parent)
    local firstRefresher = #settingsRefreshers + 1
    local page = definition.build(parent)
    local lastRefresher = #settingsRefreshers
    -- Either window can edit the same settings. Refresh only the page becoming visible.
    page:HookScript("OnShow", function()
        for i = firstRefresher, lastRefresher do settingsRefreshers[i]() end
    end)
    return page
end

local function CreateSettingsTabs(frame, tabTop, bottomInset, autoFitHeight)
    local pages = {}
    local selectedTab, previousHeight
    local inset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    inset:SetPoint("BOTTOM", frame, "BOTTOM", 0, bottomInset)
    frame.Tabs = {}
    local function FitTabs(width)
        local available = width - 2 * WINDOW_PADDING
        local insetWidth = available > 0 and math.min(INSET_WIDTH, available) or INSET_WIDTH
        inset:SetWidth(insetWidth)
        -- Blizzard's tab anchors leave three units between adjacent tabs.
        local spacing = 3 * (#frame.Tabs - 1)
        for _, tab in ipairs(frame.Tabs) do PanelTemplates_TabResize(tab, 10) end
        local tabSpace = insetWidth - 16 - spacing
        if tabSpace > 0 then PanelTemplates_ResizeTabsToFit(frame, tabSpace) end
        local tabWidth = spacing
        for _, tab in ipairs(frame.Tabs) do tabWidth = tabWidth + tab:GetWidth() end
        local first = frame.Tabs[1]
        first:ClearAllPoints()
        first:SetPoint("TOPLEFT", frame, "TOP", -tabWidth / 2, tabTop)
    end
    local function FitPageHeight(page)
        -- Blizzard owns the enclosing window for the AddOns settings panel.
        if not autoFitHeight then return end
        local content = page.fitHeightContent
        if content then
            previousHeight = previousHeight or frame:GetHeight()
            local chrome = frame.Tabs[1]:GetHeight() - tabTop - 1 + bottomInset
                + 2 * PAGE_PADDING + SCROLL_TOP + SCROLL_BOTTOM
            local height = math.max(previousHeight, math.ceil(content:GetHeight() + chrome))
            local screenHeight = UIParent:GetHeight()
            if screenHeight > 0 then
                local maximum = math.max(MIN_SETTINGS_HEIGHT, screenHeight - 2 * WINDOW_PADDING)
                height = math.min(height, maximum)
            end
            frame:SetHeight(height)
        elseif previousHeight then
            frame:SetHeight(previousHeight)
            previousHeight = nil
        end
    end
    local function SelectTab(selected)
        if selectedTab and selectedTab ~= selected then
            ns.CloseWindowsFromSettingsPage(pages[selectedTab])
        end
        selectedTab = selected
        PanelTemplates_SetTab(frame, selected)
        FitTabs(frame:GetWidth())
        for index, page in ipairs(pages) do page:SetShown(index == selected) end
        FitPageHeight(pages[selected])
    end
    for index, definition in ipairs(SETTINGS_PAGES) do
        local page = CreateSettingsPage(definition, frame)
        page:SetPoint("TOPLEFT", inset, "TOPLEFT", PAGE_PADDING, -PAGE_PADDING)
        page:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -PAGE_PADDING, PAGE_PADDING)
        page:Hide()
        pages[index] = page

        local tab = CreateFrame("Button", nil, frame, "PanelTopTabButtonTemplate")
        tab:SetID(index)
        tab:SetText(definition.title)
        PanelTemplates_TabResize(tab, 10)
        tab:SetScript("OnClick", function(self) SelectTab(self:GetID()) end)
        frame.Tabs[index] = tab
    end
    inset:SetPoint("TOP", frame, "TOP", 0, tabTop - frame.Tabs[1]:GetHeight() + 1)
    PanelTemplates_SetNumTabs(frame, #pages)
    SelectTab(1)
    if autoFitHeight then
        frame:HookScript("OnShow", function() FitPageHeight(pages[selectedTab]) end)
    end
    local previousWidth = frame:GetWidth()
    frame:HookScript("OnSizeChanged", function(_, width)
        if width == previousWidth then return end
        previousWidth = width
        FitTabs(width)
    end)
end

local function CreateSettingsWindow()
    local frame = CreateFrame("Frame", "KnownPlayersSettingsWindow", UIParent, "BasicFrameTemplateWithInset")
    local width = INSET_WIDTH + 2 * WINDOW_PADDING
    frame:SetSize(width, 560)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(width, MIN_SETTINGS_HEIGHT, width)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:Hide()
    frame.hideOtherWindows = true
    ns.EnableWindowEscape(frame)
    frame:HookScript("OnHide", function(self) self:StopMovingOrSizing() end)
    frame.TitleText:SetText("KnownPlayers")

    local resize = CreateFrame("Button", nil, frame, "PanelResizeButtonTemplate")
    resize:SetPoint("BOTTOMRIGHT", -6, 6)
    resize:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton == "LeftButton" then frame:StartSizing("BOTTOM", true) end
    end)
    resize:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton == "LeftButton" then frame:StopMovingOrSizing() end
    end)

    CreateSettingsTabs(frame, -22, 22, true)
    return frame
end

function ns.OpenSettingsWindow()
    if not settingsWindow then settingsWindow = CreateSettingsWindow() end
    ns.ShowWindow(settingsWindow)
end

function ns.OpenSettings()
    if not panel then return end
    if Settings and Settings.OpenToCategory and panel.categoryID then
        Settings.OpenToCategory(panel.categoryID)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end

function ns.CreateSettingsPanel()
    if panel then return end
    panel = CreateFrame("Frame")
    panel.name = SETTINGS_PAGES[1].title
    CreateSettingsTabs(panel, -12, 6)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        panel.categoryID = category:GetID()
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    else
        print("|cffff5555KnownPlayers:|r Unable to register settings panel on this client.")
    end
end

local addonName, ns = ...
local panel, aboutWindow
local settingsRefreshers = {}
local function RegisterSettingsRefresher(callback)
    settingsRefreshers[#settingsRefreshers + 1] = callback
end
local function RefreshSettingsControls()
    for _, callback in ipairs(settingsRefreshers) do callback() end
end

-- Reset preferences only; KnownPlayersDB and player histories are untouched.
StaticPopupDialogs["KNOWNPLAYERS_RESET_SETTINGS"] = {
    text = "Reset all KnownPlayers settings to their defaults?\n\nSaved player lists will not be deleted.",
    button1 = "Reset Settings",
    button2 = CANCEL,
    OnAccept = function()
        -- Restore WoW's own overhead-name settings before discarding the backup.
        if KnownPlayersSettings then
            KnownPlayersSettings.knownOnlyNameplates = false
            if ns.RestoreNativeOverheadNames then ns.RestoreNativeOverheadNames() end
            if ns.RestoreNPCNameplateCVars then ns.RestoreNPCNameplateCVars() end
        end
        KnownPlayersSettings = {}
        ns.InitializeDatabase()
        if ns.InitializeNameplateColors then ns.InitializeNameplateColors() end
        -- Rebind retention rows to their new SavedVariables tables, then repaint
        -- every existing control. A full UI reload would be unnecessary.
        RefreshSettingsControls()
        if ns.InvalidateBattleNetIndex then ns.InvalidateBattleNetIndex() end
        if ns.SyncNativeOverheadNames then ns.SyncNativeOverheadNames() end
        if ns.SyncNPCNameplateCVars then ns.SyncNPCNameplateCVars() end
        if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
        if ns.RefreshPlayerListWindows then ns.RefreshPlayerListWindows() end
        print("|cff33ff99KnownPlayers:|r Settings restored to defaults.")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Clear stored player histories and Battle.net associations without resetting preferences.
StaticPopupDialogs["KNOWNPLAYERS_CLEAR_ALL_LISTS"] = {
    text = "Clear ALL KnownPlayers player and NPC lists and saved Battle.net alt associations?\n\nThis cannot be undone. Automatic tracking may add players again on future encounters or roster scans.",
    button1 = "Clear All Lists",
    button2 = CANCEL,
    OnAccept = function()
        if type(KnownPlayersDB) ~= "table" then return end
        ns.ClearRemovalUndo()
        KnownPlayersDB.players = {}
        KnownPlayersDB.npcs = {}
        KnownPlayersDB.npcOverrides = {}
        KnownPlayersDB.bnetCharacters = {}
        if ns.ClearBattleNetPending then ns.ClearBattleNetPending() end
        if ns.InvalidateIdentityIndex then ns.InvalidateIdentityIndex() end
        if ns.InvalidateBattleNetIndex then ns.InvalidateBattleNetIndex() end
        if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
        if ns.RefreshPlayerListWindows then ns.RefreshPlayerListWindows() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local CATEGORIES = {
    { key = "trade", label = "Trade", tracking = "trackTrades", description = "Remember trading partners" },
    { key = "party", label = "Party", group = "party", description = "Remember party members" },
    { key = "raid", label = "Raid", group = "raid", description = "Remember raid members" },
    { key = "guild", label = "Guild", tracking = "trackGuild", description = "Remember everyone on the guild roster" },
    { key = "whisper", label = "Whisper", tracking = "trackWhispers", description = "Remember whispered players" },
    { key = "target", label = "Target", tracking = "trackTargets", description = "Remember targeted players" },
    { key = "inspect", label = "Inspect", tracking = "trackInspects", description = "Remember inspected players" },
    { key = "manual", label = "Manually Added", tracking = "trackManual", description = "Show players saved manually" },
}
local TRACKING_CATEGORIES = {
    associated = { key = "associated", label = "Known Battle.net Alts", tracking = "trackBattleNetAssociations" },
}
for _, category in ipairs(CATEGORIES) do TRACKING_CATEGORIES[category.key] = category end

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

local function ShowAbout(parent)
    if aboutWindow then
        aboutWindow:Show()
        return
    end

    local frame = CreateFrame("Frame", "KnownPlayersAboutWindow", parent, "BasicFrameTemplateWithInset")
    frame:SetWidth(520)
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    if frame.TitleText then frame.TitleText:SetText("About KnownPlayers") end
    parent:HookScript("OnHide", function() frame:Hide() end)

    Label(frame, "Version " .. ns.AddonVersion, 22, -38)
    local y = -62
    for _, section in ipairs({
        {"Remembering players",
            "Choose which interactions to track on Player Nameplates & Lists. Use a portrait menu or /kp remember to save someone manually. Open Player History to see why you know them and add a note, tags, or a favorite."},
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

    aboutWindow = frame
    frame:Show()
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

local function NewPage(title, subtitle)
    local page = CreateFrame("Frame")
    Label(page, title, 18, -16, "GameFontNormalLarge")
    Label(page, subtitle, 18, -46)
    return page
end

local function NewScrollingPage(title, subtitle)
    local page = NewPage(title, subtitle or "")
    local scroller = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroller:SetPoint("TOPLEFT", page, "TOPLEFT", 3, (subtitle and subtitle ~= "") and -75 or -55)
    scroller:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -28, 6)
    local content = CreateFrame("Frame", nil, scroller)
    content:SetSize(465, 600)
    scroller:SetScrollChild(content)
    scroller:SetScript("OnSizeChanged", function(self)
        content:SetWidth(math.max(455, self:GetWidth() - 18))
    end)
    return page, content
end

local function SetCategoryTracking(category, checked)
    if category.group then
        KnownPlayersSettings.trackGroup[category.group] = checked
        if checked and ns.ScanGroupRoster then ns.ScanGroupRoster() end
    else
        KnownPlayersSettings[category.tracking] = checked
        if checked and category.key == "guild" and ns.RequestGuildRoster then
            ns.RequestGuildRoster()
            if ns.ScanGuildRoster then ns.ScanGuildRoster() end
        elseif checked and category.key == "associated" and ns.ScanBattleNetFriends then
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

local function RetentionRow(parent, category, onLayoutChanged, compact)
    local retention = ns.GetCategoryRetention(category.key)
    if not retention then return end

    -- Let each row own its height. Custom duration inputs expand the row,
    -- and the parent reflows every row that follows it.
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(445, compact and 34 or 50)
    local fields, captions = {}, {}
    local list = CreateFrame("Frame", nil, row, "UIDropDownMenuTemplate")
    list:SetPoint("TOPLEFT", row, "TOPLEFT", 140, 3)
    UIDropDownMenu_SetWidth(list, 150)
    local custom = CreateFrame("Frame", nil, row)
    custom:SetSize(255, 24)
    custom:SetPoint("TOPLEFT", row, "TOPLEFT", 172, -36)
    local customMode = false

    local function SaveDuration()
        local caps = {days=180, hours=23, minutes=59}
        local total = 0
        for _, unit in ipairs({"days", "hours", "minutes"}) do
            local number = math.floor(tonumber(fields[unit]:GetText()) or 0)
            number = math.max(0, math.min(caps[unit], number))
            retention[unit] = number
            total = total + number * (unit == "days" and 1440 or unit == "hours" and 60 or 1)
        end
        if total == 0 then retention.minutes = 1 end
        for _, unit in ipairs({"days", "hours", "minutes"}) do
            fields[unit]:SetText(tostring(retention[unit]))
        end
    end

    local function Refresh()
        local enabled = retention.enabled == true
        local title = "Custom..."
        if not customMode then
            for _, choice in ipairs(RETENTION_PRESETS) do
                if retention.days == choice[2] and retention.hours == choice[3]
                    and retention.minutes == choice[4] then
                    title = choice[1]
                    break
                end
            end
        end
        UIDropDownMenu_SetText(list, title)
        if enabled then UIDropDownMenu_EnableDropDown(list)
        else UIDropDownMenu_DisableDropDown(list) end
        custom:SetShown(customMode)
        for unit, field in pairs(fields) do
            field:SetEnabled(enabled)
            field:SetAlpha(enabled and 1 or 0.4)
            captions[unit]:SetAlpha(enabled and 1 or 0.4)
        end
        row:SetHeight(customMode and (compact and 68 or 82) or (compact and 34 or 50))
        if onLayoutChanged then onLayoutChanged() end
    end

    local forgetToggle = Checkbox(row, 2, 0, category.label, retention.enabled, function(checked)
        retention.enabled = checked
        Refresh()
    end)
    for i, unit in ipairs({"days", "hours", "minutes"}) do
        local field = CreateFrame("EditBox", nil, custom, "InputBoxTemplate")
        field:SetSize(38, 22)
        field:SetPoint("TOPLEFT", custom, "TOPLEFT", (i-1)*81, 0)
        field:SetAutoFocus(false)
        field:SetNumeric(true)
        field:SetMaxLetters(3)
        field:SetText(tostring(retention[unit] or 0))
        field:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        field:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        field:SetScript("OnEditFocusLost", SaveDuration)
        local caption = field:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        caption:SetPoint("LEFT", field, "RIGHT", 5, 0)
        caption:SetText(({days="d", hours="h", minutes="m"})[unit])
        fields[unit], captions[unit] = field, caption
    end

    local function SelectPreset(index)
        if index == #RETENTION_PRESETS + 1 then
            customMode = true
        else
            local option = RETENTION_PRESETS[index]
            retention.days, retention.hours, retention.minutes = option[2], option[3], option[4]
            customMode = false
            for _, unit in ipairs({"days", "hours", "minutes"}) do
                fields[unit]:SetText(tostring(retention[unit]))
            end
        end
        Refresh()
    end

    UIDropDownMenu_Initialize(list, function(_, level)
        for i, choice in ipairs(RETENTION_PRESETS) do
            local index = i
            local info = UIDropDownMenu_CreateInfo()
            info.text = choice[1]
            info.func = function() SelectPreset(index) end
            info.checked = not customMode and retention.days == choice[2]
                and retention.hours == choice[3] and retention.minutes == choice[4]
            UIDropDownMenu_AddButton(info, level)
        end
        local info = UIDropDownMenu_CreateInfo()
        info.text = "Custom..."
        info.func = function() SelectPreset(#RETENTION_PRESETS + 1) end
        info.checked = customMode
        UIDropDownMenu_AddButton(info, level)
    end)

    local isPreset = false
    for _, option in ipairs(RETENTION_PRESETS) do
        if retention.days == option[2] and retention.hours == option[3]
            and retention.minutes == option[4] then
            isPreset = true
            break
        end
    end
    customMode = not isPreset
    Refresh()
    RegisterSettingsRefresher(function()
        -- Reset replaces KnownPlayersSettings, so cached retention references
        -- must point to the new settings table before the user edits them.
        retention = ns.GetCategoryRetention(category.key)
        if not retention then return end
        forgetToggle:SetChecked(retention.enabled == true)
        for _, unit in ipairs({"days", "hours", "minutes"}) do
            fields[unit]:SetText(tostring(retention[unit] or 0))
        end
        customMode = true
        for _, option in ipairs(RETENTION_PRESETS) do
            if retention.days == option[2] and retention.hours == option[3]
                and retention.minutes == option[4] then
                customMode = false
                break
            end
        end
        Refresh()
    end)
    return row
end

local function NameplateSliderRow(parent, anchor, option)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
    row:SetSize(423, 56)
    Label(row, option.label, 0, 0, "GameFontHighlight")
    local slider = CreateFrame("Slider", nil, row, "UISliderTemplate")
    slider:SetPoint("TOPLEFT", row, "TOPLEFT", 5, -22)
    slider:SetSize(245, 17)
    slider:SetMinMaxValues(option.min, option.max)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    local valueLabel = Label(row, "", 260, -23)
    local status = Label(row, "", 0, -42)

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

    defaultButton = Button(row, "Default", 74, function()
        local defaultValue = ReadNumber(C_CVar and C_CVar.GetCVarDefault)
        if defaultValue then Apply(defaultValue) end
    end)
    defaultButton:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -17)
    slider:SetScript("OnValueChanged", function(_, value)
        if not refreshing then Apply(math.floor(value + 0.5) / option.scale) end
    end)
    Refresh()
    return row, Refresh
end

local function BuildHomePage()
    local page, content = NewScrollingPage("KnownPlayers", "")
    content:SetHeight(365)
    local about = Button(page, "About", 80, function() ShowAbout(page) end)
    about:SetPoint("TOPRIGHT", page, "TOPRIGHT", -22, -12)

    Label(content, "Nameplate Filtering", 16, -10, "GameFontNormal")
    Checkbox(content, 16, -37, "Enable player nameplate filtering",
        KnownPlayersSettings.knownOnlyNameplates, function(checked)
            if ns.SetKnownOnlyNameplates then ns.SetKnownOnlyNameplates(checked) end
        end, function() return KnownPlayersSettings.knownOnlyNameplates end)
    local npcFilter = Checkbox(content, 250, -37, "Enable NPC nameplate filtering",
        KnownPlayersSettings.filterNPCNameplates, function(checked)
            KnownPlayersSettings.filterNPCNameplates = checked
            if ns.SyncNPCNameplateCVars then ns.SyncNPCNameplateCVars() end
            if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
        end, function() return KnownPlayersSettings.filterNPCNameplates end)
    local npcFilterStatus = Label(content, "", 16, -66)
    local function RefreshNPCFilterStatus()
        local paused = KnownPlayersSettings.filterNPCNameplates and not ns.IsQuestieDBConnected()
        npcFilterStatus:SetText(paused and "Automatic NPC filtering paused — QuestieDB unavailable" or "")
    end
    npcFilter:HookScript("OnClick", RefreshNPCFilterStatus)
    page:HookScript("OnShow", RefreshNPCFilterStatus)
    RegisterSettingsRefresher(RefreshNPCFilterStatus)
    RefreshNPCFilterStatus()

    local line = content:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.45, 0.45, 0.45, 0.4)
    line:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -89)
    line:SetPoint("RIGHT", content, "RIGHT", -16, 0)
    line:SetHeight(1)

    local lastRow = Label(content, "Nameplate Distance and Opacity", 16, -106, "GameFontNormal")
    local refreshSliders = {}
    for _, option in ipairs({
        {label = "NPC / non-player nameplate distance", cvar = "nameplateMaxDistance",
            min = 20, max = 60, scale = 1, suffix = " yd"},
        {label = "Player nameplate distance", cvar = "nameplatePlayerMaxDistance",
            min = 20, max = 60, scale = 1, suffix = " yd"},
        {label = "Minimum nameplate opacity", cvar = "nameplateMinAlpha",
            min = 0, max = 100, scale = 100, suffix = "%"},
    }) do
        lastRow, refreshSliders[option.cvar:lower()] = NameplateSliderRow(content, lastRow, option)
    end

    local function RefreshSliders()
        for _, refresh in pairs(refreshSliders) do refresh() end
    end
    page:SetScript("OnShow", RefreshSliders)
    RegisterSettingsRefresher(RefreshSliders)
    local events = CreateFrame("Frame", nil, page)
    events:RegisterEvent("ADDON_LOADED")
    events:RegisterEvent("CVAR_UPDATE")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:SetScript("OnEvent", function(_, event, key)
        if not page:IsVisible() then return end
        if event == "ADDON_LOADED" then
            if key == "QuestieDB" then RefreshNPCFilterStatus() end
        elseif event ~= "CVAR_UPDATE" then
            RefreshSliders()
        elseif type(key) == "string" and ns.IsAccessibleValue(key) then
            local refresh = refreshSliders[key:lower()]
            if refresh then refresh() end
        end
    end)

    local reset = Button(content, "Reset Settings to Defaults", 205, function()
        StaticPopup_Show("KNOWNPLAYERS_RESET_SETTINGS")
    end)
    reset:SetPoint("TOPLEFT", lastRow, "BOTTOMLEFT", 0, -12)
    return page
end

local function BuildPlayerPage()
    -- Color controls + retention now share this scrollable page. Only the
    -- retention rows reflow when a custom duration is selected.
    local page, body = NewScrollingPage("Player Nameplates & Lists", "")

    -- Group the controls by purpose; keep name and health-bar choices in
    -- two aligned rows so all options are visible without competing labels.
    Label(body, "Character name", 21, -10, "GameFontNormal")
    local full, first
    local function SelectNameMode(mode)
        KnownPlayersSettings.nameDisplayMode = mode
        full:SetChecked(mode == "full")
        first:SetChecked(mode == "first")
        if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
    end
    full = Checkbox(body, 20, -35, "Full name",
        KnownPlayersSettings.nameDisplayMode ~= "first", function()
            SelectNameMode("full")
        end)
    first = Checkbox(body, 165, -35, "First name",
        KnownPlayersSettings.nameDisplayMode == "first", function()
            SelectNameMode("first")
        end)
    RegisterSettingsRefresher(function()
        full:SetChecked(KnownPlayersSettings.nameDisplayMode ~= "first")
        first:SetChecked(KnownPlayersSettings.nameDisplayMode == "first")
    end)
    Checkbox(body, 305, -35, "Guild name",
        KnownPlayersSettings.showGuildInNamesOnly, function(checked)
            KnownPlayersSettings.showGuildInNamesOnly = checked
            if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
        end, function() return KnownPlayersSettings.showGuildInNamesOnly end)
    local nameLine = body:CreateTexture(nil, "ARTWORK")
    nameLine:SetColorTexture(0.45, 0.45, 0.45, 0.24)
    nameLine:SetPoint("TOPLEFT", body, "TOPLEFT", 20, -81)
    nameLine:SetSize(432, 1)

    Label(body, "Health bar", 21, -94, "GameFontNormal")
    local modeButtons = {}
    local function SelectHealthBarMode(mode)
        if ns.SetPlayerHealthBarMode then ns.SetPlayerHealthBarMode(mode) end
        for key, button in pairs(modeButtons) do
            button:SetChecked(KnownPlayersSettings.playerHealthBarMode == key)
        end
    end
    for _, item in ipairs({
        { "always", "Always", 20 },
        { "combat", "In combat", 165 },
        { "never", "Never", 305 },
    }) do
        local mode, label, x = item[1], item[2], item[3]
        modeButtons[mode] = Checkbox(body, x, -119, label,
            KnownPlayersSettings.playerHealthBarMode == mode,
            function() SelectHealthBarMode(mode) end)
    end
    RegisterSettingsRefresher(function()
        for mode, button in pairs(modeButtons) do
            button:SetChecked(KnownPlayersSettings.playerHealthBarMode == mode)
        end
    end)

    local line = body:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.45, 0.45, 0.45, 0.4)
    line:SetPoint("TOPLEFT", body, "TOPLEFT", 20, -169)
    line:SetWidth(432)
    line:SetHeight(1)

    Label(body, "Tracking, colors, and priority", 21, -182, "GameFontNormal")
    Label(body, "Top enabled category wins when a player belongs to several lists.", 21, -205)
    local colorRows = {}
    local function RefreshOrder()
        for i, row in ipairs(colorRows) do
            local key = KnownPlayersSettings.nameplateColorOrder[i]
            row.key = key
            row.checkbox.Text:SetText(i .. ". " .. TRACKING_CATEGORIES[key].label)
            row.checkbox:SetChecked(ns.CategoryTrackingEnabled(key))
            local rgb = ns.GetNameplateCategoryColor(key)
            row.swatch:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
            row.up:SetEnabled(i > 1)
            row.down:SetEnabled(i < #colorRows)
        end
        if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
    end
    local function PickColor(key)
        local picker = ColorPickerFrame
        if not picker then return end
        local color = ns.GetNameplateCategoryColor(key)
        local function SetColor()
            local r,g,b = picker:GetColorRGB()
            KnownPlayersSettings.nameplateCategoryColors[key] = {r,g,b}
            RefreshOrder()
        end
        if type(picker.SetupColorPickerAndShow) == "function" then
            picker:SetupColorPickerAndShow({r=color[1],g=color[2],b=color[3],hasOpacity=false,swatchFunc=SetColor})
        else
            picker.func = SetColor
            picker.hasOpacity = false
            picker:SetColorRGB(color[1],color[2],color[3])
            picker:Show()
        end
    end
    local colorRowSpacing = 29
    for i in ipairs(KnownPlayersSettings.nameplateColorOrder) do
        local row = {}
        local y = -236 - (i - 1) * colorRowSpacing
        row.checkbox = Checkbox(body, 20, y - 3, "", false, function(checked)
            SetCategoryTracking(TRACKING_CATEGORIES[row.key], checked)
        end)
        local button = Button(body, "Color", 72, function() PickColor(row.key) end)
        button:SetPoint("TOPLEFT", body, "TOPLEFT", 270, y)
        row.swatch = button:CreateTexture(nil,"OVERLAY")
        row.swatch:SetSize(14,14)
        row.swatch:SetPoint("LEFT",button,"LEFT",5,0)
        row.up = Button(body,"^",25,function()
            if i <= 1 then return end
            local order=KnownPlayersSettings.nameplateColorOrder
            order[i],order[i-1]=order[i-1],order[i]
            RefreshOrder()
        end)
        row.up:SetPoint("TOPLEFT", body, "TOPLEFT", 350, y)
        row.down = Button(body,"v",25,function()
            if i >= #colorRows then return end
            local order=KnownPlayersSettings.nameplateColorOrder
            order[i],order[i+1]=order[i+1],order[i]
            RefreshOrder()
        end)
        row.down:SetPoint("LEFT",row.up,"RIGHT",3,0)
        colorRows[#colorRows+1] = row
    end
    RefreshOrder()
    RegisterSettingsRefresher(RefreshOrder)

    local retentionTop = -251 - #colorRows * colorRowSpacing
    local line2 = body:CreateTexture(nil, "ARTWORK")
    line2:SetColorTexture(0.45, 0.45, 0.45, 0.4)
    line2:SetPoint("TOPLEFT", body, "TOPLEFT", 20, retentionTop)
    line2:SetWidth(432)
    line2:SetHeight(1)

    Label(body, "When should players be forgotten?", 21, retentionTop - 13, "GameFontNormal")
    Label(body, "Forget", 22, retentionTop - 47, "GameFontNormalSmall")
    Label(body, "Duration", 188, retentionTop - 47, "GameFontNormalSmall")

    local guildNote = Label(body, "Guild membership is roster-based and does not expire.", 21, -800)
    local listsSection = CreateFrame("Frame", nil, body)
    listsSection:SetSize(440, 124)
    Label(listsSection, "Player Lists", 0, -3, "GameFontNormal")
    local playerList = Button(listsSection, "Open Player List", 177, function()
        ns.OpenPlayerList("players")
    end)
    playerList:SetPoint("TOPLEFT", listsSection, "TOPLEFT", 0, -28)
    local guildList = Button(listsSection, "Guild Roster", 177, function()
        ns.OpenPlayerList("guild")
    end)
    guildList:SetPoint("TOPLEFT", listsSection, "TOPLEFT", 196, -28)
    local altList = Button(listsSection, "Known Battle.net Alts", 177, function()
        ns.OpenPlayerList("associated")
    end)
    altList:SetPoint("TOPLEFT", listsSection, "TOPLEFT", 0, -62)
    local clearAll = Button(listsSection, "Clear All Lists", 177, function()
        StaticPopup_Show("KNOWNPLAYERS_CLEAR_ALL_LISTS")
    end)
    clearAll:SetPoint("TOPLEFT", listsSection, "TOPLEFT", 196, -62)
    local bottomLine = listsSection:CreateTexture(nil, "ARTWORK")
    bottomLine:SetColorTexture(0.45, 0.45, 0.45, 0.4)
    bottomLine:SetPoint("TOPLEFT", listsSection, "TOPLEFT", 0, -105)
    bottomLine:SetWidth(432)
    bottomLine:SetHeight(1)

    local retentionRows = {}
    local function LayoutRetentionRows()
        local y = retentionTop - 67
        for _, row in ipairs(retentionRows) do
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", body, "TOPLEFT", 18, y)
            y = y - row:GetHeight()
        end
        guildNote:ClearAllPoints()
        guildNote:SetPoint("TOPLEFT", body, "TOPLEFT", 21, y - 8)
        listsSection:ClearAllPoints()
        listsSection:SetPoint("TOPLEFT", body, "TOPLEFT", 20, y - 44)
        body:SetHeight(math.max(1033, -y + 190))
    end
    for _, category in ipairs(CATEGORIES) do
        if category.key ~= "guild" then
            retentionRows[#retentionRows+1] = RetentionRow(body, category, LayoutRetentionRows, true)
        end
    end
    LayoutRetentionRows()
    return page
end

local function BuildNPCPage()
    local page, body = NewScrollingPage("NPC Nameplates & Lists", "")

    Label(body, "NPC database", 21, -8, "GameFontNormal")
    Label(body, "Automatic NPC roles come from the separately installed QuestieDB addon.", 21, -32)
    Label(body, "KnownPlayers uses its API bridge; no NPC database is bundled.", 21, -49)
    local sourceStatus = Label(body, "QuestieDB status: checking...", 21, -66)
    local function RefreshSourceStatus()
        local message = ns.GetNPCDataSourceStatus and ns.GetNPCDataSourceStatus()
            or "QuestieDB bridge unavailable"
        sourceStatus:SetText(message)
        local connected = ns.IsQuestieDBConnected and ns.IsQuestieDBConnected()
        if connected then
            sourceStatus:SetTextColor(0.35, 1.0, 0.45, 1) -- connected: green
        else
            sourceStatus:SetTextColor(1.0, 0.33, 0.33, 1) -- missing/incompatible: red
        end
    end
    page:HookScript("OnShow", RefreshSourceStatus)
    RegisterSettingsRefresher(RefreshSourceStatus)
    local sourceEvents = CreateFrame("Frame", nil, page)
    sourceEvents:RegisterEvent("ADDON_LOADED")
    sourceEvents:SetScript("OnEvent", function() if page:IsShown() then RefreshSourceStatus() end end)
    RefreshSourceStatus()

    local sourceLine = body:CreateTexture(nil, "ARTWORK")
    sourceLine:SetColorTexture(0.45, 0.45, 0.45, 0.4)
    sourceLine:SetPoint("TOPLEFT", body, "TOPLEFT", 20, -92)
    sourceLine:SetSize(432, 1)

    Label(body, "Nameplate appearance", 21, -107, "GameFontNormal")
    local full, first
    local function SelectNPCNameMode(mode)
        KnownPlayersSettings.npcNameDisplayMode = mode
        full:SetChecked(mode == "full")
        first:SetChecked(mode == "first")
        if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
    end
    full = Checkbox(body, 20, -131, "Full name",
        KnownPlayersSettings.npcNameDisplayMode ~= "first", function()
            SelectNPCNameMode("full")
        end)
    first = Checkbox(body, 125, -131, "First name",
        KnownPlayersSettings.npcNameDisplayMode == "first", function()
            SelectNPCNameMode("first")
        end)
    RegisterSettingsRefresher(function()
        full:SetChecked(KnownPlayersSettings.npcNameDisplayMode ~= "first")
        first:SetChecked(KnownPlayersSettings.npcNameDisplayMode == "first")
    end)
    Checkbox(body, 229, -131, "NPC title",
        KnownPlayersSettings.showNPCTitle, function(checked)
            KnownPlayersSettings.showNPCTitle = checked
            if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
        end, function() return KnownPlayersSettings.showNPCTitle end)
    Checkbox(body, 344, -131, "Health bar",
        not KnownPlayersSettings.npcNamesOnlyNameplates, function(checked)
            KnownPlayersSettings.npcNamesOnlyNameplates = not checked
            if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
        end, function() return not KnownPlayersSettings.npcNamesOnlyNameplates end)

    local line = body:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.45, 0.45, 0.45, 0.4)
    line:SetPoint("TOPLEFT", body, "TOPLEFT", 20, -178)
    line:SetSize(432, 1)

    Label(body, "Category colors and priority", 21, -193, "GameFontNormal")
    Label(body, "Top enabled role determines the color for multi-role NPCs.", 21, -216)
    local categoryInfo = ns.GetNPCServiceCategories and ns.GetNPCServiceCategories() or {}
    local labels = {}
    for _, category in ipairs(categoryInfo) do labels[category.key] = category.label end
    local colorRows = {}
    local function RefreshOrder()
        local order = KnownPlayersSettings.npcNameplateColorOrder
        for i, row in ipairs(colorRows) do
            local key = order[i]
            row.key = key
            row.checkbox.Text:SetText(i .. ". " .. (labels[key] or key))
            row.checkbox:SetChecked(KnownPlayersSettings.npcServiceCategories[key] == true)
            local rgb = ns.GetNPCNameplateCategoryColor(key)
            row.swatch:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
            row.up:SetEnabled(i > 1)
            row.down:SetEnabled(i < #colorRows)
        end
        if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
    end
    local function PickColor(key)
        local picker = ColorPickerFrame
        if not picker then return end
        local color = ns.GetNPCNameplateCategoryColor(key)
        local function SetColor()
            local r, g, b = picker:GetColorRGB()
            KnownPlayersSettings.npcNameplateCategoryColors[key] = {r, g, b}
            RefreshOrder()
        end
        if type(picker.SetupColorPickerAndShow) == "function" then
            picker:SetupColorPickerAndShow({
                r=color[1], g=color[2], b=color[3], hasOpacity=false, swatchFunc=SetColor,
            })
        else
            picker.func = SetColor
            picker.hasOpacity = false
            picker:SetColorRGB(color[1], color[2], color[3])
            picker:Show()
        end
    end
    -- Match the numbered category rows on the player page.
    for i = 1, #categoryInfo do
        local row = {}
        local y = -239 - (i - 1) * 29
        row.checkbox = Checkbox(body, 20, y, "",
            false, function(checked)
                KnownPlayersSettings.npcServiceCategories[row.key] = checked
                if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
            end, function()
                return KnownPlayersSettings.npcServiceCategories[row.key]
            end)
        local button = Button(body, "Color", 72, function() PickColor(row.key) end)
        button:SetPoint("TOPLEFT", body, "TOPLEFT", 270, y + 3)
        row.swatch = button:CreateTexture(nil, "OVERLAY")
        row.swatch:SetSize(14, 14)
        row.swatch:SetPoint("LEFT", button, "LEFT", 5, 0)
        row.up = Button(body, "^", 25, function()
            if i <= 1 then return end
            local order = KnownPlayersSettings.npcNameplateColorOrder
            order[i], order[i - 1] = order[i - 1], order[i]
            RefreshOrder()
        end)
        row.up:SetPoint("TOPLEFT", body, "TOPLEFT", 350, y + 3)
        row.down = Button(body, "v", 25, function()
            if i >= #colorRows then return end
            local order = KnownPlayersSettings.npcNameplateColorOrder
            order[i], order[i + 1] = order[i + 1], order[i]
            RefreshOrder()
        end)
        row.down:SetPoint("LEFT", row.up, "RIGHT", 3, 0)
        colorRows[#colorRows + 1] = row
    end
    RefreshOrder()
    RegisterSettingsRefresher(RefreshOrder)

    local bottom = -239 - #categoryInfo * 29 - 12
    local rule = body:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(0.45, 0.45, 0.45, 0.4)
    rule:SetPoint("TOPLEFT", body, "TOPLEFT", 20, bottom)
    rule:SetSize(432, 1)

    Label(body, "NPC management", 21, bottom - 20, "GameFontNormal")
    Label(body, "Search manually saved NPCs, change overrides, and manage remembered NPCs.", 21, bottom - 42)
    local npcList = Button(body, "Open NPC Manager", 180, function() ns.OpenPlayerList("npc") end)
    npcList:SetPoint("TOPLEFT", body, "TOPLEFT", 20, bottom - 61)

    Label(body, "Forget manually remembered NPCs after inactivity", 21, bottom - 96, "GameFontNormal")
    Label(body, "Forget", 22, bottom - 130, "GameFontNormalSmall")
    Label(body, "Duration", 187, bottom - 130, "GameFontNormalSmall")
    local retentionRow = RetentionRow(body, {key="npc", label="NPCs"})
    if retentionRow then
        retentionRow:SetPoint("TOPLEFT", body, "TOPLEFT", 20, bottom - 148)
    end
    body:SetHeight(math.max(700, -bottom + 240))
    return page
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
    panel = BuildHomePage()
    panel.name = "KnownPlayers"
    local players = BuildPlayerPage()
    local npcs = BuildNPCPage()
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterCanvasLayoutSubcategory then
        local parent = Settings.RegisterCanvasLayoutCategory(panel, "KnownPlayers")
        Settings.RegisterAddOnCategory(parent)
        panel.categoryID = parent:GetID()
        Settings.RegisterCanvasLayoutSubcategory(parent, players, "Player Nameplates & Lists")
        Settings.RegisterCanvasLayoutSubcategory(parent, npcs, "NPC Nameplates & Lists")
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        for _, child in ipairs({ {players,"Player Nameplates & Lists"}, {npcs,"NPC Nameplates & Lists"} }) do
            child[1].name = child[2]
            child[1].parent = "KnownPlayers"
            InterfaceOptions_AddCategory(child[1])
        end
    else
        print("|cffff5555KnownPlayers:|r Unable to register settings panel on this client.")
    end
end

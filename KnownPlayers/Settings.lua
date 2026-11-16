local addonName, ns = ...
local panel

-- Reset preferences only; KnownPlayersDB and player histories are untouched.
StaticPopupDialogs["KNOWNPLAYERS_RESET_SETTINGS"] = {
    text = "Reset all KnownPlayers settings to their defaults?\n\nSaved player lists will not be deleted.",
    button1 = "Reset Settings",
    button2 = CANCEL,
    OnAccept = function()
        KnownPlayersSettings = {}
        ns.InitializeDatabase()
        if ns.InitializeNameplateColors then ns.InitializeNameplateColors() end
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Clear stored player histories and Battle.net associations without resetting preferences.
StaticPopupDialogs["KNOWNPLAYERS_CLEAR_ALL_LISTS"] = {
    text = "Clear ALL KnownPlayers player lists and saved Battle.net alt associations?\n\nThis cannot be undone. Enabled tracking may add players again on future encounters or roster scans.",
    button1 = "Clear All Lists",
    button2 = CANCEL,
    OnAccept = function()
        if type(KnownPlayersDB) ~= "table" then return end
        KnownPlayersDB.players = {}
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
    { key = "pvp", label = "PvP Attackers", tracking = "trackPvP", description = "Remember players who attack you" },
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

local function Checkbox(parent, x, y, title, current, onClick)
    local button = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button.Text:SetText(title)
    button:SetChecked(current)
    button:SetScript("OnClick", function(self)
        onClick(self:GetChecked() and true or false)
    end)
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

-- Each category has independent tracking and forgetting preferences.
-- Keep the controls visible on the main page rather than hiding them behind
-- category expansion buttons.
local function TrackingCheckbox(parent, category, x, y)
    local current = category.group and KnownPlayersSettings.trackGroup[category.group]
        or KnownPlayersSettings[category.tracking]
    Checkbox(parent, x, y, category.label, current, function(checked)
        if category.group then
            KnownPlayersSettings.trackGroup[category.group] = checked
            if checked and ns.ScanGroupRoster then ns.ScanGroupRoster() end
        else
            KnownPlayersSettings[category.tracking] = checked
            if checked and category.key == "guild" and ns.RequestGuildRoster then
                ns.RequestGuildRoster()
                if ns.ScanGuildRoster then ns.ScanGuildRoster() end
            end
        end
        if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
    end)
end

local RETENTION_PRESETS = {
    {"1 minute", 0, 0, 1}, {"5 minutes", 0, 0, 5},
    {"1 hour", 0, 1, 0}, {"6 hours", 0, 6, 0},
    {"12 hours", 0, 12, 0}, {"1 day", 1, 0, 0},
    {"3 days", 3, 0, 0}, {"7 days", 7, 0, 0},
    {"14 days", 14, 0, 0}, {"30 days", 30, 0, 0},
    {"90 days", 90, 0, 0},
}

local function RetentionRow(parent, category, onLayoutChanged)
    local retention = ns.GetCategoryRetention(category.key)
    if not retention then return end

    -- Let each row own its height. Custom duration inputs expand the row,
    -- and the parent reflows every row that follows it.
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(445, 50)
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
        row:SetHeight(customMode and 82 or 50)
        if onLayoutChanged then onLayoutChanged() end
    end

    Checkbox(row, 2, 0, category.label, retention.enabled, function(checked)
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
    return row
end

local function BuildHomePage()
    local page, content = NewScrollingPage("KnownPlayers", "")
    -- A visibility filter, not a master switch for the tracking/database addon.
    Checkbox(content, 16, -12, "Enable KnownPlayers nameplate filtering",
        KnownPlayersSettings.knownOnlyNameplates, function(checked)
            if ns.SetKnownOnlyNameplates then ns.SetKnownOnlyNameplates(checked) end
        end)

    Label(content, "What do you want to track?", 16, -84, "GameFontNormal")
    Label(content, "Remember players from these interactions.", 16, -107)

    for index, category in ipairs(CATEGORIES) do
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        TrackingCheckbox(content, category, 16 + column * 214, -133 - row * 37)
    end

    Checkbox(content, 16, -281, "Known Battle.net Alts",
        KnownPlayersSettings.trackBattleNetAssociations, function(checked)
            KnownPlayersSettings.trackBattleNetAssociations = checked
            if checked and ns.ScanBattleNetFriends then ns.ScanBattleNetFriends() end
            if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
        end)

    local line = content:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.45, 0.45, 0.45, 0.4)
    line:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -316)
    line:SetPoint("RIGHT", content, "RIGHT", -16, 0)
    line:SetHeight(1)

    Label(content, "When should players be forgotten?", 16, -338, "GameFontNormal")
    Label(content, "Forget", 18, -387, "GameFontNormalSmall")
    Label(content, "Duration", 185, -387, "GameFontNormalSmall")
    local rows = {}
    local guildNote = Label(content, "Guild members are retained while in your saved guild list.", 18, -740)
    local reset = Button(content, "Reset Settings to Defaults", 205, function()
        StaticPopup_Show("KNOWNPLAYERS_RESET_SETTINGS")
    end)
    local function LayoutRetentionRows()
        local y = -410
        for _, row in ipairs(rows) do
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
            y = y - row:GetHeight()
        end
        guildNote:ClearAllPoints()
        guildNote:SetPoint("TOPLEFT", content, "TOPLEFT", 18, y - 8)
        reset:ClearAllPoints()
        reset:SetPoint("TOPLEFT", content, "TOPLEFT", 18, y - 46)
        content:SetHeight(math.max(700, -y + 110))
    end
    for _, category in ipairs(CATEGORIES) do
        if category.key ~= "guild" then
            rows[#rows + 1] = RetentionRow(content, category, LayoutRetentionRows)
        end
    end
    LayoutRetentionRows()
    return page
end

local function BuildListPage()
    local page = NewPage("Player Lists", "Browse and manage players saved under each interaction category.")
    local choices = {
        {key="trade",label="Trade"}, {key="party",label="Party"},
        {key="raid",label="Raid"}, {key="guild",label="Guild"},
        {key="whisper",label="Whisper"}, {key="target",label="Target"},
        {key="inspect",label="Inspect"}, {key="pvp",label="PvP Attackers"},
        {key="associated",label="Known Battle.net Alts"},
    }
    for index, choice in ipairs(choices) do
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local button = Button(page, choice.label, 195, function() ns.OpenPlayerList(choice.key) end)
        button:SetPoint("TOPLEFT", page, "TOPLEFT", 20 + column * 219, -97 - row * 47)
    end
    local clearAll = Button(page, "Clear All Lists", 160, function()
        StaticPopup_Show("KNOWNPLAYERS_CLEAR_ALL_LISTS")
    end)
    clearAll:SetPoint("TOPLEFT", page, "TOPLEFT", 20, -362)
    return page
end

local function BuildNameplatePage()
    local page = NewPage("Nameplate Appearance", "")
    -- This page fits within the Options panel; no scroll frame is needed.
    local body = CreateFrame("Frame", nil, page)
    body:SetPoint("TOPLEFT", page, "TOPLEFT", 3, -55)
    body:SetSize(465, 530)

    Label(body, "Name format and guild name apply with or without health bars.", 21, -14)
    local full, first
    local function SelectNameMode(mode)
        KnownPlayersSettings.nameDisplayMode = mode
        full:SetChecked(mode == "full")
        first:SetChecked(mode == "first")
        if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
    end
    full = Checkbox(body, 20, -42, "Full name",
        KnownPlayersSettings.nameDisplayMode ~= "first", function()
            SelectNameMode("full")
        end)
    first = Checkbox(body, 125, -42, "First name",
        KnownPlayersSettings.nameDisplayMode == "first", function()
            SelectNameMode("first")
        end)
    Checkbox(body, 229, -42, "Guild name",
        KnownPlayersSettings.showGuildInNamesOnly, function(checked)
            KnownPlayersSettings.showGuildInNamesOnly = checked
            if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
        end)

    Checkbox(body, 344, -42, "Show health bar",
        not KnownPlayersSettings.namesOnlyNameplates, function(checked)
            if ns.SetNamesOnlyNameplates then ns.SetNamesOnlyNameplates(not checked) end
        end)

    local line = body:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.45, 0.45, 0.45, 0.4)
    line:SetPoint("TOPLEFT", body, "TOPLEFT", 20, -84)
    line:SetWidth(432)
    line:SetHeight(1)

    local palette = {
        pvp="PvP Attackers", trade="Trade", guild="Guild", associated="Known Battle.net Alts",
        whisper="Whisper", raid="Raid", party="Party", inspect="Inspect", target="Target",
    }
    Label(body, "Category colors and priority", 21, -96, "GameFontNormal")
    Label(body, "Top category wins when a player belongs to several lists.", 21, -122)
    local rows = {}
    local function RefreshOrder()
        for i, row in ipairs(rows) do
            local key = KnownPlayersSettings.nameplateColorOrder[i]
            row.key = key
            row.title:SetText(i .. ". " .. palette[key])
            local rgb = ns.GetNameplateCategoryColor(key)
            row.swatch:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
            row.up:SetEnabled(i > 1)
            row.down:SetEnabled(i < #rows)
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
    for i = 1, 9 do
        local row = {}
        row.title = Label(body, "", 22, -155 - (i-1)*36, "GameFontHighlightSmall")
        local button = Button(body, "Color", 72, function() PickColor(row.key) end)
        button:SetPoint("TOPLEFT",body,"TOPLEFT",270,-152-(i-1)*36)
        row.swatch = button:CreateTexture(nil,"OVERLAY")
        row.swatch:SetSize(14,14)
        row.swatch:SetPoint("LEFT",button,"LEFT",5,0)
        row.up = Button(body,"^",25,function()
            if i <= 1 then return end
            local order=KnownPlayersSettings.nameplateColorOrder
            order[i],order[i-1]=order[i-1],order[i]
            RefreshOrder()
        end)
        row.up:SetPoint("TOPLEFT",body,"TOPLEFT",350,-152-(i-1)*36)
        row.down = Button(body,"v",25,function()
            if i >= #rows then return end
            local order=KnownPlayersSettings.nameplateColorOrder
            order[i],order[i+1]=order[i+1],order[i]
            RefreshOrder()
        end)
        row.down:SetPoint("LEFT",row.up,"RIGHT",3,0)
        rows[#rows+1] = row
    end
    RefreshOrder()
    body:SetHeight(530)
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
    local nameplates = BuildNameplatePage()
    local lists = BuildListPage()
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterCanvasLayoutSubcategory then
        local parent = Settings.RegisterCanvasLayoutCategory(panel, "KnownPlayers")
        Settings.RegisterAddOnCategory(parent)
        panel.categoryID = parent:GetID()
        Settings.RegisterCanvasLayoutSubcategory(parent, nameplates, "Nameplate Appearance")
        Settings.RegisterCanvasLayoutSubcategory(parent, lists, "Player Lists")
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        for _, child in ipairs({ {nameplates,"Nameplate Appearance"}, {lists,"Player Lists"} }) do
            child[1].name = child[2]
            child[1].parent = "KnownPlayers"
            InterfaceOptions_AddCategory(child[1])
        end
    else
        print("|cffff5555KnownPlayers:|r Unable to register settings panel on this client.")
    end
end

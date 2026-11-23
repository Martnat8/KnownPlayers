local _, ns = ...
local window

local SECTIONS = {
    {key = "settings", label = "Settings", x = 18},
    {key = "players", label = "Player history", x = 158},
    {key = "npcs", label = "Saved NPCs", x = 332},
}
local POINT_TYPES = {"manual", "automatic"}
local CONFIRM_RESTORE = "KNOWNPLAYERS_RESTORE_BACKUP"

StaticPopupDialogs[CONFIRM_RESTORE] = {
    text = "Replace the selected data?\n\n%s\n\nA restore point will be saved first.",
    button1 = "Replace",
    button2 = CANCEL,
    OnAccept = function(_, apply) apply() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function Button(parent, text, width, x, y, click)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 24)
    button:SetPoint("TOPLEFT", x, y)
    button:SetText(text)
    button:SetScript("OnClick", click)
    return button
end

local function Label(parent, text, x, y, width)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("TOPLEFT", x, y)
    label:SetWidth(width or 506)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end

local function SectionChecks(parent, y, refresh)
    local checks = {}
    for _, section in ipairs(SECTIONS) do
        local check = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
        check:SetPoint("TOPLEFT", section.x - 4, y)
        check.Text:SetText(section.label)
        check:SetScript("OnClick", refresh)
        checks[section.key] = check
    end
    return checks
end

local function SetSections(checks, sections, all)
    for key, check in pairs(checks) do
        local available = sections and sections[key] ~= nil
        check:SetEnabled(available == true)
        check:SetChecked(available == true and (all or key == "settings"))
    end
end

local function Selected(checks)
    local result = {}
    for key, check in pairs(checks) do
        if check:GetChecked() then result[key] = true end
    end
    return result
end

local function TextBox(parent, y, height)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelInputScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, y)
    scroll:SetSize(506, height)
    scroll.hideCharCount = true
    local edit = scroll.EditBox
    edit:SetWidth(488)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    parent:HookScript("OnHide", function() edit:ClearFocus() end)
    return edit, scroll
end

local function BackupDate(created)
    if type(created) == "number" then
        local ok, label = pcall(date, "%Y-%m-%d %H:%M", created)
        if ok and label then return label end
    end
    return "Date unavailable"
end

local function PointLabel(point)
    if not point then return "No restore points" end
    return (ns.SafeString(point.reason) or "Manual backup") .. "  ·  " .. BackupDate(point.created)
end

local function ApplyAndReport(snapshot, selection, mode, localBackup, status, onDone)
    local function Apply()
        local ok, result = ns.ApplyBackup(snapshot, selection, mode, localBackup)
        if not ok then status:SetText(result); return end
        if onDone then onDone() end
        local message = localBackup and "Backup restored." or "Import complete."
        if result > 0 then message = message .. " Skipped " .. result .. " ambiguous or conflicting player records." end
        status:SetText(message)
    end
    if mode == "replace" then
        StaticPopup_Show(CONFIRM_RESTORE, ns.DescribeBackup(snapshot, selection), nil, Apply)
    else
        Apply()
    end
end

local function BuildRestorePage(page)
    Label(page, "Keep one manual restore point and the latest automatic restore point.", 18, -15)
    local status = Label(page, "", 18, -244)
    local summary = Label(page, "", 18, -127)
    local selectedPoint = "manual"
    local dropdown = CreateFrame("DropdownButton", nil, page, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("TOPLEFT", 18, -90)
    dropdown:SetSize(498, 25)
    local Apply, checks
    local function RefreshSelection()
        local point = ns.GetRestorePoint(selectedPoint)
        local selection = Selected(checks)
        summary:SetText(point and ns.DescribeBackup(point, selection) or "Create a backup to use as a restore point.")
        Apply:SetEnabled(point ~= nil and next(selection) ~= nil)
    end
    checks = SectionChecks(page, -159, RefreshSelection)

    local function RefreshPoint()
        local point = ns.GetRestorePoint(selectedPoint)
        SetSections(checks, point and point.sections, true)
        dropdown:GenerateMenu()
        dropdown:Update()
        RefreshSelection()
    end

    dropdown:SetSelectionText(function() return PointLabel(ns.GetRestorePoint(selectedPoint)) end)
    dropdown:SetupMenu(function(_, menu)
        for _, kind in ipairs(POINT_TYPES) do
            local point = ns.GetRestorePoint(kind)
            if point then
                menu:CreateRadio(PointLabel(point), function(value) return selectedPoint == value end,
                    function(value) selectedPoint = value; RefreshPoint() end, kind)
            end
        end
    end)
    Button(page, "Create Backup", 130, 18, -46, function()
        local point, message = ns.CreateRestorePoint("manual", "Manual backup")
        if point then selectedPoint = "manual"; RefreshPoint() end
        status:SetText(point and "Manual backup created." or message)
    end)
    Apply = Button(page, "Restore Selected", 140, 18, -202, function()
        local point = ns.GetRestorePoint(selectedPoint)
        if point then ApplyAndReport(point, Selected(checks), "replace", true, status, RefreshPoint) end
    end)
    page:SetScript("OnShow", function()
        if not ns.GetRestorePoint(selectedPoint) then
            selectedPoint = ns.GetRestorePoint("automatic") and "automatic" or "manual"
        end
        RefreshPoint()
    end)
end

local function BuildExportPage(page)
    local status = Label(page, "", 18, -347)
    local private = Label(page, "Player history includes character names, notes, and tags. Keep this export private.", 18, -95)
    private:SetTextColor(1, 0.78, 0.26)
    local edit, scroll = TextBox(page, -136, 198)
    local output = ""
    edit:HookScript("OnTextChanged", function(self, userInput)
        if userInput then self:SetText(output); self:HighlightText() end
    end)
    local generate, checks
    local function ChangeSelection()
        local selection = Selected(checks)
        output = ""
        edit:SetText("")
        private:SetShown(selection.players == true)
        local available = ns.CanTransferBackups()
        generate:SetEnabled(available and next(selection) ~= nil)
        status:SetText(available and "" or "Export is unavailable on this WoW client.")
    end
    checks = SectionChecks(page, -15, ChangeSelection)
    generate = Button(page, "Generate Export", 132, 18, -56, function()
        local text, message = ns.ExportBackup(Selected(checks))
        if not text then status:SetText(message); return end
        output = text
        edit:SetText(output)
        scroll:SetVerticalScroll(0)
        edit:SetFocus()
        edit:HighlightText()
        status:SetText("Press Ctrl+C to copy. Keep a copy outside WoW.")
    end)
    page:SetScript("OnShow", function()
        SetSections(checks, {settings = true, players = true, npcs = true}, false)
        ChangeSelection()
    end)
end

local function BuildImportPage(page)
    local status = Label(page, "", 18, -352)
    local summary = Label(page, "", 18, -203)
    local edit = TextBox(page, -36, 125)
    Label(page, "Paste a KnownPlayers export below.", 18, -13)
    local snapshot, merge, replace, preview, checks

    local function RefreshSelection()
        local selection = Selected(checks)
        local hasHistory = selection.players or selection.npcs
        merge:SetText(hasHistory and "Merge" or "Import Settings")
        merge:SetEnabled(snapshot ~= nil and next(selection) ~= nil)
        replace:SetEnabled(snapshot ~= nil and hasHistory == true)
    end

    checks = SectionChecks(page, -254, RefreshSelection)
    local function ClearPreview()
        snapshot = nil
        SetSections(checks, nil)
        summary:SetText("")
        local available = ns.CanTransferBackups()
        preview:SetEnabled(available and edit:GetText() ~= "")
        status:SetText(available and "" or "Import is unavailable on this WoW client.")
        RefreshSelection()
    end
    local function FinishImport()
        edit:SetText("")
        ClearPreview()
    end

    preview = Button(page, "Preview", 92, 18, -174, function()
        local message
        snapshot, message = ns.ReadBackup(edit:GetText())
        SetSections(checks, snapshot and snapshot.sections, true)
        if snapshot then
            edit:ClearFocus()
            summary:SetText(BackupDate(snapshot.created) .. "  ·  " .. ns.DescribeBackup(snapshot, Selected(checks)))
        end
        status:SetText(message or "")
        RefreshSelection()
    end)
    merge = Button(page, "Merge", 130, 18, -297, function()
        if snapshot then ApplyAndReport(snapshot, Selected(checks), "merge", false, status, FinishImport) end
    end)
    replace = Button(page, "Replace Selected", 133, 158, -297, function()
        if snapshot then ApplyAndReport(snapshot, Selected(checks), "replace", false, status, FinishImport) end
    end)
    edit:HookScript("OnTextChanged", ClearPreview)
    page:SetScript("OnShow", function() edit:SetText(""); ClearPreview() end)
end

local function CreateWindow()
    local frame = CreateFrame("Frame", "KnownPlayersBackupWindow", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(568, 465)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:HookScript("OnHide", function(self) self:StopMovingOrSizing() end)
    frame.TitleText:SetText("Backup & Restore")
    frame:Hide()
    ns.EnableWindowEscape(frame)

    local tabs, pages = {}, {}
    local function Select(index)
        for i, page in ipairs(pages) do
            page:SetShown(i == index)
            tabs[i]:SetEnabled(i ~= index)
        end
    end
    for index, definition in ipairs({
        {"Restore Points", BuildRestorePage}, {"Export", BuildExportPage}, {"Import", BuildImportPage},
    }) do
        local page = CreateFrame("Frame", nil, frame)
        page:SetPoint("TOPLEFT", 8, -69)
        page:SetPoint("BOTTOMRIGHT", -8, 11)
        page:Hide()
        definition[2](page)
        pages[index] = page
        tabs[index] = Button(frame, definition[1], 108, 24 + 114 * (index - 1), -32, function() Select(index) end)
    end
    Select(1)
    return frame
end

function ns.OpenBackupWindow(settingsPage)
    if not window then window = CreateWindow() end
    ns.ShowWindow(window, settingsPage)
end

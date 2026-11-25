local _, ns = ...
local window

local SECTIONS = {
    {key = "settings", label = "Settings", x = 18},
    {key = "players", label = "Player history", x = 158},
    {key = "npcs", label = "Saved NPCs", x = 332},
}
local POINT_TYPES = {"manual", "automatic"}
local CONFIRM_RESTORE = "KNOWNPLAYERS_RESTORE_BACKUP"
local CONFIRM_DELETE = "KNOWNPLAYERS_DELETE_RESTORE_POINT"

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

StaticPopupDialogs[CONFIRM_DELETE] = {
    text = "Permanently delete this local restore point?\n\n%s",
    button1 = "Delete",
    button2 = CANCEL,
    OnAccept = function(_, delete) delete() end,
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

local function SetPayloadVisible(scroll, button, visible)
    -- Keep the edit box shown so WoW can handle the clipboard shortcut.
    scroll:SetAlpha(visible and 1 or 0)
    scroll.EditBox:EnableMouse(visible)
    button:SetText(visible and "Hide Backup Text" or "Show Backup Text")
end

local function PayloadToggle(page, scroll, x, y)
    return Button(page, "Show Backup Text", 142, x, y, function(self)
        SetPayloadVisible(scroll, self, scroll:GetAlpha() == 0)
    end)
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
        local ok, result, refreshFailed = ns.ApplyBackup(snapshot, selection, mode, localBackup)
        if not ok then status:SetText(result); return end
        if onDone and not pcall(onDone) then refreshFailed = true end
        local message = localBackup and "Backup restored." or "Import complete."
        if result > 0 then message = message .. " Skipped " .. result .. " ambiguous or conflicting player records." end
        if refreshFailed then message = message .. " Some views could not refresh. Reopen the affected windows or reload the UI." end
        status:SetText(message)
    end
    if mode == "replace" then
        StaticPopup_Show(CONFIRM_RESTORE, ns.DescribeBackup(snapshot, selection), nil, Apply)
    else
        Apply()
    end
end

local function BuildRestorePage(page)
    Label(page, "Forget removes active player history. Manual and automatic restore points can still contain copies.", 18, -15)
    local status = Label(page, "", 18, -266)
    local summary = Label(page, "", 18, -127)
    local selectedPoint = "manual"
    local dropdown = CreateFrame("DropdownButton", nil, page, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("TOPLEFT", 18, -90)
    dropdown:SetSize(498, 25)
    local Apply, Delete, checks
    local function RefreshSelection()
        local point = ns.GetRestorePoint(selectedPoint)
        local selection = Selected(checks)
        summary:SetText(point and ns.DescribeBackup(point, selection) or "Create a backup to use as a restore point.")
        Apply:SetEnabled(point ~= nil and next(selection) ~= nil)
        Delete:SetEnabled(point ~= nil)
    end
    checks = SectionChecks(page, -183, RefreshSelection)

    local function RefreshPoint()
        local point = ns.GetRestorePoint(selectedPoint)
        if not point then
            selectedPoint = ns.GetRestorePoint("manual") and "manual" or "automatic"
            point = ns.GetRestorePoint(selectedPoint)
        end
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
    Apply = Button(page, "Restore Selected", 140, 18, -224, function()
        local point = ns.GetRestorePoint(selectedPoint)
        if point then ApplyAndReport(point, Selected(checks), "replace", true, status, RefreshPoint) end
    end)
    Delete = Button(page, "Delete Restore Point", 152, 168, -224, function()
        local kind = selectedPoint
        local point = ns.GetRestorePoint(kind)
        if not point then return end
        StaticPopup_Show(CONFIRM_DELETE, PointLabel(point), nil, function()
            local deleted = ns.DeleteRestorePoint(kind, point)
            RefreshPoint()
            status:SetText(deleted and "Restore point deleted." or "The restore point changed before it could be deleted.")
        end)
    end)
    page:SetScript("OnShow", RefreshPoint)
end

local function BuildExportPage(page)
    local summary = Label(page, "", 18, -92)
    local status = Label(page, "", 18, -161)
    local private = Label(page, "Player history includes character names, notes, and tags. Keep this export private.", 18, -123)
    private:SetTextColor(1, 0.78, 0.26)
    local edit, scroll = TextBox(page, -197, 160)
    local reveal = PayloadToggle(page, scroll, 163, -54)
    local output = ""
    edit:HookScript("OnTextChanged", function(self, userInput)
        if userInput then self:SetText(output); self:HighlightText() end
    end)
    local prepare, checks
    local function ClearExport()
        output = ""
        edit:ClearFocus()
        edit:SetText("")
        reveal:SetEnabled(false)
        SetPayloadVisible(scroll, reveal, false)
        summary:SetText("")
    end
    local function ChangeSelection()
        local selection = Selected(checks)
        ClearExport()
        private:SetShown(selection.players == true)
        local available = ns.CanTransferBackups()
        prepare:SetEnabled(available == true and next(selection) ~= nil)
        status:SetText(available and "" or "Export is unavailable on this WoW client.")
    end
    checks = SectionChecks(page, -15, ChangeSelection)
    prepare = Button(page, "Prepare to Copy", 135, 18, -54, function()
        local selection = Selected(checks)
        local text, message, snapshot = ns.ExportBackup(selection)
        if not text then
            ClearExport()
            status:SetText(message)
            return
        end
        output = text
        edit:SetText(output)
        reveal:SetEnabled(true)
        summary:SetText(ns.DescribeBackup(snapshot, selection))
        scroll:SetVerticalScroll(0)
        edit:SetFocus()
        edit:HighlightText()
        status:SetText("Backup ready. Press Ctrl+C, then save it outside WoW.")
    end)
    page:SetScript("OnShow", function()
        SetSections(checks, {settings = true, players = true, npcs = true}, false)
        ChangeSelection()
    end)
    page:HookScript("OnHide", ClearExport)
end

local function BuildImportPage(page)
    local status = Label(page, "", 18, -51)
    local summary = Label(page, "", 18, -82)
    local edit, scroll = TextBox(page, -216, 150)
    local reveal = PayloadToggle(page, scroll, 148, -15)
    local paste = Button(page, "Paste Backup", 120, 18, -15, function()
        edit:SetFocus()
        edit:HighlightText()
        status:SetText("Press Ctrl+V to paste a KnownPlayers backup.")
    end)
    local snapshot, merge, replace, checks

    local function RefreshSelection()
        local selection = Selected(checks)
        local description = snapshot and ns.DescribeBackup(snapshot, selection)
        summary:SetText(description and description ~= "" and (BackupDate(snapshot.created) .. "  ·  " .. description) or "")
        local hasHistory = selection.players or selection.npcs
        merge:SetText(hasHistory and "Merge" or "Import Settings")
        merge:SetEnabled(snapshot ~= nil and next(selection) ~= nil)
        replace:SetEnabled(snapshot ~= nil and hasHistory == true)
    end

    checks = SectionChecks(page, -139, RefreshSelection)
    local function ResetImport()
        snapshot = nil
        edit:ClearFocus()
        edit:SetText("")
        SetPayloadVisible(scroll, reveal, false)
        SetSections(checks, nil)
        local available = ns.CanTransferBackups()
        paste:SetEnabled(available == true)
        reveal:SetEnabled(available == true)
        status:SetText(available and "" or "Import is unavailable on this WoW client.")
        RefreshSelection()
    end

    merge = Button(page, "Merge", 130, 18, -177, function()
        if snapshot then ApplyAndReport(snapshot, Selected(checks), "merge", false, status, ResetImport) end
    end)
    replace = Button(page, "Replace Selected", 133, 158, -177, function()
        if snapshot then ApplyAndReport(snapshot, Selected(checks), "replace", false, status, ResetImport) end
    end)
    edit:HookScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local text = self:GetText()
        local message
        snapshot = nil
        if text ~= "" then snapshot, message = ns.ReadBackup(text) end
        SetSections(checks, snapshot and snapshot.sections, true)
        if snapshot and scroll:GetAlpha() == 0 then self:ClearFocus() end
        status:SetText(message or "")
        RefreshSelection()
    end)
    page:SetScript("OnShow", ResetImport)
    page:HookScript("OnHide", ResetImport)
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

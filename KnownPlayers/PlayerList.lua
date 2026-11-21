local addonName, ns = ...

local CATEGORIES = {
    { key = "trade", label = "Trade" },
    { key = "party", label = "Party" },
    { key = "raid", label = "Raid" },
    { key = "guild", label = "Guild" },
    { key = "whisper", label = "Whisper" },
    { key = "target", label = "Target" },
    { key = "inspect", label = "Inspect" },
    { key = "manual", label = "Manually Added" },
}

local function FormatKnownDuration(firstSeen)
    if type(firstSeen) ~= "number" then return "Unknown" end
    local seconds = math.max(0, time() - firstSeen)
    local days = math.floor(seconds / 86400)
    local hours = math.floor(seconds / 3600) % 24
    local minutes = math.floor(seconds / 60) % 60
    if days > 0 then return string.format("%dd %dh", days, hours) end
    if hours > 0 then return string.format("%dh %dm", hours, minutes) end
    return string.format("%dm", minutes)
end

local windows = {}
local RefreshAllWindows

local function AddUndoButton(frame)
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(72, 22)
    button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -21, -35)
    button:SetText("Undo")
    button:SetEnabled(ns.HasRemovalUndo())
    button:SetScript("OnClick", function()
        local _, message = ns.UndoLastRemoval()
        print("|cff33ff99KnownPlayers:|r " .. message)
    end)
    frame.undoButton = button
end

function ns.RefreshRemovalUndoButtons()
    for _, frame in pairs(windows) do
        if frame.undoButton then frame.undoButton:SetEnabled(ns.HasRemovalUndo()) end
    end
end

local popupKey = "KNOWNPLAYERS_CLEAR_CATEGORY_WINDOW"
StaticPopupDialogs[popupKey] = {
    text = "Clear all entries from the %s list?\nOther lists will be kept.",
    button1 = YES,
    button2 = CANCEL,
    OnAccept = function(_, categoryKey)
        if categoryKey then
            ns.ClearRemovalUndo()
            if categoryKey == "npc" then ns.ClearNPCs()
            else ns.ClearPlayerCategory(categoryKey) end
            if RefreshAllWindows then RefreshAllWindows() end
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function CreateCategoryWindow(category, index)
    -- A separate top-level window for each category, independent from Settings.
    local frameName = "KnownPlayers" .. category.label:gsub("%s+", "") .. "ListWindow"
    local frame = CreateFrame("Frame", frameName, UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(570, 440)
    frame:SetPoint("CENTER", UIParent, "CENTER", (index - 4) * 28, (index - 4) * 16)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:Hide()

    -- Handle Escape in this window rather than adding it to UISpecialFrames.
    -- Blizzard can otherwise dismiss both the pop-out and the Settings panel
    -- during one Escape press.
    frame:EnableKeyboard(true)
    frame:SetPropagateKeyboardInput(true)
    frame:SetScript("OnKeyDown", function(self, key)
        -- SetPropagateKeyboardInput is restricted in combat on modern clients.
        if InCombatLockdown and InCombatLockdown() then return end
        local closeWindow = key == "ESCAPE"
        self:SetPropagateKeyboardInput(not closeWindow)
        if closeWindow then self:Hide() end
    end)
    frame:HookScript("OnShow", function(self)
        if not InCombatLockdown or not InCombatLockdown() then
            self:SetPropagateKeyboardInput(true)
        end
    end)

    if frame.TitleText then
        frame.TitleText:SetText("KnownPlayers - " .. category.label)
    else
        local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOP", frame, "TOP", 0, -8)
        title:SetText("KnownPlayers - " .. category.label)
    end

    local count = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    count:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -40)
    AddUndoButton(frame)

    local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    search:SetSize(300, 24)
    search:SetPoint("TOPLEFT", frame, "TOPLEFT", 25, -82)
    search:SetAutoFocus(false)
    search:SetMaxLetters(100)
    search:SetText("")
    search:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        frame:Hide()
    end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local searchHint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    searchHint:SetPoint("LEFT", search, "RIGHT", 12, 0)
    searchHint:SetText("Search names")

    local durationHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    durationHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 273, -141)
    durationHeader:SetText("Known for")

    local clear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clear:SetSize(115, 24)
    clear:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -111)
    clear:SetText("Clear List")
    clear:SetScript("OnClick", function()
        StaticPopup_Show(popupKey, category.label, nil, category.key)
    end)

    local scroller = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroller:SetPoint("TOPLEFT", frame, "TOPLEFT", 21, -161)
    scroller:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -39, 20)

    local content = CreateFrame("Frame", nil, scroller)
    content:SetSize(480, 1)
    scroller:SetScrollChild(content)

    local rows = {}
    local ROW_HEIGHT = 29
    local function GetRow(index)
        if rows[index] then return rows[index] end
        local item = CreateFrame("Frame", nil, content)
        item:SetHeight(ROW_HEIGHT)
        item:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
        item:SetPoint("RIGHT", content, "RIGHT", 0, 0)

        local name = item:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        name:SetPoint("LEFT", item, "LEFT", 4, 0)
        name:SetWidth(240)
        name:SetJustifyH("LEFT")

        local knownSince = item:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        knownSince:SetPoint("LEFT", name, "RIGHT", 8, 0)
        knownSince:SetWidth(62)
        knownSince:SetJustifyH("LEFT")

        local remove = CreateFrame("Button", nil, item, "UIPanelButtonTemplate")
        remove:SetSize(85, 22)
        remove:SetPoint("RIGHT", item, "RIGHT", -4, 0)
        remove:SetText("Remove")

        local history = CreateFrame("Button", nil, item, "UIPanelButtonTemplate")
        history:SetSize(68, 22)
        history:SetPoint("RIGHT", remove, "LEFT", -6, 0)
        history:SetText("History")

        item.nameText = name
        item.knownSinceText = knownSince
        item.historyButton = history
        item.removeButton = remove
        rows[index] = item
        return item
    end

    local empty = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    empty:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -8)

    local function Refresh()
        local all = category.key == "npc" and ns.GetNPCList()
            or ns.GetCategoryPlayers(category.key)
        local term = search:GetText():lower():match("^%s*(.-)%s*$")
        local filtered = {}
        for _, entry in ipairs(all) do
            if term == "" or entry.name:lower():find(term, 1, true)
                or entry.realm:lower():find(term, 1, true) then
                filtered[#filtered + 1] = entry
            end
        end

        count:SetText(#all .. (category.key == "npc" and " NPCs (" or " players (") .. #filtered .. " shown)")
        clear:SetEnabled(#all > 0)
        content:SetHeight(math.max(1, #filtered * ROW_HEIGHT))
        empty:SetShown(#filtered == 0)
        if #filtered == 0 then
            empty:SetText(term ~= "" and "No matching entries." or "No saved entries in this list.")
        end

        for i, entry in ipairs(filtered) do
            local item = GetRow(i)
            item.nameText:SetText(entry.name)
            item.knownSinceText:SetText(FormatKnownDuration(entry.firstSeen))
            item.historyButton:SetScript("OnClick", function() ns.OpenPlayerHistory(entry.key) end)
            item.removeButton:SetScript("OnClick", function()
                if category.key == "npc" then ns.ForgetNPC(entry.key)
                else ns.RemovePlayerCategory(entry.key, category.key, true) end
                if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
                RefreshAllWindows()
            end)
            item:Show()
        end
        for i = #filtered + 1, #rows do rows[i]:Hide() end
        if scroller.SetVerticalScroll then scroller:SetVerticalScroll(0) end
        if scroller.UpdateScrollChildRect then scroller:UpdateScrollChildRect() end
    end

    search:SetScript("OnTextChanged", Refresh)
    frame:SetScript("OnShow", Refresh)
    frame.Refresh = Refresh
    return frame
end

local function LatestInteraction(record)
    local latest
    for _, category in ipairs(CATEGORIES) do
        local stamp = record.categories[category.key] and record.categoryLastSeen
            and record.categoryLastSeen[category.key]
        if type(stamp) == "number" and (not latest or stamp > latest) then latest = stamp end
    end
    return latest or record.lastSeen
end

local function InteractionAge(stamp)
    if type(stamp) ~= "number" then return "Unknown" end
    return FormatKnownDuration(stamp) .. " ago"
end

local function CreatePlayerHistoryWindow()
    local frame = CreateFrame("Frame", "KnownPlayersPlayerHistoryWindow", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(520, 478)
    frame:SetPoint("CENTER")
    -- Keep the editor above the list and its child controls.
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:Hide()
    if frame.TitleText then frame.TitleText:SetText("KnownPlayers - Player History") end

    local name = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", 23, -40)
    name:SetMaxLines(1)
    name:SetJustifyH("LEFT")

    local favorite = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    favorite:SetPoint("LEFT", name, "RIGHT", 10, 0)
    favorite.Text:SetText("Favorite (keep when inactive)")

    local realm = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    realm:SetPoint("TOPLEFT", 23, -63)
    local appearance = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    appearance:SetPoint("TOPLEFT", 23, -82)

    local noteLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    noteLabel:SetPoint("TOPLEFT", 23, -112)
    noteLabel:SetText("Personal note")
    local noteScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelInputScrollFrameTemplate")
    noteScroll:SetPoint("TOPLEFT", 27, -135)
    noteScroll:SetSize(450, 69)
    noteScroll.hideCharCount = true
    local note = noteScroll.EditBox
    note:SetWidth(445)

    local tagsLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    tagsLabel:SetPoint("TOPLEFT", 23, -223)
    tagsLabel:SetText("Tags (comma-separated)")
    local tags = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    tags:SetPoint("TOPLEFT", 27, -243)
    tags:SetSize(450, 25)
    tags:SetAutoFocus(false)
    tags:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local reasonsLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    reasonsLabel:SetPoint("TOPLEFT", 23, -288)
    reasonsLabel:SetText("Why you know this player")
    local reasons = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    reasons:SetPoint("TOPLEFT", 23, -309)
    reasons:SetWidth(468)
    reasons:SetJustifyH("LEFT")

    local save = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    save:SetPoint("BOTTOMRIGHT", -22, 21)
    save:SetSize(82, 24)
    save:SetText("Save")
    local key, record
    save:SetScript("OnClick", function()
        if ns.GetPlayer(key) ~= record
            or not ns.SavePlayerDetails(key, note:GetText(), tags:GetText(), favorite:GetChecked()) then
            print("|cff33ff99KnownPlayers:|r The player record is no longer available. Reopen Player History to edit it.")
        end
        frame:Hide()
    end)
    frame:HookScript("OnHide", function()
        note:ClearFocus()
        tags:ClearFocus()
    end)

    function frame.Open(playerKey, player)
        key, record = playerKey, player
        name:SetText(ns.GetDisplayName(key, record))
        name:SetWidth(math.min(name:GetUnboundedStringWidth(), 275))
        realm:SetText(ns.SafeString(record.realm) or "")
        appearance:SetText("Race: " .. (ns.SafeString(record.race) or "Unknown")
            .. "    Class: " .. (ns.SafeString(record.class) or "Unknown"))
        local history = {}
        for _, category in ipairs(CATEGORIES) do
            if record.categories[category.key] then
                local stamp = record.categoryLastSeen and record.categoryLastSeen[category.key]
                history[#history + 1] = category.label .. " (" .. InteractionAge(stamp) .. ")"
            end
        end
        reasons:SetText(table.concat(history, "\n"))
        noteScroll:SetVerticalScroll(0)
        note:SetText(ns.SafeString(record.note) or "")
        note:SetCursorPosition(0)
        tags:SetText(ns.SafeString(record.tags) or "")
        tags:SetCursorPosition(0)
        favorite:SetChecked(record.favorite == true)
        frame:Show()
        frame:Raise()
    end
    return frame
end

local historyWindow
function ns.OpenPlayerHistory(key, unit)
    local record = ns.GetPlayer(key)
    if not ns.HasPlayerCategory(record) then return end
    ns.RefreshPlayerAppearance(record, unit)
    if not historyWindow then historyWindow = CreatePlayerHistoryWindow() end
    historyWindow.Open(key, record)
end

-- All player interactions are already stored in one hash table:
-- KnownPlayersDB.players[characterKey].categories[reason] = true.
-- This consolidated window is a view of that table, not a second store.
local function CreatePlayersWindow()
    local frame = CreateFrame("Frame", "KnownPlayersAllPlayersWindow", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(790, 635)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:Hide()
    frame:EnableKeyboard(true)
    frame:SetPropagateKeyboardInput(true)
    frame:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown and InCombatLockdown() then return end
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then self:Hide() end
    end)
    frame:HookScript("OnShow", function(self)
        if not InCombatLockdown or not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
    end)
    if frame.TitleText then frame.TitleText:SetText("KnownPlayers - All Players") end

    local count = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    count:SetPoint("TOPLEFT", 23, -43)
    AddUndoButton(frame)
    local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    search:SetSize(300, 24)
    search:SetPoint("TOPLEFT", 26, -79)
    search:SetAutoFocus(false)
    search:SetMaxLetters(100)
    search:SetText("")
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus(); frame:Hide() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("LEFT", search, "RIGHT", 12, 0)
    hint:SetText("Search names, reasons, notes, or tags")

    local filterEnabled = {}
    local Refresh
    for _, category in ipairs(CATEGORIES) do filterEnabled[category.key] = true end
    local filterTitle = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    filterTitle:SetPoint("TOPLEFT", 26, -113)
    filterTitle:SetText("Filter reasons (any selected)")
    local checkboxes = {}
    for index, category in ipairs(CATEGORIES) do
        local column = (index - 1) % 3
        local row = math.floor((index - 1) / 3)
        local check = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
        check:SetPoint("TOPLEFT", frame, "TOPLEFT", 22 + 220 * column, -134 - 29 * row)
        check.Text:SetText(category.label)
        check:SetChecked(true)
        check:SetScript("OnClick", function(self)
            filterEnabled[category.key] = self:GetChecked() and true or false
            if Refresh then Refresh() end
        end)
        checkboxes[#checkboxes + 1] = check
    end
    local function SetAllFilters(checked)
        for index, category in ipairs(CATEGORIES) do
            filterEnabled[category.key] = checked
            checkboxes[index]:SetChecked(checked)
        end
        if Refresh then Refresh() end
    end
    local allFilters = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    allFilters:SetSize(54, 21)
    allFilters:SetPoint("TOPLEFT", frame, "TOPLEFT", 541, -106)
    allFilters:SetText("All")
    allFilters:SetScript("OnClick", function() SetAllFilters(true) end)
    local noFilters = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    noFilters:SetSize(54, 21)
    noFilters:SetPoint("LEFT", allFilters, "RIGHT", 6, 0)
    noFilters:SetText("None")
    noFilters:SetScript("OnClick", function() SetAllFilters(false) end)

    local recent = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    recent:SetPoint("TOPLEFT", 22, -226)
    recent.Text:SetText("Most recent first")
    recent:SetScript("OnClick", function() Refresh() end)
    local favorites = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    favorites:SetPoint("TOPLEFT", 242, -226)
    favorites.Text:SetText("Favorites only")
    favorites:SetScript("OnClick", function() Refresh() end)

    local nameHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    nameHeader:SetPoint("TOPLEFT", 26, -264)
    nameHeader:SetText("Character")
    local reasonHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    reasonHeader:SetPoint("TOPLEFT", 211, -264)
    reasonHeader:SetText("Reasons known")
    local durationHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    durationHeader:SetPoint("TOPLEFT", 441, -264)
    durationHeader:SetText("Known for")
    local recentHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    recentHeader:SetPoint("TOPLEFT", 508, -264)
    recentHeader:SetText("Last interaction")

    local scroller = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroller:SetPoint("TOPLEFT", 21, -285)
    scroller:SetPoint("BOTTOMRIGHT", -37, 20)
    local content = CreateFrame("Frame", nil, scroller)
    content:SetSize(715, 1)
    scroller:SetScrollChild(content)
    local rows = {}
    local ROW_HEIGHT = 31
    local function ReasonsFor(record)
        local result = {}
        for _, category in ipairs(CATEGORIES) do
            if type(record.categories) == "table" and record.categories[category.key] then
                result[#result + 1] = category.label
            end
        end
        return result
    end
    local function FirstSeen(record)
        local first
        if type(record.categoryFirstSeen) == "table" then
            for category, stamp in pairs(record.categoryFirstSeen) do
                if ns.IsPlayerCategory(category) and record.categories[category]
                    and type(stamp) == "number" and (not first or stamp < first) then first = stamp end
            end
        end
        return first or record.lastSeen
    end

    local function GetRow(index)
        if rows[index] then return rows[index] end
        local item = CreateFrame("Frame", nil, content)
        item:SetHeight(ROW_HEIGHT)
        item:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
        item:SetPoint("RIGHT", 0, 0)
        item.name = item:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        item.name:SetPoint("LEFT", 4, 0)
        item.name:SetWidth(175)
        item.name:SetJustifyH("LEFT")
        item.name:SetMaxLines(1)
        item.reasons = item:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        item.reasons:SetPoint("LEFT", 190, 0)
        item.reasons:SetWidth(225)
        item.reasons:SetJustifyH("LEFT")
        item.reasons:SetMaxLines(1)
        item.known = item:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        item.known:SetPoint("LEFT", 420, 0)
        item.known:SetWidth(64)
        item.known:SetJustifyH("LEFT")
        item.recent = item:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        item.recent:SetPoint("LEFT", 487, 0)
        item.recent:SetWidth(72)
        item.recent:SetJustifyH("LEFT")
        item.remove = CreateFrame("Button", nil, item, "UIPanelButtonTemplate")
        item.remove:SetSize(76, 23)
        item.remove:SetPoint("RIGHT", -3, 0)
        item.remove:SetText("Remove")
        item.details = CreateFrame("Button", nil, item, "UIPanelButtonTemplate")
        item.details:SetSize(68, 23)
        item.details:SetPoint("RIGHT", item.remove, "LEFT", -6, 0)
        item.details:SetText("History")
        rows[index] = item
        return item
    end
    local empty = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    empty:SetPoint("TOPLEFT", 6, -8)
    Refresh = function()
        local all = {}
        for key, record in pairs(KnownPlayersDB.players or {}) do
            if ns.HasPlayerCategory(record) then
                local reasons = ReasonsFor(record)
                all[#all + 1] = {
                    key = key, name = ns.GetDisplayName(key, record),
                    realm = record.realm or "", reasons = table.concat(reasons, ", "),
                    firstSeen = FirstSeen(record), lastSeen = LatestInteraction(record),
                    favorite = record.favorite == true,
                }
            end
        end
        local sortRecent = recent:GetChecked()
        table.sort(all, function(a,b)
            if a.favorite ~= b.favorite then return a.favorite end
            if sortRecent then
                local aSeen, bSeen = tonumber(a.lastSeen) or 0, tonumber(b.lastSeen) or 0
                if aSeen ~= bSeen then return aSeen > bSeen end
            end
            if a.name:lower() ~= b.name:lower() then return a.name:lower() < b.name:lower() end
            return a.key < b.key
        end)
        local term = search:GetText():lower():match("^%s*(.-)%s*$")
        local nameTerm = term:gsub("%-", " ")
        local filtered = {}
        for _, entry in ipairs(all) do
            local record = KnownPlayersDB.players[entry.key]
            local eligible = false
            for _, category in ipairs(CATEGORIES) do
                if filterEnabled[category.key] and record.categories[category.key] then
                    eligible = true
                    break
                end
            end
            if eligible and (not favorites:GetChecked() or entry.favorite)
                and (term == "" or entry.name:lower():find(nameTerm, 1, true)
                or entry.realm:lower():find(term, 1, true)
                or entry.reasons:lower():find(term, 1, true)
                or (ns.SafeString(record.note) or ""):lower():find(term, 1, true)
                or (ns.SafeString(record.tags) or ""):lower():find(term, 1, true)) then
                filtered[#filtered + 1] = entry
            end
        end
        count:SetText(#all .. " players (" .. #filtered .. " shown)")
        content:SetHeight(math.max(1, #filtered * ROW_HEIGHT))
        empty:SetShown(#filtered == 0)
        if #filtered == 0 then empty:SetText("No players match the current filters.") end
        for index, entry in ipairs(filtered) do
            local item = GetRow(index)
            item.name:SetText((entry.favorite and "|cffffd100*|r " or "") .. entry.name)
            item.reasons:SetText(entry.reasons)
            item.known:SetText(FormatKnownDuration(entry.firstSeen))
            item.recent:SetText(InteractionAge(entry.lastSeen))
            item.details:SetScript("OnClick", function() ns.OpenPlayerHistory(entry.key) end)
            item.remove:SetScript("OnClick", function()
                if ns.ForgetPlayer(entry.key, true) then
                    if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
                    if RefreshAllWindows then RefreshAllWindows() end
                end
            end)
            item:Show()
        end
        for i = #filtered + 1, #rows do rows[i]:Hide() end
        if scroller.SetVerticalScroll then scroller:SetVerticalScroll(0) end
        if scroller.UpdateScrollChildRect then scroller:UpdateScrollChildRect() end
    end
    search:SetScript("OnTextChanged", Refresh)
    frame:SetScript("OnShow", Refresh)
    frame.Refresh = Refresh
    return frame
end

local function CreateAssociatedWindow()
    local frame = CreateFrame("Frame", "KnownPlayersAssociatedListWindow", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(570, 490)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:Hide()
    frame:EnableKeyboard(true)
    frame:SetPropagateKeyboardInput(true)
    frame:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown and InCombatLockdown() then return end
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then self:Hide() end
    end)
    frame:HookScript("OnShow", function(self)
        if not InCombatLockdown or not InCombatLockdown() then
            self:SetPropagateKeyboardInput(true)
        end
    end)
    if frame.TitleText then frame.TitleText:SetText("KnownPlayers - Known Battle.net Alts") end

    local description = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", 23, -42)
    description:SetText("Battle.net friends' other characters, recognized through a known character.")
    local count = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    count:SetPoint("TOPLEFT", 23, -66)

    local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    search:SetSize(300, 24)
    search:SetPoint("TOPLEFT", 26, -94)
    search:SetAutoFocus(false)
    search:SetMaxLetters(100)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus(); frame:Hide() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local searchLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    searchLabel:SetPoint("LEFT", search, "RIGHT", 12, 0)
    searchLabel:SetText("Search names")

    local header = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    header:SetPoint("TOPLEFT", 27, -140)
    header:SetText("Character")
    local linkHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    linkHeader:SetPoint("TOPLEFT", 229, -140)
    linkHeader:SetText("Recognized through")

    local scroller = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroller:SetPoint("TOPLEFT", 21, -160)
    scroller:SetPoint("BOTTOMRIGHT", -39, 20)
    local content = CreateFrame("Frame", nil, scroller)
    content:SetSize(480, 1)
    scroller:SetScrollChild(content)
    local rows = {}
    local function Refresh()
        local all = ns.GetAssociatedCharacters()
        local term = search:GetText():lower():match("^%s*(.-)%s*$")
        local filtered = {}
        for _, entry in ipairs(all) do
            if term == "" or entry.name:lower():find(term, 1, true)
                or (entry.realm or ""):lower():find(term, 1, true)
                or (entry.linkedTo or ""):lower():find(term, 1, true) then
                filtered[#filtered + 1] = entry
            end
        end
        count:SetText(#all .. " associated characters (" .. #filtered .. " shown)")
        content:SetHeight(math.max(1, #filtered * 28))
        for i, entry in ipairs(filtered) do
            if not rows[i] then
                local row = CreateFrame("Frame", nil, content)
                row:SetHeight(28)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * 28)
                row:SetPoint("RIGHT", 0, 0)
                row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                row.name:SetPoint("LEFT", 5, 0)
                row.name:SetWidth(195)
                row.name:SetJustifyH("LEFT")
                row.source = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                row.source:SetPoint("LEFT", 208, 0)
                row.source:SetWidth(154)
                row.source:SetJustifyH("LEFT")
                row.historyButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                row.historyButton:SetSize(105, 22)
                row.historyButton:SetPoint("RIGHT", -4, 0)
                row.historyButton:SetText("Linked History")
                rows[i] = row
            end
            local row = rows[i]
            row.name:SetText(entry.name)
            row.source:SetText(entry.linkedTo or "Known player")
            row.historyButton:SetScript("OnClick", function()
                ns.OpenPlayerHistory(entry.linkedPlayerKey)
            end)
            row:Show()
        end
        for i = #filtered + 1, #rows do rows[i]:Hide() end
        if scroller.SetVerticalScroll then scroller:SetVerticalScroll(0) end
        if scroller.UpdateScrollChildRect then scroller:UpdateScrollChildRect() end
    end
    search:SetScript("OnTextChanged", Refresh)
    frame:SetScript("OnShow", function()
        ns.ScanBattleNetFriends()
        Refresh()
    end)
    frame.Refresh = Refresh
    return frame
end

-- NPC management is deliberately a saved-exceptions list, not a QuestieDB
-- browser. NPC identities are read only for remembered or overridden entries.
local function CreateNPCManagementWindow()
    local frame = CreateFrame("Frame", "KnownPlayersNPCManagerWindow", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(790, 595)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:Hide()
    frame:EnableKeyboard(true)
    frame:SetPropagateKeyboardInput(true)
    frame:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown and InCombatLockdown() then return end
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then self:Hide() end
    end)
    frame:HookScript("OnShow", function(self)
        if not InCombatLockdown or not InCombatLockdown() then
            self:SetPropagateKeyboardInput(true)
        end
    end)
    if frame.TitleText then frame.TitleText:SetText("KnownPlayers - NPC Manager") end
    local count = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    count:SetPoint("TOPLEFT", 22, -43)
    AddUndoButton(frame)
    local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 22, -63)
    hint:SetText("Saved NPCs only. Click a Visibility button to cycle Automatic / Show / Hide.")

    local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    search:SetSize(300, 23)
    search:SetPoint("TOPLEFT", 25, -91)
    search:SetAutoFocus(false)
    search:SetMaxLetters(100)
    search:SetText("")
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus(); frame:Hide() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local searchHint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    searchHint:SetPoint("LEFT", search, "RIGHT", 10, 0)
    searchHint:SetText("Search name or NPC ID")

    local categories = ns.GetNPCServiceCategories()
    local filterEnabled, checkboxes = {}, {}
    for _, category in ipairs(categories) do filterEnabled[category.key] = true end
    filterEnabled.override = true
    local Refresh
    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 23, -127)
    title:SetText("Show saved entries with any selected category")
    for index, category in ipairs(categories) do
        local col, row = (index - 1) % 4, math.floor((index - 1) / 4)
        local check = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
        check:SetPoint("TOPLEFT", frame, "TOPLEFT", 20 + 172 * col, -147 - row * 28)
        check.Text:SetText(category.label)
        check:SetChecked(true)
        check:SetScript("OnClick", function(self)
            filterEnabled[category.key] = self:GetChecked() and true or false
            if Refresh then Refresh() end
        end)
        checkboxes[category.key] = check
    end
    local overrideCheck = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    overrideCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 20 + 172, -147 - 2 * 28)
    overrideCheck.Text:SetText("Overrides")
    overrideCheck:SetChecked(true)
    overrideCheck:SetScript("OnClick", function(self)
        filterEnabled.override = self:GetChecked() and true or false
        if Refresh then Refresh() end
    end)
    checkboxes.override = overrideCheck
    local favorites = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    favorites:SetPoint("TOPLEFT", frame, "TOPLEFT", 364, -203)
    favorites.Text:SetText("Favorites only")
    favorites:SetScript("OnClick", function() Refresh() end)

    local allFilters = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    allFilters:SetSize(85, 22)
    allFilters:SetPoint("TOPLEFT", frame, "TOPLEFT", 400, -92)
    allFilters:SetText("Select All")
    allFilters:SetScript("OnClick", function()
        for key, checkbox in pairs(checkboxes) do
            filterEnabled[key] = true
            checkbox:SetChecked(true)
        end
        Refresh()
    end)
    local clear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clear:SetSize(155, 22)
    clear:SetPoint("TOPLEFT", frame, "TOPLEFT", 511, -92)
    clear:SetText("Clear Saved NPCs")
    local clearPopup = "KNOWNPLAYERS_CLEAR_NPC_MANAGEMENT"
    if not StaticPopupDialogs[clearPopup] then
        StaticPopupDialogs[clearPopup] = {
            text = "Clear ALL manually remembered NPCs and NPC visibility overrides? This cannot be undone.",
            button1 = YES, button2 = CANCEL,
            OnAccept = function()
                ns.ClearNPCManagement()
                if RefreshAllWindows then RefreshAllWindows() end
            end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
    end
    clear:SetScript("OnClick", function() StaticPopup_Show(clearPopup) end)

    for _, column in ipairs({
        {26, "NPC name / ID"}, {211, "Categories / source"}, {407, "Visibility"},
        {530, "Saved"}, {645, "Favorite"},
    }) do
        local heading = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        heading:SetPoint("TOPLEFT", frame, "TOPLEFT", column[1], -252)
        heading:SetText(column[2])
    end
    local scroller = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroller:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -270)
    scroller:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -40, 19)
    local content = CreateFrame("Frame", nil, scroller)
    content:SetSize(713, 1)
    scroller:SetScrollChild(content)
    local rows = {}
    local HEIGHT = 36
    local function Row(index)
        if rows[index] then return rows[index] end
        local item = CreateFrame("Frame", nil, content)
        item:SetHeight(HEIGHT)
        item:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * HEIGHT)
        item:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        local name = item:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        name:SetPoint("LEFT", item, "LEFT", 4, 0)
        name:SetWidth(181)
        name:SetJustifyH("LEFT")
        local categoriesLabel = item:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        categoriesLabel:SetPoint("LEFT", item, "LEFT", 189, 0)
        categoriesLabel:SetWidth(186)
        categoriesLabel:SetJustifyH("LEFT")
        local mode = CreateFrame("Button", nil, item, "UIPanelButtonTemplate")
        mode:SetSize(115, 24)
        mode:SetPoint("LEFT", item, "LEFT", 385, 0)
        local manual = CreateFrame("Button", nil, item, "UIPanelButtonTemplate")
        manual:SetSize(105, 24)
        manual:SetPoint("LEFT", item, "LEFT", 508, 0)
        local pin = CreateFrame("Button", nil, item, "UIPanelButtonTemplate")
        pin:SetSize(67, 24)
        pin:SetPoint("LEFT", item, "LEFT", 623, 0)
        item.nameText, item.categoryText = name, categoriesLabel
        item.modeButton, item.manualButton, item.pinButton = mode, manual, pin
        rows[index] = item
        return item
    end
    local empty = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    empty:SetPoint("TOPLEFT", content, "TOPLEFT", 7, -10)
    Refresh = function()
        local all, filtered = ns.GetNPCList(), {}
        local term = search:GetText():lower():match("^%s*(.-)%s*$")
        for _, entry in ipairs(all) do
            local matchesSearch = term == "" or entry.name:lower():find(term, 1, true)
                or entry.key:find(term, 1, true)
            local matchesCategory = (entry.manual and filterEnabled.manual)
                or (entry.override ~= "auto" and filterEnabled.override)
            for _, category in ipairs(categories) do
                if entry.services and entry.services[category.key] and filterEnabled[category.key] then
                    matchesCategory = true
                end
            end
            if matchesSearch and matchesCategory and (not favorites:GetChecked() or entry.favorite) then
                filtered[#filtered + 1] = entry
            end
        end
        count:SetText(#all .. " saved NPCs (" .. #filtered .. " shown)")
        clear:SetEnabled(#all > 0)
        content:SetHeight(math.max(1, #filtered * HEIGHT))
        empty:SetShown(#filtered == 0)
        if #filtered == 0 then
            empty:SetText(term ~= "" and "No matching saved NPCs." or "No saved NPCs match these filters.")
        end
        local roleLabels = {}
        for _, category in ipairs(categories) do roleLabels[category.key] = category.label end
        for i, entry in ipairs(filtered) do
            local row = Row(i)
            row.nameText:SetText((entry.favorite and "|cffffd100*|r " or "") .. entry.name .. " (" .. entry.key .. ")")
            local roleNames = {}
            if entry.manual then roleNames[#roleNames + 1] = "Remembered" end
            if entry.services then
                for _, category in ipairs(categories) do
                    if category.key ~= "manual" and entry.services[category.key] then
                        roleNames[#roleNames + 1] = roleLabels[category.key]
                    end
                end
            end
            if #roleNames == 0 then roleNames[1] = "Override" end
            row.categoryText:SetText(table.concat(roleNames, ", "))
            local display = {auto = "Automatic", show = "Always Show", hide = "Always Hide"}
            row.modeButton:SetText(display[entry.override] or "Automatic")
            row.modeButton:SetScript("OnClick", function()
                local nextMode = ({auto="show",show="hide",hide="auto"})[entry.override]
                ns.SetNPCVisibilityOverride(entry.key, entry.name, nextMode)
                Refresh()
            end)
            row.manualButton:SetText(entry.manual and "Forget" or "Remember")
            row.manualButton:SetScript("OnClick", function()
                if entry.manual then ns.ForgetNPC(entry.key)
                else ns.RememberNPC(entry.key, entry.name) end
                Refresh()
            end)
            row.pinButton:SetText(entry.favorite and "Unpin" or "Pin")
            row.pinButton:SetScript("OnClick", function()
                ns.ToggleNPCFavorite(entry.key, entry.name)
            end)
            row:Show()
        end
        for i = #filtered + 1, #rows do rows[i]:Hide() end
        if scroller.SetVerticalScroll then scroller:SetVerticalScroll(0) end
        if scroller.UpdateScrollChildRect then scroller:UpdateScrollChildRect() end
    end
    search:SetScript("OnTextChanged", Refresh)
    frame:SetScript("OnShow", Refresh)
    frame.Refresh = Refresh
    return frame
end

RefreshAllWindows = function()
    for _, frame in pairs(windows) do
        if frame:IsShown() then frame.Refresh() end
    end
end

function ns.RefreshPlayerListWindows()
    RefreshAllWindows()
end

local function OpenCategoryWindow(category, index)
    local window = windows[category.key]
    if not window then
        window = CreateCategoryWindow(category, index)
        windows[category.key] = window
    end
    window:Show()
    window:Raise()
    window.Refresh()
end

-- Settings controls open these dialogs; the dialogs contain list tools only.
function ns.OpenPlayerList(categoryKey)
    if categoryKey == "guild" and ns.RefreshGuildList then
        ns.RefreshGuildList()
    end
    if categoryKey == "players" then
        if not windows.players then windows.players = CreatePlayersWindow() end
        windows.players:Show()
        windows.players:Raise()
        windows.players.Refresh()
        return
    end
    if categoryKey == "associated" then
        if not windows.associated then windows.associated = CreateAssociatedWindow() end
        windows.associated:Show()
        windows.associated:Raise()
        windows.associated.Refresh()
        return
    end
    if categoryKey == "npc" then
        if not windows.npc then windows.npc = CreateNPCManagementWindow() end
        windows.npc:Show()
        windows.npc:Raise()
        windows.npc.Refresh()
        return
    end
    for index, category in ipairs(CATEGORIES) do
        if category.key == categoryKey then
            OpenCategoryWindow(category, index)
            return
        end
    end
end

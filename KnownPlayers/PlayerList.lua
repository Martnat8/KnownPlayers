local addonName, ns = ...

local CATEGORIES = {
    { key = "trade", label = "Trade" },
    { key = "party", label = "Party" },
    { key = "raid", label = "Raid" },
    { key = "guild", label = "Guild" },
    { key = "whisper", label = "Whisper" },
    { key = "target", label = "Target" },
    { key = "inspect", label = "Inspect" },
    { key = "pvp", label = "PvP Attackers" },
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

local popupKey = "KNOWNPLAYERS_CLEAR_CATEGORY_WINDOW"
StaticPopupDialogs[popupKey] = {
    text = "Clear all entries from the %s list?\nOther lists will be kept.",
    button1 = YES,
    button2 = CANCEL,
    OnAccept = function(_, categoryKey)
        if categoryKey then
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
    local frame = CreateFrame("Frame", "KnownPlayers" .. category.label .. "ListWindow", UIParent, "BasicFrameTemplateWithInset")
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
        knownSince:SetWidth(113)
        knownSince:SetJustifyH("LEFT")

        local remove = CreateFrame("Button", nil, item, "UIPanelButtonTemplate")
        remove:SetSize(85, 22)
        remove:SetPoint("RIGHT", item, "RIGHT", -4, 0)
        remove:SetText("Remove")

        item.nameText = name
        item.knownSinceText = knownSince
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
            item.removeButton:SetScript("OnClick", function()
                if category.key == "npc" then ns.ForgetNPC(entry.key)
                else ns.RemovePlayerCategory(entry.key, category.key) end
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
    linkHeader:SetPoint("TOPLEFT", 265, -140)
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
                row.name:SetWidth(230)
                row.name:SetJustifyH("LEFT")
                row.source = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                row.source:SetPoint("LEFT", 244, 0)
                row.source:SetWidth(220)
                row.source:SetJustifyH("LEFT")
                rows[i] = row
            end
            rows[i].name:SetText(entry.name)
            rows[i].source:SetText(entry.linkedTo or "Known player")
            rows[i]:Show()
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
    if categoryKey == "associated" then
        if not windows.associated then windows.associated = CreateAssociatedWindow() end
        windows.associated:Show()
        windows.associated:Raise()
        windows.associated.Refresh()
        return
    end
    if categoryKey == "npc" then
        OpenCategoryWindow({key="npc", label="NPCs"}, #CATEGORIES + 1)
        return
    end
    for index, category in ipairs(CATEGORIES) do
        if category.key == categoryKey then
            OpenCategoryWindow(category, index)
            return
        end
    end
end

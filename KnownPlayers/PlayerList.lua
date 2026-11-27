local addonName, ns = ...

local CATEGORIES = ns.PlayerCategories

local function NormalizeSearchName(name)
    return (name:lower():gsub("%-", " "):gsub("%s+", " "))
end

local function PlayerSearchTerms(search)
    local term = search:GetText():lower():match("^%s*(.-)%s*$")
    return term, NormalizeSearchName(term)
end

local function MatchesPlayerSearch(entry, term, nameTerm)
    return term == "" or NormalizeSearchName(entry.name):find(nameTerm, 1, true)
        or (entry.realm or ""):lower():find(term, 1, true)
end

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

local classTokens
local function GetRowClass(appearance)
    if not classTokens then
        classTokens = {}
        for _, names in ipairs({LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {}}) do
            for token, name in pairs(names) do classTokens[name:lower()] = token:lower() end
        end
    end
    local name = ns.SafeString(appearance.class)
    local token = ns.SafeString(appearance.classToken)
    token = (token and token:lower()) or (name and classTokens[name:lower()])
    local key = token or (name and name:lower()) or ""
    local localized = token and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token:upper()]
    return key, localized or name or token, token and ("classicon-" .. token)
end

local CLASS_COLUMN_WIDTH = 112

local function AddClassFilter(frame, x, y, refresh)
    local selected, labels, options = "all", {}, {}
    local dropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    frame.classFilter = dropdown
    dropdown:SetSize(CLASS_COLUMN_WIDTH, 22)
    dropdown:SetPoint("TOPLEFT", x, y)
    dropdown:SetSelectionText(function()
        if selected == "all" then return "All classes" end
        return labels[selected] or "Unknown class"
    end)
    local function IsSelected(key) return selected == key end
    local function Select(key)
        selected = key
        refresh()
    end
    dropdown:SetupMenu(function(_, menu)
        menu:CreateRadio("All classes", IsSelected, Select, "all")
        for _, key in ipairs(options) do menu:CreateRadio(labels[key], IsSelected, Select, key) end
        menu:CreateRadio("Unknown class", IsSelected, Select, "")
    end)

    return function(entries)
        local changed = false
        for _, entry in ipairs(entries) do
            local key, label, atlas = GetRowClass(entry.appearance)
            entry.classKey, entry.classLabel, entry.classAtlas = key, label, atlas
            if key ~= "" and not labels[key] then
                labels[key] = label
                options[#options + 1] = key
                changed = true
            end
        end
        if changed then
            table.sort(options, function(a, b)
                local aLabel, bLabel = labels[a]:lower(), labels[b]:lower()
                if aLabel ~= bLabel then return aLabel < bLabel end
                return a < b
            end)
            dropdown:GenerateMenu()
        end
        return selected
    end
end

local atlasAvailable = {}
local function HasAtlas(atlas)
    if not atlas or not C_Texture or not C_Texture.GetAtlasInfo then return false end
    if atlasAvailable[atlas] == nil then atlasAvailable[atlas] = type(C_Texture.GetAtlasInfo(atlas)) == "table" end
    return atlasAvailable[atlas]
end

local function GetRaceAtlas(appearance)
    local atlas = ns.SafeString(appearance.raceAtlas)
    if atlas and not HasAtlas(atlas) then atlas = atlas:gsub("^raceicon128%-", "raceicon-") end
    return HasAtlas(atlas) and atlas or nil
end

local function ShowIconTooltip(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, self.tooltipAnchor or "ANCHOR_RIGHT")
    GameTooltip:SetText(self.tooltip)
    GameTooltip:Show()
end

local function HideIconTooltip(self)
    if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

local function AddHistoryTooltip(button)
    button.tooltipAnchor = "ANCHOR_LEFT"
    button:SetScript("OnEnter", ShowIconTooltip)
    button:SetScript("OnLeave", HideIconTooltip)
    button:SetScript("OnHide", HideIconTooltip)
end

local function PlayerIdentityText(entry)
    local realm = ns.SafeString(entry.realm)
    return realm and (entry.name .. "\n" .. realm) or entry.name
end

local function UpdateHistoryTooltip(button, text)
    button.tooltip = text
    if GameTooltip and GameTooltip:IsOwned(button) then ShowIconTooltip(button) end
end

local function AddAppearanceIcons(row, x)
    local function CreateIcon()
        local icon = CreateFrame("Frame", nil, row)
        icon:SetSize(18, 18)
        icon:EnableMouse(true)
        icon.texture = icon:CreateTexture(nil, "ARTWORK")
        icon.texture:SetAllPoints()
        icon:SetScript("OnEnter", ShowIconTooltip)
        icon:SetScript("OnLeave", HideIconTooltip)
        icon:SetScript("OnHide", HideIconTooltip)
        return icon
    end
    row.appearanceCenter = x + CLASS_COLUMN_WIDTH / 2
    row.classIcon = CreateIcon()
    row.raceIcon = CreateIcon()
end

local function ShowAppearanceIcons(row, entry)
    local classAtlas = HasAtlas(entry.classAtlas) and entry.classAtlas or nil
    local raceAtlas = GetRaceAtlas(entry.appearance)
    local function SetIcon(icon, atlas, label, offset)
        icon.tooltip = label
        if atlas then
            icon:ClearAllPoints()
            icon:SetPoint("CENTER", row, "LEFT", row.appearanceCenter + offset, 0)
            icon.texture:SetAtlas(atlas)
        end
        icon:SetShown(atlas ~= nil)
    end
    SetIcon(row.classIcon, classAtlas, ns.SafeString(entry.appearance.class) or entry.classLabel or "Class",
        raceAtlas and -12 or 0)
    SetIcon(row.raceIcon, raceAtlas, ns.SafeString(entry.appearance.race) or "Race", classAtlas and 12 or 0)
end

local function AppearanceText(label, atlas)
    if HasAtlas(atlas) then return CreateAtlasMarkup(atlas, 16, 16) .. " " .. label end
    return label
end

local function AddSortHeaders(frame, y, knownX, refresh, recent, nameX)
    local field, reversed = "name", false

    local function AddHeader(label, key, x, width)
        local button = CreateFrame("Button", nil, frame)
        button:SetSize(width, 20)
        button:SetPoint("TOPLEFT", x, y)
        local text = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        text:SetPoint("LEFT")
        button:SetFontString(text)
        button:SetNormalFontObject(GameFontHighlightSmall)
        button:SetHighlightFontObject(GameFontNormalSmall)
        button:SetText(label)

        local arrow = button:CreateTexture(nil, "ARTWORK")
        arrow:SetSize(9, 8)
        arrow:SetPoint("LEFT", text, "RIGHT", 3, 0)
        arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")

        button:SetScript("OnClick", function()
            local wasRecent = recent and recent:GetChecked()
            reversed = not wasRecent and field == key and not reversed
            field = key
            if wasRecent then recent:SetChecked(false) end
            refresh()
        end)
        return arrow
    end

    local nameArrow = AddHeader("Name", "name", nameX or 26, 62)
    local knownArrow = AddHeader("Known for", "known", knownX, 65)
    return function(entries, favoritesFirst)
        local mode = recent and recent:GetChecked() and "recent" or field
        nameArrow:SetShown(mode == "name")
        knownArrow:SetShown(mode == "known")
        nameArrow:SetTexCoord(0, 0.5625, reversed and 1 or 0, reversed and 0 or 1)
        knownArrow:SetTexCoord(0, 0.5625, reversed and 0 or 1, reversed and 1 or 0)

        table.sort(entries, function(a, b)
            if favoritesFirst and a.favorite ~= b.favorite then return a.favorite end
            if mode ~= "name" then
                local aTime, bTime
                if mode == "recent" then
                    aTime, bTime = tonumber(a.lastSeen), tonumber(b.lastSeen)
                else
                    aTime, bTime = a.firstSeen, b.firstSeen
                end
                if type(aTime) ~= "number" then aTime = nil end
                if type(bTime) ~= "number" then bTime = nil end
                if aTime ~= bTime then
                    if aTime == nil then return false end
                    if bTime == nil then return true end
                    if mode == "known" and not reversed then return aTime < bTime end
                    return aTime > bTime
                end
            end
            local aName, bName = a.name:lower(), b.name:lower()
            if aName ~= bName then
                if mode == "name" and reversed then return aName > bName end
                return aName < bName
            end
            return a.key < b.key
        end)
    end
end

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

local function CreateIconButton(parent)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(22, 22)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(18, 18)
    button.icon:SetPoint("CENTER")
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(button.icon)
    highlight:SetColorTexture(1, 1, 1, 0.15)
    button:SetScript("OnEnter", ShowIconTooltip)
    button:SetScript("OnLeave", HideIconTooltip)
    button:SetScript("OnHide", HideIconTooltip)
    return button
end

local function ShowFavoriteState(button, favorite)
    button.icon:SetAtlas(favorite and "auctionhouse-icon-favorite" or "auctionhouse-icon-favorite-off")
    button.tooltip = favorite and "Remove favorite\nInactivity limits and Clear List apply again"
        or "Add favorite\nKeep this player through inactivity and list clearing"
    if GameTooltip and GameTooltip:IsOwned(button) then ShowIconTooltip(button) end
end

local function AddPlayerRowActions(row, removeTooltip, gap)
    row.favoriteButton = CreateIconButton(row)
    row.favoriteButton:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.avoidButton = CreateIconButton(row)
    row.avoidButton:SetPoint("LEFT", row.favoriteButton, "RIGHT", gap or 1, 0)
    row.avoidButton.icon:SetTexture("Interface\\Icons\\INV_Misc_Bone_HumanSkull_01")
    row.removeButton = CreateIconButton(row)
    row.removeButton:SetPoint("LEFT", row.avoidButton, "RIGHT", gap or 1, 0)
    row.removeButton.icon:SetTexture("Interface\\AddOns\\" .. addonName .. "\\Textures\\Trash")
    row.removeButton.tooltip = removeTooltip
end

local function UpdateAvoidButton(button, entry)
    local avoided = ns.PlayerHasCategory(entry.appearance, "avoid")
    button.icon:SetDesaturated(not avoided)
    button.icon:SetAlpha(avoided and 1 or 0.65)
    button.tooltip = (avoided and "Remove from " or "Add to ") .. ns.GetPlayerCategoryLabel("avoid")
    if GameTooltip and GameTooltip:IsOwned(button) then ShowIconTooltip(button) end
    button:SetScript("OnClick", function()
        ns.SetPlayerAvoided(entry.key, entry.appearance, not avoided)
    end)
end

local function UpdateFavoriteButton(button, entry)
    ShowFavoriteState(button, entry.appearance.favorite == true)
    button:SetScript("OnClick", function()
        ns.SetPlayerFavorite(entry.key, entry.appearance, not entry.appearance.favorite)
    end)
end

function ns.RefreshRemovalUndoButtons()
    for _, frame in pairs(windows) do
        if frame.undoButton then frame.undoButton:SetEnabled(ns.HasRemovalUndo()) end
    end
end

local popupKey = "KNOWNPLAYERS_CLEAR_CATEGORY_WINDOW"
StaticPopupDialogs[popupKey] = {
    text = "Clear the %s list? Favorited players will stay on this list.\n\nA restore point will be saved in Backup & Restore.",
    button1 = YES,
    button2 = CANCEL,
    OnAccept = function(_, categoryKey)
        if ns.IsPlayerCategory(categoryKey) then
            local keep, hasRemovable = {}, false
            for _, entry in ipairs(ns.GetCategoryPlayers(categoryKey)) do
                if entry.appearance.favorite == true then
                    keep[entry.key] = true
                else
                    hasRemovable = true
                end
            end
            if not hasRemovable or not ns.BackupBeforeChange("Before clearing a list", {players = true}) then return end
            ns.ClearRemovalUndo()
            ns.ClearPlayerCategory(categoryKey, keep)
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
    frame:SetSize(632, 440)
    frame:SetPoint("CENTER", UIParent, "CENTER", (index - 4) * 28, (index - 4) * 16)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:Hide()

    ns.EnableWindowEscape(frame)

    local title = frame.TitleText
    if not title then
        title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOP", frame, "TOP", 0, -8)
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
    search:SetScript("OnEscapePressed", ns.EscapeFromEditBox)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local searchHint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    searchHint:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -4)
    searchHint:SetText("Search names or realms")

    local Refresh
    local Sort = AddSortHeaders(frame, -137, 411, function() Refresh() end, nil, 97)
    local ReadClassFilter = AddClassFilter(frame, 343, -83, function() Refresh() end)
    local appearanceHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    appearanceHeader:SetPoint("CENTER", frame, "TOPLEFT", 341, -147)
    appearanceHeader:SetText("Class / race")

    local clear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clear:SetSize(115, 24)
    clear:SetPoint("RIGHT", frame.undoButton, "LEFT", -10, 0)
    clear:SetText("Clear List")
    clear:SetScript("OnClick", function()
        StaticPopup_Show(popupKey, ns.GetPlayerCategoryLabel(category.key), nil, category.key)
    end)

    local scroller = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroller:SetPoint("TOPLEFT", frame, "TOPLEFT", 21, -161)
    scroller:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -39, 20)

    local content = CreateFrame("Frame", nil, scroller)
    content:SetSize(542, 1)
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
        name:SetPoint("LEFT", item, "LEFT", 76, 0)
        name:SetWidth(179)
        name:SetJustifyH("LEFT")
        name:SetMaxLines(1)
        AddAppearanceIcons(item, 264)

        local knownSince = item:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        knownSince:SetPoint("LEFT", item, "LEFT", 390, 0)
        knownSince:SetWidth(62)
        knownSince:SetJustifyH("LEFT")

        local history = CreateFrame("Button", nil, item, "UIPanelButtonTemplate")
        history:SetSize(68, 22)
        history:SetPoint("RIGHT", item, "RIGHT", -4, 0)
        history:SetText("History")
        AddHistoryTooltip(history)

        item.nameText = name
        item.knownSinceText = knownSince
        item.historyButton = history
        AddPlayerRowActions(item)
        rows[index] = item
        return item
    end

    local empty = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    empty:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -8)

    Refresh = function(keepScroll)
        local label = ns.GetPlayerCategoryLabel(category.key)
        title:SetText("KnownPlayers - " .. label)
        local all = ns.GetCategoryPlayers(category.key)
        local classFilter = ReadClassFilter(all)
        local term, nameTerm = PlayerSearchTerms(search)
        local filtered = {}
        for _, entry in ipairs(all) do
            if (classFilter == "all" or entry.classKey == classFilter)
                and MatchesPlayerSearch(entry, term, nameTerm) then
                filtered[#filtered + 1] = entry
            end
        end

        Sort(filtered)
        count:SetText(#all .. " players (" .. #filtered .. " shown)")
        clear:SetEnabled(#all > 0)
        content:SetHeight(math.max(1, #filtered) * ROW_HEIGHT)
        empty:SetShown(#filtered == 0)
        if #filtered == 0 then
            empty:SetText(#all > 0 and "No matching entries." or "No saved entries in this list.")
        end

        for i, entry in ipairs(filtered) do
            local item = GetRow(i)
            item.nameText:SetText(entry.name)
            ShowAppearanceIcons(item, entry)
            item.knownSinceText:SetText(FormatKnownDuration(entry.firstSeen))
            UpdateFavoriteButton(item.favoriteButton, entry)
            UpdateAvoidButton(item.avoidButton, entry)
            item.removeButton.tooltip = "Remove from the " .. label .. " list"
            UpdateHistoryTooltip(item.historyButton, PlayerIdentityText(entry))
            item.historyButton:SetScript("OnClick", function() ns.OpenPlayerHistory(entry.key, nil, frame.settingsPage) end)
            item.removeButton:SetScript("OnClick", function()
                if ns.GetPlayer(entry.key) ~= entry.appearance
                    or not ns.RemovePlayerCategory(entry.key, category.key, true) then return end
                if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
                RefreshAllWindows()
            end)
            item:Show()
        end
        for i = #filtered + 1, #rows do rows[i]:Hide() end
        if keepScroll ~= true and scroller.SetVerticalScroll then scroller:SetVerticalScroll(0) end
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
        local stamp = ns.PlayerHasCategory(record, category.key)
            and ns.PlayerCategoryTime(record, category.key, "lastSeen")
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
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:Hide()
    ns.EnableWindowEscape(frame)
    if frame.TitleText then frame.TitleText:SetText("KnownPlayers - Player History") end

    local name = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", 50, -40)
    name:SetWidth(440)
    name:SetMaxLines(1)
    name:SetJustifyH("LEFT")

    local favorite = CreateIconButton(frame)
    favorite:SetPoint("RIGHT", name, "LEFT", -4, 0)

    local realm = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    realm:SetPoint("TOPLEFT", 50, -63)
    local appearance = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    appearance:SetPoint("TOPLEFT", 50, -82)

    local reasonsLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    reasonsLabel:SetPoint("TOPLEFT", 23, -112)
    reasonsLabel:SetText("Saved reasons and last activity")
    local reasons = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    reasons:SetPoint("TOPLEFT", reasonsLabel, "BOTTOMLEFT", 0, -6)
    reasons:SetWidth(468)
    reasons:SetJustifyH("LEFT")

    local noteLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    noteLabel:SetPoint("TOPLEFT", reasons, "BOTTOMLEFT", 0, -16)
    noteLabel:SetText("Personal note (saved locally)")
    local noteScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelInputScrollFrameTemplate")
    noteScroll:SetPoint("TOPLEFT", noteLabel, "BOTTOMLEFT", 4, -7)
    noteScroll:SetSize(450, 69)
    noteScroll.hideCharCount = true
    local note = noteScroll.EditBox
    note:SetWidth(445)
    note:SetScript("OnEscapePressed", ns.EscapeFromEditBox)

    local tagsLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    tagsLabel:SetPoint("TOPLEFT", noteScroll, "BOTTOMLEFT", -4, -16)
    tagsLabel:SetText("Searchable tags (separate with commas)")
    local tags = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    tags:SetPoint("TOPLEFT", tagsLabel, "BOTTOMLEFT", 4, -7)
    tags:SetSize(450, 25)
    tags:SetAutoFocus(false)
    tags:SetScript("OnEscapePressed", ns.EscapeFromEditBox)

    local save = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    save:SetPoint("BOTTOMRIGHT", -22, 21)
    save:SetSize(82, 24)
    save:SetText("Save")
    local saveStatus = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    saveStatus:SetPoint("LEFT", frame, "BOTTOMLEFT", 23, 33)
    saveStatus:SetWidth(372)
    saveStatus:SetJustifyH("LEFT")
    local key, record
    function frame.RefreshFavorite()
        local available = ns.GetPlayer(key) == record and ns.HasPlayerCategory(record)
        ShowFavoriteState(favorite, available and record.favorite == true)
        favorite:SetEnabled(available)
    end

    favorite:SetScript("OnClick", function()
        if not ns.SetPlayerFavorite(key, record, not record.favorite) then frame.RefreshFavorite() end
    end)

    save:SetScript("OnClick", function()
        if not ns.SavePlayerDetails(key, record, note:GetText(), tags:GetText()) then
            saveStatus:SetText("This player record is no longer available. Copy your edits before closing.")
            return
        end
        frame:Hide()
    end)
    frame:HookScript("OnHide", function(self)
        self:StopMovingOrSizing()
        note:ClearFocus()
        tags:ClearFocus()
    end)

    function frame.RefreshHistory()
        local history = {}
        for _, category in ipairs(CATEGORIES) do
            if ns.PlayerHasCategory(record, category.key) then
                local stamp = ns.PlayerCategoryTime(record, category.key, "lastSeen")
                history[#history + 1] = ns.GetPlayerCategoryLabel(category.key) .. " (" .. InteractionAge(stamp) .. ")"
            end
        end
        reasons:SetText(table.concat(history, "\n"))
        frame:SetHeight(math.max(478, 380 + reasons:GetStringHeight()))
    end

    function frame.Open(playerKey, player, settingsPage)
        key, record = playerKey, player
        name:SetText(ns.GetDisplayName(key, record))
        realm:SetText(ns.SafeString(record.realm) or "")
        local _, classLabel, classAtlas = GetRowClass(record)
        appearance:SetText("Race: " .. AppearanceText(ns.SafeString(record.race) or "Unknown", GetRaceAtlas(record))
            .. "    Class: " .. AppearanceText(ns.SafeString(record.class) or classLabel or "Unknown", classAtlas))
        frame.RefreshHistory()
        saveStatus:SetText("")
        noteScroll:SetVerticalScroll(0)
        note:SetText(ns.SafeString(record.note) or "")
        note:SetCursorPosition(0)
        tags:SetText(ns.SafeString(record.tags) or "")
        tags:SetCursorPosition(0)
        frame.RefreshFavorite()
        ns.ShowWindow(frame, settingsPage)
    end
    return frame
end

local historyWindow
function ns.OpenPlayerHistory(key, unit, settingsPage)
    local record = ns.GetPlayer(key)
    if not ns.HasPlayerCategory(record) then return end
    ns.RefreshPlayerAppearance(record, unit)
    if not historyWindow then historyWindow = CreatePlayerHistoryWindow() end
    historyWindow.Open(key, record, settingsPage)
end

-- All player interactions are already stored in one hash table:
-- KnownPlayersDB.players[characterKey].categories[reason] = true.
-- This consolidated window is a view of that table, not a second store.
local function CreatePlayersWindow()
    local frame = CreateFrame("Frame", "KnownPlayersAllPlayersWindow", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(882, 635)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:Hide()
    ns.EnableWindowEscape(frame)
    if frame.TitleText then frame.TitleText:SetText("KnownPlayers - All Players") end

    local count = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    count:SetPoint("TOPLEFT", 23, -43)
    AddUndoButton(frame)
    local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    search:SetSize(300, 24)
    search:SetPoint("TOPLEFT", 26, -68)
    search:SetAutoFocus(false)
    search:SetMaxLetters(100)
    search:SetText("")
    search:SetScript("OnEscapePressed", ns.EscapeFromEditBox)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -4)
    hint:SetText("Search names, realms, reasons, notes, or tags")

    local Refresh
    local ReadClassFilter = AddClassFilter(frame, 344, -69, function() Refresh() end)
    local favorites = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    favorites:SetPoint("LEFT", frame.classFilter, "RIGHT", 14, 0)
    favorites.Text:SetText("Favorites only")
    favorites:SetScript("OnClick", function() Refresh() end)

    local filterEnabled = {}
    for _, category in ipairs(CATEGORIES) do filterEnabled[category.key] = true end
    local filterTitle = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    filterTitle:SetPoint("TOPLEFT", 26, -119)
    filterTitle:SetText("Match any selected reason")
    local checkboxes = {}
    for index, category in ipairs(CATEGORIES) do
        local column = (index - 1) % 3
        local row = math.floor((index - 1) / 3)
        local check = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
        check:SetPoint("TOPLEFT", frame, "TOPLEFT", 22 + 220 * column, -140 - 29 * row)
        check.Text:SetText(ns.GetPlayerCategoryLabel(category.key))
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
    allFilters:SetPoint("LEFT", filterTitle, "RIGHT", 12, 0)
    allFilters:SetText("All")
    allFilters:SetScript("OnClick", function() SetAllFilters(true) end)
    local noFilters = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    noFilters:SetSize(54, 21)
    noFilters:SetPoint("LEFT", allFilters, "RIGHT", 6, 0)
    noFilters:SetText("None")
    noFilters:SetScript("OnClick", function() SetAllFilters(false) end)

    local recent = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    recent:SetPoint("TOPLEFT", 670, -226)
    recent.Text:SetText("Most recent first")
    recent:SetScript("OnClick", function() Refresh() end)
    local sortHint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sortHint:SetPoint("LEFT", frame, "TOPLEFT", 26, -239)
    sortHint:SetText("Favorites appear first in every sort")

    local Sort = AddSortHeaders(frame, -260, 607, function() Refresh() end, recent, 107)
    local appearanceHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    appearanceHeader:SetPoint("CENTER", frame, "TOPLEFT", 313, -270)
    appearanceHeader:SetText("Class / race")
    local reasonHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    reasonHeader:SetPoint("LEFT", frame, "TOPLEFT", 377, -270)
    reasonHeader:SetText("Saved reasons")
    local recentHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    recentHeader:SetPoint("LEFT", frame, "TOPLEFT", 674, -270)
    recentHeader:SetText("Last activity")

    local scroller = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroller:SetPoint("TOPLEFT", 21, -285)
    scroller:SetPoint("BOTTOMRIGHT", -37, 20)
    local content = CreateFrame("Frame", nil, scroller)
    content:SetSize(807, 1)
    scroller:SetScrollChild(content)
    local rows = {}
    local ROW_HEIGHT = 31
    local function ReasonsFor(record)
        local result = {}
        for _, category in ipairs(CATEGORIES) do
            if ns.PlayerHasCategory(record, category.key) then
                result[#result + 1] = ns.GetPlayerCategoryLabel(category.key)
            end
        end
        return result
    end
    local function FirstSeen(record)
        local first
        for _, category in ipairs(CATEGORIES) do
            local stamp = ns.PlayerHasCategory(record, category.key)
                and ns.PlayerCategoryTime(record, category.key, "firstSeen")
            if type(stamp) == "number" and (not first or stamp < first) then first = stamp end
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
        item.name:SetPoint("LEFT", 86, 0)
        item.name:SetWidth(145)
        item.name:SetJustifyH("LEFT")
        item.name:SetMaxLines(1)
        AddAppearanceIcons(item, 236)
        item.reasons = item:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        item.reasons:SetPoint("LEFT", 356, 0)
        item.reasons:SetWidth(225)
        item.reasons:SetJustifyH("LEFT")
        item.reasons:SetMaxLines(1)
        item.known = item:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        item.known:SetPoint("LEFT", 586, 0)
        item.known:SetWidth(64)
        item.known:SetJustifyH("LEFT")
        item.recent = item:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        item.recent:SetPoint("LEFT", 653, 0)
        item.recent:SetWidth(72)
        item.recent:SetJustifyH("LEFT")
        item.details = CreateFrame("Button", nil, item, "UIPanelButtonTemplate")
        item.details:SetSize(68, 23)
        item.details:SetPoint("RIGHT", -3, 0)
        item.details:SetText("History")
        AddHistoryTooltip(item.details)
        AddPlayerRowActions(item, "Forget this player from every list", 6)
        rows[index] = item
        return item
    end
    local empty = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    empty:SetPoint("TOPLEFT", 6, -8)
    Refresh = function(keepScroll)
        for index, category in ipairs(CATEGORIES) do
            checkboxes[index].Text:SetText(ns.GetPlayerCategoryLabel(category.key))
        end
        local all = {}
        for key, record in pairs(KnownPlayersDB.players or {}) do
            if ns.HasPlayerCategory(record) then
                local reasons = ReasonsFor(record)
                all[#all + 1] = {
                    key = key, name = ns.GetDisplayName(key, record),
                    realm = record.realm or "", reasons = table.concat(reasons, ", "),
                    firstSeen = FirstSeen(record), lastSeen = LatestInteraction(record),
                    favorite = record.favorite == true,
                    appearance = record,
                }
            end
        end
        local classFilter = ReadClassFilter(all)
        local term, nameTerm = PlayerSearchTerms(search)
        local filtered = {}
        for _, entry in ipairs(all) do
            local record = KnownPlayersDB.players[entry.key]
            local eligible = false
            for _, category in ipairs(CATEGORIES) do
                if filterEnabled[category.key] and ns.PlayerHasCategory(record, category.key) then
                    eligible = true
                    break
                end
            end
            if eligible and (classFilter == "all" or entry.classKey == classFilter)
                and (not favorites:GetChecked() or entry.favorite)
                and (MatchesPlayerSearch(entry, term, nameTerm)
                or entry.reasons:lower():find(term, 1, true)
                or (ns.SafeString(record.note) or ""):lower():find(term, 1, true)
                or (ns.SafeString(record.tags) or ""):lower():find(term, 1, true)) then
                filtered[#filtered + 1] = entry
            end
        end
        Sort(filtered, true)
        count:SetText(#all .. " players (" .. #filtered .. " shown)")
        content:SetHeight(math.max(1, #filtered) * ROW_HEIGHT)
        empty:SetShown(#filtered == 0)
        if #filtered == 0 then
            local reasonSelected = false
            for _, enabled in pairs(filterEnabled) do
                if enabled then
                    reasonSelected = true
                    break
                end
            end
            if #all == 0 then
                empty:SetText("No saved players yet")
            elseif not reasonSelected then
                empty:SetText("Select at least one reason or click All")
            elseif term ~= "" then
                empty:SetText("No matching players. Clear search or broaden filters.")
            elseif classFilter == "all" and not favorites:GetChecked() then
                empty:SetText("No matching players. Select more reasons or click All.")
            else
                empty:SetText("No matching players. Broaden the class, favorites, or reason filters.")
            end
        end
        for index, entry in ipairs(filtered) do
            local item = GetRow(index)
            item.name:SetText(entry.name)
            ShowAppearanceIcons(item, entry)
            item.reasons:SetText(entry.reasons)
            item.known:SetText(FormatKnownDuration(entry.firstSeen))
            item.recent:SetText(InteractionAge(entry.lastSeen))
            UpdateFavoriteButton(item.favoriteButton, entry)
            UpdateAvoidButton(item.avoidButton, entry)
            UpdateHistoryTooltip(item.details, PlayerIdentityText(entry))
            item.details:SetScript("OnClick", function() ns.OpenPlayerHistory(entry.key, nil, frame.settingsPage) end)
            item.removeButton:SetScript("OnClick", function()
                if ns.GetPlayer(entry.key) ~= entry.appearance then return end
                if ns.ForgetPlayer(entry.key, true) then
                    if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
                    if RefreshAllWindows then RefreshAllWindows() end
                end
            end)
            item:Show()
        end
        for i = #filtered + 1, #rows do rows[i]:Hide() end
        if keepScroll ~= true and scroller.SetVerticalScroll then scroller:SetVerticalScroll(0) end
        if scroller.UpdateScrollChildRect then scroller:UpdateScrollChildRect() end
    end
    search:SetScript("OnTextChanged", Refresh)
    frame:SetScript("OnShow", Refresh)
    frame.Refresh = Refresh
    return frame
end

local function CreateAssociatedWindow()
    local frame = CreateFrame("Frame", "KnownPlayersAssociatedListWindow", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(760, 490)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:Hide()
    ns.EnableWindowEscape(frame)
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
    search:SetScript("OnEscapePressed", ns.EscapeFromEditBox)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local searchLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    searchLabel:SetPoint("LEFT", search, "RIGHT", 12, 0)
    searchLabel:SetText("Search names, realms, or linked characters")

    local Refresh
    local Sort = AddSortHeaders(frame, -136, 508, function() Refresh() end)
    local ReadClassFilter = AddClassFilter(frame, 229, -137, function() Refresh() end)
    local linkHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    linkHeader:SetPoint("TOPLEFT", 349, -140)
    linkHeader:SetText("Recognized through")

    local scroller = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroller:SetPoint("TOPLEFT", 21, -160)
    scroller:SetPoint("BOTTOMRIGHT", -39, 20)
    local content = CreateFrame("Frame", nil, scroller)
    content:SetSize(670, 1)
    scroller:SetScrollChild(content)
    local rows = {}
    local ROW_HEIGHT = 28
    local empty = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    empty:SetPoint("TOPLEFT", 6, -8)
    Refresh = function()
        local all = ns.GetAssociatedCharacters()
        local classFilter = ReadClassFilter(all)
        local term, nameTerm = PlayerSearchTerms(search)
        local filtered = {}
        for _, entry in ipairs(all) do
            if (classFilter == "all" or entry.classKey == classFilter)
                and (MatchesPlayerSearch(entry, term, nameTerm)
                or (entry.linkedTo or ""):lower():find(term, 1, true)) then
                filtered[#filtered + 1] = entry
            end
        end
        Sort(filtered)
        count:SetText(#all .. " associated characters (" .. #filtered .. " shown)")
        content:SetHeight(math.max(1, #filtered) * ROW_HEIGHT)
        empty:SetShown(#filtered == 0)
        if #filtered == 0 then
            if #all == 0 then
                empty:SetText("No linked Battle.net alts to show")
            elseif term ~= "" then
                empty:SetText("No matching alts. Clear search or change the class filter.")
            else
                empty:SetText("No alts match this class. Try All classes.")
            end
        end
        for i, entry in ipairs(filtered) do
            if not rows[i] then
                local row = CreateFrame("Frame", nil, content)
                row:SetHeight(ROW_HEIGHT)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
                row:SetPoint("RIGHT", 0, 0)
                row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                row.name:SetPoint("LEFT", 5, 0)
                row.name:SetWidth(195)
                row.name:SetJustifyH("LEFT")
                row.name:SetMaxLines(1)
                AddAppearanceIcons(row, 208)
                row.source = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                row.source:SetPoint("LEFT", 328, 0)
                row.source:SetWidth(154)
                row.source:SetJustifyH("LEFT")
                row.known = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                row.known:SetPoint("LEFT", 487, 0)
                row.known:SetWidth(63)
                row.known:SetJustifyH("LEFT")
                row.historyButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                row.historyButton:SetSize(105, 22)
                row.historyButton:SetPoint("RIGHT", -4, 0)
                row.historyButton:SetText("Linked History")
                AddHistoryTooltip(row.historyButton)
                rows[i] = row
            end
            local row = rows[i]
            row.name:SetText(entry.name)
            ShowAppearanceIcons(row, entry)
            local linkedName = entry.linkedTo or "Known player"
            row.source:SetText(linkedName)
            row.known:SetText(FormatKnownDuration(entry.firstSeen))
            UpdateHistoryTooltip(row.historyButton, PlayerIdentityText(entry) .. "\nOpens history for " .. linkedName)
            row.historyButton:SetScript("OnClick", function()
                ns.OpenPlayerHistory(entry.linkedPlayerKey, nil, frame.settingsPage)
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
    frame:SetSize(860, 595)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:Hide()
    ns.EnableWindowEscape(frame)
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
    search:SetScript("OnEscapePressed", ns.EscapeFromEditBox)
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
    allFilters:SetPoint("LEFT", title, "RIGHT", 12, 0)
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
    clear:SetPoint("RIGHT", frame.undoButton, "LEFT", -10, 0)
    clear:SetText("Clear Saved NPCs")
    local clearPopup = "KNOWNPLAYERS_CLEAR_NPC_MANAGEMENT"
    if not StaticPopupDialogs[clearPopup] then
        StaticPopupDialogs[clearPopup] = {
            text = "Clear all manually remembered NPCs and NPC visibility overrides?\n\nA restore point will be saved in Backup & Restore.",
            button1 = YES, button2 = CANCEL,
            OnAccept = function()
                if not ns.BackupBeforeChange("Before clearing saved NPCs", {npcs = true}) then return end
                ns.ClearNPCManagement()
                if RefreshAllWindows then RefreshAllWindows() end
            end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
    end
    clear:SetScript("OnClick", function() StaticPopup_Show(clearPopup) end)

    local Sort = AddSortHeaders(frame, -248, 407, function() Refresh() end)
    for _, column in ipairs({
        {211, "Categories / source"}, {477, "Visibility"},
        {600, "Saved"}, {715, "Favorite"},
    }) do
        local heading = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        heading:SetPoint("TOPLEFT", frame, "TOPLEFT", column[1], -252)
        heading:SetText(column[2])
    end
    local scroller = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroller:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -270)
    scroller:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -40, 19)
    local content = CreateFrame("Frame", nil, scroller)
    content:SetSize(783, 1)
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
        local known = item:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        known:SetPoint("LEFT", item, "LEFT", 385, 0)
        known:SetWidth(63)
        known:SetJustifyH("LEFT")
        local mode = CreateFrame("Button", nil, item, "UIPanelButtonTemplate")
        mode:SetSize(115, 24)
        mode:SetPoint("LEFT", item, "LEFT", 455, 0)
        local manual = CreateFrame("Button", nil, item, "UIPanelButtonTemplate")
        manual:SetSize(105, 24)
        manual:SetPoint("LEFT", item, "LEFT", 578, 0)
        local pin = CreateFrame("Button", nil, item, "UIPanelButtonTemplate")
        pin:SetSize(67, 24)
        pin:SetPoint("LEFT", item, "LEFT", 693, 0)
        item.nameText, item.categoryText, item.knownText = name, categoriesLabel, known
        item.modeButton, item.manualButton, item.pinButton = mode, manual, pin
        rows[index] = item
        return item
    end
    local empty = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
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
        Sort(filtered, true)
        count:SetText(#all .. " saved NPCs (" .. #filtered .. " shown)")
        clear:SetEnabled(#all > 0)
        content:SetHeight(math.max(1, #filtered) * HEIGHT)
        empty:SetShown(#filtered == 0)
        if #filtered == 0 then
            if #all == 0 then
                empty:SetText("No saved NPCs yet")
            elseif term ~= "" then
                empty:SetText("No matching saved NPCs. Clear search or broaden filters.")
            else
                empty:SetText("No saved NPCs match these filters. Select more categories or turn off Favorites only.")
            end
        end
        local roleLabels = {}
        for _, category in ipairs(categories) do roleLabels[category.key] = category.label end
        for i, entry in ipairs(filtered) do
            local row = Row(i)
            row.nameText:SetText((entry.favorite and "|cffffd100*|r " or "") .. entry.name .. " (" .. entry.key .. ")")
            row.knownText:SetText(FormatKnownDuration(entry.firstSeen))
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

RefreshAllWindows = function(keepScroll)
    for _, frame in pairs(windows) do
        if frame:IsShown() then frame.Refresh(keepScroll) end
    end
    if historyWindow and historyWindow:IsShown() then
        historyWindow.RefreshFavorite()
        historyWindow.RefreshHistory()
    end
end

function ns.RefreshPlayerListWindows(keepScroll)
    RefreshAllWindows(keepScroll)
end

local function ShowListWindow(window, settingsPage)
    local alreadyShown = window:IsShown()
    ns.ShowWindow(window, settingsPage)
    -- A hidden window refreshes in OnShow; raising a visible window does not.
    if alreadyShown then window.Refresh() end
end

local function OpenCategoryWindow(category, index, settingsPage)
    local window = windows[category.key]
    if not window then
        window = CreateCategoryWindow(category, index)
        windows[category.key] = window
    end
    ShowListWindow(window, settingsPage)
end

-- Settings controls open these dialogs; the dialogs contain list tools only.
function ns.OpenPlayerList(categoryKey, settingsPage)
    if categoryKey == "guild" and ns.RefreshGuildList then
        ns.RefreshGuildList()
    end
    if categoryKey == "players" then
        if not windows.players then windows.players = CreatePlayersWindow() end
        ShowListWindow(windows.players, settingsPage)
        return
    end
    if categoryKey == "associated" then
        if not windows.associated then windows.associated = CreateAssociatedWindow() end
        ShowListWindow(windows.associated, settingsPage)
        return
    end
    if categoryKey == "npc" then
        if not windows.npc then windows.npc = CreateNPCManagementWindow() end
        ShowListWindow(windows.npc, settingsPage)
        return
    end
    for index, category in ipairs(CATEGORIES) do
        if category.key == categoryKey then
            OpenCategoryWindow(category, index, settingsPage)
            return
        end
    end
end

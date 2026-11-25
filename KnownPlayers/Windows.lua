local _, ns = ...

local openWindows = {}
local hidingForNavigation
local escapeFrame

local function RemoveOpenWindow(frame)
    for i = #openWindows, 1, -1 do
        if openWindows[i] == frame then
            table.remove(openWindows, i)
            return
        end
    end
end

local function HideForNavigation(frame)
    local previous = hidingForNavigation
    hidingForNavigation = frame
    frame:Hide()
    hidingForNavigation = previous
end

local function UpdateOpenWindows()
    local singleWindow = false
    for _, frame in ipairs(openWindows) do
        if frame.hideOtherWindows == true then
            singleWindow = true
            break
        end
    end
    local latest = openWindows[#openWindows]
    for _, frame in ipairs(openWindows) do
        if frame ~= latest and singleWindow and frame:IsShown() then
            -- Keep this frame in the navigation stack so closing the child returns to it.
            HideForNavigation(frame)
        end
    end
    for _, frame in ipairs(openWindows) do
        if frame == latest or not singleWindow then frame:Show() end
    end
    if latest then latest:Raise() end
    if escapeFrame then escapeFrame:SetShown(latest ~= nil) end
end

local function ShowWindow(frame, settingsPage)
    frame.settingsPage = settingsPage
    RemoveOpenWindow(frame)
    openWindows[#openWindows + 1] = frame
    UpdateOpenWindows()
end

function ns.CloseWindowsFromSettingsPage(page)
    if not page then return end
    local closing = {}
    for i = #openWindows, 1, -1 do
        local frame = openWindows[i]
        if frame.settingsPage == page then
            table.remove(openWindows, i)
            closing[#closing + 1] = frame
        end
    end
    if #closing == 0 then return end
    for _, frame in ipairs(closing) do HideForNavigation(frame) end
    UpdateOpenWindows()
end

local function CloseLatestWindow()
    local frame = openWindows[#openWindows]
    if not frame then return end
    if frame.classFilter and frame.classFilter:IsMenuOpen() then
        frame.classFilter:CloseMenu()
    else
        frame:Hide()
    end
end

local function EnableWindowKeyboard(frame)
    frame:EnableKeyboard(true)
    frame:SetPropagateKeyboardInput(true)
end

local function EnableWindowEscape(frame)
    if frame.CloseButton then
        frame.CloseButton:SetScript("OnClick", function() frame:Hide() end)
    end
    frame:HookScript("OnHide", function(self)
        if self == hidingForNavigation or self:IsShown() then return end
        RemoveOpenWindow(self)
        UpdateOpenWindows()
    end)

    if type(UISpecialFrames) == "table" then
        if not escapeFrame then
            -- WoW closes every visible special frame. Register one frame so Escape
            -- still closes only the top KnownPlayers window.
            escapeFrame = CreateFrame("Frame", "KnownPlayersEscapeFrame", UIParent)
            escapeFrame:Hide()
            escapeFrame:SetScript("OnHide", function(self)
                if self:IsShown() then return end
                CloseLatestWindow()
                if #openWindows > 0 then self:Show() end
            end)
            UISpecialFrames[#UISpecialFrames + 1] = "KnownPlayersEscapeFrame"
        end
        return
    end

    frame:HookScript("OnShow", function(self)
        if InCombatLockdown and InCombatLockdown() then
            self:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            EnableWindowKeyboard(self)
        end
    end)
    frame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if self:IsShown() then EnableWindowKeyboard(self) end
    end)
    frame:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown and InCombatLockdown() then return end
        local escape = key == "ESCAPE"
        self:SetPropagateKeyboardInput(not escape)
        if escape then CloseLatestWindow() end
    end)
end

ns.ShowWindow = ShowWindow
ns.EnableWindowEscape = EnableWindowEscape

function ns.EscapeFromEditBox(self)
    self:ClearFocus()
    CloseLatestWindow()
end

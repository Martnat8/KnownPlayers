local addonName, ns = ...
local button

local function CreateMinimapButton()
    -- MinimapButtonButton collects named addon buttons that are direct children
    -- of Minimap. Leave the parent and anchors alone after creating the button.
    local launcher = CreateFrame("Button", "KnownPlayersMinimapButton", Minimap)
    launcher:SetSize(31, 31)
    launcher:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    launcher:SetPoint("CENTER", Minimap, "CENTER", -0.43 * Minimap:GetWidth(), -0.27 * Minimap:GetHeight())
    launcher:RegisterForClicks("LeftButtonUp")
    launcher:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = launcher:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", launcher, "TOPLEFT", 16, -15)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local mask = launcher:CreateMaskTexture(nil, "ARTWORK")
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
    local border = launcher:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    local function HideTooltip(self)
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end
    launcher:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("KnownPlayers")
        GameTooltip:AddLine("Click to open the KnownPlayers window.", 1, 1, 1)
        GameTooltip:Show()
    end)
    launcher:SetScript("OnLeave", HideTooltip)
    launcher:SetScript("OnHide", HideTooltip)
    launcher:SetScript("OnClick", ns.OpenSettingsWindow)
    return launcher
end

function ns.RefreshMinimapButton()
    if KnownPlayersSettings and KnownPlayersSettings.showMinimapButton then
        if not button and Minimap then button = CreateMinimapButton() end
        if button and not button:IsShown() then button:Show() end
    elseif button and button:IsShown() then
        button:Hide()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", ns.RefreshMinimapButton)

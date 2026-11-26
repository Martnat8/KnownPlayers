local addonName, ns = ...

local ADDON_VERSION = "0.5.3b4"
ns.AddonVersion = ADDON_VERSION
local PRUNE_INTERVAL = 5

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")

local function Print(message)
    print("|cff33ff99KnownPlayers:|r " .. message)
end

local function PruneExpiredRecords()
    local now = time()
    local players = ns.PruneExpiredPlayers(now)
    local npcs = ns.PruneExpiredNPCs(now)
    if players + npcs > 0 then
        ns.RefreshKnownNameplates()
        ns.RefreshPlayerListWindows()
    end
end

local function TestDatabase()
    Print("Expiration self-test (sample data): " .. (ns.TestPlayerExpiration() and "PASS" or "FAIL"))
end

local function HandleSlashCommand(message)
    local command = (message or ""):lower():match("^%s*(.-)%s*$")

    if command == "options" then
        if ns.OpenSettings then
            ns.OpenSettings()
        else
            Print("Settings panel is not available.")
        end
        return
    end

    if command == "" or command == "help" then
        Print("Available commands:")
        Print("/kp status - Show addon and database status.")
        Print("/kp options - Open addon settings.")
        Print("/kp dbtest - Test expiration on sample data.")
        Print("/kp list - Show up to 10 saved player records.")
        Print("/kp players - Open the searchable All Players window.")
        Print("/kp scan - Scan the current party or raid.")
        Print("/kp guildscan - Request and scan the guild roster.")
        Print("/kp platehide - Temporarily hide the target player nameplate.")
        Print("/kp plateshow - Restore the target player nameplate.")
        Print("/kp npctoggle - Remember/remove current target NPC.")
        Print("/kp npcsource - Show the NPC database source.")
        Print("/kp remember - Add the targeted player to Manually Added.")
        Print("/kp undo - Restore the last individual removal within 30 seconds.")
        Print("/kp help - Show this help.")
        return
    end

    if command == "platehide" or command == "plateshow" then
        if ns.TestTargetNameplate then ns.TestTargetNameplate(command == "platehide") end
        return
    end

    if command == "remember" then
        local key, guidOrReason, name, realm = ns.GetPlayerFromUnit("target")
        if not key then
            Print(guidOrReason)
            return
        end
        ns.RememberPlayer(key, "manual", nil, guidOrReason, realm, "target")
        if ns.RefreshKnownNameplates then ns.RefreshKnownNameplates() end
        if ns.RefreshPlayerListWindows then ns.RefreshPlayerListWindows() end
        Print("Added to Manually Added: " .. name)
        return
    end

    if command == "undo" then
        local _, status = ns.UndoLastRemoval()
        Print(status)
        return
    end

    if command == "npcsource" then
        Print(ns.GetNPCDataSourceStatus and ns.GetNPCDataSourceStatus()
            or "QuestieDB bridge unavailable")
        return
    end

    if command == "npctoggle" then
        local id, name = ns.GetNPCFromUnit("target")
        if not id then
            Print("Target a creature NPC first.")
        elseif KnownPlayersDB.npcs[id] then
            ns.ForgetNPC(id)
            Print("Removed NPC: " .. name)
        else
            ns.RememberNPC(id, name)
            Print("Remembered NPC: " .. name)
        end
        return
    end

    if command == "status" then
        Print("Version " .. ADDON_VERSION .. " loaded.")
        Print("Saved player records: " .. ns.CountPlayers())
        Print("Saved NPCs: " .. ns.CountNPCs())
        Print("Associated characters: " .. ns.CountAssociatedCharacters())
        local enabled, total = 0, 0
        for category, retention in pairs(KnownPlayersSettings.categoryRetention) do
            if (category == "npc" or ns.IsPlayerCategory(category)) and type(retention) == "table" then
                total = total + 1
                if retention.enabled then enabled = enabled + 1 end
            end
        end
        Print("Category expiration: " .. enabled .. " of " .. total .. " enabled")
        return
    end

    if command == "scan" then
        Print("Group members processed: " .. ns.ScanGroupRoster())
        return
    end

    if command == "guildscan" then
        if not IsInGuild() then
            Print("You are not in a guild.")
        elseif not KnownPlayersSettings.trackGuild then
            Print("Guild tracking is disabled in settings.")
        else
            ns.RequestGuildRoster()
            Print("Guild members processed from current roster cache: " .. ns.ScanGuildRoster())
            Print("A later GUILD_ROSTER_UPDATE may import additional members.")
        end
        return
    end

    if command == "players" then
        ns.OpenPlayerList("players")
        return
    end

    if command == "list" then
        local shown = 0
        for name, record in pairs(KnownPlayersDB.players) do
            if shown >= 10 then break end
            local categories = {}
            for _, category in ipairs(ns.PlayerCategories) do
                if ns.PlayerHasCategory(record, category.key) then
                    categories[#categories + 1] = category.key == "avoid"
                        and ns.GetPlayerCategoryLabel(category.key) or category.key
                end
            end
            if #categories > 0 then
                table.sort(categories)
                Print(ns.GetDisplayName(name, record) .. " [" .. table.concat(categories, ", ") .. "]")
                shown = shown + 1
            end
        end
        if shown == 0 then Print("No saved players.") end
        if ns.CountPlayers() > shown then Print("Showing " .. shown .. " of " .. ns.CountPlayers() .. " players.") end
        return
    end

    if command == "dbtest" then
        TestDatabase()
        return
    end

    Print("Unknown command. Use /kp help.")
end

eventFrame:SetScript("OnEvent", function(self, event, loadedAddon)
    if event ~= "ADDON_LOADED" or loadedAddon ~= addonName then
        return
    end

    ns.InitializeDatabase()
    if ns.SyncNativeOverheadNames then ns.SyncNativeOverheadNames() end
    if ns.InitializeNameplateColors then ns.InitializeNameplateColors() end
    ns.MigratePlayerRecords()
    if ns.InvalidateIdentityIndex then ns.InvalidateIdentityIndex() end
    if ns.PruneUnlinkedBattleNetData then ns.PruneUnlinkedBattleNetData() end
    PruneExpiredRecords()
    if ns.SyncNPCNameplateCVars then ns.SyncNPCNameplateCVars() end
    ns.CreateSettingsPanel()
    ns.RefreshMinimapButton()
    if ns.InitializeNPCMenu then ns.InitializeNPCMenu() end
    if ns.InitializePlayerMenu then ns.InitializePlayerMenu() end
    -- Capture an existing group when the addon is loaded or reloaded.
    ns.ScanGroupRoster()
    ns.RequestGuildRoster()
    ns.ScanGuildRoster()
    ns.ScanBattleNetFriends()

    SLASH_KNOWNPLAYERS1 = "/kp"
    SlashCmdList.KNOWNPLAYERS = HandleSlashCommand

    C_Timer.NewTicker(PRUNE_INTERVAL, PruneExpiredRecords)

    self:UnregisterEvent("ADDON_LOADED")
    Print("Version " .. ADDON_VERSION .. " loaded.")
    Print("Saved player records: " .. ns.CountPlayers())
end)

local addonName, ns = ...

local ADDON_VERSION = "0.5.0b4"
ns.AddonVersion = ADDON_VERSION
local PRUNE_INTERVAL = 600
local elapsedSincePrune = 0

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")

local function Print(message)
    print("|cff33ff99KnownPlayers:|r " .. message)
end

local function TestDatabase()
    local testName = "__KnownPlayers_DatabaseTest__"
    local existing = KnownPlayersDB.players[testName]
    if existing ~= nil then
        Print("Database test skipped: reserved test record already exists.")
        return
    end

    local partyRetention = KnownPlayersSettings.categoryRetention.party
    local tradeRetention = KnownPlayersSettings.categoryRetention.trade
    local oldParty = { enabled = partyRetention.enabled, days = partyRetention.days,
        hours = partyRetention.hours, minutes = partyRetention.minutes }
    local oldTrade = { enabled = tradeRetention.enabled, days = tradeRetention.days,
        hours = tradeRetention.hours, minutes = tradeRetention.minutes }
    local now = time()

    -- Exercise insertion, category storage, timestamp refresh, and expiry.
    ns.RememberPlayer(testName, "party", now - 3 * 86400)
    local record = ns.GetPlayer(testName)
    local insertOK = record and record.categories.party == true
    ns.RememberPlayer(testName, "trade", now)
    record = ns.GetPlayer(testName)
    local refreshOK = record and record.lastSeen == now
        and record.categories.party and record.categories.trade

    partyRetention.enabled = true
    partyRetention.days, partyRetention.hours, partyRetention.minutes = 1, 0, 0
    tradeRetention.enabled = false
    local kept = ns.PruneExpiredPlayers(now) >= 0 and ns.GetPlayer(testName) ~= nil
    tradeRetention.enabled = true
    tradeRetention.days, tradeRetention.hours, tradeRetention.minutes = 1, 0, 0
    ns.RememberPlayer(testName, "party", now - 3 * 86400)
    ns.RememberPlayer(testName, "trade", now - 3 * 86400)
    ns.PruneExpiredPlayers(now)
    local expired = ns.GetPlayer(testName) == nil

    -- Restore settings and remove only the temporary record.
    for key, value in pairs(oldParty) do partyRetention[key] = value end
    for key, value in pairs(oldTrade) do tradeRetention[key] = value end
    ns.ForgetPlayer(testName)

    Print("Database self-test: "
        .. ((insertOK and refreshOK and kept and expired) and "PASS" or "FAIL"))
    Print("No test player records retained; settings restored.")
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
        Print("/kp dbtest - Test database and expiration logic.")
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
            if type(record) == "table" and type(record.categories) == "table" then
                for category, enabled in pairs(record.categories) do
                    if enabled and ns.IsPlayerCategory(category) then table.insert(categories, category) end
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
    ns.PruneExpiredPlayers()
    if ns.PruneExpiredNPCs then ns.PruneExpiredNPCs() end
    if ns.SyncNPCNameplateCVars then ns.SyncNPCNameplateCVars() end
    ns.CreateSettingsPanel()
    if ns.InitializeNPCMenu then ns.InitializeNPCMenu() end
    if ns.InitializePlayerMenu then ns.InitializePlayerMenu() end
    -- Capture an existing group when the addon is loaded or reloaded.
    ns.ScanGroupRoster()
    ns.RequestGuildRoster()
    ns.ScanGuildRoster()
    ns.ScanBattleNetFriends()

    SLASH_KNOWNPLAYERS1 = "/kp"
    SlashCmdList.KNOWNPLAYERS = HandleSlashCommand

    self:SetScript("OnUpdate", function(_, elapsed)
        elapsedSincePrune = elapsedSincePrune + elapsed
        if elapsedSincePrune >= PRUNE_INTERVAL then
            elapsedSincePrune = 0
            ns.PruneExpiredPlayers()
            if ns.PruneExpiredNPCs then ns.PruneExpiredNPCs() end
        end
    end)

    self:UnregisterEvent("ADDON_LOADED")
    Print("Version " .. ADDON_VERSION .. " loaded.")
    Print("Saved player records: " .. ns.CountPlayers())
end)

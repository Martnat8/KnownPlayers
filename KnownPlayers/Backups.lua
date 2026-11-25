local _, ns = ...

local FORMAT = 1
local PREFIX = "KnownPlayers:"
local MAX_EXPORT_BYTES = 4 * 1024 * 1024
local MAX_PLAYERS = 25000
local MAX_NPCS = 10000
local ALL_SECTIONS = {settings = true, players = true, npcs = true}
local TRACKING_CATEGORIES = {ns.AssociatedCategory}
for _, category in ipairs(ns.PlayerCategories) do
    TRACKING_CATEGORIES[#TRACKING_CATEGORIES + 1] = category
end

local function Invalid()
    error("The backup contains invalid KnownPlayers data.", 0)
end

local function Object(value)
    if type(value) ~= "table" then Invalid() end
    return value
end

local function Text(value, limit)
    if type(value) ~= "string" or #value > limit or value:find("\0", 1, true) then Invalid() end
    return value
end

local function Name(value)
    if Text(value, 256) == "" then Invalid() end
    return value
end

local function Note(value) return Text(value, 65536) end

local function Boolean(value)
    if type(value) ~= "boolean" then Invalid() end
    return value
end

local function Number(value, maximum)
    if type(value) ~= "number" or value ~= value or value < 0 or value > maximum then Invalid() end
    return value
end

local function Stamp(value) return Number(value, 9007199254740991) end

local function Guid(value)
    if not ns.SafePlayerGUID(Name(value)) then Invalid() end
    return value
end

local function NPCID(value)
    if not Name(value):match("^%d+$") or #value > 12 or tonumber(value) < 1 then Invalid() end
    return value
end

local function Fields(value, fields)
    Object(value)
    local copy = {}
    for key, check in pairs(fields) do
        if value[key] ~= nil then copy[key] = check(value[key]) end
    end
    return copy
end

local function Map(value, keyCheck, valueCheck, limit)
    Object(value)
    local count, copy = 0, {}
    for key, entry in pairs(value) do
        count = count + 1
        if limit and count > limit then Invalid() end
        copy[keyCheck(key)] = valueCheck(entry)
    end
    return copy
end

local function Flags(value) return Map(value, Name, Boolean, 64) end
local function Duration(value)
    return Fields(value, {enabled = Boolean, days = Stamp, hours = Stamp, minutes = Stamp})
end

local function Color(value)
    Object(value)
    return {Number(value[1], 1), Number(value[2], 1), Number(value[3], 1)}
end

local function Colors(value) return Map(value, Name, Color, 64) end

local function Order(value)
    Object(value)
    local length = #value
    if length > 64 then Invalid() end
    local copy = {}
    for index = 1, length do copy[index] = Name(value[index]) end
    return copy
end

local function NameMode(value)
    if value ~= "full" and value ~= "first" then Invalid() end
    return value
end

local function HealthMode(value)
    if value ~= "always" and value ~= "combat" and value ~= "never" then Invalid() end
    return value
end

local function Settings(value)
    local fields = {
        categoryRetention = function(durations) return Map(durations, Name, Duration, 64) end,
        trackGroup = Flags, showMinimapButton = Boolean,
        knownOnlyNameplates = Boolean, filterNPCNameplates = Boolean,
        nameDisplayMode = NameMode, npcNameDisplayMode = NameMode,
        playerHealthBarMode = HealthMode, npcHealthBarMode = HealthMode,
        showGuildInNamesOnly = Boolean, showNPCTitle = Boolean,
        nameplateCategoryColors = Colors, npcNameplateCategoryColors = Colors,
        nameplateColorOrder = Order, npcNameplateColorOrder = Order,
        npcServiceCategories = Flags,
    }
    for _, category in ipairs(TRACKING_CATEGORIES) do
        if category.tracking then fields[category.tracking] = Boolean end
    end
    return Fields(value, fields)
end

local function Membership(value) return Fields(value, {firstSeen = Stamp, lastSeen = Stamp}) end

local function LocalNote(value)
    if type(value) ~= "string" then Invalid() end
    return value
end

local function Player(value, localBackup)
    local mapLimit = not localBackup and 64 or nil
    local membershipLimit = not localBackup and 200 or nil
    local note = localBackup and LocalNote or Note
    local function TimeMap(value) return Map(value, Name, Stamp, mapLimit) end
    local player = Fields(value, {
        displayName = Name, realm = Name, guid = Guid, class = Name, classToken = Name,
        race = Name, raceAtlas = Name, note = note, tags = note, favorite = Boolean,
        categories = function(categories) return Map(categories, Name, Boolean, mapLimit) end,
        lastSeen = Stamp, categoryFirstSeen = TimeMap, categoryLastSeen = TimeMap,
        guildMemberships = function(memberships) return Map(memberships, Name, Membership, membershipLimit) end,
        preservedGuildDetails = Boolean,
    })
    player.categories = player.categories or {}
    if player.categories.guild then Invalid() end
    return player
end

local function NPC(value)
    return Fields(value, {name = Name, firstSeen = Stamp, lastSeen = Stamp, favorite = Boolean})
end

local function Override(value)
    local copy = Fields(value, {name = Name, firstSeen = Stamp, mode = Name})
    if copy.mode ~= "show" and copy.mode ~= "hide" then Invalid() end
    return copy
end

local function BattleNet(value)
    return Map(value, Name, function(group)
        return Map(group, Name, function(entry)
            return Fields(entry, {
                name = Name, realm = Name, guid = Guid, class = Name, classToken = Name,
                race = Name, raceAtlas = Name, firstObserved = Stamp, lastObserved = Stamp,
            })
        end)
    end)
end

local function Validate(snapshot, localBackup, selection)
    Object(snapshot)
    if snapshot.version ~= FORMAT then error("This backup format is unsupported.", 0) end
    local sections = Object(snapshot.sections)
    local copy = {version = FORMAT, created = Stamp(snapshot.created), sections = {}}
    if sections.settings ~= nil and (not selection or selection.settings) then
        copy.sections.settings = Settings(sections.settings)
    end
    if sections.players ~= nil and (not selection or selection.players) then
        local data = Object(sections.players)
        local limit = not localBackup and MAX_PLAYERS or nil
        copy.sections.players = {records = Map(data.records, Name, function(record)
            return Player(record, localBackup)
        end, limit)}
        if localBackup and data.bnet ~= nil then copy.sections.players.bnet = BattleNet(data.bnet) end
    end
    if sections.npcs ~= nil and (not selection or selection.npcs) then
        local data = Object(sections.npcs)
        local limit = not localBackup and MAX_NPCS or nil
        copy.sections.npcs = {
            records = Map(data.records, NPCID, NPC, limit),
            overrides = Map(data.overrides, NPCID, Override, limit),
        }
    end
    if not selection and not next(copy.sections) then error("Select at least one section to back up.", 0) end
    return copy
end

local function Capture(selection, localBackup)
    local sections = {}
    if selection.settings then sections.settings = KnownPlayersSettings end
    if selection.players then
        sections.players = {records = KnownPlayersDB.players, bnet = localBackup and KnownPlayersDB.bnetCharacters or nil}
    end
    if selection.npcs then
        sections.npcs = {records = KnownPlayersDB.npcs, overrides = KnownPlayersDB.npcOverrides}
    end
    return Validate({version = FORMAT, created = time(), sections = sections}, localBackup)
end

function ns.CreateRestorePoint(kind, reason, selection)
    local ok, snapshot = pcall(Capture, selection or ALL_SECTIONS, true)
    if not ok then return nil, snapshot end
    local points = KnownPlayersDB.restorePoints
    if type(points) ~= "table" then points = {}; KnownPlayersDB.restorePoints = points end
    snapshot.reason = reason
    points[kind] = snapshot
    return snapshot
end

function ns.GetRestorePoint(kind)
    local points = KnownPlayersDB.restorePoints
    local snapshot = type(points) == "table" and points[kind]
    if type(snapshot) ~= "table" or snapshot.version ~= FORMAT or type(snapshot.sections) ~= "table" then return nil end
    return snapshot
end

function ns.DeleteRestorePoint(kind, expected)
    local point = ns.GetRestorePoint(kind)
    if not point or point ~= expected then return false end
    KnownPlayersDB.restorePoints[kind] = nil
    return true
end

function ns.BackupBeforeChange(reason, selection)
    local point, message = ns.CreateRestorePoint("automatic", reason, selection)
    if not point then print("|cff33ff99KnownPlayers:|r Could not create a restore point. " .. message) end
    return point ~= nil
end

function ns.CanTransferBackups()
    local codec = C_EncodingUtil
    return codec and type(codec.SerializeCBOR) == "function" and type(codec.DeserializeCBOR) == "function"
        and type(codec.EncodeBase64) == "function" and type(codec.DecodeBase64) == "function"
end

function ns.ExportBackup(selection)
    if not ns.CanTransferBackups() then return nil, "Export is unavailable on this WoW client." end
    local captured, snapshot = pcall(Capture, selection, false)
    if not captured then return nil, snapshot end
    local ok, encoded = pcall(function()
        return C_EncodingUtil.EncodeBase64(C_EncodingUtil.SerializeCBOR(snapshot))
    end)
    if not ok or type(encoded) ~= "string" then return nil, "Could not encode this backup." end
    local result = PREFIX .. FORMAT .. ":" .. encoded
    if #result > MAX_EXPORT_BYTES then return nil, "This export is too large. Export fewer sections at a time." end
    return result
end

function ns.ReadBackup(text)
    if not ns.CanTransferBackups() then return nil, "Import is unavailable on this WoW client." end
    if type(text) ~= "string" or #text > MAX_EXPORT_BYTES then return nil, "This import is too large." end
    local version, payload = text:gsub("%s+", ""):match("^KnownPlayers:(%d+):([A-Za-z0-9+/=]+)$")
    if not version then return nil, "Paste a complete KnownPlayers export." end
    if tonumber(version) ~= FORMAT then return nil, "This backup format is unsupported." end
    local ok, snapshot = pcall(function()
        return C_EncodingUtil.DeserializeCBOR(C_EncodingUtil.DecodeBase64(payload))
    end)
    if not ok or type(snapshot) ~= "table" then return nil, "Could not read this backup. Check that you copied all the text." end
    local valid, copy = pcall(Validate, snapshot, false)
    if not valid then return nil, copy end
    return copy
end

local function CountLabel(records, singular, plural)
    local count = 0
    for _ in pairs(records) do count = count + 1 end
    return count .. " " .. (count == 1 and singular or plural)
end

local function VisitTrackingOptions(settings, visit)
    for _, category in ipairs(TRACKING_CATEGORIES) do
        local fields = settings
        if category.group then
            fields = type(settings.trackGroup) == "table" and settings.trackGroup or nil
        end
        visit(category, fields, category.group or category.tracking)
    end
end

local function PreserveOmittedTracking(settings)
    settings.trackGroup = settings.trackGroup or {}
    VisitTrackingOptions(settings, function(category, fields, key)
        if fields[key] == nil then fields[key] = ns.CategoryTrackingEnabled(category.key) end
    end)
end

local function DescribeTrackingChanges(settings)
    local enabled, disabled = {}, {}
    VisitTrackingOptions(settings, function(category, fields, key)
        local value = fields and fields[key]
        if type(value) == "boolean" and value ~= ns.CategoryTrackingEnabled(category.key) then
            local changes = value and enabled or disabled
            changes[#changes + 1] = category.label
        end
    end)
    local lines = {}
    if #enabled > 0 then lines[#lines + 1] = "Enable: " .. table.concat(enabled, ", ") end
    if #disabled > 0 then lines[#lines + 1] = "Disable: " .. table.concat(disabled, ", ") end
    return lines
end

function ns.DescribeBackup(snapshot, selection)
    local sections, items = snapshot.sections, {}
    if selection.settings and sections.settings then items[#items + 1] = "Settings" end
    if selection.players and type(sections.players) == "table" and type(sections.players.records) == "table" then
        items[#items + 1] = CountLabel(sections.players.records, "player record", "player records")
    end
    if selection.npcs and type(sections.npcs) == "table" and type(sections.npcs.records) == "table"
        and type(sections.npcs.overrides) == "table" then
        items[#items + 1] = CountLabel(sections.npcs.records, "saved NPC", "saved NPCs")
        items[#items + 1] = CountLabel(sections.npcs.overrides, "NPC override", "NPC overrides")
    end
    local summary = table.concat(items, ", ")
    if selection.settings and type(sections.settings) == "table" then
        for _, change in ipairs(DescribeTrackingChanges(sections.settings)) do
            summary = summary .. "\n" .. change
        end
    end
    return summary
end

local function MergeNPCs(staged, incoming)
    for id, entry in pairs(incoming.records) do
        local existing = staged.records[id]
        if existing then
            existing.name = existing.name or entry.name
            if entry.firstSeen then existing.firstSeen = math.min(existing.firstSeen or entry.firstSeen, entry.firstSeen) end
            if entry.lastSeen then existing.lastSeen = math.max(existing.lastSeen or entry.lastSeen, entry.lastSeen) end
            existing.favorite = (existing.favorite or entry.favorite) and true or nil
        else
            staged.records[id] = entry
        end
    end
    for id, entry in pairs(incoming.overrides) do
        if not staged.overrides[id] then staged.overrides[id] = entry end
    end
end

local function CheckMergedCount(records, limit, label)
    local count = 0
    for _ in pairs(records) do
        count = count + 1
        if count > limit then
            error("Merging would exceed the backup limit of " .. limit .. " " .. label .. ".", 0)
        end
    end
end

local function PlanRestore(snapshot, selection, mode, localBackup)
    local sections = Validate(snapshot, localBackup, localBackup and selection or nil).sections
    local plan = {}
    for key in pairs(ALL_SECTIONS) do
        if selection[key] then
            if not sections[key] then Invalid() end
            plan[key] = sections[key]
        end
    end
    if not next(plan) then error("Select at least one section to restore.", 0) end

    local skipped = 0
    if mode == "merge" then
        local current = Capture(selection, true).sections
        if plan.players then
            skipped = ns.MergeBackupPlayers(current.players.records, plan.players.records)
            if not localBackup then
                CheckMergedCount(current.players.records, MAX_PLAYERS, "player records")
                -- A merge can also combine maps within one player record.
                current.players.records = Map(current.players.records, Name, Player, MAX_PLAYERS)
            end
            plan.players = current.players
        end
        if plan.npcs then
            MergeNPCs(current.npcs, plan.npcs)
            if not localBackup then
                CheckMergedCount(current.npcs.records, MAX_NPCS, "saved NPCs")
                CheckMergedCount(current.npcs.overrides, MAX_NPCS, "NPC overrides")
            end
            plan.npcs = current.npcs
        end
    end
    return plan, skipped
end

function ns.ApplyBackup(snapshot, selection, mode, localBackup)
    if mode ~= "merge" and mode ~= "replace" then return nil, "Choose how to restore this backup." end
    local ok, plan, skipped = pcall(PlanRestore, snapshot, selection, mode, localBackup)
    if not ok then return nil, plan end
    if plan.settings then PreserveOmittedTracking(plan.settings) end
    local scans = plan.settings and ns.GetInitialTrackingScans(plan.settings) or {}
    local checkpoint = {settings = plan.settings ~= nil, players = plan.players ~= nil or #scans > 0,
        npcs = plan.npcs ~= nil}
    local reason = localBackup and "Before restoring a backup" or "Before importing"
    local point, message = ns.CreateRestorePoint("automatic", reason, checkpoint)
    if not point then return nil, "Could not create a restore point. " .. message end

    if plan.players then
        KnownPlayersDB.players = plan.players.records
        if plan.players.bnet then KnownPlayersDB.bnetCharacters = plan.players.bnet end
        ns.InvalidateIdentityIndex()
        ns.PruneUnlinkedBattleNetData()
    end
    if plan.npcs then
        KnownPlayersDB.npcs = plan.npcs.records
        KnownPlayersDB.npcOverrides = plan.npcs.overrides
    end
    local refreshFailed = false
    local function Refresh(callback)
        if callback then
            local refreshed, err = pcall(callback)
            if not refreshed then
                refreshFailed = true
                if geterrorhandler then pcall(function() geterrorhandler()(err) end) end
            end
        end
    end

    if plan.players or plan.npcs then Refresh(ns.ClearRemovalUndo) end
    if plan.settings then
        ns.ApplyKnownPlayersSettings(plan.settings, scans, Refresh)
    else
        Refresh(ns.RefreshKnownNameplates)
        Refresh(ns.RefreshPlayerListWindows)
    end
    return true, skipped, refreshFailed
end

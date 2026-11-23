local _, ns = ...

local FORMAT = 1
local PREFIX = "KnownPlayers:"
local MAX_EXPORT_BYTES = 4 * 1024 * 1024
local MAX_PLAYERS = 25000
local MAX_NPCS = 10000
local ALL_SECTIONS = {settings = true, players = true, npcs = true}

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
        if count > limit then Invalid() end
        copy[keyCheck(key)] = valueCheck(entry)
    end
    return copy
end

local function TimeMap(value) return Map(value, Name, Stamp, 64) end
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
        trackGroup = Flags, trackBattleNetAssociations = Boolean, showMinimapButton = Boolean,
        knownOnlyNameplates = Boolean, filterNPCNameplates = Boolean,
        nameDisplayMode = NameMode, npcNameDisplayMode = NameMode,
        playerHealthBarMode = HealthMode, npcHealthBarMode = HealthMode,
        showGuildInNamesOnly = Boolean, showNPCTitle = Boolean,
        nameplateCategoryColors = Colors, npcNameplateCategoryColors = Colors,
        nameplateColorOrder = Order, npcNameplateColorOrder = Order,
        npcServiceCategories = Flags,
    }
    for _, category in ipairs(ns.PlayerCategories) do
        if category.tracking then fields[category.tracking] = Boolean end
    end
    return Fields(value, fields)
end

local function Membership(value) return Fields(value, {firstSeen = Stamp, lastSeen = Stamp}) end

local function Player(value)
    local player = Fields(value, {
        displayName = Name, realm = Name, guid = Guid, class = Name, classToken = Name,
        race = Name, raceAtlas = Name, note = Note, tags = Note, favorite = Boolean,
        categories = Flags, lastSeen = Stamp, categoryFirstSeen = TimeMap, categoryLastSeen = TimeMap,
        guildMemberships = function(memberships) return Map(memberships, Name, Membership, 200) end,
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
        end, MAX_PLAYERS)
    end, 3000)
end

local function Validate(snapshot, localBackup)
    Object(snapshot)
    if snapshot.version ~= FORMAT then error("This backup format is unsupported.", 0) end
    local sections = Object(snapshot.sections)
    local copy = {version = FORMAT, created = Stamp(snapshot.created), sections = {}}
    if sections.settings ~= nil then copy.sections.settings = Settings(sections.settings) end
    if sections.players ~= nil then
        local data = Object(sections.players)
        copy.sections.players = {records = Map(data.records, Name, Player, MAX_PLAYERS)}
        if localBackup and data.bnet ~= nil then copy.sections.players.bnet = BattleNet(data.bnet) end
    end
    if sections.npcs ~= nil then
        local data = Object(sections.npcs)
        copy.sections.npcs = {
            records = Map(data.records, NPCID, NPC, MAX_NPCS),
            overrides = Map(data.overrides, NPCID, Override, MAX_NPCS),
        }
    end
    if not next(copy.sections) then error("Select at least one section to back up.", 0) end
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

function ns.CreateRestorePoint(kind, reason)
    local ok, snapshot = pcall(Capture, ALL_SECTIONS, true)
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

function ns.BackupBeforeChange(reason)
    local point, message = ns.CreateRestorePoint("automatic", reason)
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
    return table.concat(items, ", ")
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

local function PlanRestore(snapshot, selection, mode, localBackup)
    local sections = Validate(snapshot, localBackup).sections
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
            plan.players = current.players
        end
        if plan.npcs then
            MergeNPCs(current.npcs, plan.npcs)
            plan.npcs = current.npcs
        end
    end
    return plan, skipped
end

function ns.ApplyBackup(snapshot, selection, mode, localBackup)
    if mode ~= "merge" and mode ~= "replace" then return nil, "Choose how to restore this backup." end
    local ok, plan, skipped = pcall(PlanRestore, snapshot, selection, mode, localBackup)
    if not ok then return nil, plan end
    local reason = localBackup and "Before restoring a backup" or "Before importing"
    local point, message = ns.CreateRestorePoint("automatic", reason)
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
    if plan.players or plan.npcs then ns.ClearRemovalUndo() end
    if plan.settings then
        ns.ApplyKnownPlayersSettings(plan.settings)
    else
        ns.RefreshKnownNameplates()
        ns.RefreshPlayerListWindows()
    end
    return true, skipped
end

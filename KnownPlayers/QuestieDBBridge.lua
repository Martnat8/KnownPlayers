local addonName, ns = ...

-- NPC classifications come exclusively from QuestieDB's public API (contract 4).
-- QuestieDB is separately installed and its database is never redistributed
-- or written into KnownPlayers SavedVariables.
local provider
local providerStatus = "QuestieDB not connected - automatic NPC categories unavailable"
local servicesCache = {}

local FLAGS_TO_CATEGORIES = {
    VENDOR = "vendor", TRAINER = "trainer", BANKER = "banker",
    AUCTIONEER = "auctioneer", FLIGHT_MASTER = "flight",
    INNKEEPER = "innkeeper", REPAIR = "repair", QUEST_GIVER = "quest",
}

local function HasBit(value, flag)
    return type(value) == "number" and type(flag) == "number" and flag > 0
        and math.floor(value / flag) % 2 >= 1
end

local function ResolveProvider()
    local lib = LibQuestieDB
    if provider and provider.lib == lib then return provider end
    if provider then
        provider = nil
        servicesCache = {}
    end
    -- Do not cache absence: an optional addon could load later in the session.
    if type(lib) ~= "table" then
        providerStatus = "QuestieDB not connected - automatic NPC categories unavailable"
        return nil
    end
    local npc = lib.Npc
    if type(npc) ~= "table" or type(npc.GetAll) ~= "function"
        or type(lib.RequireContract) ~= "function" then
        providerStatus = "QuestieDB API unavailable - automatic NPC categories unavailable"
        return nil
    end
    local ok, supported = pcall(lib.RequireContract, 4)
    if not ok or supported ~= true then
        providerStatus = "QuestieDB requires API contract 4"
        return nil
    end
    local flags = type(lib.Enum) == "table" and lib.Enum.npcFlags
    if type(flags) ~= "table" then
        providerStatus = "QuestieDB NPC service flags unavailable"
        return nil
    end
    provider = { lib = lib, npc = npc, flags = flags }
    providerStatus = "QuestieDB connected"
    return provider
end

function ns.GetNPCServiceInfo(id)
    id = tostring(id or "")
    local numericID = tonumber(id)
    if not id:match("^%d+$") or not numericID or numericID <= 0 or numericID % 1 ~= 0 then return nil end
    local active = ResolveProvider()
    if not active then return nil end
    local cached = servicesCache[id]
    if cached ~= nil then return cached or nil end

    local ok, values = pcall(active.npc.GetAll, numericID, {
        "npcFlags", "questStarts", "questEnds",
    })
    -- Cache unknown IDs while allowing a failed lookup to be retried.
    if ok and values == nil then servicesCache[id] = false end
    if not ok or type(values) ~= "table" then return nil end

    local found = {}
    local flags = tonumber(values[1]) or 0
    for flagKey, category in pairs(FLAGS_TO_CATEGORIES) do
        if HasBit(flags, active.flags[flagKey]) then found[category] = true end
    end
    -- Quest start/end relationships are more inclusive than just QUEST_GIVER.
    if type(values[2]) == "table" and next(values[2])
        or type(values[3]) == "table" and next(values[3]) then
        found.quest = true
    end
    -- An empty table identifies a known NPC with no supported service roles.
    servicesCache[id] = found
    return found
end

function ns.IsQuestieDBConnected()
    return ResolveProvider() ~= nil
end

function ns.GetNPCDataSourceStatus()
    ResolveProvider()
    return providerStatus
end

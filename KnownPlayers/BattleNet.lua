local addonName, ns = ...

-- BattleTags are used only for persistent associations that actually connect
-- to a directly known character. Unlinked friend observations remain in RAM
-- until the client closes, and are not written to SavedVariables.
local pending = {}
local associationDirty = true
local indexedMembersByKey, indexedMembersByGUID = {}, {}
local linkedGroups = {}

local function IsPlayerGUID(guid)
    return ns.SafePlayerGUID(guid) ~= nil
end

local function IsCharacterName(name)
    return ns.SafeString(name) ~= nil and name ~= UNKNOWNOBJECT
end

local function ValidBattleTag(tag)
    local safe = ns.SafeString(tag)
    return safe ~= nil and safe:find("#", 1, true) ~= nil
end

function ns.InvalidateBattleNetIndex()
    associationDirty = true
end

local function DirectRecord(key, observed)
    return ns.FindDirectRecord and ns.FindDirectRecord(key, observed and observed.guid) or nil
end

local function HasStoredCategory(record)
    return type(record) == "table" and type(record.categories) == "table"
        and next(record.categories) ~= nil
end

local function HasDirectAnchor(members, hasCategory)
    if type(members) ~= "table" then return false end
    for key, entry in pairs(members) do
        if type(entry) == "table" and hasCategory(DirectRecord(key, entry)) then
            return true
        end
    end
    return false
end

local function MergeObservations(destination, source)
    if type(source) ~= "table" then return end
    for key, entry in pairs(source) do
        if type(entry) == "table" then
            if type(destination[key]) ~= "table" then
                destination[key] = entry
            else
                local saved = destination[key]
                if type(entry.firstObserved) == "number" and
                    (type(saved.firstObserved) ~= "number" or entry.firstObserved < saved.firstObserved) then
                    saved.firstObserved = entry.firstObserved
                end
                if type(entry.lastObserved) == "number" and
                    (type(saved.lastObserved) ~= "number" or entry.lastObserved > saved.lastObserved) then
                    saved.lastObserved = entry.lastObserved
                end
                saved.guid = saved.guid or entry.guid
            end
        end
    end
end

-- Existing saved groups that do not connect to any known player are removed
-- from disk. They are still available transiently in this play session so
-- linking a character later can promote the associated observations.
function ns.PruneUnlinkedBattleNetData()
    if type(KnownPlayersDB) ~= "table" then return end
    local groups = KnownPlayersDB.bnetCharacters or {}
    for tag, members in pairs(groups) do
        if type(members) ~= "table" or not HasDirectAnchor(members, HasStoredCategory) then
            if type(members) == "table" then
                pending[tag] = pending[tag] or {}
                MergeObservations(pending[tag], members)
            end
            groups[tag] = nil
        end
    end
    ns.InvalidateBattleNetIndex()
end

function ns.PromotePendingBattleNetObservations()
    if not KnownPlayersDB then return end
    local stored = KnownPlayersDB.bnetCharacters or {}
    KnownPlayersDB.bnetCharacters = stored
    local changed = false
    for tag, members in pairs(pending) do
        local group = stored[tag]
        if HasDirectAnchor(members, ns.HasPlayerCategory) or HasDirectAnchor(group, ns.HasPlayerCategory) then
            group = type(group) == "table" and group or {}
            MergeObservations(group, members)
            stored[tag] = group
            pending[tag] = nil
            changed = true
        end
    end
    if changed then ns.InvalidateBattleNetIndex() end
end

local function ObserveCharacter(tag, game)
    if type(game) ~= "table" or game.isOnline == false then return end
    if game.clientProgram ~= "WoW" and game.clientProgram ~= "WOW" then return end
    if not IsCharacterName(game.characterName) or not IsCharacterName(game.realmName) then return end
    local key = game.characterName .. "-" .. game.realmName
    local stored = KnownPlayersDB.bnetCharacters
    local group = stored[tag]
    if type(group) ~= "table" then
        group = pending[tag]
        if type(group) ~= "table" then
            group = {}
            pending[tag] = group
        end
    end
    local entry = group[key]
    if type(entry) ~= "table" then
        entry = { firstObserved = time() }
        group[key] = entry
    end
    entry.name = game.characterName
    entry.realm = game.realmName
    if IsPlayerGUID(game.playerGuid) then entry.guid = game.playerGuid end
    entry.lastObserved = time()
    ns.InvalidateBattleNetIndex()
end

function ns.ScanBattleNetFriends()
    if not KnownPlayersDB or not KnownPlayersSettings
        or not KnownPlayersSettings.trackBattleNetAssociations
        or type(BNGetNumFriends) ~= "function"
        or type(C_BattleNet) ~= "table"
        or type(C_BattleNet.GetFriendAccountInfo) ~= "function" then return 0 end

    KnownPlayersDB.bnetCharacters = KnownPlayersDB.bnetCharacters or {}
    local processed = 0
    for i = 1, (BNGetNumFriends() or 0) do
        local ok, account = pcall(C_BattleNet.GetFriendAccountInfo, i)
        if ok and type(account) == "table" and ValidBattleTag(account.battleTag) then
            local tag = account.battleTag
            ObserveCharacter(tag, account.gameAccountInfo)
            if type(C_BattleNet.GetFriendNumGameAccounts) == "function"
                and type(C_BattleNet.GetFriendGameAccountInfo) == "function" then
                local success, count = pcall(C_BattleNet.GetFriendNumGameAccounts, i)
                if success and type(count) == "number" then
                    for j = 1, math.min(count, 20) do
                        local gotGame, game = pcall(C_BattleNet.GetFriendGameAccountInfo, i, j)
                        if gotGame then ObserveCharacter(tag, game) end
                    end
                end
            end
            processed = processed + 1
        end
    end
    ns.PromotePendingBattleNetObservations()
    return processed
end

local function IsTrackingEnabled(category)
    if not KnownPlayersSettings then return false end
    if category == "party" or category == "raid" then
        return type(KnownPlayersSettings.trackGroup) == "table"
            and KnownPlayersSettings.trackGroup[category] == true
    end
    local setting = {
        trade = "trackTrades", guild = "trackGuild", whisper = "trackWhispers",
        target = "trackTargets", inspect = "trackInspects",
        manual = "trackManual",
    }
    local key = setting[category]
    return key ~= nil and KnownPlayersSettings[key] == true
end

local function HasEnabledCategory(record)
    if not HasStoredCategory(record) then return false end
    for category, present in pairs(record.categories) do
        if present and IsTrackingEnabled(category) then return true end
    end
    return false
end

-- Cache which characters belong to which BNet friend. Rebuild only on
-- observation changes or direct record changes, never per nameplate tick.
local function BuildAssociationIndex()
    if not associationDirty then return end
    indexedMembersByKey, indexedMembersByGUID, linkedGroups = {}, {}, {}
    for tag, group in pairs(KnownPlayersDB.bnetCharacters or {}) do
        if type(group) == "table" then
            local direct = {}
            for key, observed in pairs(group) do
                if type(observed) == "table" then
                    local record = DirectRecord(key, observed)
                    if ns.HasPlayerCategory(record) then direct[#direct+1] = record end
                end
            end
            if #direct > 0 then
                local summary = { members = group, direct = direct, tag = tag }
                linkedGroups[#linkedGroups+1] = summary
                for key, observed in pairs(group) do
                    if type(observed) == "table" then
                        indexedMembersByKey[key] = summary
                        if IsPlayerGUID(observed.guid) then
                            indexedMembersByGUID[observed.guid] = summary
                        end
                    end
                end
            end
        end
    end
    associationDirty = false
end

local function AssociatedGroup(name, guid)
    BuildAssociationIndex()
    if IsPlayerGUID(guid) and indexedMembersByGUID[guid] then
        return indexedMembersByGUID[guid]
    end
    local group = indexedMembersByKey[name]
    if group and IsPlayerGUID(guid) then
        local observed = group.members[name]
        if observed and observed.guid and observed.guid ~= guid then return nil end
    end
    return group
end

local function EnabledAnchor(group)
    if not group then return false end
    for _, record in ipairs(group.direct) do
        if HasEnabledCategory(record) then return true end
    end
    return false
end

function ns.IsAssociatedCharacter(name, guid)
    if not KnownPlayersSettings or not KnownPlayersSettings.trackBattleNetAssociations then return false end
    return EnabledAnchor(AssociatedGroup(name, guid))
end

function ns.IsKnownOrAssociated(name, guid)
    if not KnownPlayersDB or not KnownPlayersSettings or type(name) ~= "string" then return false end
    if HasEnabledCategory(ns.FindDirectRecord(name, guid)) then return true end
    return ns.IsAssociatedCharacter(name, guid)
end

function ns.GetAssociatedCharacters()
    local result = {}
    if not KnownPlayersDB or not KnownPlayersSettings
        or not KnownPlayersSettings.trackBattleNetAssociations then return result end
    BuildAssociationIndex()
    for _, group in ipairs(linkedGroups) do
        local anchor, anchorKey
        for key, observed in pairs(group.members) do
            local directKey = type(observed) == "table" and (ns.FindDirectKeyByGUID(observed.guid)
                or ns.FindDirectKeyByName(key, observed.guid))
            local direct = directKey and ns.GetPlayer(directKey)
            if ns.HasPlayerCategory(direct) then
                anchor = direct.displayName or observed.name or directKey
                anchorKey = directKey
                break
            end
        end
        if anchor then
            for key, observed in pairs(group.members) do
                if type(observed) == "table" and not ns.HasPlayerCategory(DirectRecord(key, observed))
                    and IsCharacterName(observed.name) then
                    result[#result+1] = {
                        key = key, name = observed.name, realm = observed.realm,
                        linkedTo = anchor, linkedPlayerKey = anchorKey, battleTag = group.tag,
                        firstSeen = observed.firstObserved,
                    }
                end
            end
        end
    end
    return result
end

function ns.CountAssociatedCharacters()
    return #ns.GetAssociatedCharacters()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("BN_CONNECTED")
frame:RegisterEvent("BN_FRIEND_INFO_CHANGED")
frame:RegisterEvent("BN_FRIEND_ACCOUNT_ONLINE")
frame:RegisterEvent("BN_FRIEND_LIST_SIZE_CHANGED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function()
    if KnownPlayersDB and KnownPlayersSettings then ns.ScanBattleNetFriends() end
end)

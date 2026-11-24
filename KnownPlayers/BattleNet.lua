local addonName, ns = ...

-- BattleTags are used only for persistent associations that actually connect
-- to a directly known character. Unlinked friend observations remain in RAM
-- until the client closes, and are not written to SavedVariables.
local pending = {}
local friendListReady = false
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
                ns.MergePlayerAppearance(saved, entry)
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
        if type(members) ~= "table" or not HasDirectAnchor(members, ns.HasStoredPlayerCategory) then
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
        if HasDirectAnchor(members, ns.HasStoredPlayerCategory) or HasDirectAnchor(group, ns.HasStoredPlayerCategory) then
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
    ns.SetPlayerClass(entry, game.className, game.classFilename)
    ns.SetPlayerRace(entry, game.raceName)
    ns.RefreshPlayerAppearance(entry)
    entry.lastObserved = time()
    ns.InvalidateBattleNetIndex()
end

local function ReadFriendCount()
    local connected, online = pcall(BNConnected)
    if not connected or not ns.IsAccessibleValue(online) or online ~= true then return nil end
    local ok, count = pcall(BNGetNumFriends)
    if ok and ns.IsAccessibleValue(count) and type(count) == "number" and count >= 0 then return count end
end

function ns.ScanBattleNetFriends(rosterUpdated)
    if not KnownPlayersDB or not KnownPlayersSettings
        or not KnownPlayersSettings.trackBattleNetAssociations
        or type(BNGetNumFriends) ~= "function"
        or type(C_BattleNet) ~= "table"
        or type(C_BattleNet.GetFriendAccountInfo) ~= "function" then return 0 end
    local total = ReadFriendCount()
    if total == nil then return 0 end

    KnownPlayersDB.bnetCharacters = KnownPlayersDB.bnetCharacters or {}
    local processed, friends = 0, {}
    for i = 1, total do
        local ok, account = pcall(C_BattleNet.GetFriendAccountInfo, i)
        if ok and ns.IsAccessibleValue(account) and type(account) == "table"
            and ValidBattleTag(account.battleTag) and not friends[account.battleTag] then
            local tag = account.battleTag
            friends[tag] = true
            ObserveCharacter(tag, account.gameAccountInfo)
            if type(C_BattleNet.GetFriendNumGameAccounts) == "function"
                and type(C_BattleNet.GetFriendGameAccountInfo) == "function" then
                local success, count = pcall(C_BattleNet.GetFriendNumGameAccounts, i)
                if success and ns.IsAccessibleValue(count) and type(count) == "number" then
                    for j = 1, math.min(count, 20) do
                        local gotGame, game = pcall(C_BattleNet.GetFriendGameAccountInfo, i, j)
                        if gotGame then ObserveCharacter(tag, game) end
                    end
                end
            end
            processed = processed + 1
        end
    end
    local removed = false
    -- An empty response before the list is initialized can also mean loading.
    if processed == total and ReadFriendCount() == total and (rosterUpdated or friendListReady or total > 0) then
        friendListReady = true
        for tag in pairs(KnownPlayersDB.bnetCharacters) do
            if not friends[tag] then
                KnownPlayersDB.bnetCharacters[tag] = nil
                removed = true
            end
        end
        for tag in pairs(pending) do
            if not friends[tag] then pending[tag] = nil end
        end
    end
    if removed then ns.InvalidateBattleNetIndex() end
    ns.PromotePendingBattleNetObservations()
    return processed, removed
end

local function HasEnabledCategory(record)
    if not record then return false end
    for _, category in ipairs(ns.PlayerCategories) do
        if ns.PlayerHasCategory(record, category.key) and ns.CategoryTrackingEnabled(category.key) then return true end
    end
    return false
end

-- Cache which characters belong to which BNet friend. Rebuild only on
-- observation changes or direct record changes, never per nameplate tick.
local function AssociationNameKey(name, realm)
    name = ns.SafeString(name)
    if name then return (ns.NormalizePlayerKey(name, realm) or name):lower() end
end

local function IndexAssociatedName(key, observed, group)
    local name = AssociationNameKey(key, observed.realm)
    if not name then return end
    local existing = indexedMembersByKey[name]
    local guid = ns.SafePlayerGUID(observed.guid)
    if existing == nil then
        indexedMembersByKey[name] = {group = group, guid = guid}
    elseif existing and (existing.group ~= group or (guid and existing.guid and guid ~= existing.guid)) then
        indexedMembersByKey[name] = false
    elseif existing and guid then
        existing.guid = guid
    end
end

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
                        IndexAssociatedName(key, observed, summary)
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
    local entry = indexedMembersByKey[AssociationNameKey(name)]
    if entry and (not IsPlayerGUID(guid) or not entry.guid or entry.guid == guid) then return entry.group end
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
    if not ns.SafePlayerGUID(guid) then
        local _, ambiguous = ns.FindDirectKeyByName(name)
        if ambiguous then return false end
    end
    return EnabledAnchor(AssociatedGroup(name, guid))
end

function ns.IsKnownOrAssociated(name, guid)
    name, guid = ns.SafeString(name), ns.SafePlayerGUID(guid)
    if not KnownPlayersDB or not KnownPlayersSettings or not (name or guid) then return false end
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
            if HasEnabledCategory(direct) then
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
                        appearance = observed,
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
frame:RegisterEvent("BN_DISCONNECTED")
frame:RegisterEvent("BN_FRIEND_INFO_CHANGED")
frame:RegisterEvent("BN_FRIEND_ACCOUNT_ONLINE")
frame:RegisterEvent("BN_FRIEND_LIST_SIZE_CHANGED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(_, event)
    if event == "BN_DISCONNECTED" then friendListReady = false; return end
    local _, removed = ns.ScanBattleNetFriends(event == "BN_FRIEND_LIST_SIZE_CHANGED")
    if removed then
        ns.RefreshKnownNameplates()
        ns.RefreshPlayerListWindows()
    end
end)

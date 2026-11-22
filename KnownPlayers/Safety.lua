local addonName, ns = ...

-- Secret values can report their ordinary Lua type. Check accessibility before
-- comparing, indexing, concatenating or parsing data returned by game APIs.
function ns.IsAccessibleValue(value)
    if type(canaccessvalue) == "function" then
        local ok, accessible = pcall(canaccessvalue, value)
        if not ok or accessible ~= true then return false end
    elseif type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or secret then return false end
    end
    return true
end

function ns.SafeString(value)
    if not ns.IsAccessibleValue(value) then return nil end
    if type(value) ~= "string" or value == "" then return nil end
    return value
end

function ns.SafePlayerGUID(value)
    local guid = ns.SafeString(value)
    if guid and guid:match("^Player%-") then return guid end
    return nil
end

function ns.SafeUnitGUID(unit)
    if not unit or type(UnitGUID) ~= "function" then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok then return nil end
    return ns.SafeString(guid)
end

function ns.IsPlayerMinion(unit)
    if type(UnitIsMinion) ~= "function" then return false end
    local ok, result = pcall(UnitIsMinion, unit)
    return ok and ns.IsAccessibleValue(result) and result == true
end

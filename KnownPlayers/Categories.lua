local _, ns = ...

ns.PlayerCategories = {
    {key = "trade", label = "Trade", tracking = "trackTrades"},
    {key = "party", label = "Party", group = "party"},
    {key = "raid", label = "Raid", group = "raid"},
    {key = "guild", label = "Guild", tracking = "trackGuild"},
    {key = "whisper", label = "Whisper", tracking = "trackWhispers"},
    {key = "target", label = "Target", tracking = "trackTargets"},
    {key = "inspect", label = "Inspect", tracking = "trackInspects"},
    {key = "manual", label = "Manually Remembered", tracking = "trackManual"},
    {key = "avoid", label = "Avoid", tracking = "trackAvoid"},
}

local categories = {}
for _, category in ipairs(ns.PlayerCategories) do categories[category.key] = category end
ns.PlayerCategoryByKey = categories
ns.AssociatedCategory = {key = "associated", label = "Known Battle.net Alts", tracking = "trackBattleNetAssociations"}

function ns.GetPlayerCategoryLabel(key)
    if key == "avoid" and KnownPlayersSettings and KnownPlayersSettings.useAlternateAvoidName then
        return "Shitbags"
    end
    local category = key == "associated" and ns.AssociatedCategory or categories[key]
    return category and category.label
end

function ns.IsPlayerCategory(key)
    return categories[key] ~= nil
end

function ns.CategoryTrackingEnabled(key, settings)
    settings = settings or KnownPlayersSettings
    local category = key == "associated" and ns.AssociatedCategory or categories[key]
    if not settings or not category then return false end
    if category.group then
        return type(settings.trackGroup) == "table" and settings.trackGroup[category.group] == true
    end
    return settings[category.tracking] == true
end

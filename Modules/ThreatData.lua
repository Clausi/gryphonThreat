local _, ns = ...
local Compat = ns.Compat
local ThreatData = ns:RegisterModule("ThreatData")

-- Collects the threat of the own group (player, party or raid, with pets) on one hostile unit.
-- Blizzard's damage meter gets its data from C_DamageMeter; threat has no such API, so it is read
-- per group member with UnitDetailedThreatSituation.

local MAX_PARTY_MEMBERS = 4
local MAX_RAID_MEMBERS = 40

-- Reused between updates, the list is rebuilt several times a second in combat.
local entries = {}
local entryPool = {}

-- Hostile unit whose threat is shown: the target, or where the client allows it the target of a
-- friendly target (Compat.CanUseTargetOfTarget). nil without a hostile unit.
function ThreatData:GetMobUnit()
    if UnitExists("target") and UnitCanAttack("player", "target") then
        return "target"
    end
    if Compat.CanUseTargetOfTarget() and UnitExists("targettarget")
        and UnitCanAttack("player", "targettarget") then
        return "targettarget"
    end
    return nil
end

-- UnitIsUnit may return a secret value, so the player is found by unit token.
local function AddEntry(unit, mobUnit, isPet, isPlayer)
    local isTanking, status, percent, rawPercent, threat, isSecret = Compat.GetThreat(unit, mobUnit)
    if isSecret == nil then
        return
    end

    local entry = table.remove(entryPool) or {}
    entry.unit = unit
    entry.name = Compat.GetUnitDisplayName(unit)
    entry.classFilename = not isPet and Compat.GetUnitClassFilename(unit) or nil
    entry.isPet = isPet
    entry.isPlayer = isPlayer
    entry.isTanking = isTanking
    entry.status = status
    entry.percent = percent
    entry.rawPercent = rawPercent
    entry.threat = threat
    entry.isSecret = isSecret
    entries[#entries + 1] = entry
end

local function AddUnit(unit, petUnit, mobUnit, isPlayer)
    if UnitExists(unit) then
        AddEntry(unit, mobUnit, false, isPlayer)
    end
    if UnitExists(petUnit) then
        AddEntry(petUnit, mobUnit, true, false)
    end
end

-- Highest threat first; the tank (100 %) before everyone else.
local function CompareEntries(a, b)
    if a.threat ~= b.threat then
        return a.threat > b.threat
    end
    return a.percent > b.percent
end

-- Threat of all group members on mobUnit, highest first. Each entry has unit, name,
-- classFilename (nil for pets), isPet, isPlayer, isTanking, status, percent (0-100), rawPercent,
-- threat (raw value as shown in-game) and isSecret. The list is reused by the next call.
-- If any value is secret, the list can not be sorted and keeps the group order (hasSecret = true).
function ThreatData:GetThreatList(mobUnit)
    for i = #entries, 1, -1 do
        entryPool[#entryPool + 1] = entries[i]
        entries[i] = nil
    end
    if not mobUnit then
        return entries, false
    end

    if IsInRaid() then
        local playerIndex = UnitInRaid("player")
        for i = 1, MAX_RAID_MEMBERS do
            AddUnit("raid" .. i, "raidpet" .. i, mobUnit, i == playerIndex)
        end
    else
        AddUnit("player", "pet", mobUnit, true)
        for i = 1, MAX_PARTY_MEMBERS do
            AddUnit("party" .. i, "partypet" .. i, mobUnit, false)
        end
    end

    local hasSecret = false
    for i = 1, #entries do
        if entries[i].isSecret then
            hasSecret = true
            break
        end
    end
    if not hasSecret then
        table.sort(entries, CompareEntries)
    end
    return entries, hasSecret
end

-- Aggro is pulled at 110 % of the threat of the unit with aggro in melee range, at 130 % beyond it.
local PULL_FACTOR_MELEE = 1.1
local PULL_FACTOR_RANGED = 1.3
-- rawPercent / percent is 1.1 in melee range and 1.3 beyond it; anything above this is ranged.
local RANGED_RATIO = 1.2

-- Threat the player still needs to pull aggro, and the player's percentage of the pull threshold
-- (0-100). nil if the player has aggro, nobody has it or the values are secret.
function ThreatData:GetPullAggro(list, hasSecret)
    if hasSecret then
        return nil
    end
    local tank, player
    for _, entry in ipairs(list) do
        if entry.isTanking then
            tank = entry
        end
        if entry.isPlayer then
            player = entry
        end
    end
    if not tank or tank.isPlayer then
        return nil
    end

    local factor = PULL_FACTOR_MELEE
    if player and player.rawPercent and player.percent > 0
        and player.rawPercent / player.percent > RANGED_RATIO then
        factor = PULL_FACTOR_RANGED
    end
    local playerThreat = player and player.threat or 0
    local needed = math.max(0, tank.threat * factor - playerThreat)
    return needed, player and player.percent or 0
end

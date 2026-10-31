local _, ns = ...

-- Differences between the supported clients (Retail, later Forever), in one place. Detects the
-- APIs a client has instead of comparing version numbers. Blizzard UI reference: the live and
-- forever branches of Gethe/wow-ui-source.
local Compat = {}
ns.Compat = Compat

-- Forever names are "First Surname", unique per region, without a realm part. Other clients use
-- "Name-Realm". RegionalUniqueNamesEnabled() is the check Blizzard's own NameUtil uses.
function Compat.HasRealmNames()
    return not (RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled())
end

local function IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end
Compat.IsSecret = IsSecret

-- Threat of unit on mobUnit, or nil if unit is not on the mob's threat table:
--   isTanking, status (0-3), scaledPercentage (0-100, 100 = pulls aggro), rawPercentage (threat
--   relative to the unit with aggro, 110 % pulls in melee range, 130 % at range), rawThreat, isSecret
-- On Retail and Forever the values are secret in restricted content
-- (C_Secrets.ShouldUnitThreatValuesBeSecret). Secret values are returned unchanged; the caller may
-- only pass them to widgets (StatusBar:SetValue, FontString:SetFormattedText), not compare them.
function Compat.GetThreat(unit, mobUnit)
    local isTanking, status, scaledPercentage, rawPercentage, rawThreat = UnitDetailedThreatSituation(unit, mobUnit)
    if IsSecret(scaledPercentage) or IsSecret(rawThreat) then
        return isTanking, status, scaledPercentage, rawPercentage, rawThreat, true
    end
    if scaledPercentage == nil then
        return nil
    end
    -- The API sometimes returns less than 100 % for the unit that has aggro.
    if isTanking then
        scaledPercentage, rawPercentage = 100, 100
    end
    return isTanking, status, scaledPercentage, rawPercentage, rawThreat, false
end

-- Whether the threat on the target of a friendly target (e.g. the mob the tank fights while a
-- healer targets the tank) can be shown. Clients with secret values (Retail, Forever) return secret
-- threat values for "targettarget", which can not be sorted, and send no UNIT_THREAT_LIST_UPDATE
-- for it.
function Compat.CanUseTargetOfTarget()
    return C_Secrets == nil
end

-- Name of a unit to show, the first name on Forever, UNKNOWN without a name. May be a secret value
-- on restricted units, which is returned unchanged (no boolean test on it).
function Compat.GetUnitDisplayName(unit)
    local name = UnitName(unit)
    if IsSecret(name) then
        return name
    end
    return name or UNKNOWN
end

-- Class file name ("MAGE") of a unit, or nil if unknown or secret (restricted unit identity).
function Compat.GetUnitClassFilename(unit)
    local _, classFilename = UnitClass(unit)
    if classFilename == nil or IsSecret(classFilename) then
        return nil
    end
    return classFilename
end

-- Look of Blizzard's damage meter (Blizzard_DamageMeter), which the threat window copies. The
-- settings that Edit Mode changes (bar height, padding, ...) are in ThreatWindow.LAYOUT_DEFAULTS.
-- Atlases and fonts are the same on Retail and Forever. The bar colors are set by the client
-- (DAMAGE_METER_STATUS_BAR_*_COLOR); the fallbacks only apply if a client does not have them.
local meterStyle

function Compat.GetMeterStyle()
    if meterStyle then
        return meterStyle
    end
    meterStyle = {
        -- DamageMeterSessionWindow.xml
        headerAtlas = "ui-damagemeters-header-bar",
        headerHeight = 32,
        headerFont = "GameFontNormalMed1",
        backgroundAtlas = "damagemeters-background",
        collapseAtlas = "ui-questtrackerbutton-collapse-all",
        collapsePressedAtlas = "ui-questtrackerbutton-collapse-all-pressed",
        expandAtlas = "ui-questtrackerbutton-expand-all",
        expandPressedAtlas = "ui-questtrackerbutton-expand-all-pressed",
        minimizeHighlightAtlas = "ui-questtrackerbutton-red-highlight",
        settingsAtlas = "common-dropdown-a-button-settings-shadowless",
        settingsHoverAtlas = "common-dropdown-a-button-settings-hover-shadowless",
        settingsPressedAtlas = "common-dropdown-a-button-settings-pressed-shadowless",
        settingsOpenAtlas = "common-dropdown-a-button-settings-open-shadowless",
        resizeAtlas = "damagemeters-scalehandle",
        resizeHoverAtlas = "damagemeters-scalehandle-hover",
        resizePressedAtlas = "damagemeters-scalehandle-pressed",
        -- DamageMeterEntry.xml
        barAtlas = "UI-HUD-CoolDownManager-Bar",
        barBackgroundAtlas = "ui-damagemeters-bar-shadowbg",
        barBackgroundEdgeAtlas = "ui-damagemeters-bar-shadowedge",
        barBorderedBackgroundAtlas = "UI-HUD-CoolDownManager-Bar-BG",
        barFont = "NumberFontNormal",
        -- Ranges of the Edit Mode sliders (EditModeSettingDisplayInfo.lua)
        minWidth = 200,
        minHeight = 120,
        maxWidth = 600,
        maxHeight = 400,
        defaultColor = DAMAGE_METER_STATUS_BAR_DEFAULT_COLOR or CreateColor(0.5, 0.5, 0.5),
        creatureColor = DAMAGE_METER_STATUS_BAR_CREATURE_COLOR or CreateColor(0.6, 0.4, 0.2),
    }
    return meterStyle
end

-- Class icon atlas as shown on the damage meter bars, or nil.
function Compat.GetClassIconAtlas(classFilename)
    if not classFilename or classFilename == "" or not GetClassAtlas then
        return nil
    end
    return GetClassAtlas(classFilename)
end

-- Opens a context menu at owner (Blizzard's Menu system on Retail and Forever).
function Compat.OpenContextMenu(owner, generator)
    return MenuUtil.CreateContextMenu(owner, generator)
end

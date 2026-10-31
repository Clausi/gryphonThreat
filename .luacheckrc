-- luacheck configuration for GryphonThreat (WoW Retail, later Forever, Lua 5.1)
std = "lua51"
max_line_length = 120
exclude_files = { ".tools/", "Libs/" }

-- Methods defined with ":" do not have to use the implicit self.
self = false

-- Globals the addon defines.
globals = {
    "GryphonThreatDB",
    "GryphonThreatCharDB",
    "SLASH_GRYPHONTHREAT1",
    "SLASH_GRYPHONTHREAT2",
    "SlashCmdList",
}

-- WoW API and Blizzard UI globals the addon reads. Add new ones here when used.
read_globals = {
    -- WoW Lua extensions
    "floor",
    "strtrim",
    "issecretvalue",
    "hooksecurefunc",

    -- Libraries
    "LibStub",

    -- API
    "C_AddOns",
    "C_Secrets",
    "C_Timer",
    "unpack",
    "CreateColor",
    "CreateFrame",
    "GetAddOnMemoryUsage",
    "UpdateAddOnMemoryUsage",
    "GetClassAtlas",
    "GetLocale",
    "IsInRaid",
    "RegionalUniqueNamesEnabled",
    "UnitCanAttack",
    "UnitClass",
    "UnitDetailedThreatSituation",
    "UnitExists",
    "UnitInRaid",
    "UnitAffectingCombat",
    "IsInGroup",
    "InCombatLockdown",
    "CopyTable",
    "UnitName",

    -- UI helpers
    "AbbreviateLargeNumbers",
    "BreakUpLargeNumbers",
    "MenuUtil",
    "MinimalSliderWithSteppersMixin",

    -- Frames
    "DEFAULT_CHAT_FRAME",
    "UIParent",

    -- Constants and global strings
    "RAID_CLASS_COLORS",
    "UNKNOWN",
    "DAMAGE_METER_STATUS_BAR_DEFAULT_COLOR",
    "DAMAGE_METER_STATUS_BAR_CREATURE_COLOR",
}

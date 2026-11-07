local _, ns = ...
local L = ns.L

-- Shows the own threat in percent at Blizzard's target frame. The unit frames already have this
-- display (UnitFrame_UpdateThreatIndicator in Blizzard_UnitFrame), only Retail and Forever have no
-- option for it. So this module only switches the CVar and keeps no saved variable: the game stores
-- the value, and a change with /console shows up here as well.
--
-- Turned on in the settings menu of the window (Modules/ThreatWindow.lua) or with
-- "/gryphonthreat targetframe on".

-- Only on clients that have the CVar.
if not ns.Compat.HasNumericThreat() then
    return
end

local TargetFrameThreat = ns:RegisterModule("TargetFrameThreat")

function TargetFrameThreat:IsEnabled()
    return ns.Compat.IsNumericThreatEnabled()
end

-- The target frame reads the CVar on its own, at the latest after 0.5 s (TargetFrameMixin:OnUpdate).
function TargetFrameThreat:SetEnabled(enabled)
    ns.Compat.SetNumericThreatEnabled(enabled)
end

-- "/gryphonthreat targetframe on|off" sets the display, without argument shows the setting. Also the
-- way to change it while the window, and with it the settings menu, is hidden.
ns:RegisterCommand("targetframe", function(args)
    local value = args:lower()
    if value == "on" then
        TargetFrameThreat:SetEnabled(true)
    elseif value == "off" then
        TargetFrameThreat:SetEnabled(false)
    elseif value ~= "" then
        ns:Print(L["HELP_TARGET_FRAME"])
        return
    end
    ns:Print(TargetFrameThreat:IsEnabled() and L["TARGET_FRAME_ON"] or L["TARGET_FRAME_OFF"])
end, { L["HELP_TARGET_FRAME"] })

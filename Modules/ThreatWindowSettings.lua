local _, ns = ...
local L = ns.L
local ThreatWindowSettings = ns:RegisterModule("ThreatWindowSettings")

-- Adds the threat window to Blizzard's Edit Mode with LibEditMode, with the settings dialog of the
-- damage meter (EditModeSettingDisplayInfo.lua, Enum.EditModeSystem.DamageMeter): style, numbers,
-- size, bar height, padding, opacity, background, text size, visibility, icons and class colors.
-- The values are saved per Edit Mode layout in ns.db.layouts (ThreatWindow:GetLayout).

local LibEditMode = LibStub("LibEditMode")

local function FormatPercentage(value)
    return L["SLIDER_PERCENT"]:format(value)
end

-- A setting stored in the layout under key. Changes are applied right away, the dialog only
-- exists in Edit Mode, i.e. for the active layout.
local function LayoutSetting(kind, key, name, desc, extra)
    local ThreatWindow = ns.modules.ThreatWindow
    local setting = {
        kind = kind,
        name = name,
        desc = desc,
        default = ThreatWindow.LAYOUT_DEFAULTS[key],
        get = function(layoutName)
            return ThreatWindow:GetLayout(layoutName)[key]
        end,
        set = function(layoutName, value)
            ThreatWindow:GetLayout(layoutName)[key] = value
            ThreatWindow:ApplyLayout()
        end,
    }
    for field, value in pairs(extra or {}) do
        setting[field] = value
    end
    return setting
end

local function Round(value)
    return floor(value + 0.5)
end

-- All sliders move in whole steps. Values are rounded both ways: the slider may report rounding
-- errors, and sizes saved by the resize handle of older versions may have decimals.
local function Slider(key, name, minValue, maxValue, valueStep, formatter)
    local setting = LayoutSetting(LibEditMode.SettingType.Slider, key, name, nil, {
        minValue = minValue,
        maxValue = maxValue,
        valueStep = valueStep,
        formatter = formatter,
    })
    local get, set = setting.get, setting.set
    setting.get = function(layoutName)
        return Round(get(layoutName))
    end
    setting.set = function(layoutName, value)
        set(layoutName, Round(value))
    end
    return setting
end

local function Dropdown(key, name, values)
    return LayoutSetting(LibEditMode.SettingType.Dropdown, key, name, nil, { values = values })
end

-- Blizzard hides the selection overlay of a system while the mouse is on settings that change its
-- look (hideSystemSelectionOnInteract: style, opacity, background), so the change can be seen.
local function SetSelectionHidden(hidden)
    local selection = ns.modules.ThreatWindow:GetFrame().Selection
    selection:SetAlpha(hidden and 0 or 1)
end

-- Dropdown whose options hide the selection while hovered, like EditModeSettingDropdownMixin. Uses
-- a generator instead of values, because LibEditMode has no hover callbacks for its options.
local function PreviewDropdown(key, name, values)
    local setting = Dropdown(key, name, values)
    setting.hideSelectionOnInteract = true
    setting.generator = function(_, rootDescription)
        local function IsSelected(value)
            return setting.get(LibEditMode:GetActiveLayoutName()) == value
        end
        local function SetSelected(value)
            setting.set(LibEditMode:GetActiveLayoutName(), value)
        end
        for _, option in ipairs(values) do
            local radio = rootDescription:CreateRadio(option.text, IsSelected, SetSelected, option.value)
            radio:SetOnEnter(function()
                SetSelectionHidden(true)
            end)
            radio:SetOnLeave(function()
                SetSelectionHidden(false)
            end)
        end
    end
    return setting
end

-- LibEditMode's dialog reuses its widgets for every frame, so the hooks are added once per widget
-- and check the setting it currently shows. Dropdowns hide the selection on hover, sliders while
-- dragged (MinimalSliderWithSteppers interaction events), as in Blizzard's dialog.
local hookedWidgets = {}

local function HookWidget(widget)
    if hookedWidgets[widget] then
        return
    end
    hookedWidgets[widget] = true
    local function OnInteract(hidden)
        if widget.setting and widget.setting.hideSelectionOnInteract then
            SetSelectionHidden(hidden)
        end
    end
    if widget.Dropdown then
        widget.Dropdown:HookScript("OnEnter", function()
            OnInteract(true)
        end)
        widget.Dropdown:HookScript("OnLeave", function()
            OnInteract(false)
        end)
    elseif widget.Slider and widget.Slider.RegisterCallback then
        local events = MinimalSliderWithSteppersMixin.Event
        widget.Slider:RegisterCallback(events.OnInteractStart, function()
            OnInteract(true)
        end, hookedWidgets)
        widget.Slider:RegisterCallback(events.OnInteractEnd, function()
            OnInteract(false)
        end, hookedWidgets)
    end
end

-- Uses LibEditMode's internal dialog (lib.internal.dialog, Settings.widgets), as the library has no
-- API for it. Without it, the selection just stays visible.
local function HookSettingsDialog()
    local dialog = LibEditMode.internal and LibEditMode.internal.dialog
    if not dialog then
        return
    end
    hooksecurefunc(dialog, "Update", function()
        for _, widget in ipairs(dialog.Settings.widgets or {}) do
            HookWidget(widget)
        end
    end)
    -- The overlay must not stay hidden after the dialog closes in the middle of a hover.
    dialog:HookScript("OnHide", function()
        SetSelectionHidden(false)
    end)
end

local function Checkbox(key, name, desc)
    return LayoutSetting(LibEditMode.SettingType.Checkbox, key, name, desc)
end

local function PreviewSlider(...)
    local setting = Slider(...)
    setting.hideSelectionOnInteract = true
    return setting
end

local function BuildSettings()
    local ThreatWindow = ns.modules.ThreatWindow
    local Style, Numbers, Visibility = ThreatWindow.Style, ThreatWindow.Numbers, ThreatWindow.Visibility
    local style = ns.Compat.GetMeterStyle()

    return {
        PreviewDropdown("style", L["SETTING_STYLE"], {
            { text = L["SETTING_STYLE_DEFAULT"], value = Style.Default },
            { text = L["SETTING_STYLE_BORDERED"], value = Style.Bordered },
            { text = L["SETTING_STYLE_THIN"], value = Style.Thin },
        }),
        Dropdown("numbers", L["SETTING_NUMBERS"], {
            { text = L["SETTING_NUMBERS_MINIMAL"], value = Numbers.Minimal },
            { text = L["SETTING_NUMBERS_COMPACT"], value = Numbers.Compact },
            { text = L["SETTING_NUMBERS_COMPLETE"], value = Numbers.Complete },
        }),
        Slider("width", L["SETTING_WIDTH"], style.minWidth, style.maxWidth, 1),
        Slider("height", L["SETTING_HEIGHT"], style.minHeight, style.maxHeight, 1),
        Slider("barHeight", L["SETTING_BAR_HEIGHT"], 15, 40, 1),
        Slider("padding", L["SETTING_PADDING"], 2, 10, 1),
        PreviewSlider("opacity", L["SETTING_OPACITY"], 50, 100, 1, FormatPercentage),
        PreviewSlider("background", L["SETTING_BACKGROUND"], 0, 100, 1, FormatPercentage),
        Slider("textSize", L["SETTING_TEXT_SIZE"], 50, 150, 10, FormatPercentage),
        Dropdown("visibility", L["SETTING_VISIBILITY"], {
            { text = L["SETTING_VISIBILITY_ALWAYS"], value = Visibility.Always },
            { text = L["SETTING_VISIBILITY_IN_COMBAT"], value = Visibility.InCombat },
            { text = L["SETTING_VISIBILITY_IN_GROUP"], value = Visibility.InGroup },
            { text = L["SETTING_VISIBILITY_HIDDEN"], value = Visibility.Hidden },
        }),
        Checkbox("showIcons", L["SETTING_SHOW_ICONS"]),
        Checkbox("classColors", L["SETTING_CLASS_COLORS"], L["SETTING_CLASS_COLORS_DESC"]),
        Checkbox("showPullAggro", L["SETTING_PULL_AGGRO"], L["SETTING_PULL_AGGRO_DESC"]),
    }
end

-- LibEditMode callback after the window was dragged, moved with the arrow keys or reset.
local function OnPositionChanged(_, layoutName, point, x, y)
    if not layoutName then
        return
    end
    local ThreatWindow = ns.modules.ThreatWindow
    ThreatWindow:SavePosition(layoutName, point, point, x, y)
    ThreatWindow:ApplyLayout()
end

local function RegisterLayoutCallbacks()
    local ThreatWindow = ns.modules.ThreatWindow
    local layouts = ns.db.layouts

    LibEditMode:RegisterCallback("layout", function(layoutName)
        ThreatWindow:SetActiveLayout(layoutName)
    end)
    LibEditMode:RegisterCallback("enter", function()
        ThreatWindow:SetEditing(true)
    end)
    LibEditMode:RegisterCallback("exit", function()
        ThreatWindow:SetEditing(false)
    end)
    LibEditMode:RegisterCallback("create", function(layoutName, _, sourceLayoutName)
        local source = sourceLayoutName and layouts[sourceLayoutName]
        if source then
            layouts[layoutName] = CopyTable(source)
        end
    end)
    LibEditMode:RegisterCallback("rename", function(oldLayoutName, newLayoutName)
        layouts[newLayoutName] = layouts[oldLayoutName]
        layouts[oldLayoutName] = nil
    end)
    LibEditMode:RegisterCallback("delete", function(layoutName)
        layouts[layoutName] = nil
    end)
end

function ThreatWindowSettings:OnEnable()
    local ThreatWindow = ns.modules.ThreatWindow
    local frame = ThreatWindow:GetFrame()

    -- The name is the title of the settings dialog and the Edit Mode label; the addon name makes clear
    -- where the window comes from.
    LibEditMode:AddFrame(frame, OnPositionChanged, ThreatWindow.DEFAULT_POSITION, ns.name)
    LibEditMode:AddFrameSettings(frame, BuildSettings())
    -- LibEditMode silently ignores clicks in combat (e.g. still fighting a training dummy). The
    -- selection is Blizzard's EditModeSystemSelectionTemplate, which sets frame.Selection.
    frame.Selection:HookScript("OnMouseDown", function()
        if InCombatLockdown() then
            ns:Print(L["EDIT_MODE_IN_COMBAT"])
        end
    end)
    -- AddFrame creates LibEditMode's dialog.
    HookSettingsDialog()
    RegisterLayoutCallbacks()
end

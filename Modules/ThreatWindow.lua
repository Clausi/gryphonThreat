local _, ns = ...
local L = ns.L
local Compat = ns.Compat
local ThreatWindow = ns:RegisterModule("ThreatWindow")

-- Window with the threat on the current target, built like a session window of Blizzard's damage
-- meter (DamageMeterSessionWindow.xml, DamageMeterEntry.xml / .lua): header bar with title,
-- settings and minimize buttons, one status bar per group member, resize handle on mouse over.
-- Own frames with the same atlases and anchors; Blizzard's damage meter frames are not touched.
--
-- Like the damage meter, the look and position are Edit Mode settings saved per layout
-- (ns.db.layouts[layoutName], see ThreatWindowSettings.lua), while shown, locked and minimized are
-- saved per character (ns.charDb.window).

-- Values of the Edit Mode settings, in the order of Blizzard's Enum.DamageMeterStyle,
-- Enum.DamageMeterNumbers and Enum.DamageMeterVisibility.
ThreatWindow.Style = { Default = 0, Thin = 1, Bordered = 2 }
ThreatWindow.Numbers = { Minimal = 0, Compact = 1, Complete = 2 }
ThreatWindow.Visibility = { Always = 0, InCombat = 1, Hidden = 2, InGroup = 3 }

-- Settings of one Edit Mode layout, as Blizzard's preset layout sets up the damage meter
-- (Mainline/EditModePresetLayouts.lua; the raw values are converted like EditModeSettingDisplayInfo.lua
-- does: minimum + raw value, or minimum + raw value * step). point is nil until the window was
-- moved: { point, relativePoint, x, y } relative to UIParent.
ThreatWindow.LAYOUT_DEFAULTS = {
    style = ThreatWindow.Style.Default,
    numbers = ThreatWindow.Numbers.Compact,
    width = 400,
    height = 140,
    barHeight = 16,
    padding = 4,
    opacity = 100,
    background = 50,
    textSize = 100,
    visibility = ThreatWindow.Visibility.Always,
    showIcons = true,
    classColors = true,
    -- Extra first bar with the threat the player still needs to pull aggro.
    showPullAggro = true,
}

-- Also the position LibEditMode's "Reset Position" moves the window to.
ThreatWindow.DEFAULT_POSITION = { point = "CENTER", x = 400, y = -150 }

-- Coalesces the many threat events in combat into one redraw.
local REFRESH_DELAY = 0.1
-- Space between the header and the first bar, and below the last bar (DamageMeterSessionWindowMixin).
local LIST_TOP_OFFSET, LIST_BOTTOM_OFFSET = 2, 6
-- Aggro colors: from green over yellow to red as a unit gets closer to pulling aggro, red from
-- AGGRO_RED_PERCENT on. Used by the pull aggro bar, and by all bars without class colors.
local AGGRO_COLORS = {
    { 0.2, 0.8, 0.2 },
    { 1, 0.8, 0 },
    { 0.8, 0.15, 0.15 },
}
local AGGRO_RED_PERCENT = 90
-- The pull aggro bar shows the icon of the spell Taunt, the same as the addon's icon in the TOC.
local PULL_AGGRO_ICON = "Interface\\Icons\\Spell_Nature_Reincarnation"
-- Crops the border of a spell icon, like the TexCoords of DamageMeterEntryTemplate.
local ICON_TEX_COORD = { 0.0625, 0.9, 0.0625, 0.9 }
local ICON_SIZE = 24

-- Sample bars for the test mode and Edit Mode, like EDIT_MODE_SESSION of the damage meter.
local TEST_ENTRIES = {
    { name = L["TEST_SOURCE_1"], classFilename = "WARRIOR", percent = 100, threat = 1825000, isTanking = true },
    { name = L["TEST_SOURCE_2"], classFilename = "MAGE", percent = 82, threat = 1496500 },
    { name = L["TEST_SOURCE_3"], classFilename = "WARLOCK", percent = 71, threat = 1295750 },
    { name = L["TEST_SOURCE_4"], classFilename = "HUNTER", percent = 64, threat = 1168000 },
    { name = L["TEST_SOURCE_5"], classFilename = "PALADIN", percent = 40, threat = 730000, isPlayer = true },
}

local style
local window
local bars = {}
local testMode = false
local isEditing = false
local refreshPending = false
-- Name of the active Edit Mode layout, nil until LibEditMode knows it (shortly after login).
local activeLayoutName

local function GetCharSettings()
    return ns.charDb.window
end

-- Settings of an Edit Mode layout (default: the active one), with missing values filled in.
-- Before the layout is known, the defaults are returned (not saved).
function ThreatWindow:GetLayout(layoutName)
    layoutName = layoutName or activeLayoutName
    if not layoutName then
        return self.LAYOUT_DEFAULTS
    end
    local layouts = ns.db.layouts
    layouts[layoutName] = ns.ApplyDefaults(layouts[layoutName] or {}, self.LAYOUT_DEFAULTS)
    return layouts[layoutName]
end

-- Aggro color (r, g, b) for a percentage of the pull threshold (0-100).
local function GetAggroColor(percent)
    local progress = math.min(1, math.max(0, percent / AGGRO_RED_PERCENT))
    -- Two halves: green to yellow, then yellow to red.
    local from, to, t
    if progress < 0.5 then
        from, to, t = AGGRO_COLORS[1], AGGRO_COLORS[2], progress * 2
    else
        from, to, t = AGGRO_COLORS[2], AGGRO_COLORS[3], (progress - 0.5) * 2
    end
    return from[1] + (to[1] - from[1]) * t, from[2] + (to[2] - from[2]) * t, from[3] + (to[3] - from[3]) * t
end

-- Bar color (r, g, b): the class color, or with "Show Class Color" off the aggro color of the
-- unit's percentage, as the damage meter shows no class without its class color. Secret
-- percentages can not be compared, so those bars keep the default color.
local function GetBarColor(entry, layout)
    if not layout.classColors then
        if entry.isSecret then
            return style.defaultColor:GetRGB()
        end
        return GetAggroColor(entry.percent)
    end
    if entry.isPet then
        return style.creatureColor:GetRGB()
    end
    local classColor = entry.classFilename and RAID_CLASS_COLORS[entry.classFilename]
    return (classColor or style.defaultColor):GetRGB()
end

-- One bar of the list, see DamageMeterEntryTemplate. Anchors depend on the style and are set by
-- UpdateBarStyle.
local function CreateBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetClipsChildren(true)

    -- Fixed 24x24 like the Icon frame of DamageMeterEntryTemplate; the bar clips it to its height.
    bar.Icon = bar:CreateTexture(nil, "ARTWORK")
    bar.Icon:SetSize(ICON_SIZE, ICON_SIZE)
    bar.Icon:SetPoint("LEFT")

    local statusBar = CreateFrame("StatusBar", nil, bar)
    local barTexture = statusBar:CreateTexture(nil, "ARTWORK")
    barTexture:SetAtlas(style.barAtlas)
    statusBar:SetStatusBarTexture(barTexture)
    statusBar:SetMinMaxValues(0, 100)
    bar.StatusBar = statusBar

    bar.Background = statusBar:CreateTexture(nil, "BACKGROUND")

    bar.BackgroundEdge = statusBar:CreateTexture(nil, "OVERLAY")
    bar.BackgroundEdge:SetAtlas(style.barBackgroundEdgeAtlas)
    bar.BackgroundEdge:SetPoint("TOPLEFT", -2, 2)
    bar.BackgroundEdge:SetPoint("BOTTOMRIGHT", 2, -2)

    bar.Value = statusBar:CreateFontString(nil, "OVERLAY", style.barFont)
    bar.Value:SetJustifyH("LEFT")

    bar.Name = statusBar:CreateFontString(nil, "OVERLAY", style.barFont)
    bar.Name:SetJustifyH("LEFT")
    bar.Name:SetWordWrap(false)

    return bar
end

-- DamageMeterEntryMixin:SetupDefaultStyle, SetupBorderedStyle and SetupThinStyle.
local function UpdateBarStyle(bar, layout)
    local isBordered = layout.style == ThreatWindow.Style.Bordered
    local isThin = layout.style == ThreatWindow.Style.Thin
    local statusBar, name, value = bar.StatusBar, bar.Name, bar.Value

    bar:SetHeight(layout.barHeight)
    bar.Icon:SetShown(layout.showIcons)

    statusBar:ClearAllPoints()
    name:ClearAllPoints()
    value:ClearAllPoints()

    -- GetIconAttachmentAnchor: next to the icon, with a gap for the bordered and thin styles.
    local anchorTo, anchorPoint, anchorX = bar, "LEFT", 0
    if layout.showIcons then
        anchorTo, anchorPoint = bar.Icon, "RIGHT"
        anchorX = (isBordered or isThin) and 5 or 0
    end

    if isThin then
        statusBar:SetPoint("LEFT", anchorTo, anchorPoint, anchorX, 0)
        statusBar:SetPoint("TOP", name, "BOTTOM", 0, 0)
        statusBar:SetPoint("BOTTOMRIGHT", 0, 1)
        name:SetPoint("TOP", bar, "TOP", 0, 0)
        name:SetPoint("LEFT", anchorTo, anchorPoint, anchorX, 0)
        name:SetPoint("RIGHT", value, "LEFT", -25, 0)
        value:SetPoint("TOP", bar, "TOP", 0, 0)
        value:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    else
        statusBar:SetPoint("LEFT", anchorTo, anchorPoint, anchorX, 0)
        statusBar:SetPoint("TOP", 0, -1)
        statusBar:SetPoint("BOTTOMRIGHT", -4, 1)
        name:SetPoint("LEFT", 2, 0)
        name:SetPoint("RIGHT", value, "LEFT", -25, 0)
        value:SetPoint("RIGHT", -3, 0)
    end

    -- SetupSharedStyleBackground
    bar.Background:ClearAllPoints()
    if isBordered then
        bar.Background:SetAtlas(style.barBorderedBackgroundAtlas)
        bar.Background:SetPoint("TOPLEFT", -2, 2)
        bar.Background:SetPoint("BOTTOMRIGHT", 6, -7)
    else
        bar.Background:SetAtlas(style.barBackgroundAtlas)
        bar.Background:SetPoint("TOPLEFT", -2, 2)
        bar.Background:SetPoint("BOTTOMRIGHT", 2, -2)
    end
    bar.BackgroundEdge:SetShown(not isBordered)

    local textScale = layout.textSize / 100
    name:SetTextScale(textScale)
    value:SetTextScale(textScale)
end

-- Threat as text: abbreviated ("1.3M"), or in full ("1,276,086") for the "Complete" numbers.
local function FormatThreat(threat, numbers)
    if numbers == ThreatWindow.Numbers.Complete then
        return BreakUpLargeNumbers(floor(threat))
    end
    return AbbreviateLargeNumbers(floor(threat))
end

-- Value text for the "Numbers" setting: Minimal "100%", Compact "1.3M (100%)", Complete
-- "1,276,086 (100%)". Secret values allow no arithmetic, so only the percentage is shown then.
local function SetValueText(fontString, entry, numbers)
    if entry.isSecret or numbers == ThreatWindow.Numbers.Minimal then
        fontString:SetFormattedText(L["ENTRY_VALUE_PERCENT"], entry.percent)
        return
    end
    fontString:SetFormattedText(L["ENTRY_VALUE"], FormatThreat(entry.threat, numbers), entry.percent)
end

-- Bar values like DamageMeterSourceEntryMixin:Init: "1. Name" and the value text. Secret values
-- only go to SetValue and SetFormattedText.
local function SetBarEntry(bar, entry, index, layout)
    bar.Name:SetFormattedText(L["ENTRY_NAME"], index, entry.name)
    bar.StatusBar:SetValue(entry.percent)
    SetValueText(bar.Value, entry, layout.numbers)

    bar.StatusBar:SetStatusBarColor(GetBarColor(entry, layout))

    -- SetAtlas also resets the texture coordinates of the pull aggro icon.
    local iconAtlas = not entry.isPet and Compat.GetClassIconAtlas(entry.classFilename)
    if iconAtlas then
        bar.Icon:SetAtlas(iconAtlas)
    else
        bar.Icon:SetTexture(nil)
    end
    bar:Show()
end

-- Anchors bar index below the header, as the scroll box of the damage meter lays them out.
local function PlaceBar(bar, index, layout)
    local offset = -LIST_TOP_OFFSET - (index - 1) * (layout.barHeight + layout.padding)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", window.Header, "BOTTOMLEFT", 5, offset)
    bar:SetPoint("RIGHT", window, "RIGHT", -1, 0)
end

local function GetBar(index, layout)
    local bar = bars[index]
    if not bar then
        bar = CreateBar(window.Container)
        UpdateBarStyle(bar, layout)
        PlaceBar(bar, index, layout)
        bars[index] = bar
    end
    return bar
end

-- Number of bars that fit into the window below the header.
local function GetVisibleBarCount(layout)
    local listHeight = window:GetHeight() - style.headerHeight - LIST_TOP_OFFSET - LIST_BOTTOM_OFFSET
    local rowHeight = layout.barHeight + layout.padding
    return math.max(0, floor((listHeight + layout.padding) / rowHeight))
end

-- First bar while someone else has aggro: "Pull Aggro" and the threat still missing. It fills up
-- and turns from green to red with the player's percentage of the pull threshold.
local function SetPullAggroBar(bar, needed, percent, layout)
    bar.Name:SetText(L["PULL_AGGRO"])
    bar.StatusBar:SetValue(percent)
    bar.Value:SetFormattedText(L["PULL_AGGRO_VALUE"], FormatThreat(needed, layout.numbers))
    bar.StatusBar:SetStatusBarColor(GetAggroColor(percent))
    bar.Icon:SetTexture(PULL_AGGRO_ICON)
    bar.Icon:SetTexCoord(unpack(ICON_TEX_COORD))
    bar:Show()
end

-- Like the damage meter's local player entry: if the player is below the visible bars, the last
-- visible bar shows the player instead. needed and percent come from ThreatData:GetPullAggro; with
-- needed, the pull aggro bar takes the first row.
local function ShowEntries(entries, layout, needed, percent)
    local barCount = GetVisibleBarCount(layout)
    local offset = 0
    if needed and barCount > 0 then
        SetPullAggroBar(GetBar(1, layout), needed, percent, layout)
        offset = 1
    end

    local visibleCount = math.min(#entries, barCount - offset)
    local playerIndex
    for i = 1, #entries do
        if entries[i].isPlayer then
            playerIndex = i
            break
        end
    end

    for i = 1, visibleCount do
        local index = i
        if i == visibleCount and playerIndex and playerIndex > visibleCount then
            index = playerIndex
        end
        SetBarEntry(GetBar(i + offset, layout), entries[index], index, layout)
    end
    for i = visibleCount + offset + 1, #bars do
        bars[i]:Hide()
    end
end

-- Pull aggro values for ShowEntries, if the layout shows the bar.
local function GetPullAggro(entries, hasSecret, layout)
    if not layout.showPullAggro then
        return nil
    end
    return ns.modules.ThreatData:GetPullAggro(entries, hasSecret)
end

function ThreatWindow:Refresh()
    if not window or not window:IsShown() or GetCharSettings().minimized then
        return
    end
    local layout = self:GetLayout()

    if testMode or isEditing then
        window.Title:SetText(L["TEST_TARGET"])
        window.EmptyText:SetText(nil)
        ShowEntries(TEST_ENTRIES, layout, GetPullAggro(TEST_ENTRIES, false, layout))
        return
    end

    local ThreatData = ns.modules.ThreatData
    local mobUnit = ThreatData:GetMobUnit()
    local entries, hasSecret = ThreatData:GetThreatList(mobUnit)
    if mobUnit then
        window.Title:SetText(Compat.GetUnitDisplayName(mobUnit))
        window.EmptyText:SetText(#entries == 0 and L["NO_THREAT"] or nil)
    else
        window.Title:SetText(L["WINDOW_TITLE"])
        window.EmptyText:SetText(L["NO_TARGET"])
    end
    ShowEntries(entries, layout, GetPullAggro(entries, hasSecret, layout))
end

local function RequestRefresh()
    if refreshPending then
        return
    end
    refreshPending = true
    C_Timer.After(REFRESH_DELAY, function()
        refreshPending = false
        ThreatWindow:Refresh()
    end)
end

-- Whether the window is shown: always in Edit Mode and test mode, otherwise if not hidden by the
-- player and the "Visibility" setting allows it.
local function ShouldBeShown()
    if isEditing or testMode then
        return true
    end
    if not GetCharSettings().shown then
        return false
    end
    local visibility = ThreatWindow:GetLayout().visibility
    if visibility == ThreatWindow.Visibility.Hidden then
        return false
    elseif visibility == ThreatWindow.Visibility.InCombat then
        return UnitAffectingCombat("player")
    elseif visibility == ThreatWindow.Visibility.InGroup then
        return IsInGroup()
    end
    return true
end

local function UpdateVisibility()
    local shown = ShouldBeShown()
    if shown ~= window:IsShown() then
        window:SetShown(shown)
        if shown then
            ThreatWindow:Refresh()
        end
    end
end

local function UpdateMinimized()
    -- Edit Mode always shows the whole window, as the damage meter does (SetIsEditing).
    local minimized = GetCharSettings().minimized and not isEditing
    local button = window.MinimizeButton
    if minimized then
        button:SetNormalAtlas(style.expandAtlas)
        button:SetPushedAtlas(style.expandPressedAtlas)
    else
        button:SetNormalAtlas(style.collapseAtlas)
        button:SetPushedAtlas(style.collapsePressedAtlas)
    end
    window.Background:SetShown(not minimized)
    window.Container:SetShown(not minimized)
end

-- Applies the settings of the active layout: position, size, transparency, bar style.
function ThreatWindow:ApplyLayout()
    if not window then
        return
    end
    local layout = self:GetLayout()
    local position = layout.point
    window:ClearAllPoints()
    if position then
        window:SetPoint(position[1], UIParent, position[2], position[3], position[4])
    else
        local default = self.DEFAULT_POSITION
        window:SetPoint(default.point, UIParent, default.point, default.x, default.y)
    end
    window:SetSize(layout.width, layout.height)
    window:SetAlpha(layout.opacity / 100)
    window.Background:SetAlpha(layout.background / 100)

    for index, bar in ipairs(bars) do
        UpdateBarStyle(bar, layout)
        PlaceBar(bar, index, layout)
    end
    UpdateVisibility()
    self:Refresh()
end

-- Activates an Edit Mode layout, called by ThreatWindowSettings.lua.
function ThreatWindow:SetActiveLayout(layoutName)
    activeLayoutName = layoutName
    self:ApplyLayout()
end

-- Saves a position relative to UIParent in a layout (default: the active one).
function ThreatWindow:SavePosition(layoutName, point, relativePoint, x, y)
    self:GetLayout(layoutName).point = { point, relativePoint, x, y }
end

-- Edit Mode shows the whole window with sample bars, like the damage meter in Edit Mode.
function ThreatWindow:SetEditing(editing)
    isEditing = editing
    if not window then
        return
    end
    window.EditModeResizeButton:SetShown(editing)
    UpdateMinimized()
    UpdateVisibility()
    self:Refresh()
end

-- The window can be moved and resized outside Edit Mode while it is not locked. In Edit Mode,
-- LibEditMode moves it and the Edit Mode resize handle or the settings dialog sizes it.
local function CanMoveOrResize()
    return not GetCharSettings().locked and not isEditing
end

-- Fades the resize handle in while the mouse is over the window, as the damage meter does in its
-- OnUpdate. The OnUpdate only runs while hovered.
local function OnHoverUpdate()
    local resizeButton = window.ResizeButton
    local isMouseOver = window:IsMouseOver() or resizeButton:IsMouseOver() or window.isResizing
    if isMouseOver then
        return
    end
    window.hovered = false
    if resizeButton:GetAlpha() > 0 then
        resizeButton.FadeIn:Play(true)
    end
    window:SetScript("OnUpdate", nil)
end

local function OnWindowEnter()
    if window.hovered then
        return
    end
    window.hovered = true
    if CanMoveOrResize() then
        window.ResizeButton.FadeIn:Play()
    end
    window:SetScript("OnUpdate", OnHoverUpdate)
end

local function GenerateSettingsMenu(_, rootDescription)
    local settings = GetCharSettings()
    rootDescription:CreateButton(settings.locked and L["MENU_UNLOCK"] or L["MENU_LOCK"], function()
        ThreatWindow:SetLocked(not settings.locked)
    end)
    rootDescription:CreateCheckbox(L["MENU_TEST"], function()
        return testMode
    end, function()
        ThreatWindow:SetTestMode(not testMode)
    end)
    rootDescription:CreateButton(L["MENU_HIDE"], function()
        ThreatWindow:SetShown(false)
        ns:Print(L["WINDOW_HIDDEN"])
    end)
end

-- Settings button as DamageMeterSettingsDropdownButtonTemplate: a gear icon with own atlases per
-- button state. Opens a context menu instead of being a dropdown.
local function CreateSettingsButton()
    local button = CreateFrame("Button", nil, window)
    button:SetSize(27, 27)
    button:SetPoint("RIGHT", window.MinimizeButton, "LEFT", -2, -2)
    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.Icon:SetPoint("CENTER")

    local function SetIcon(atlas)
        button.Icon:SetAtlas(atlas, true)
    end
    SetIcon(style.settingsAtlas)
    button:SetScript("OnEnter", function()
        SetIcon(style.settingsHoverAtlas)
        OnWindowEnter()
    end)
    button:SetScript("OnLeave", function()
        SetIcon(style.settingsAtlas)
    end)
    button:SetScript("OnMouseDown", function()
        SetIcon(style.settingsPressedAtlas)
    end)
    button:SetScript("OnMouseUp", function()
        SetIcon(button:IsMouseOver() and style.settingsHoverAtlas or style.settingsAtlas)
    end)
    button:SetScript("OnClick", function()
        SetIcon(style.settingsOpenAtlas)
        Compat.OpenContextMenu(button, GenerateSettingsMenu)
    end)
    return button
end

-- StartSizing("BOTTOMRIGHT") keeps the TOPLEFT corner in place only if the window is anchored there;
-- with other anchors (e.g. the default CENTER), the window jumps when the drag starts. So the window
-- is anchored at its current top left corner first.
local function StartResizing(button)
    local left, top = window:GetLeft(), window:GetTop()
    window:ClearAllPoints()
    window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    button:SetButtonState("PUSHED", true)
    button:GetHighlightTexture():Hide()
    window:StartSizing("BOTTOMRIGHT")
    window.isResizing = true
end

-- Saves size (in whole pixels, as the Edit Mode sliders show them) and position in the layout.
local function StopResizing(button)
    button:SetButtonState("NORMAL", false)
    button:GetHighlightTexture():Show()
    window:StopMovingOrSizing()
    window.isResizing = false
    local layout = ThreatWindow:GetLayout()
    local width, height = window:GetSize()
    layout.width, layout.height = floor(width + 0.5), floor(height + 0.5)
    window:SetSize(layout.width, layout.height)
    local point, _, relativePoint, x, y = window:GetPoint(1)
    ThreatWindow:SavePosition(nil, point, relativePoint, x, y)
end

-- Mouse handling of a resize handle; canResize tells whether it may be used right now.
local function SetupResizeButton(button, canResize)
    button:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton == "LeftButton" and canResize() then
            StartResizing(button)
        end
    end)
    button:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton == "LeftButton" and window.isResizing then
            StopResizing(button)
        end
    end)
end

local function CreateResizeButton()
    local button = CreateFrame("Button", nil, window.Container)
    button:SetSize(60, 60)
    button:SetPoint("BOTTOMRIGHT", 9, -8)
    button:SetNormalAtlas(style.resizeAtlas)
    button:SetHighlightAtlas(style.resizeHoverAtlas)
    button:SetPushedAtlas(style.resizePressedAtlas)
    button:SetAlpha(0)

    local fadeIn = button:CreateAnimationGroup()
    fadeIn:SetToFinalAlpha(true)
    local alpha = fadeIn:CreateAnimation("Alpha")
    alpha:SetDuration(0.25)
    alpha:SetFromAlpha(0)
    alpha:SetToAlpha(1)
    button.FadeIn = fadeIn

    SetupResizeButton(button, CanMoveOrResize)
    button:HookScript("OnEnter", OnWindowEnter)
    return button
end

-- Resize handle in Edit Mode, like the EditModeResizeButton of EditModeDamageMeterSystemTemplate:
-- above the Edit Mode selection (HIGH strata), shown only in Edit Mode.
local function CreateEditModeResizeButton()
    local button = CreateFrame("Button", nil, window)
    button:SetFrameStrata("HIGH")
    button:SetToplevel(true)
    button:SetSize(60, 60)
    button:SetPoint("BOTTOMRIGHT", 10, -10)
    button:SetNormalAtlas(style.resizeAtlas)
    button:SetHighlightAtlas(style.resizeHoverAtlas)
    button:SetPushedAtlas(style.resizePressedAtlas)
    button:Hide()
    SetupResizeButton(button, function()
        return isEditing
    end)
    return button
end

local function CreateWindow()
    style = Compat.GetMeterStyle()

    window = CreateFrame("Frame", nil, UIParent)
    window.editModeName = ns.name
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:SetResizable(true)
    window:SetResizeBounds(style.minWidth, style.minHeight, style.maxWidth, style.maxHeight)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function()
        if CanMoveOrResize() then
            -- LibEditMode turns movable off again when it leaves Edit Mode with the window selected.
            window:SetMovable(true)
            window:StartMoving()
        end
    end)
    window:SetScript("OnDragStop", function()
        window:StopMovingOrSizing()
        local point, _, relativePoint, x, y = window:GetPoint(1)
        ThreatWindow:SavePosition(nil, point, relativePoint, x, y)
    end)
    window:SetScript("OnEnter", OnWindowEnter)
    window:SetScript("OnSizeChanged", function()
        ThreatWindow:Refresh()
    end)

    -- The damage meter draws its background on the minimize container; here it is on the window
    -- below the header, and hidden with the container.
    window.Background = window:CreateTexture(nil, "BACKGROUND", nil, -1)
    window.Background:SetAtlas(style.backgroundAtlas)
    window.Background:SetAllPoints()

    window.Header = window:CreateTexture(nil, "BACKGROUND")
    window.Header:SetAtlas(style.headerAtlas)
    window.Header:SetHeight(style.headerHeight)
    window.Header:SetPoint("TOPLEFT")
    window.Header:SetPoint("TOPRIGHT")

    local minimizeButton = CreateFrame("Button", nil, window)
    minimizeButton:SetSize(18, 19)
    minimizeButton:SetPoint("TOPRIGHT", window.Header, "TOPRIGHT", -3, -5)
    minimizeButton:SetHighlightAtlas(style.minimizeHighlightAtlas, "ADD")
    minimizeButton:SetScript("OnClick", function()
        ThreatWindow:SetMinimized(not GetCharSettings().minimized)
    end)
    window.MinimizeButton = minimizeButton

    window.SettingsButton = CreateSettingsButton()

    window.Title = window:CreateFontString(nil, "OVERLAY", style.headerFont)
    window.Title:SetJustifyH("LEFT")
    window.Title:SetWordWrap(false)
    window.Title:SetPoint("TOPLEFT", window.Header, "TOPLEFT", 6, -9)
    window.Title:SetPoint("RIGHT", window.SettingsButton, "LEFT", -5, 0)

    window.Container = CreateFrame("Frame", nil, window)
    window.Container:SetAllPoints()

    window.EmptyText = window.Container:CreateFontString(nil, "OVERLAY", style.headerFont)
    window.EmptyText:SetJustifyH("CENTER")
    window.EmptyText:SetPoint("TOPLEFT", window.Header, "BOTTOMLEFT", 20, 0)
    window.EmptyText:SetPoint("BOTTOMRIGHT", -20, 0)

    window.ResizeButton = CreateResizeButton()
    window.EditModeResizeButton = CreateEditModeResizeButton()

    UpdateMinimized()
end

function ThreatWindow:GetFrame()
    return window
end

function ThreatWindow:SetShown(shown)
    GetCharSettings().shown = shown
    UpdateVisibility()
end

function ThreatWindow:SetLocked(locked)
    GetCharSettings().locked = locked
end

function ThreatWindow:SetMinimized(minimized)
    GetCharSettings().minimized = minimized
    UpdateMinimized()
    self:Refresh()
end

function ThreatWindow:SetTestMode(enabled)
    testMode = enabled
    ns:Print(enabled and L["TEST_ON"] or L["TEST_OFF"])
    UpdateVisibility()
    self:Refresh()
end

-- Resets position and size of the active layout.
function ThreatWindow:ResetPosition()
    local layout = self:GetLayout()
    layout.point = nil
    layout.width = self.LAYOUT_DEFAULTS.width
    layout.height = self.LAYOUT_DEFAULTS.height
    self:ApplyLayout()
end

function ThreatWindow:OnEnable()
    CreateWindow()
    self:ApplyLayout()

    local ThreatData = ns.modules.ThreatData
    ns:RegisterEvent("PLAYER_TARGET_CHANGED", RequestRefresh)
    -- The target of the target only matters where it can be shown (Compat.CanUseTargetOfTarget).
    if Compat.CanUseTargetOfTarget() then
        ns:RegisterEvent("UNIT_TARGET", function(_, unit)
            if unit == "target" then
                RequestRefresh()
            end
        end)
    end
    -- Fires for every mob whose threat list changes; only the shown one needs a redraw, which
    -- matters on large pulls.
    ns:RegisterEvent("UNIT_THREAT_LIST_UPDATE", function(_, unit)
        if unit == ThreatData:GetMobUnit() then
            RequestRefresh()
        end
    end)
    ns:RegisterEvent("UNIT_PET", RequestRefresh)
    -- Also for the "Visibility" setting (in combat, in group).
    local function OnStateChanged()
        UpdateVisibility()
        RequestRefresh()
    end
    ns:RegisterEvent("GROUP_ROSTER_UPDATE", OnStateChanged)
    ns:RegisterEvent("PLAYER_REGEN_ENABLED", OnStateChanged)
    ns:RegisterEvent("PLAYER_REGEN_DISABLED", OnStateChanged)
end

ns:RegisterCommand("show", function()
    ThreatWindow:SetShown(true)
    ns:Print(L["WINDOW_SHOWN"])
end, { L["HELP_SHOW"] })

ns:RegisterCommand("hide", function()
    ThreatWindow:SetShown(false)
    ns:Print(L["WINDOW_HIDDEN"])
end, { L["HELP_HIDE"] })

ns:RegisterCommand("lock", function()
    local locked = not GetCharSettings().locked
    ThreatWindow:SetLocked(locked)
    ns:Print(locked and L["WINDOW_LOCKED"] or L["WINDOW_UNLOCKED"])
end, { L["HELP_LOCK"] })

ns:RegisterCommand("reset", function()
    ThreatWindow:ResetPosition()
    ns:Print(L["WINDOW_RESET"])
end, { L["HELP_RESET"] })

ns:RegisterCommand("test", function()
    ThreatWindow:SetTestMode(not testMode)
end, { L["HELP_TEST"] })

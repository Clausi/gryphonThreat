# GryphonThreat

World of Warcraft addon that shows the threat on the current target in a window that looks like
Blizzard's built-in damage meter.

**Load the `wow-lua` skill (`.claude/skills/wow-lua/`) before working on code.** It holds the rules
shared by all WoW addons (luacheck, locales, addon structure, Blizzard UI, secret values, names,
compatibility, changelog). The git workflow and commit messages are in the global `CLAUDE.md`. This
file only adds what is specific to GryphonThreat.

## Target clients

- **Supported: Retail** (120105, `_retail_`, `live` branch of wow-ui-source), the client the addon
  is developed and tested on first.
- **Supported: WoW Forever** (16001, `_forever_`, `forever` branch of wow-ui-source). Test every
  change there too. Keep it in mind for every design decision (Mainline UI and API, "First Surname"
  names without realm, secret values). Every client difference goes through `ns.Compat`, even
  where Retail and Forever use the same code yet.
- `Core/Names.lua` does not exist yet. When a feature builds or compares names, take over
  `Core/Names.lua` from GryphonMail. Until then names are only shown, with the first return of
  `UnitName` (the first name on Forever).

## Damage meter look

- The window copies the look of `Blizzard_DamageMeter` (`DamageMeterSessionWindow.xml`,
  `DamageMeterEntry.xml` / `.lua`) with own frames: same atlases, fonts, sizes and anchors, and the
  styles Default, Thin and Bordered (`DamageMeterEntryMixin:Setup*Style`). It does not inherit or
  hook Blizzard's damage meter templates, so it works without the damage meter being enabled and
  does not taint it.
- Atlases, fonts and colors that may differ between clients are in `Compat.GetMeterStyle()`. When
  Blizzard changes the damage meter, compare the `live` and `forever` branches and update it there.
  The `forever` branch adds `Camelot/DamageMeterEntryOverrides.lua` (no classification icons), and
  `DamageMeterEntry.lua` / `DamageMeterSessionWindow.lua` differ only in classification icons,
  secret value checks and the scroll box; the Edit Mode settings and defaults are the same.
- The Edit Mode settings mirror the damage meter's (`Blizzard_EditMode/Shared/EditModeSettingDisplayInfo.lua`,
  `Enum.EditModeSystem.DamageMeter`; defaults from `Mainline/EditModePresetLayouts.lua`). The values
  of style, numbers and visibility are the ones of Blizzard's `Enum.DamageMeterStyle`,
  `Enum.DamageMeterNumbers` and `Enum.DamageMeterVisibility`.

## Threat values

- `UnitDetailedThreatSituation` returns secret values when `C_Secrets.ShouldUnitThreatValuesBeSecret`
  says so (e.g. in restricted content). Secret values are passed unchanged to `StatusBar:SetValue`
  and `FontString:SetText` / `SetFormattedText`; they can not be sorted, so the list keeps the group
  order then. All of this goes through `Compat.GetThreat`.
- The threat on "targettarget" is secret on Retail and Forever and sends no
  `UNIT_THREAT_LIST_UPDATE`, so only the own target is used there (`Compat.CanUseTargetOfTarget`).
- `UNIT_THREAT_LIST_UPDATE` fires for every mob; the window only redraws for the shown one.
- The unit with aggro is shown with 100 % (`Compat.GetThreat`), the API sometimes returns less.
- `rawThreat` is the threat itself and is shown unchanged (verified on Retail and Forever: about the
  damage done times the threat modifier, not times 100).

## Threat at the target frame

`Modules/TargetFrameThreat.lua` only switches the CVar `threatShowNumeric`, which has no Blizzard
setting on Retail and Forever; the display is Blizzard's own (`UnitFrame_UpdateThreatIndicator`). The
game stores the value, so there is no saved variable, and the option is in the settings menu of the
window instead of Edit Mode, because it does not depend on the layout.

## Libraries

- `.tools/fetch-libs.cmd` fetches the same library versions as the `externals` in `.pkgmeta`
  (LibStub, LibEditMode) into `Libs/`. luacheck skips `Libs/`.
- LibEditMode's license only allows embedding it unmodified.
- LibEditMode (`LibStub("LibEditMode")`) adds the threat window and its settings dialog to Blizzard's
  Edit Mode (`Modules/ThreatWindowSettings.lua`). API docs: the comments in
  `Libs/LibEditMode/LibEditMode.lua` and https://github.com/p3lim-wow/LibEditMode/wiki.

## Locales

`enUS` (base), `deDE`, `frFR`.

## Saved variables

- `GryphonThreatDB` (account-wide): debug, and the Edit Mode settings of the threat window per
  layout name in `layouts` (position, size, style, ...). The module handles LibEditMode's `create`,
  `rename` and `delete` callbacks.
- `GryphonThreatCharDB` (per character): window shown, locked, minimized and notifications, like the
  damage meter's `DamageMeterPerCharacterSettings`.

## Testing

`/gryphonthreat test` and Edit Mode fill the window with sample bars, as Edit Mode does for the
damage meter.

## Commit scopes

`threat-data`, `threat-window`, `threat-window-settings`, `target-frame-threat`, `core`, `locales`, `toc`.

# GryphonThreat

A World of Warcraft addon that shows the threat on your target in a window that looks like the
built-in damage meter.

## Features

- **Threat window:** one bar per group member (and pet) with the threat on your target, highest
  first, in the look of Blizzard's damage meter: header bar, class colors and icons, "1. Name" and
  "threat (percent)". The bar shows how close a unit is to pulling aggro (100 % = has aggro). With
  class colors turned off, the bars turn from green over yellow to red as a unit gets closer to it.
- **Pull aggro bar (optional):** while someone else has aggro, the first bar shows how much threat
  you still need to pull it (110 % in melee range, 130 % at range). It fills up and turns from
  green over yellow to red as you get closer.
- **Always yourself:** if your bar is below the visible bars, the last visible bar shows you.
- **Edit Mode:** the window is part of Blizzard's Edit Mode (Esc > Edit Mode), with the same
  settings as the damage meter: style (default, bordered, thin), numbers (minimal, compact,
  complete), frame width and height, bar height, padding, opacity, background, text size, visibility
  (always, in combat, in group, hidden), class icons, class colors and the pull aggro bar. Saved per
  Edit Mode layout. As in the damage meter, the selection overlay hides while you preview the
  style, opacity or background.
- **Window:** move by dragging, resize with the handle in the bottom right corner (both saved in the
  Edit Mode layout), minimize with the button in the header, lock and hide in the settings menu
  (gear button). Shown, locked and minimized are stored per character.
- **Test mode:** sample bars to place and size the window without a fight; Edit Mode shows them too.

The full description for CurseForge and Wago is in [docs/addon-description.md](docs/addon-description.md),
for WoWInterface (BBCode) in [docs/addon-description-wowinterface.txt](docs/addon-description-wowinterface.txt).

## Supported clients

| Client  | Interface | Status                                   |
| ------- | --------- | ---------------------------------------- |
| Retail  | 120105    | Supported, in development                |
| Forever | 16001     | Planned (not yet in `## Interface:`)     |

Both use the Mainline UI and API. Client differences are handled in `Core/Compat.lua`.

Known limitations:

- Only the threat on your own target is shown. The threat on the target of a friendly target (e.g.
  the tank's target) is secret on Retail and Forever.
- In restricted content, Blizzard makes threat values secret. The window then shows the percentage
  only and keeps the group order, because secret values can not be sorted. The pull aggro bar is
  hidden then.
- The window can not be changed in Edit Mode during combat (LibEditMode blocks it); the addon says
  so in the chat.

## Installation

Install it from [Wago Addons](https://addons.wago.io/addons/gryphonthreat), or copy (or symlink)
the `GryphonThreat` folder into the client's AddOns folder:

```
World of Warcraft\<client folder>\Interface\AddOns\GryphonThreat
```

During development, run `.tools\fetch-libs.cmd` once, then `.tools\deploy-retail.cmd` (or
`.tools\deploy-forever.cmd`) copies the addon there.

## Libraries

The packager embeds these libraries from the externals in `.pkgmeta`:

- [LibStub](https://www.wowace.com/projects/libstub) (public domain)
- [LibEditMode](https://github.com/p3lim-wow/LibEditMode) by p3lim: adds own frames to the Edit
  Mode. Its license allows embedding it unmodified into an addon; it stays under its own license
  (`Libs/LibEditMode/LICENSE.txt`), not under the MIT license of GryphonThreat.

## Releasing

1. Move the `[Unreleased]` entries in `CHANGELOG.md` to a new version section and bump
   `## Version` in `GryphonThreat.toc`, then merge that into `main`.
2. Tag the merge commit on `main` and push the tag:

   ```
   git tag v0.1.0
   git push origin v0.1.0
   ```

3. The `Release` workflow runs luacheck, builds the package with the
   [BigWigs packager](https://github.com/BigWigsMods/packager) and uploads it to CurseForge (project
   ID from `X-Curse-Project-ID` in the TOC), Wago Addons (`X-Wago-ID`), WoWInterface
   (`X-WoWI-ID`) and as a GitHub release. Game versions come from `## Interface`. It needs the
   repository secrets `CF_API_KEY`, `WAGO_API_TOKEN` and `WOWI_API_TOKEN`. So far only the Wago ID
   is in the TOC; the packager skips sites without an ID.

## Structure

```
GryphonThreat/
├── .github/workflows/
│   ├── luacheck.yml       # luacheck on pushes to main and on pull requests
│   └── release.yml        # Builds and uploads a release on version tags (BigWigs packager)
├── .pkgmeta               # Packager config: libraries, changelog and files left out of the package
├── GryphonThreat.toc      # Addon manifest, defines load order
├── LICENSE                # MIT license
├── docs/
│   ├── addon-description.md  # Description text for CurseForge / Wago, Markdown (not shipped)
│   └── addon-description-wowinterface.txt  # Same text for WoWInterface, BBCode (not shipped)
├── Libs/                  # Embedded libraries, not in the repo (fetched by the packager)
├── Locales/
│   ├── enUS.lua           # Base locale (fallback, all keys)
│   ├── deDE.lua           # German translation
│   └── frFR.lua           # French translation
├── Core/
│   ├── Init.lua           # Namespace, saved variable defaults, module registry, event dispatcher
│   ├── Compat.lua         # Client differences (Retail, Forever): threat API, secret values, damage meter look
│   ├── Util.lua           # Print/Debug helpers, debug memory output, defaults
│   └── Main.lua           # Bootstrap: saved variables, module lifecycle, slash commands
└── Modules/
    ├── ThreatData.lua     # Threat of the group (with pets) on the target, sorted
    ├── ThreatWindow.lua   # Window in the look of the damage meter, layout settings, window commands
    └── ThreatWindowSettings.lua # Edit Mode integration and settings dialog (LibEditMode)
```

## Adding a module

1. Create `Modules/MyModule.lua`:

   ```lua
   local _, ns = ...
   local MyModule = ns:RegisterModule("MyModule")

   function MyModule:OnInitialize() end -- saved variables available
   function MyModule:OnEnable() end     -- PLAYER_LOGIN
   ```

2. Add it to `GryphonThreat.toc` above `Core\Main.lua`.

## Localization

All strings live in `Locales/`. Add new keys to `enUS.lua` first; other locales
only override what they translate. Missing keys fall back to English.

## Development

Lint with [luacheck](https://github.com/lunarmodules/luacheck). Place `luacheck.exe` in `.tools/`
(ignored by git) and run from the repo root:

```
./.tools/luacheck.exe .
```

`sh .tools/check-interface.sh` compares the live client versions with `## Interface:`.

## Slash commands

`/gryphonthreat` or `/gthreat`:

- `/gryphonthreat` – help
- `/gryphonthreat show` / `hide` – show or hide the threat window
- `/gryphonthreat lock` – lock or unlock the threat window
- `/gryphonthreat reset` – reset position and size of the threat window (current Edit Mode layout)
- `/gryphonthreat test` – show sample bars to place the window
- `/gryphonthreat version` – show version
- `/gryphonthreat notify on|off` – automatic messages (login), default on
- `/gryphonthreat debug` – toggle debug output (after a `/reload`, also the memory each module keeps;
  the memory in use at combat start and end)

Modules add subcommands with `ns:RegisterCommand(name, handler, helpLines)`.

## License

[MIT](LICENSE)

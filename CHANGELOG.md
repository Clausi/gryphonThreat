# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-10-31

### Added

- Threat window in the look of the built-in damage meter: the threat of your group and pets on your
  target, highest first, with class colors and icons. The title shows the name of the target.
- Your own bar stays visible when the list is longer than the window.
- With class colors turned off, the bars turn from green over yellow to red as a unit gets closer to
  pulling aggro.
- Optional "Pull Aggro" bar: while someone else has aggro, the first bar shows how much threat you
  still need to pull it (110 % in melee range, 130 % at range). It turns from green to red as you
  get closer.
- The window is part of Edit Mode, with the settings of the damage meter: style, numbers, frame
  size, bar height, padding, opacity, background, text size, visibility, class icons, class colors
  and the pull aggro bar. Saved per Edit Mode layout. As in the damage meter, the selection overlay
  hides while you preview the style, opacity or background. Like the damage meter, the window has a
  resize handle in Edit Mode.
- Moving, resizing, minimizing, locking and hiding the window; shown, locked and minimized are stored
  per character.
- Test mode with sample bars (`/gryphonthreat test` or the settings menu).
- Slash commands `/gryphonthreat` (`/gthreat`): `show`, `hide`, `lock`, `reset`, `test`, `version`,
  `notify`, `debug`.
- English, German and French texts.

[Unreleased]: https://github.com/Clausi/gryphonThreat/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Clausi/gryphonThreat/releases/tag/v0.1.0

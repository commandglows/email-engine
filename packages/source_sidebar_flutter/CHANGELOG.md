# Changelog

## Unreleased

- Show a localized in-app message when the shared workspace zoom reaches its
  configured minimum or maximum.
- Added complete keyboard reading controls, optional account switching and chooser,
  host-owned summaries, and unique multi-project distribution.
- Made keyboard help capability-aware and restored a valid workspace focus after
  cancelled, successful, or failed asynchronous host actions.

## 0.4.0

- Renamed the visible label concept to Categories and added host-defined names,
  colors, and icons while keeping `SourceSidebarItem.tags` compatible.
- Added accessible fallback presentation for category identifiers without a
  host definition.
- Added bounded whole-interface zoom with Ctrl/Command+wheel and a customizable
  Ctrl/Command+0 reset command, without replacing native text scaling.
- Reused the focused `shipglows_flutter_zoom` package as the canonical zoom
  implementation for adoption by other Flutter applications.
- Made keyboard row navigation reclaim primary focus from toolbar controls so
  the active cursor, focus styling, and Enter activation remain synchronized.

## 0.3.0

- Added complete, host-customizable keyboard navigation with Glows defaults:
  `W` delete, `E` archive, `L` Later, `V` move, `J/K` navigation, explicit
  open/back/search commands, and `?` help.
- Added provider-neutral move destinations and protected all alphabetic
  shortcuts while an editable text control owns focus.
- Added visible row focus, predictable focus restoration, and automatic scroll
  tracking for the active source.
- Added an optional Later navigation state that removes configured Later items
  from Inbox while preserving the legacy Inbox behavior when Later is absent.

## 0.2.0

- Rebuilt the interface as a faithful, full-height source workspace with a
  global search header, left navigation, dense inbox rows, and an in-place
  reading surface.
- Added inbox, unread, processed, archived, and label filtering.
- Added provider-neutral header actions and an optional library callback.
- Preserved responsive keyboard navigation and exposed semantic color tokens.

## 0.1.0

- Initial provider-neutral Flutter port of the source sidebar interaction.
- Responsive list and reading panes, search, keyboard selection, source actions,
  loading, empty, error, and confirmation states.

# source_sidebar_flutter

A provider-neutral Flutter source workspace rebuilt from the interaction and
visual grammar of the original prototype in this repository.

The package owns the global search header, left navigation and categories, dense
inbox rows, in-place reading, responsive behavior, keyboard focus, accessible
actions, and state presentation. It deliberately does not know about Readwise,
authentication, project routing, agents, or persistence. Applications supply
already-sanitized plain-text content and callbacks.

```dart
SourceSidebar(
  title: 'Technical sources',
  items: items,
  selectedId: selectedId,
  onSelected: selectSource,
  onOpenLibrary: openProviderLibrary,
  onIngest: ingestSource,
  onArchive: archiveSource,
  onDelete: deleteSource,
  moveDestinations: const [
    SourceMoveDestination(id: 'later', label: 'Later'),
    SourceMoveDestination(id: 'reference', label: 'Reference'),
  ],
  laterDestinationId: 'later',
  onMove: moveSource,
  accounts: accounts,
  currentAccountId: currentAccountId,
  onAccountSelected: switchAccount,
  onSummarize: summarizeSource,
  projectDestinations: projects,
  onDistribute: distributeSource,
  categories: const [
    SourceCategory(
      id: 'security',
      name: 'Cybersecurity',
      color: Color(0xFFB3261E),
      icon: Icons.shield_outlined,
    ),
  ],
)
```

Hosts can map their semantic palette through `SourceSidebarStyle.colors` and
can add provider-neutral widgets to `topBarActions`. The package includes
inbox, unread, processed, archived, search, and category filters without
mutating the supplied collection. `SourceSidebarItem.tags` remains the stable,
backwards-compatible list of category identifiers. Definitions supplied through
`categories` control their visible name, color, and icon. An unknown identifier
remains usable and accessible with its raw value and the fallback label icon.
If definitions repeat an identifier, the last definition wins.

Consumers should pin an immutable Git commit:

```yaml
source_sidebar_flutter:
  git:
    url: https://github.com/commandglows/email-sidebar-app.git
    ref: <commit-sha>
    path: packages/source_sidebar_flutter
```

Never pass unsanitized HTML or remote-image markup into `content`. Provider
credentials and destructive-action authorization belong to the host.

## Keyboard contract

The default Glows bindings are `J/K` and the arrow keys to navigate, `O` or
Enter to open, `/` or Ctrl/Command+F to search, `U` or Escape to return,
`E` to archive, `W` to delete with confirmation, `V` to choose a move
destination, `L` to move directly to the configured Later destination, and
Ctrl/Command+Shift+`I` to send to the legacy single-project action,
Ctrl/Command+Shift+`S` to summarize, Ctrl/Command+Shift+`D` to select and send
to one or more projects, `[`/`]` to switch accounts, and Ctrl/Command+Shift+`A`
to choose an account. In the reader, Alt+Up/Down scrolls by line, PageUp/PageDown
by page, and Home/End goes to the content boundary. `?` shows only commands
whose host capability is available. Tab, Shift+Tab, Enter, and Space continue to use
Flutter's native focus traversal and button activation.

Alphabetic commands are ignored whenever any editable text control owns focus.
The active row uses `SourceSidebarColors.focus`, regains focus after dialogs and
actions, and is scrolled into view during keyboard navigation.
Using `J/K` or the arrow keys also transfers primary focus from any previously
tabbed toolbar control to the active source row, so focus styling and native
Enter activation remain synchronized.

When `laterDestinationId` is configured, Later appears as a counted navigation
state and those items leave Inbox while remaining recoverable there. Without
that configuration, Inbox keeps its previous behavior; other host-defined move
locations remain in Inbox.

Every command accepts a typed list of `ShortcutActivator`s. Replace a list to
customize it or pass an empty list to disable the command without forking:

```dart
shortcuts: const SourceSidebarShortcuts(
  delete: [SingleActivator(LogicalKeyboardKey.keyD)],
  archive: [],
),
```

If two customized bindings collide, the later command in the documented
constructor order wins. Accounts and project destinations use opaque host-owned
identifiers. Project selection is de-duplicated and cannot be submitted empty.
Summary, account switching, and distribution remain optional callbacks; failures
are reported through `onActionError` and keyboard focus is restored. Move destinations are host-owned identifiers and
labels; the package does not translate them into provider API concepts.

## Interface zoom

Ctrl/Command+mouse wheel scales the complete workspace, including layout,
icons, spacing, and text. Responsive breakpoints are recalculated against the
zoomed logical viewport, ordinary wheel scrolling is left untouched, and the
ambient Flutter text scaler continues to apply. Ctrl/Command+0 resets the
workspace to `SourceSidebarStyle.initialZoom`.

The behavior is supplied by the shared `shipglows_flutter_zoom` package so
other Flutter applications can adopt the same tested viewport independently.

Hosts can configure `minimumZoom`, `maximumZoom`, `initialZoom`, and `zoomStep`
through `SourceSidebarStyle`. They can replace or disable the reset shortcut
through `SourceSidebarShortcuts.resetZoom`.
# Unified email groups

Hosts can reuse the existing dense rows and reader across providers using
`itemSectionIds` and ordered `sectionLabels`. `navigationHeader` inserts facet
links into the existing sidebar. `sectionKeys` supplies scroll anchors;
`sectionEmptyMessages` keeps individual empty/error states visible.
`readerFooter` adds contextual actions without creating another reader.
Without grouping, the original Sources behavior is unchanged.

---
artifact: design_system_authority
metadata_schema_version: "1.0"
artifact_version: "1.3.0"
project: flutter-source-and-newsletter-workspace
created: "2026-08-26"
updated: "2026-08-27"
status: active
source_skill: 006-sg-design
scope: public-flutter-workspace-preview
owner: Diane
confidence: high
risk_level: low
security_impact: none
docs_impact: yes
linked_systems:
  - packages/source_sidebar_flutter/lib/src/source_sidebar_style.dart
  - packages/newsletter_studio_flutter/lib/src/newsletter_studio_style.dart
  - demo/lib/preview_theme.dart
depends_on: []
supersedes: []
evidence:
  - "The package owns provider-neutral layout and semantic color adapters through SourceSidebarStyle and SourceSidebarColors."
  - "The preview owns its explicit light and dark semantic palettes through PreviewTheme."
  - "Inspected Flutter captures exist for list and reader states at 1440x900 and 390x844 under shipglows_data/visual-proof."
  - "Category names, accent colors, and icons are host-owned semantic inputs; the package owns their accessible fallback and consistent navigation, row, and reader presentation."
  - "Whole-workspace zoom limits and increments are centralized in SourceSidebarStyle while ambient Flutter text scaling remains independently active."
  - "NewsletterStudioStyle owns newsletter breakpoints, pane geometry, review surfaces, density, transitions, and zoom; PreviewTheme maps both package palettes to one host visual language."
next_review: "2027-02-26"
next_step: "Prove the unified source-to-newsletter flow, responsive states, category rendering, focus transfer, and whole-workspace zoom through CI and an authorized hosted preview."
---

# Flutter Workspace Design-System Authority

The reusable packages consume Flutter `ThemeData` and expose semantic layout
and color adapters through `SourceSidebarStyle`, `SourceSidebarColors`,
`NewsletterStudioStyle`, and `NewsletterStudioColors`. Host applications own
their brand tokens and may map them explicitly; neither package may introduce
a product brand or provider assumption.

Category identifiers remain source data, while each host supplies their visible
name, accent color, and icon through `SourceCategory`. Category accent colors do
not replace theme-owned foreground text colors, so an arbitrary host accent
cannot silently become the only readability mechanism. Unknown identifiers use
the package's accessible semantic fallback.

The public preview's sole host-theme authority is `PreviewTheme`. It maps both
packages to the light and dark palettes derived from the v0 reference: white
surfaces, a blue-gray canvas and search field, pale-blue selection, restrained
blue focus, and compact neutral typography. Demo screens must not add local
colors.

`SourceSidebarStyle` remains the sole package authority for breakpoints,
navigation width, global-header height, content padding, radii, row density,
action sizing, category presentation, and workspace zoom bounds. Zoom changes
the logical viewport used by responsive breakpoints but does not replace the
ambient Flutter text scaler. The inspected captures in
`shipglows_data/visual-proof` define the durable visual baseline for this
implementation.

`NewsletterStudioStyle` is the sole newsletter-package authority for adaptive
breakpoints, pane and review widths, canvas density, blocks, transitions,
semantic warning surfaces, and workspace zoom. Newsletter Studio follows the
same visual language but preserves its own interaction contract: source tray,
focused composition canvas, contextual inspector, and a distinct delivery
review surface. The embedded message preview is approximate and is never a
substitute for received-client proof.

The campaign workspace reuses `NewsletterStudioStyle` and its semantic colors,
spacing and radii. The authenticated web operator's host theme is `EngineTheme`
in `app/lib/engine_theme.dart`, preserving the existing blue accent through
Material ColorScheme for both brightness modes. The synthetic preview remains
owned by `PreviewTheme`. These hosts share the package's layout authority.
# Cockpit extension

`EmailCockpitLayout` owns cockpit geometry and breakpoints. Shared cockpit and
support colors derive from the host Material ColorScheme, with Material icons.
Tests cover retained workspace state, drawer navigation, narrow dark support at
large text, and explicit confirmation. Rendered proof includes the integrated
dashboard and support conversation, separately from authenticated provider proof.

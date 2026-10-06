---
artifact: code_docs_map
metadata_schema_version: "1.0"
artifact_version: "1.0.0"
project: email-sidebar-app
created: "2026-09-03"
updated: "2026-09-03"
status: reviewed
source_skill: sg-docs
scope: repository-code-to-documentation-routing
owner: Diane
confidence: high
risk_level: medium
security_impact: yes
docs_impact: yes
linked_systems:
  - packages/source_sidebar_flutter
  - packages/newsletter_studio_flutter
  - packages/shipglows_flutter_zoom
  - demo
  - scripts/vercel-build.sh
  - shipglows_data/technical/README.md
  - shipglows_data/technical/design-system-authority.md
depends_on:
  - artifact: shipglows_data/technical/README.md
    artifact_version: "1.0.0"
    required_status: reviewed
  - artifact: shipglows_data/technical/design-system-authority.md
    artifact_version: "1.3.0"
    required_status: active
supersedes: []
evidence:
  - Major tracked code, configuration, public documentation, and test paths inspected on 2026-09-03.
  - Keyboard-first email workspace verified with 19 package tests and 7 demo tests.
next_review: "2026-12-03"
next_step: apply this map to every code-changing documentation reflection
---

# Code-to-Documentation Map

This file is the canonical path-to-documentation router for the repository. It
does not duplicate package usage guides or implementation specs. It identifies
which document owns the contract that may change when a code path changes.

## Mapping Contract

For each task-owned changed path, match the most specific row. Read the primary
owner before editing, consult secondary context only when the trigger applies,
and include the listed proof surface in the documentation reflection. A change
is `not impacted` only when the matched row's trigger is demonstrably false.
An unmatched tracked code area is `needs review` until this map is extended.

| Code or configuration path | Responsibility | Primary documentation owner | Secondary context | Update trigger | Focused proof |
| --- | --- | --- | --- | --- | --- |
| `packages/source_sidebar_flutter/lib/**` | Source/email list, reader, keyboard workflow, models, host callbacks, and presentation API | `packages/source_sidebar_flutter/README.md` | `design-system-authority.md`; active source-sidebar spec | Public API, shortcut, focus, state, callback, host-boundary, layout, or styling behavior changes | `cd packages/source_sidebar_flutter && flutter analyze && flutter test` |
| `packages/source_sidebar_flutter/test/**` | Durable source-sidebar behavior proof | `packages/source_sidebar_flutter/README.md` | Active source-sidebar spec | Accepted behavior, supported scenario, or documented proof claim changes; pure refactoring of equivalent assertions is non-impacting | `cd packages/source_sidebar_flutter && flutter test` |
| `packages/source_sidebar_flutter/pubspec.yaml` | Package identity, SDK range, and dependencies | `packages/source_sidebar_flutter/README.md` | Root `README.md` | Consumer requirements, dependency model, installation path, or supported runtime changes | `cd packages/source_sidebar_flutter && flutter pub get && flutter analyze && flutter test` |
| `packages/newsletter_studio_flutter/lib/**` | Newsletter composition, review, preview, delivery handoff, models, and host callbacks | `packages/newsletter_studio_flutter/README.md` | `design-system-authority.md`; active newsletter spec | Public API, shortcut, workflow, validation, delivery boundary, layout, or styling behavior changes | `cd packages/newsletter_studio_flutter && flutter analyze && flutter test` |
| `packages/newsletter_studio_flutter/test/**` | Durable Newsletter Studio behavior proof | `packages/newsletter_studio_flutter/README.md` | Active newsletter spec | Accepted behavior, supported scenario, or documented proof claim changes | `cd packages/newsletter_studio_flutter && flutter test` |
| `packages/newsletter_studio_flutter/pubspec.yaml` | Package identity, SDK range, and dependencies | `packages/newsletter_studio_flutter/README.md` | Root `README.md` | Consumer requirements, dependency model, installation path, or supported runtime changes | `cd packages/newsletter_studio_flutter && flutter pub get && flutter analyze && flutter test` |
| `packages/shipglows_flutter_zoom/lib/**` | Shared whole-workspace zoom and reset behavior | `packages/shipglows_flutter_zoom/README.md` | `design-system-authority.md` | Zoom API, supported input, bounds, scaling, viewport, or reset behavior changes | `cd packages/shipglows_flutter_zoom && flutter analyze && flutter test` |
| `packages/shipglows_flutter_zoom/test/**` | Durable shared-zoom proof | `packages/shipglows_flutter_zoom/README.md` | None; tests are the proof owner | Supported scenario or documented proof claim changes | `cd packages/shipglows_flutter_zoom && flutter test` |
| `packages/shipglows_flutter_zoom/pubspec.yaml` | Package identity, SDK range, and dependencies | `packages/shipglows_flutter_zoom/README.md` | Root `README.md` | Consumer requirements, dependency model, installation path, or supported runtime changes | `cd packages/shipglows_flutter_zoom && flutter pub get && flutter analyze && flutter test` |
| `demo/lib/**` | Synthetic integration, theme mapping, and provider-free host behavior | Root `README.md` | `design-system-authority.md`; affected package README | Demonstrated capability, synthetic/real boundary, package integration, theme mapping, or visible workflow changes | `cd demo && flutter analyze && flutter test` |
| `demo/test/**` | Cross-package integration proof | Root `README.md` | Affected package README and active spec | Demonstrated scenario or repository validation claim changes | `cd demo && flutter test` |
| `demo/pubspec.yaml` | Demo SDK and local package composition | Root `README.md` | Package READMEs | Local dependency graph, runtime requirement, or preview command changes | `cd demo && flutter pub get && flutter analyze && flutter test` |
| `demo/web/**` | Installable web shell metadata | Root `README.md` | None; standard Flutter-generated shell has explicit non-coverage | App name, icons, install behavior, browser metadata, or public shell behavior changes | `cd demo && flutter build web --release` |
| `scripts/vercel-build.sh`, `vercel.json` | Hosted demo build and routing contract | Root `README.md` | `PITCH.md` only when public availability claims change | Flutter version, build command, output path, routing, or deployment expectation changes | Review command/path consistency, then run the declared release build in an authorized release context |
| `analysis_options.yaml`, `**/analysis_options.yaml` | Static-analysis policy | This map | Package README only if consumer-visible requirements change | Rule-set, exclusion, or analyzer invocation changes | Run `flutter analyze` in every affected package/app |
| `.github/**` | Repository automation | Root `README.md` when validation or delivery claims change | This map | CI checks, release behavior, supported validation, permissions, or artifact handling changes | Validate workflow syntax and observe the corresponding authorized CI run |

## Campaign Integration Coverage

Cockpit and support: `packages/newsletter_studio_flutter/lib/src/email_cockpit.dart`
and `support_*.dart` map to the package README/CHANGELOG and design authority.
`app/lib/source_workspace.dart` and `support_repository.dart` map to app/README
and the CommandGlows Reader/support API contract. `demo/lib/support_demo_repository.dart`
is explicitly synthetic and maps to the root README. No real mailbox content is
an allowed demonstration fixture.

Additional campaign scope: `app/**` maps to `app/README.md`, with the newsletter
package README and CommandGlows campaign API contract as integration references.
Validate with the app analyzer/tests and the CI web artifact. The local artifact
installer `scripts/install-operator-web.ps1` maps to the same app README; verify
its exact source/target and installed index. Neither path implies deployment.

## Explicit Non-Coverage

| Path family | Reason |
| --- | --- |
| Generated Flutter directories and `.dart_tool/**` | Disposable outputs are not canonical source or documentation. |
| `build/**`, `.vercel/**`, and test-output directories | Disposable proof/build artifacts; never document them as durable implementation state. |
| `.mcp.json` | Agent integration configuration; document only when it changes an operator-visible setup or proof route. Never copy credentials or private configuration into documentation. |
| `ENVIRONMENT.md` | ShipGlows-managed runtime metadata, not a product-code documentation owner. Its lifecycle is governed by the development environment. |
| `LICENSE` and `.gitignore` | Self-describing repository policy files; map them only if a future change creates a material consumer or governance consequence. |

## Documentation Update Plan

For every code-changing workstream, record:

| Changed path | Matched map row | Documentation action | Owner role | Proof |
| --- | --- | --- | --- | --- |
| `<task-owned path>` | `<most specific row>` | `update <doc>` or `not impacted — <trigger is false because…>` | `executor` or `integrator` | `<focused command or inspected evidence>` |

Shared files such as this map, the technical entrypoint, and the design-system
authority use the `integrator` role. Package-specific README and changelog
updates normally use the `executor` role.

## Reader Checklist

- New tracked code directory -> add a mapping or an explicit non-coverage row.
- Public API or host-boundary change -> update the owning package README and changelog.
- Keyboard, focus, dialog, responsive, theme, or visual behavior change -> load
  `design-system-authority.md` and run the mapped Flutter proof plus the
  design-system drift check.
- Test-only change -> decide whether the accepted/documented behavior changed;
  assertion refactoring alone does not require public documentation churn.
- Build/deploy configuration change -> reconcile the root validation and
  availability claims without implying deployment from build success.
- Provider/auth/data/recipient behavior introduced -> create or map a dedicated
  technical owner before implementation; current presentation-package docs are
  insufficient for that trust boundary.

## Maintenance Rule

Update this map in the same workstream whenever a major code area, documentation
owner, validation command, public API boundary, design authority, or explicit
non-coverage decision changes. Review unmatched changed paths before any
completion claim.

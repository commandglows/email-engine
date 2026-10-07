---
artifact: technical_context
metadata_schema_version: "1.0"
artifact_version: "1.1.0"
project: email-sidebar-app
created: "2026-09-03"
updated: "2026-10-07"
status: reviewed
source_skill: sg-docs
scope: technical-documentation-entrypoint
owner: Diane
confidence: high
risk_level: low
security_impact: no
docs_impact: yes
linked_systems:
  - shipglows_data/technical/code-docs-map.md
  - shipglows_data/technical/design-system-authority.md
depends_on: []
supersedes: []
evidence:
  - Repository code, package READMEs, tests, and validation commands inspected on 2026-09-03.
  - 2026-10-07: authenticated operator app added as a major technical surface, routed to the app guide and CommandGlows API contract.
next_review: "2027-03-03"
next_step: keep mappings aligned with code ownership
---

# Technical Documentation

This directory is the canonical internal technical-documentation entrypoint for
the repository. Public setup and package-consumer guidance remain in the root
and package `README.md` files; implementation contracts, ownership, and
documentation routing belong here.

## Navigation

- [`code-docs-map.md`](code-docs-map.md) maps code paths to their owning
  documentation, proof surface, and documentation-update trigger.
- [`design-system-authority.md`](design-system-authority.md) owns the Flutter
  workspace's theme, token, layout, motion, and visual-proof constraints.
- [`../workflow/specs/`](../workflow/specs/) owns implementation contracts and
  chantier history; specs do not replace current package documentation.

## Technical Surfaces

| Surface | Responsibility | Primary entrypoint |
| --- | --- | --- |
| Authenticated operator app | Server-backed source reader, Gmail support and campaign controls | `app/README.md` and mapped CommandGlows API contracts |
| Source sidebar | Provider-neutral source and email review, keyboard processing, categories, and host callbacks | `packages/source_sidebar_flutter/README.md` |
| Newsletter Studio and support cockpit | Provider-neutral newsletter composition and support presentation models/workspace | `packages/newsletter_studio_flutter/README.md` |
| Shared zoom | Whole-workspace Flutter web/desktop zoom behavior | `packages/shipglows_flutter_zoom/README.md` |
| Demo | Synthetic integration and visual/proof host for all packages | Root `README.md` |
| Web build | Reproducible hosted demo build only | Root `README.md` and `scripts/vercel-build.sh` |

## Reader Workflow

1. Start with `code-docs-map.md` when a task names a code path.
2. Load only the mapped internal authority and public contract.
3. Use the mapped tests and validation commands as the first proof surface.
4. Update mapped documentation in the same workstream when a trigger applies.
5. Treat missing coverage as a documentation-governance gap rather than
   inferring ownership from the nearest README.

## Security Boundary

The reusable packages are presentation components. Hosts own authentication,
authorization, persistence, provider APIs, recipient consent, sanitization,
idempotency, and external side effects. Internal documentation must never store
credentials, tokens, private URLs, provider payloads, recipient data, or raw
logs.

## Validation

Run the focused analyzer and test suite declared for the affected surface in
`code-docs-map.md`. Validate changed governed Markdown with the canonical
ShipGlows metadata linter and rerun the governance-topology audit after moving
or adding canonical documentation.

## Maintenance Rule

Update this entrypoint when a major technical surface, canonical authority, or
documentation-navigation layer is added, removed, or reassigned.

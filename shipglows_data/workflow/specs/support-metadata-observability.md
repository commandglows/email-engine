---
artifact: implementation_spec
metadata_schema_version: "1.0"
artifact_version: "1.0.1"
project: email-sidebar-app
created: "2026-10-07"
updated: "2026-10-07"
status: active
source_skill: sg-development
scope: support-gmail-metadata-observability
owner: Diane
confidence: high
risk_level: high
security_impact: yes
docs_impact: yes
linked_systems: [app, newsletter_studio_flutter, source_sidebar_flutter, CommandGlows, Gmail]
depends_on: [shipglows_data/workflow/specs/support-rich-email.md, shipglows_data/technical/design-system-authority.md, C:/Users/Diane/ShipGlows/commandglows/shipglows_data/technical/gmail-support-api.md]
supersedes: []
evidence:
  - "Operator explicitly requests editable Gmail metadata and incoming observability with logs and metrics."
  - "At task intake, Gmail OAuth asked for gmail.readonly and gmail.send; support listed the inbox on demand and stored operator statuses/reply locks but no ingress event ledger or metrics."
  - "2026-10-07: local backend and Flutter implementation now exposes Gmail-confirmed metadata writes and bounded operator-observed ingress/failure records; Flutter/Dart static analysis passed, while backend typecheck and focused tests remain unproven."
next_review: "2026-11-07"
next_step: "Complete focused backend and Flutter test/typecheck proof before marking this implementation reviewed; live OAuth and mailbox proof remain separate."
---

# Support Gmail metadata and incoming observability

## Contract

- Add authenticated per-thread mark read/unread and archive/restore controls.
  Gmail owns these facts; distinguish them from local pending/waiting/resolved
  support statuses. Confirm writes from Gmail before updating the UI.
- Use Gmail `gmail.modify` only for mailboxes whose owner reconnects and grants
  it. Preserve separate `gmail.send`; never imply an old readonly connection can
  mutate Gmail. No provider credential reaches Flutter.
- Record a bounded, deduplicated ingress activity row per newly observed incoming
  Gmail message; never persist body, subject, address, or attachment data.
  Distinguish `observed in mailbox` from provider receipt or downstream delivery.
- Surface recent ingress entries and counts from persisted rows: retained rows
  in the selected window, per state, lag/freshness and sample/coverage. The
  selected 90-day query window and 500-row cap bound the available history; the
  cap can evict older in-window rows. Mark coverage
  partial because Gmail is observed through operator paging; no push-sync daemon
  is configured. Missing/empty/unavailable stays distinct from zero.
- Display operational failure stage, stable error code, first/last occurrence,
  attempt count and retryability without private payload. Any retry must be an
  explicit read/refresh reconciliation; do not replay or redeliver customer mail.

## Execution batches

1. `commandglows/commandglows_site/src/lib/email/support/**`, Convex support
   event storage, focused tests, and CommandGlows Gmail support contract. Owner:
   backend observability agent; Gmail metadata mutations and read/summary hooks
   are included in this batch.
2. `email-engine/app/**` and only required presentation-package API
   additions, tests, UI and docs. Owner: app agent. Consume the backend HTTP
   contract agreed before integration; no edits in CommandGlows.

The primary agent owns shared-contract review, integration verification,
configuration/proof boundaries, and final documentation reconciliation.

## Required proof

Server tests cover OAuth scope migration, read/unread and archive/restore
ownership, stale messages, idempotent ingress observation, PII redaction,
bounded window metrics, honest freshness/coverage, and provider failures.
Flutter tests cover confirmed metadata controls, loading/recovery, log/metric
states including unknown, and narrow accessible layout. Scoped Doppler test and
analyzers; no OAuth against a live account or deployment.

## Implementation and validation record

- Backend CommandGlows stores granted OAuth scopes, fails closed for existing
  connections without scope evidence, confirms Gmail label changes by rereading
  the thread, and records hashed incoming message observations plus aggregated
  stable-code failures. The selected query window is 90 days, with each category
  capped at 500 rows per mailbox. The cap can evict older in-window rows.
  Expired rows are pruned on later writes; there is no scheduled physical purge.
  Counts describe the retained bounded ledger; coverage is
  partial because there is no background Gmail push consumer.
- Flutter exposes read/unread and archive/restore controls only when
  `can_modify` is true, and validates the server receipt plus a fresh thread read
  before updating visible state. Observability distinguishes exact retained
  counts from the 100-row API sample and 30-row UI sample; unavailable values
  remain distinct from zero.
- On 2026-10-07, Flutter app analysis and Dart analysis for the package, demo,
  and existing fake repository passed. `git diff --check` passed. No tests were
  run for this tranche. The backend TypeScript check was started under Doppler
  but stopped without completing. No live OAuth, mailbox mutation, or deployment
  was performed.

## Skill Run History

| Date UTC | Skill | Model | Action | Result | Next step |
|----------|-------|-------|--------|--------|-----------|
| 2026-10-07 | sg-docs | unknown | Reconciled app docs, technical path mapping, and implementation state | Local behavior and proof limits recorded; spec remains active | Complete focused backend and Flutter test/typecheck proof |
| 2026-10-07 | sg-docs | unknown | Clarified that the 30-day horizon is an implementation bound, not a product policy; added the app to the technical surface index | Retention choice remains open; documentation reflects the 500-row cap and prune-on-write behavior | Record the desired horizon, then complete focused backend and Flutter test/typecheck proof |
| 2026-10-07 | sg-development | unknown | Applied the selected 90-day observability horizon to the Flutter selector and API mapping | UI and app docs expose 90 days; 500-row cap and prune-on-write behavior remain documented | Complete focused backend and Flutter test/typecheck proof |

## Current Chantier Flow

- Local implementation is present and statically analyzed on Flutter surfaces.
- The selected observation horizon is 90 days; the 500-row cap can shorten
  effective history, and expired rows are pruned on later writes.
- Backend typecheck and focused server/Flutter tests remain open; hosted OAuth
  and live-mailbox proof are outside this local documentation update.

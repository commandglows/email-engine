---
artifact: implementation_spec
metadata_schema_version: "1.0"
artifact_version: "1.0.0"
project: shipglows-email-engine
created: "2026-09-08"
updated: "2026-09-08"
created_at: "2026-09-08T12:00:00Z"
updated_at: "2026-09-08T12:00:00Z"
status: ready
source_skill: sg-development
source_model: gpt-6
scope: newsletter-campaigns-postmark
owner: Diane
confidence: high
risk_level: high
security_impact: yes
docs_impact: yes
linked_systems: [newsletter_studio_flutter, commandglows_site, Convex, Postmark, Clerk]
depends_on: []
supersedes: []
evidence:
  - User approved the campaign, studio, central API, scheduling and reporting plan on 2026-09-08.
  - Newsletter presentation package and central-email-postmark commit 3cb5d79 inspected.
next_step: implement and verify the campaign contract; live activation remains separately gated
---

# Title
Newsletter campaigns through the central Postmark API

## Status
Ready for implementation. Not deployed or approved for real recipients.

## User Story
An authorized operator can create, save, review, test, schedule or send a newsletter and follow its real delivery status from the Flutter engine, using CommandGlows as the canonical backend.

## Minimal Behavior Contract
Opening Campaigns lists a bounded page of campaigns and permits creation. Opening a draft restores its authoritative version. The operator selects a configured audience, writes content, previews and explicitly confirms an immutable version before delivery. Failures retain the draft and explain recovery. A withdrawal after approval must exclude that recipient before dispatch.

## Success Behavior
Draft changes persist with optimistic concurrency. Review binds content revision and audience cutoff. Scheduled jobs expand eligible recipients in bounded resumable pages. Individual jobs use existing Postmark transport. The UI distinguishes queued, submitted, delivered, failed, unknown and cancelled outcomes.

## Error Behavior
Missing login, admin permission, business binding or configuration fails closed. Conflicting updates require reload; no silent overwrite. Ambiguous transport results remain unknown and cannot trigger blind retries. Cancellation stops future expansion/claims but cannot recall accepted mail. Unconfigured production capabilities remain disabled with an explanation.

## Problem
The presentation demo is synthetic and the central backend implements a one-recipient broadcast pilot. Neither is a full campaign application. The native CommandGlows app is not currently a consumer.

## Solution
Extend the provider-neutral Flutter package with a campaign workspace and a typed host repository. Add a real HTTP adapter and an operator web entry point using the existing Clerk-protected CommandGlows server boundary. Add additive campaign storage and bounded workers to the central email service. Keep the synthetic preview explicitly separate.

## Scope In
- Campaign list, create/edit, audience selection, preview/review, test, scheduling, cancellation and aggregate delivery status.
- Existing server-controlled business/sender/audience configuration and existing admin identity authority.
- Immutable approved content, optimistic concurrency, stable command keys, bounded pagination and expansion.
- French actionable labels, keyboard/focus, narrow screens, theme and text scaling.
- Focused tests and current public documentation.

## Scope Out
- Provider migration, Auth0 migration, contact imports, billing and production activation.
- Changing pilot allowedRecipients, consent rules, tracking policy, legal footer or retention policy.
- Sending real mail, deploying protected production data or distributing any credentials.
- Native mobile authentication changes; the first real host uses existing Clerk web sessions.

## Constraints
Presentation packages contain no Postmark/service secrets. The browser calls same-origin admin endpoints with its existing session. Server resolves admin identity in the canonical identity backend and applies explicitly configured email business scope. No permissive CORS or client-selected privilege. Existing scopes are not broadened.

## Test Contract
Backend tests use isolated Convex test state and mocked provider HTTP. Cover role/tenant denial, malformed input, stale revision, duplicate commands, unknown receipt, cancellation, withdrawal, bounded expansion and aggregate status. Flutter tests cover dashboard paging, save races, error recovery, review confirmation and disabled capabilities. Managed Flutter web preview proves rendered layout/keyboard using synthetic data only. Hosted login, provider acceptance, inbox receipt and unsubscribe propagation are distinct pending proofs; obtain concrete recipient authorization before a real test.

## Dependencies
Reuse Flutter, existing theme tokens, Astro, Convex and Clerk. Reuse existing safe email renderer and outbox transport. The real web host must serve its Flutter artifact from the same origin as the authenticated admin API. No client secret is a substitute for that host.

## Invariants
- Purchase/account creation never grants marketing consent.
- Unsubscribe never removes a license or account.
- Cross-business campaign IDs reveal no data and grant no operation.
- Approval freezes version, audience and schedule; edits cannot change queued content.
- One recipient per outbox job; no shared To/CC.
- Unknown submission remains distinct from failed/not accepted.
- Pilot allowlist, suppression, transport activation and server/stream checks remain enforced.
- Counters and pages are bounded; no campaign request loads the entire audience.

## Links & Consequences
Upstream: CommandGlows central-email-postmark implementation at 3cb5d79. Downstream: existing newsletter consumers remain source compatible; synthetic demo gains campaign navigation. Site serves an authenticated Flutter host; native app integration is excluded. Public repository contains models/UI only and no audience records.

## Documentation Coherence
Update root and newsletter README, code-docs map, design authority if tokens change, and a dedicated CommandGlows campaign API/operations document. Preserve pre-existing dirty source_sidebar_style.dart and ENVIRONMENT.md, and the original email operations working copy.

## Edge Cases
ZOMBIES: zero campaigns/eligible recipients; one recipient; many paginated recipients; boundaries on body size/version/page/date; interface rejects raw secret errors; exceptions retain edits; simple happy path create-to-status. Additional races: two editors, duplicate approve, cancel during expansion, withdraw after approval, stale test receipt, provider timeout and late webhook.

## OWASP Security Gate
Applicable access control/authentication, injection, security configuration, integrity and exceptional-condition concerns: Clerk identity plus server admin verification, scoped operator service permission, escaped HTML, strict payload validation/size limits, Origin checks, no-store responses, transactionally idempotent commands, redacted errors and fail-closed missing configuration. Behavioral tests prove the changed boundaries; no certification claim.

## Implementation Tasks
1. Backend: additive campaign schema/API/worker and tests in isolated CommandGlows worktree; preserve existing one-recipient endpoints.
2. Presentation: campaign models/workspace and studio reliability in newsletter package; widget/analyzer proof.
3. Integration: HTTP repository, real same-origin web entry point, protected site host, synthetic demo and API contract proof.
4. Review: adversarial code review, focused tests, rendered responsive proof, docs and exact-scope Git delivery.

## Acceptance Criteria
All actions have implemented host wiring or a truthful disabled configuration state. No fake success in the real application. State and content survive server reload. Concurrent/duplicate actions cannot silently alter an approved campaign. Test mail requires an authorized recipient and carries current revision. Scheduling uses an unambiguous instant; cancellation and reporting have truthful limits. Existing tests remain passing.

## Test Strategy
Run backend email tests/type checks; newsletter package and affected app Flutter analyzer/widget tests; inspect managed preview at desktop and mobile widths. Review exact diffs for security and bounded work. Do not substitute source/build checks for hosted session or inbox proof.

## Risks
The existing email service and identity service may use different Convex deployments; maintain separate authority resolution. Existing pilot transport capacity and allowlist stay constrained until explicit production policy approval. Same-origin web hosting is a deployment prerequisite. External gates remain visible, not bypassed.

## Execution Notes
Engine branch codex/newsletter-campaigns at C:/Users/Diane/ShipGlows/shipglows-email-engine. Backend branch codex/newsletter-campaigns at C:/Users/Diane/ShipGlows/worktrees/commandglows-newsletter-campaigns, based on 3cb5d79. First reads: studio models/hooks, central api.ts, email.ts, emailSchema.ts, admin/licenses.ts. Design authority: NewsletterStudioStyle/Colors and host PreviewTheme. Existing review-before-send convention is retained; source selection is supplementary to campaign creation.

## Execution Batches
Ready non-overlapping parallel batch: backend agent owns CommandGlows convex/email*, central campaign server modules, admin email routes and backend tests/docs. UI agent owns newsletter package lib/test/README only. Integrator owns engine app/demo/CI/root docs/spec and CommandGlows dashboard host page. Shared API contract is agreed before adapter writes. Integrator reviews all changes and owns final tests/delivery.

## Open Questions
No blocker to source implementation. Exact hosted configuration and live recipient authorization are required before real delivery proof; no value is guessed.

## Skill Run History
- 2026-09-08: sg-development intake: existing package and central pilot inspected; approved scope reconstructed.
- 2026-09-08: 100-sg-spec: authored new cross-surface campaign promise; prior source-keyboard spec is complete and does not own this work.
- 2026-09-08: 101-sg-ready: ready for source implementation; authorization, immutable versions, recipient eligibility, UI host and proof boundaries explicit.

## Current Chantier Flow

### Approved unified-interface correction — 2026-09-08

The annotated user correction supersedes the separate cockpit dashboard below.
Keep one topbar, one sidebar and one scrolling list: Sources, Service client,
then Diffusion, separated by whitespace. All three reuse SourceSidebar's dense
email row and reader. Only contextual actions differ. Facet links scroll within
the same interface; campaign editing uses the existing studio. No provider action
or production activation is included.

Execution batches: shared-component owner implements optional grouping, anchors
and reader footer with regression tests; app owner integrates real adapters and
reply/draft tests; integrator handles the synthetic demo, documentation and
rendered verification. Preserve unrelated style and runtime metadata changes.

Verification: shared component tests cover grouping, reader reuse, isolated empty
states and distant scroll anchors. Demo integration covers support and campaign
selection in the same reader. App tests cover scoped IDs, retained reply drafts,
explicit confirmation and unknown-send locking. Browser evidence is synthetic.

## Approved Cockpit Extension — 2026-09-08

Current extension state: implemented, source and mock-provider verification pass.
Auth/provider activation and actual reply routing remain unverified. Keep review
branches while these external proofs are pending; do not merge/deploy implicitly.

User explicitly approved the revised plan after clarifying provider ownership:
Sources retains its name and Readwise Reader connection; Service client uses only
the operator's own Gmail accounts through OAuth/Gmail API and preserves Mutant
Mail reply routing; Diffusion retains Postmark campaigns. No provider migration.
The shared cockpit becomes the default landing surface with the three sections in
this order and direct campaign access. Support owns pending/waiting/resolved
conversation status. Never infer a connection or success from synthetic data.
Credentials, Google app configuration and actual mailbox consent are external
activation prerequisites; no live reply is authorized by implementation approval.

### Cockpit Execution Batches (ready)

- Backend agent: isolated CommandGlows worktree only; new Gmail OAuth/support
  modules, persistence schema additions, admin support endpoints and focused tests
  and operations doc. Own schema.ts only for its additive table spread. Reuse
  existing verified admin authority. No deployed configuration or live mail actions.
- Support UI agent: engine new shared support widget/model files and focused tests
  plus app/lib/support_repository.dart only. No main.dart, exports or pubspec edits.
  Agree a compact API contract with backend first; UI remains provider neutral.
- Integrator: shared cockpit shell/dashboard, app/demo main wiring, Sources adapter,
  exports/dependencies, docs and combined verification. Sources integration stays
  read-only with server-side token configuration. Review all agent diffs.

Dependency order: agree API; write independent batches; integrate; focused auth,
  routing, pagination, support reply and responsive tests; build and managed demo
  visual verification. Preserve unrelated sidebar-style/runtime metadata edits.
Proof must distinguish synthetic UI, mock-provider tests and actual OAuth/mailbox
  access. No secrets or message bodies in logs, Git or documentation.

### Cockpit Verification

- Backend combined email/bridge checks: 185 tests pass; Astro check 0 errors and
  0 warnings (one unrelated existing hint); Convex TypeScript passes.
- Newsletter/cockpit/support package: 17 tests pass. App: 6 tests pass. Demo:
  7 existing interaction tests pass; legacy source tests intentionally exercise
  the isolated Sources harness. Integrated cockpit has separate retained-state
  and mobile drawer tests plus manual browser journeys.
- Dashboard and support inspected at 1440x1000 and 390x844. Responsive reparenting
  now retains the support widget itself rather than recreating its session draft.
- Reviewer corrections: same-origin support reads despite global suite CORS,
  reopen status on new inbound (excluding SENT/DRAFT), bounded OAuth state purge
  and rate bound. Unknown replies remain durably locked; exact relay domains are
  configured server-side and never inferred from sender text.
- Sources adapter reads only email documents, pages25 and fetches one selected
  body as plain text; no Readwise mutations. Support initially reads Gmail inbox
  on demand; no attachments, push synchronization, direct-address reply or token
  revocation UI. Personal connection values and consent remain user/environment
  prerequisites. No live login or email send was performed.
- Topology: two non-overlapping write agents and one read-only security reviewer;
  integration owner main. Source implementations integrated and reviewed.
Source implementation and local verification complete; hosted activation and real
delivery proof remain pending. Keep both `codex/newsletter-campaigns` branches for
review, without merging the unactivated central-email work into production.

## Verification Record — 2026-09-08

- Backend: 163 email/bridge tests across 19 files pass; Convex TypeScript passes.
- Flutter: newsletter package 9 tests, real app 6 tests and synthetic demo 7 tests
  pass. Analyzers pass. Release web artifact builds with `/email-engine/` base.
- Local installer copies the built artifact into the isolated CommandGlows site's
  ignored `public/email-engine/` directory; it does not deploy or enable the host.
- Managed synthetic preview: web-server, `flutter run -d web-server`, active at
  port 3012. Dashboard and editor inspected at 1280x720 and 390x844; dark desktop
  studio inspected. Inspector wrapping fixes the formerly clipped final tab.
- Design drift scan has two false positives: widget-test viewport dimensions
  1280x900. These are test geometry, not product styling; no token bypass accepted.
- Security review fixed frozen recipient snapshots, unsubscribe/resubscribe races,
  renderer marker injection and worker starvation behind blocked legacy rows.
- No Postmark send, production configuration change, hosted admin login, protected
  data access or inbox delivery was tested. Those remain separate required proofs
  in the authorized hosted environment with an exact authorized test recipient.
- Existing unrelated sidebar-style and runtime-metadata edits remain excluded.

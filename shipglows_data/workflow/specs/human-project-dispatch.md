---
artifact: master-workflow
metadata_schema_version: "1.0"
artifact_version: "1.0.0"
project: email-engine
created: "2026-10-07"
updated: "2026-10-07"
created_at: "2026-10-07T08:30:00+02:00"
updated_at: "2026-10-07T15:52:04+02:00"
source_model: GPT-6
status: active
source_skill: sg-development
scope: human-project-dispatch
owner: Diane
confidence: medium
risk_level: high
security_impact: yes
docs_impact: yes
linked_systems: [CommandGlows, ContentGlows, ShipGlows]
depends_on: []
supersedes: []
evidence: ["Operator approved the initial seven-step plan on 2026-10-07", "Operator confirmed per-user private mailbox connections shared across both apps, Gmail modify without send, and visible external AI consent on 2026-10-07"]
next_step: Complete hosted privacy evidence, verify linked identities and destination grants, configure host integrations, then complete visible Google OAuth consent
---

# Human project dispatch

## Status / User Story

The initial inactive implementation is complete. The operator subsequently
requested real use locally and in the cloud, with this same mailbox integrated
in ContentGlows and ShipGlows.app and AI pre-triage before human dispatch.
Activation and application integration are now in progress; real use is not proven.
As the email operator, I review a factual proposal, edit its contribution, select
one or more projects and explicitly confirm their private review intake. Each
destination then has an independently recoverable receipt.

## Minimal Behavior Contract

Reading email never dispatches. Manual preparation works without AI. Confirmation
binds the selected Gmail message, proposal revision and final destination payloads.
A project receives a private pending_review contribution, never publishable content.
Lost responses are unknown until reconciled; successful destinations are not resent.

## Success Behavior / Error Behavior

Each destination exposes a durable intake identifier and pending_review state.
The central ledger records authorization before attempting HTTP. Forbidden and
unconfigured destinations remain unavailable. A changed source or revision is a
conflict requiring refresh. An ambiguous HTTP result remains unknown. Recovery
uses the same stable key and exact payload, not a fresh request identity.

## Problem / Solution

SupportRepository currently has no dispatch. ContentGlows collections persist
text as ready sources, not review records. ShipGlows TASKS.md is execution
governance, not an email inbox. Add a separate dispatch repository and UI, a
central durable orchestration ledger, and private project review intake APIs.

## Common Contract

Version 1: dispatch_id, source_key (opaque digest), source_revision, revision,
summary, candidates [{destination_id, contribution_type, justification,
confidence, risks}], human decision and destination receipts. Contribution types:
newsletter_inspiration, thematic_source, potential_task, other. AI suggestions
have no ownership, authorization or mutation authority. Host review state is
separate. Account-provider analysis is permitted only after visible per-analysis
consent, using that user's BYOK key, authorized project context and bounded,
transient input. No synthetic suggestion may appear as real AI analysis.

Intake POST /api/projects/{project_id}/review-intake accepts client_intake_id
(stable UUID), source_key, summary (1..4000), contribution_type, justification
(0..2000), confidence (optional 0..1), risks (max 10, 500 each). No raw body,
sender, subject, credentials, attachment or arbitrary URL is accepted.
GET .../review-intake/{client_intake_id} reconciles the same client identifier.
GET .../review-intake lists private pending entries. Receipt: schema_version=1,
client_intake_id, intake_id, project_id, state=pending_review, created_at.
Same key and changed payload returns 409 idempotency_conflict. Atomic unique
insertion prevents concurrent duplicates. Private review can accept/reject entries
later; acceptance must not publish or generate anything implicitly.

## Scope In / Implementation Tasks

1. Save this contract and preserve unrelated dirty files.
2. Implement ContentGlows strict authenticated project-owned review intake,
   transactional persistence, unique key/hash and safe read/list APIs.
3. Implement ShipGlows opt-in local HTTP intake service, opaque bearer grants
   scoped server-side to explicit projects, SQLite private storage outside Git,
   atomic idempotency and private read/list APIs. No TASKS.md writes.
4. Implement CommandGlows authenticated mailbox-scoped durable dispatch ledger,
   per-destination claims and reconciliation. Destination registry is server-owned;
   URLs and tokens cannot come from the client. Production adapters require
   explicit actor-scoped connections and destination authorization. No config or
   secret is created/modified in this work; absent connections fail closed.
5. Implement Flutter proposal editing, multi-selection, exact payload preview,
   explicit confirmation, receipt recovery and partial-error controls. Use the
   existing EmailCockpitTokens and Material components. Keep Support reply and
   Gmail metadata actions independent. Synthetic demo remains separate from app.
6. Synthetic verification, documentation, final diff review.

## Scope Out / Constraints / Invariants

No automatic email forwarding, reply/send, archive, trash/delete, publication,
content generation or real email fixtures. User-initiated Gmail metadata changes,
archive and trash/delete are allowed only after explicit action in the mailbox UI.
The mailbox connector requests only the gmail.modify scope and exposes no send
route or UI; this scope is also accepted by Google's send API, so it must not be
described as technically incapable of sending. Dispatch never triggers Gmail
modification automatically.
No direct client access to project databases. No credentials in the ledger.
Do not infer project rights from the CommandGlows admin role or email address.
ContentGlows retains its verified OIDC/global identity and ownership dependencies.
ShipGlows grants are a separate opt-in local service boundary, not a new default
account identity. Configuring a grant requires separate operator authority.

## Privacy / Dependencies / Risks

Raw Gmail text is transient in the current reader. Dispatch persists only the
explicitly validated private contribution in central/project stores; derivatives
may themselves be sensitive. The project review payload is automatically deleted
after 90 days in both ContentGlows and ShipGlows.app. A minimal project/client
idempotency tombstone remains without the contribution payload to block a delayed
replay from recreating an expired receipt. Disable payload/request/exception-local telemetry,
emit allowlisted codes/opaque IDs only, never exception messages containing data.
Approved contribution payloads expire after 90 days in ContentGlows,
ShipGlows.app and the CommandGlows dispatch ledger. The ledger leaves only a
minimal dispatch ID/fingerprint/expiry tombstone so an old confirmation cannot
recreate an expired intake. Project queues retain only project/client IDs and
expiry time in their tombstones. Convex documents manual/daily snapshots for 7
days and weekly snapshots for 14 days; the active production schedule has not
been checked. ContentGlows Turso backup retention remains unconfirmed. Primary
store deletion therefore does not prove immediate deletion from provider
snapshots. Project connection setup, provider identity compatibility and
authenticated hosted proof are activation dependencies, not grounds for an auth
bypass. AI activation requires a
documented provider/model, input boundaries, retention, backups, telemetry and
deletion policy, and explicit operator approval.

## Acceptance Criteria / Test Contract / Test Strategy

Use synthetic fixtures only. Test auth denial and cross-project isolation; zero
intake before confirmation; empty/invalid/multi-destination proposals; double
click and concurrent claims; changed key payload; stale source/revision; lost
receipt and restart recovery; successful + failed + unknown destinations;
reconciliation before retry; malformed receipts and bounded/redacted errors.
Use focused local Python/TypeScript/Flutter checks under each existing Doppler
configuration, with ShipGlows CLI's explicit no-Doppler repository override.
Interactive proof uses flutter run when a valid local runtime is available.
No local result proves hosted identity, provider analysis or real project dispatch.

## OWASP Security Gate / Edge Cases / ZOMBIES coverage

Broken access control: project ownership on all reads/writes, server-owned registry,
mailbox permission and destination grant. Injection: email and AI output are inert
data, strict schemas and bound lengths, parameterized SQL. SSRF: fixed trusted
origins/paths, redirects disabled. Sensitive logging: opaque metadata only.
Concurrency: durable atomic claim and unique project intake identity. Zero/one/many
destinations, bounds, duplicates, stale source and partial failures covered.

## Links & Consequences / Documentation Coherence

The historical shared-source-analysis-contract-and-email-adapters.md remains
unchanged. Reuse its separation/privacy principles, not its Neovim scheduler,
Idea Pool derivation or archive policy. Its referenced source-analysis-v1 JSON
schema is absent at the advertised path. Document this work here and add
code-proximate integration notes in each affected repo; do not alter unrelated
technical architecture changes. No TASKS.md or shared tracker mutation.

## Execution Notes / Execution Batches

Independent write scopes after readiness: one agent owns ContentGlows new intake
model/store/router/migration/tests, bounded registration and its dedicated docs;
after completing that scope it owns ShipGlows' three new intake service/test/doc
files. Another agent owns Flutter app reader adapter, shared dispatch UI/models,
synthetic demo and focused UI tests/package docs. Main owns CommandGlows, machine
contracts, this spec and app README and integrates the fixed HTTP contract.
No overlapping writes or commits/pushes. Existing ContentGlows main.py changes
were preserved; only two router-registration lines were added.

Central POST JSON is capped at 65536 bytes. Common field bounds count Unicode
codepoints; Flutter's UTF-16 preflight is conservatively stricter for astral text.
Each thread is capped at 100 durable dispatches to keep recovery history complete.
ContentGlows' explicit review intake migration extends the existing migration
catalog and schema-readiness gate. It was applied to the `dev` and `prd` Turso
databases on 2026-10-07; the API has not been deployed or restarted.

Local proof: 9 new CommandGlows dispatch tests pass, including actual Support
wire-envelope with mocked Gmail, concurrency, lease expiry/fencing, timeout/partial
recovery and structured absence. Astro check: 0 errors, 0 warnings, 1 existing hint.
Direct tsc hits pre-existing Preline tailwindcss/types/config dependency error.
ContentGlows: 3 tests pass with temporary SQLite/router-only app under its existing
contentglows_app/dev Doppler scope. ShipGlows: 4 tests pass under its explicit
repository no-Doppler exception. Flutter: 3 targeted tests pass; final flutter
analyze reports no issues under the documented CommandGlows host Doppler scope.
The synthetic demo compiled through flutter run and was started through the
managed runtime. Browser proof covers actual text entry, two selected destinations,
exact preview, cancellation and retained draft. Full confirm/recover browser proof
was limited by Flutter semantics/CDP automation; widget tests cover those paths.
The browser tab was closed and the demo restored to stopped. All transports and
fixtures are synthetic. Nineteen new focused tests pass across the four surfaces.

Existing Support regression limits: isolated CommandGlows Support suite has 25
passing/2 failing tests with relay_not_verified; its implementation and tests are
unchanged. Flutter Support suite has 2 passing/4 failing tests; the agent reproduced
the same failures with its HEAD widget and restored the current file exactly.
Those baseline failures remain outside this dispatch implementation.

## Open Questions

The activation request supersedes the initial inactive-only scope. The operator
selected la première boîte connectée as the first mailbox to connect and authorized
account-provider AI analysis with visible per-analysis consent. Users may add
their own mailboxes; each connection is private to its owner and visible in both
apps only after both verified sessions resolve to the same canonical global user.
No identity is inferred from an email address. No passwords, service keys or
refresh tokens should be requested in chat.

Current configuration evidence (2026-10-07): Google Cloud project CommandGlows
has the Gmail API enabled, a dedicated web OAuth client with the production
callback URI, and only the `gmail.modify` scope. The consent audience remains
external/Test; `la première boîte connectée` is its one test user. This is setup only: no
mailbox has completed Google consent. CommandGlows Doppler dev/prd contain the
OAuth client settings, token-encryption keys and mailbox-origin allowlist.
Vercel production now lists the OAuth settings, token-encryption key and
`EMAIL_MAILBOX_ALLOWED_ORIGINS`; the latter's stored value still needs an
authoritative check. Production still has no project destination registry or
dispatch activation flag. A live read-only migration status through the exact
ContentGlows dev and prd Doppler configs confirms all 14 migrations, including
`012_project_review_intake`, are applied in both Turso databases. ContentGlows
dev has its Auth0/identity bridge and Turso configuration, with Sentry enabled.
These are configuration findings, not proof that code or backend functions are
deployed.

Google's official OAuth documentation states that refresh tokens issued while
an external consent screen is in Testing expire after seven days. Google's Gmail
scope documentation classifies `gmail.modify` as restricted and says server-side
storage or transmission of restricted-scope data requires a security assessment.
The Gmail `users.messages.send` method also accepts `gmail.modify`; the current
mailbox bridge allowlists only read, metadata and trash paths and contains no
send route. Production use by general users therefore needs Google OAuth
verification/security-assessment readiness, not only adding a test user. Sources:
https://developers.google.com/identity/protocols/oauth2
https://developers.google.com/gmail/api/auth/scopes
https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/send

Google Auth Platform listed two clients predating this mailbox setup: the
Google-service auto-created web client redirects to Firebase's auth handler,
and CommandGlows Clerk Production redirects to Clerk. Neither has the Gmail
callback URI. The dedicated `CommandGlows Gmail Mailbox` client was created on
2026-10-07 for the mailbox OAuth callback. Thus OAuth clients already existed
in the project, but no preexisting client was configured for this Gmail flow.

ContentGlows' existing Reader sources panel reads Readwise, not Gmail. Its IMAP
newsletter ingestion generates ideas and archives messages and must not become
this inbox. ShipGlows.app is a separate active Flutter application; its actual
Firebase session/managed runner is distinct from CommandGlows' Clerk admin
session and ContentGlows' Auth0 session. Email-address matching cannot link them.
Embedding a widget or supplying a bearer does not establish server authorization.
The initial ShipGlows CLI loopback intake is not a hosted ShipGlows.app queue.

Delivery proceeds through user-owned Gmail OAuth, verified cross-app identity,
private review queues and authenticated project connections. Cloud release
requires resolvable shared packages and authenticated project endpoints reachable
from the central gateway. AI processing additionally requires explicit consent at
each analysis, a per-user BYOK provider key, authorized candidate projects, a
configured model, bounded transient input and filtered telemetry. No synthetic
analysis may be presented as real. No actual email is dispatched during setup.

## Skill Run History

| Date | Owner | Result |
| --- | --- | --- |
| 2026-10-07 | sg-planning | Current contracts inspected; seven-step plan approved |
| 2026-10-07 | 100-sg-spec | New owning contract recorded; historical scope reconciled |
| 2026-10-07 | 101-sg-ready | Ready for local inactive implementation; activation excluded |
| 2026-10-07 | sg-development | In progress; frontend/backend/domain/privacy gates apply |
| 2026-10-07 | 102-sg-start | Local inactive dispatch, two private intake APIs and synthetic UI implemented |
| 2026-10-07 | 103-sg-verify | Local contract/security scenarios pass; hosted identity/privacy/provider proof remains open |
| 2026-10-07 | sg-development | 19 focused tests pass; Flutter clean, Astro clean with existing hint; browser preview/cancel verified; remote activation closed |
| 2026-10-07 | sg-release | Isolated CommandGlows candidate: 142 focused tests, Astro check and Vercel production build pass; collateral commerce assertion also fails in the canonical checkout; no commit or push |
| 2026-10-07 | sg-release | Commit 0c28fcc4 pushed to an isolated branch; Vercel preview READY; 277 focused tests pass; unauthenticated callback returns 400 and mailbox/dispatch routes return 401; production unchanged |

## Current Chantier Flow

Initial implementation complete; per-user local/cloud integration is in progress.
Verification is partial for the overall real dispatch outcome. The original
inactive-only constraints above describe the first batch; the subsequent user
request authorizes working toward activation. Human confirmation of each actual
dispatch, project ownership and private-data consent remain mandatory. Gmail
archive/trash/delete requires an independent user action; dispatch never changes
the Gmail message. OAuth and allowlist configuration has changed, but the current
CommandGlows production deployment still returns 404 for the new OAuth callback.
No feature deployment, Google mailbox consent, real Gmail read/mutation, external
AI call or actual project intake has occurred.

Activation batch implementation: reusable bounded mailbox transport with optional
short-lived bearer supply; shared mailbox entry in both applications;
explicit verified Auth0/Firebase-to-operator delegation in CommandGlows; private
ContentGlows review screen; actual managed-runner ShipGlows.app review intake and
project detail queue. The managed runner's separate private SQLite store and
durable project-scoped service grants supersede the CLI listener for this product
integration. Every current project capability is checked again per request.

ContentGlows has a bounded transient BYOK-only triage API requiring explicit
consent, authorized project context, configured server model and privacy filters.
The shared panel requests consent, displays inert candidates and requires an
explicit action to populate the editable draft; analysis never confirms dispatch.
The ShipGlows.app session has no established access to the ContentGlows BYOK
runtime, so its AI connection remains unavailable rather than borrowing Auth0
credentials or bypassing ownership. A common analysis provider connection is
still required for parity. Cloud compilation can use an explicit sibling-source
workspace and deploy its built artifacts; package publication is not inherently
required, but source resolution and release identity must be reproducible.

Current additional synthetic proof: 5 central mailbox bridge tests pass; all 9
dispatch tests remain passing. Astro check reports zero errors/warnings and one
existing hint. TypeScript's direct site check still reports only the existing
Preline tailwindcss/types/config issue. The actual ShipGlows.app intake has 4
passing temporary-database/Fastify tests and a clean runner typecheck. Shared
dispatch UI has 5 passing tests including consent cancellation, inert candidates
and stale analysis refusal; its analyzer is clean. Further host-specific evidence
is recorded in the host documentation. These are not actual Gmail/provider/cloud
dispatch proofs.

The durable ContentGlows review authority is now implemented on both sides.
Its server-owned connection requires the destination's canonical globalUserId,
verified current Clerk admin link and live suite product entitlement; ContentGlows
independently checks project ownership. Only private review routes accept this
authority. No static user JWT, email-based identity inference or fabricated access
flag is used. Central tests now total 18 passing; ContentGlows' targeted backend
and privacy tests total 25 passing, with 7 host Flutter tests and clean scoped
analysis. ShipGlows.app's actual runner intake now has 5 passing tests, including
registration in the real app with a temporary private database and no execution
side effects. Its runner typecheck is clean. Host Flutter analysis and focused
transport/read-only/review tests pass.

Actual hosted inventory was inspected by environment names: Vercel production
has the ContentGlows identity bridge, SENTRY_DSN, OAuth client settings,
token-encryption key, mailbox-origin variable and the existing email operator
and Convex credentials. Secret values were not pulled into repository files.
The current production alias is Ready but its new OAuth callback returns 404;
the feature code and Convex additions remain undeployed. Source inspection found
no active site Sentry SDK; hosted request privacy is nevertheless unproven and
the conservative dispatch gate remains closed. The project destination registry
and dispatch activation flag are absent.

Interactive ShipGlows.app launch could not start on canonical port 3005 because
an existing Flutter process owns it. It was preserved. This does not prove the
new integration in that running instance. The previous operator-input questions
are resolved. New acceptance requires self-service OAuth for any user's Gmail,
owner-private storage keyed by the canonical global identity, verified resolution
of Auth0 and Firebase sessions to that same identity, requesting only the
`gmail.modify` scope, and explicit user actions for archive/trash. Google also
accepts that scope for its send endpoint, but the app has no send route or UI.
External AI
analysis remains per-action consented and BYOK-only. No real email or provider
processing is enabled and no actual project dispatch is attempted. Complete
activation must not be reported as achieved.

## Activation Steering — 2026-10-07

The operator explicitly expanded the approved activation outcome:

- Any user may add one or more Gmail boxes through visible Google OAuth; never
  ask for passwords or tokens in chat.
- The connection belongs to that user and is private by default. It is available
  in ContentGlows and ShipGlows.app only if both verified sessions resolve to the
  same canonical global identity. Identity linking must be explicit; matching
  email addresses are insufficient.
- Request only Gmail `gmail.modify` for read plus user-directed status/archive/
  trash actions. Do not request `gmail.send`; no reply/send UI or API is in scope.
- User-initiated archive/trash/delete is permitted after a direct confirmation.
  Dispatch and triage never archive or delete messages automatically.
- Per-analysis visible consent authorizes transient transmission of the selected
  email text and bounded context for authorized projects to the user's configured
  OpenRouter BYOK provider. No platform key or implicit fallback is allowed.
- The first mailbox selected for OAuth is `la première boîte connectée`. No live OAuth
  consent has yet occurred.

Implementation readiness must cover the identity mapping, per-user mailbox
registry and token ownership, least-privilege OAuth scopes, Gmail mutation
confirmation, per-user AI consent, and release/deployment proof. Existing static
operator grants and admin-only mailbox configuration are not acceptable as the
self-service user connection model.

Implementation progress: CommandGlows now has owner-scoped OAuth start/callback,
connection listing/removal and Gmail support routes using only `gmail.modify`.
The shared Flutter workspace exposes add-mailbox, archive and confirmed-trash
actions; ContentGlows and ShipGlows.app launch Google OAuth from their mailbox
screens and hide reply controls. CommandGlows now routes dispatch requests for
verified mailbox owners through the same owner scope, and rechecks the current
Gmail message revision before the durable intent is created. Project destinations
remain explicit server configuration keyed to the canonical owner. Flutter
analysis is clean for ShipGlows.app and the shared engine. ContentGlows analysis
reports 36 findings in unrelated pre-existing files; none point to its mailbox
screen. Astro check has zero errors and warnings plus one unrelated existing
hint. Native apps may supply a return origin, but the server requires an exact
origin allowlist match; browser requests remain bound to their request origin.

OAuth credentials and hosted CORS origins are present in CommandGlows Doppler
dev/prd and named variables are present in Vercel production; the Vercel origin
allowlist's value remains unverified. The production Sentry privacy gate
remains closed. Project destinations/tokens are not configured;
`012_project_review_intake` and `013_project_review_intake_expiry` are applied in
both ContentGlows Turso environments, but the API has not been deployed.
ShipGlows.app now has a local server-to-server bridge to ContentGlows BYOK triage.
It requires a verified linked Firebase identity, current ContentGlows entitlement,
owner-bound destinations, visible consent, and a server re-read matching the
latest Gmail message ID and exact text. Synthetic tests pass; hosted bridge URL and
token are absent and no real provider call occurred.

Current Vercel production has the Gmail OAuth client settings, but the public
callback still returns 404. Dispatch destinations, activation and private
telemetry attestation are absent. CommandGlows commit `0c28fcc4` is pushed to an
isolated task branch and its Vercel preview is ready. The preview callback
returns 400 when called without an OAuth code; unauthenticated dispatch and
mailbox bridge calls return 401. Google consent remains pending. No real email,
provider processing or dispatch occurred. Live identity linking and project
ownership have not been verified.

## Live Cloud Probe — 2026-10-07

Read-only public checks against the current production aliases returned `200` for
ContentGlows `/health`, but `404` for both `/api/email-triage` and
`/api/email-triage/bridge`. CommandGlows' Gmail OAuth callback also returned
`404`. No OAuth code, email body, provider call, or dispatch was submitted. This
confirms that the feature routes are still absent from the hosted releases.

The Vercel production environment-name inventory still lacks the dispatch enable
flag, destination registry, private-telemetry attestation, and the CommandGlows
server-to-server ContentGlows triage URL/token. A read-only Vercel log-drain
inventory request was not available through the current API access, so hosted
telemetry remains unverified and the dispatch privacy gate stays closed.

The release check confirms Git divergence after a read-only fetch: email-engine
and the canonical CommandGlows checkout are each one local and one remote commit
apart; ContentGlows is nine local and three remote commits apart; ShipGlows.app
is four local and three remote commits apart. The CommandGlows task branch is
pushed at `0c28fcc4` and passes 142 identity/dispatch tests plus 135 account and
commerce tests. Astro check reports 0 errors, 0 warnings and 1 existing hint;
the full Vercel production build includes OAuth callback, dispatch, mailbox and
review-authority routes. Preview deployment is `READY`; the callback returns 400
without OAuth parameters and the unauthenticated dispatch/mailbox bridges return
401. Production still returns 404 for the OAuth callback and ContentGlows triage
routes. ContentGlows' nine local commits span other work; its branch and the
ShipGlows.app checkout have not been shipped. The GitHub push also surfaced three
high and one moderate Dependabot alerts in the default branch lockfile; scope and
reachability are under review. No email, OAuth code, AI provider call or dispatch
was sent. The ShipGlows.app repository instructions prohibit worktrees.

## Resumption evidence — 2026-10-11

This read-only refresh supersedes the delivery and checkout blockers in the
2026-10-08 handoff. Activation remains incomplete.

- CommandGlows PR #8, `feat: add private Gmail project dispatch`, was merged
  on 2026-10-07 at 23:04:29 UTC. Its merge commit `5da8d507` is in the current
  canonical `main` history. The previously reported PR-creation refusal is no
  longer the delivery blocker; no alternate delivery was attempted in this run.
  Review: https://github.com/commandglows/commandglows/pull/8.
- Public requests without OAuth parameters return 308 from the apex callback
  to `www`, then 400 from the `www` callback, replacing the historical 404.
  This proves route availability only, not consent, token storage, identity
  linking or Gmail access. No OAuth start or consent was performed in this run.
- CommandGlows Doppler `dev` now contains `EMAIL_OPERATOR_CREDENTIAL` and
  `EMAIL_CONVEX_URL`. An in-memory comparison confirms those values and
  `EMAIL_SUPPORT_TOKEN_KEY` differ from `prd`; no secret values were displayed
  or written to files. Distinct settings do not prove backend connectivity.
- The Vercel production environment-name inventory still lacks
  `EMAIL_PROJECT_DESTINATIONS`, `EMAIL_PROJECT_DISPATCH_ENABLED`,
  `EMAIL_PRIVATE_DATA_TELEMETRY_VERIFIED`,
  `CONTENTGLOWS_EMAIL_TRIAGE_BRIDGE_URL` and `EMAIL_TRIAGE_BRIDGE_TOKEN`.
  `SENTRY_DSN` remains present. No environment settings were changed.
- Authenticated read-only Vercel `/v1/drains` and `/v1/log-drains` inventories
  for the selected team both return zero configured drains. This does not prove
  internal request-log filtering, Sentry behavior, database backups or provider
  retention. The dispatch and triage privacy gates must remain closed.
- Both shared-engine local paths resolve to `main` at `9da9dcd`; the existing
  `source_sidebar.dart` modification was preserved. CommandGlows and
  ContentGlows canonical checkouts are clean at `0118fd0b` and `569bc262`.
  ShipGlows.app is at `shipglows_app`, on
  `codex/reconcile-mailbox-cockpit` at `a988ce9`, with its `TODO.md` edit
  preserved. The historical temporary CommandGlows release checkout and
  ContentGlows release path from the handoff are absent.
- Current ShipGlows.app source already contains the linked ContentGlows BYOK
  bridge integration; its hosted URL/token and live behavior remain unproven.
  This run did not read real mail, call an AI provider, mutate Gmail, dispatch
  a contribution, run builds/tests, or deploy anything.

Remaining acceptance: hosted logs/traces/backups and provider retention evidence;
verified canonical identity links; explicitly authorized destination projects and
durable grants; exact shared-source CI/artifact identities and host configuration;
visible Google consent with Diane; authenticated mailbox and private-queue proof.
Actual dispatch still requires Diane's explicit selection of a message and its
destinations. No review receipt may contain the raw email body.

## Shared-source integration step — 2026-10-11

Both host apps now pin their shared Flutter dependency checkout to the same
reviewed email-engine commit `9da9dcd0fae749ab289c35871369d1b9a3ecf325`.
Their setup scripts reject a different existing checkout without overwriting it.
ContentGlows' dependency script also had Windows line endings that made Bash
fail; those were normalized in that script only. Existing ContentGlows and
ShipGlows.app local changes were preserved. These edits remain uncommitted and
unpushed in their current checkouts.

Proof under each app's own Doppler `dev` config: dependency setup and
`flutter pub get --enforce-lockfile` pass for both apps; the ContentGlows private
workspace tests pass (3), its mailbox-screen analysis is clean, ShipGlows.app's
private review panel tests pass (2), and its mailbox-screen analysis is clean.
The production CommandGlows bridge accepts CORS preflight for
`https://app.shipglows.com` and `https://app.contentglows.com` (204); its
Firebase and Auth0 connection-list routes return 401 without a session, as
expected. These checks establish dependency resolution, source-level screens
and route/origin availability, not authenticated owner linkage or Gmail access.

Still open before Google consent: prove the current user sessions resolve to the
same canonical global identity, and complete the app-specific hosted build
configuration/release proof. Dispatch and AI triage remain gated on hosted
privacy/retention proof. No app build, OAuth state, Gmail read, AI provider call
or dispatch was created in this step.

## Main-branch consolidation and hosting recheck — 2026-10-11

- `shipglows-email-engine` has only the `main` worktree. Its email feature and
  shared-client commits were already ancestors of `main`; redundant local email
  branches and their clean linked worktree were removed. Existing local edits
  in `source_sidebar.dart` and this specification remain untouched.
- CommandGlows `main` is clean and synced with `origin/main`. The dispatch
  implementation is already present through merged PR #8. No local feature
  branch or extra worktree remains.
- ContentGlows `main` now contains the prior exact engine-revision pin plus the
  four commits from `origin/main`, through local merge commit `29d17038`. The
  checkout is two commits ahead and was not pushed. ShipGlows.app remains on
  synced `main`; its two unrelated local documentation edits remain untouched.
- The CommandGlows Vercel project was paused. After the operator explicitly
  authorized the metered-usage restart, the dashboard now reports it active and
  shows `Pause Project`; the latest deployment is marked updated just now.
  A no-parameter callback probe follows the apex redirect and returns 400 from
  `www` (`redirects=1`), confirming route availability only. No OAuth flow was
  started and no mailbox consent or access occurred.
- The hosted privacy audit still lacks Sentry retention/scrubbing evidence,
  Vercel internal request-log settings, Convex/Turso backup-retention proof, and
  LLM-provider retention policy. The Vercel production registry/grants and
  privacy attestation remain absent. Dispatch and triage must remain closed.
- The authenticated Sentry organization settings show Enhanced Privacy,
  required server-side scrubbing, required default scrubbers, and IP-address
  scrubbing all disabled. Its visible project list has no CommandGlows project;
  the production `SENTRY_DSN` project mapping and retention remain unverified.
- The CommandGlows Vercel project has `Improve models with this project's data`
  enabled in Data Preferences. Vercel describes this as sharing project code
  and chat data for model training. This setting was observed only and was not
  changed during the project-resume action.
- The Vercel dashboard lists `contentglows_site`, `contentglows_app`, and
  `shipglows-app` as paused. Only CommandGlows was resumed by explicit request;
  these apps' production mailbox routes are not live proof.
- CommandGlows production has the Gmail OAuth client, callback, origins,
  operator credential, and Convex ledger configured by variable name. Project
  destinations, static session grants, dispatch activation, privacy attestation,
  and ContentGlows triage bridge are absent. Both app origins pass CORS preflight
  (`204`), which does not verify Diane's Firebase/Auth0 identity link. No live
  canonical identity or Gmail session was inspected.
- The CommandGlows production Convex dashboard reports `Last backup: No backup
  yet`; Backup & Restore has no existing backup and the schedule is `Never`
  (marked PRO). No backup was created during this audit. Diane then signed into
  Turso and the `contentflow-prod2` production database overview was inspected
  without opening its data. The account shows the Free plan; its database page
  exposes no backup schedule. Turso's official PITR documentation says commits
  are backed up automatically and Free restores cover only the previous 24
  hours. This establishes the documented plan retention, not deletion from all
  replicas or proof about application logs. Two old timestamped snapshot
  branches are visible but are not evidence of a current scheduled backup.
  Doppler metadata-only inventory shows ContentGlows `prd` has the database URL
  and auth token, with no Turso platform API token available for a settings
  query.
- OpenRouter's official [provider logging and retention documentation](https://openrouter.ai/docs/features/privacy-and-logging)
  says provider logging/training policies vary and can be filtered by account
  settings. The OpenRouter account page redirects to sign-in, so Diane's active
  privacy filters and any chosen provider endpoint remain unverified. No model
  request was sent.

No Google OAuth, Gmail read, Gmail modification, external AI analysis, or real
dispatch occurred. Account-link status and destination grants remain unverified.

## Hosted privacy controls applied — 2026-10-12

After Diane's explicit approval, Vercel Team Settings → General → Data
Preferences was changed to disable `Improve models with my data`. The setting
remained off after reload; Vercel's UI states team code and chat data will not
be shared going forward for projects owned by this team.

Sentry organization `diane-defores` Security & Privacy controls were enabled:
Enhanced Privacy, Require Data Scrubber, Require Using Default Scrubbers, and
Prevent Storing of IP Addresses. All four remained enabled after reload. The
IP control applies to new events. This does not establish the production
CommandGlows DSN's project mapping, event retention, backup retention, or any
other internal logging path. Dispatch and AI triage remain gated until those
remaining hosted data paths and the required identity/destination grants are
verified.

## Re-audit — 2026-10-12

Read-only checks after the privacy controls were applied found:

- The four Sentry controls above are enabled, but no CommandGlows project is
  visible in the connected Sentry organization. The production `SENTRY_DSN`
  mapping, event retention, and internal Vercel request-log retention remain
  unverified. Vercel API and log drains are empty; this does not cover internal
  Vercel logs.
- CommandGlows Production Convex has no backup and its backup schedule is
  `Never` (backup scheduling is marked PRO). No database content was opened.
  Turso's current console does not expose a backup schedule; retention and
  restore behavior for the ContentGlows database were not verified in the UI.
- OpenRouter redirected to sign-in, so account privacy filters and provider
  retention remain unverified. No model call was made.
- No session-bound evidence proves that ContentGlows and ShipGlows.app resolve
  to the same `globalUserId`. Their Vercel production configurations expose
  different identity setups, and neither app's Doppler `dev` config contains
  mailbox or triage variables.
- CommandGlows production still lacks `EMAIL_PROJECT_DESTINATIONS`,
  `EMAIL_PROJECT_DISPATCH_ENABLED`, `EMAIL_PRIVATE_DATA_TELEMETRY_VERIFIED`,
  and the ContentGlows triage bridge. No destination grants were verified.
  The latest Vercel deployments for the two apps display `UNKNOWN`, so their
  current health is also unverified.

Keep Gmail consent, external AI analysis, dispatch, and triage closed. The next
safe identity check must be bound to the active app sessions, resolve Firebase
and Auth0 identities through the trusted bridge, and return only a match
boolean. Then configure development credentials and authorized destinations,
and finish retention checks for Sentry, Vercel internal logs, Convex, Turso,
and OpenRouter before opening any privacy gate.

## OpenRouter privacy settings before approval — 2026-10-12

Before the approved change below, the OpenRouter Personal account's Privacy page showed
Zero Data Retention disabled for “All other models” and the provider-specific
ZDR switches disabled. The account allowed paid endpoints that train on request
data, free endpoints that train on request data, free endpoints that publish
prompts, and the 1% data discount that lets workspaces separately consent to
using inputs and outputs to improve the product. These values were observed in
the UI; none were changed and no model request was made. Do not send email
content through this provider until the protections below are confirmed in the
account and app behavior.

## OpenRouter privacy protections applied — 2026-10-12

After Diane confirmed the change, the Personal account was configured to require
Zero Data Retention endpoints for all other models and to disallow paid
endpoints that train on request data, free endpoints that train on request
data, free endpoints that publish prompts, and the 1% data discount that lets
workspaces separately use inputs and outputs to improve the product. Both
settings sections were saved and all five values remained set after a page
reload. The eligibility preview changed from 634 available models to 481
available and 153 unavailable. OpenRouter states that Zero Data Retention
applies to provider routing, not plugins or tools. No model request was made.

## Reprise hébergée et intégration — 2026-10-13

Read-only production checks on 2026-10-13 found:

- The CommandGlows Gmail OAuth callback redirects from the apex domain to
  `www` and returns HTTP 400 with a generic no-store failure when called
  without OAuth state. The route is deployed; this is not proof of consent,
  token exchange, identity linkage, or Gmail access.
- Vercel's metadata-only production environment-name inventory for CommandGlows
  includes the mailbox client, redirect, allowed-origin, operator, and ledger
  settings. It does not include `EMAIL_PROJECT_DESTINATIONS`,
  `EMAIL_PROJECT_DISPATCH_ENABLED`,
  `EMAIL_PRIVATE_DATA_TELEMETRY_VERIFIED`, or the ContentGlows triage bridge
  URL/token. The ContentGlows and ShipGlows.app production inventories contain
  no email mailbox or triage variables. Secret values were not displayed.
- An initial Vercel deployment-list snapshot reported CommandGlows `READY` at
  `88b27b810a1d268c7a4984b1940010f022e3db3e`, ContentGlows `BLOCKED` at
  `982f913257dfad4961bce0d1a448f1a34e51d316`, and ShipGlows.app `BLOCKED` at
  `a9ea8295f73a15bbf81b90614b939984b41f4223`. The project settings clarified
  the live state: `contentglows_site` was paused. After Diane authorized its
  resumption, Vercel changed the control to `Pause Project` and recorded the
  update; no redeployment was triggered. `shipglows-app` already showed
  `Pause Project`, so it was active and was not changed. Direct GET checks of
  `https://contentglows.com/` and `https://app.shipglows.com/` now return HTTP
  200. These checks establish root availability only, not authenticated app
  sessions or identity linkage.
- The two apps still pin the shared engine to
  `9da9dcd0fae749ab289c35871369d1b9a3ecf325`. Comparing that revision with the
  current engine `main` (`f7c0fb0386f22efe1660532ec58b67e3e86c611f`) shows no
  changes within either consumed Flutter package, so the reviewed package
  contents match despite the newer repository head.
- The Sentry, internal Vercel request-log, Convex/Turso backup-retention, and
  chosen LLM-provider retention evidence remains incomplete. No active
  session-bound proof links the two host-app identities to one canonical
  `globalUserId`; project destinations and grants remain unconfigured.

Keep Gmail consent, AI triage, and dispatch closed. With both production roots
available, continue by verifying the session-bound identities and canonical
`globalUserId`, then explicitly select permitted destination projects and
complete the remaining hosted retention review. No OAuth, Gmail read or
modification, model request, or dispatch occurred in this run.

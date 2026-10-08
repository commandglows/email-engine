# Unified email web application

One SourceSidebar provides navigation, grouped email rows and the reader for
Sources, Service client and Diffusion. Provider adapters supply scoped IDs and
contextual reader actions. Campaign editing opens the existing studio.

Sources reads email documents through the admin-only `sources` proxy. Configure
`READWISE_READER_TOKEN` and comma-separated `READWISE_READER_OWNER_IDS` on the
server; the latter contains exact authorized Clerk administrator IDs. The token
never reaches Flutter. Lists page 25 documents, bodies load only on selection,
and upstream HTML is displayed as bounded plain text. This first adapter is
read-only; archive/move/import mutations are not exposed as fake successes.

Service client uses `support/*`: personal Gmail OAuth, conversations, persistent
pending/waiting/resolved status, explicit reply confirmation and durable unknown
send locks. Configure the exact server contract in CommandGlows
`shipglows_data/technical/gmail-support-api.md`. Replies require a verified relay
domain and activation; direct Gmail messages currently remain read-only. Sources,
support and campaigns keep separate credentials, provider ownership and states.
Draft replies stay in widget session memory across section changes and responsive
resizing; refreshing or closing the browser does not persist those drafts.

Support now offers an enriched, selectable HTML reader with tables, lists and
emphasis, plus a plain-text toggle. Both server and client strip active content;
remote images never load, and opening HTTPS links requires confirmation.
Attachments can be downloaded through the authenticated same-origin API or
added/removed from a reply draft. The limit is 10 outgoing files and 3 MiB total;
downloads are limited to 3 MiB per file so base64 JSON fits the hosted function
payload limit. Files remain in session memory and clear only after submission.

Reply all previews server-derived Reply-To/To/Cc recipients, excluding the owned
mailbox and duplicates. It is enabled only when all participants have verified
relay routing. Direct customer addresses do not bypass the relay policy.
Confirmation binds the current message, chosen mode and files to the durable
send lock; an unknown outcome cannot be retried by changing mode or attachments.

The top-bar Gmail search action queries all connected authorized mailboxes on
the server, including archives, spam and trash. Gmail search operators are
supported; load more continues every mailbox's result cursor with the same
query. The existing main search field filters only already-loaded rows. Lists
read Gmail metadata; message bodies load when selecting a conversation.

Service client exposes Gmail-owned read/unread and archive/restore controls
separately from the local pending/waiting/resolved workflow status. Mutations are
disabled unless that mailbox context reports `can_modify`; a connection without
stored `gmail.modify` scope evidence stays read-only until reconnect and never
implies that a write succeeded.
After a metadata command, the app validates the server's Gmail re-read receipt
and reloads the thread before changing its displayed state. Failed updates leave
the old state visible and offer an explicit refresh.

The incoming activity panel reads persisted observations and operational
failures from `support/observability`. Its 24h/7d/30d/90d selector maps to
24/168/720/2160 hours. The displayed count is the number of rows currently
retained in the selected query window. The selected horizon is 90 days, and the
ledger is capped at 500 rows per mailbox. This can evict older observations
before the time window ends. Expired rows are pruned on later event writes; there is no
scheduled physical purge. The API caps its sample at 100 rows and the UI shows
up to 30; sample truncation is reported separately from the ledger cap. Sample
rows contain hashed message IDs only. Coverage is partial because observations
are recorded while an operator pages Gmail; they do not prove provider receipt or downstream delivery.
Missing values are unavailable, separate from zero. Failures show stable
stage/code, count, first/last occurrence and retryability; refresh is an explicit
read and never replays or resends customer mail. Failure aggregates are also
capped at 500 per mailbox. Rows outside the current query window are pruned on
later event writes, not by a scheduled purge.

This application calls `/api/admin/email` on its own origin using the existing
CommandGlows Clerk session. It never accepts Postmark tokens or internal service
credentials. The `demo` application is separate and deliberately synthetic.

Build the web application with `flutter build web --release --base-href /email-engine/`.
The CI `email-engine-web` artifact contains the resulting static application.
Install that artifact at the CommandGlows site's `public/email-engine/` before
building the site. `/dashboard/newsletters` is the authenticated operator host.
Do not serve the real application on an unrelated origin or substitute API secrets
for session authentication. No recipient data is baked into the artifact.

The application loads server-configured businesses, audiences and permitted test
recipients. Missing authorization or configuration produces an explicit error;
there is no fallback to example data. Every mutation has an idempotency key. A lost
response is not automatically retried. For an ambiguous POST, the current API
client instance retains a keyed HMAC fingerprint and idempotency key, not the
serialized request body, so retrying that exact command reuses its key. Successful
and known-rejected responses release the entry. The client holds at most 128
distinct pending commands; at the limit, further writes fail closed. Reconcile
their status before reloading the app or starting a new intent.

The backend and frontend must use the campaign API contract documented in
CommandGlows `shipglows_data/technical/newsletter-campaign-api.md`. The email
ledger and transport retain their existing pilot activation and allowlist gates.

Campaign review exposes an explicit link-check action through the same-origin
admin API. The client sends only the configured business and saved campaign
version to `campaigns/{id}/links/check`; the server extracts authored links,
stores a redacted revision-bound report and returns the GET-side-effect
disclosure. Approval and scheduling bind that report to the existing review and
single-use challenge. Uncertain links use the separate `approve_link_override`
challenge and audited override field; stale, incomplete or blocked reports are
rejected by the client and remain subject to server enforcement.

**Integration status (2026-09-23):** the local API adapts Convex list/detail
responses to Flutter's campaign models and maps `paused` to `suspended` and
worker states to `sending`. Approval and resume obtain a short-lived server
challenge bound to the Clerk actor/session, current report, campaign revision and
action. Pause is a stale-version-safe stop. Resume runs a fresh preflight and
requires human confirmation. Plan reduction now pages frozen, PII-free recipient
references; operators can choose only backend-marked reducible references,
review protected/locked counts, and must explicitly confirm a version-bound
reduction before preflight and approval are repeated. The editor route provides
a Scaffold for action feedback.

Incidents have a tenant-authorized paged read and a read-only UI showing persisted
state, severity, motif and transition time. Measurement, threshold, sample,
coverage and freshness are explicitly unavailable because no evaluator writes
them; there is no acknowledge/resolve mutation. Aggregate metrics remain
unavailable because the current events do not support complete campaign
attribution and coverage. No rate is fabricated as zero. The legacy
`/api/v1/email/campaigns` machine relay cannot issue a human session challenge and
must not be used to approve campaigns. No provider activation or real delivery is
authorized by this note.

Focused campaign evidence on 2026-09-23: 9 campaign API tests passed, and the
campaign controls widget test covers incident honesty and explicit reduction
confirmation. This evidence predates the support metadata and observability work.

Support metadata and observability static analysis on 2026-10-07: `flutter analyze`
passed for the app; `dart analyze` passed for the newsletter package, demo, and
existing fake repository. No test suite was run for this change. The backend
TypeScript check was started under CommandGlows Doppler but did not finish before
it was stopped. CI also checks the web artifact. Local analysis and fixture
captures do not prove hosted login, Gmail OAuth, live mailbox mutations, real
delivery, or inbox rendering.

## Human project dispatch (integration prepared, activation pending)

The Gmail reader now includes a private dispatch panel: prepare the factual
summary/type/reason/confidence/risks, select multiple available projects, inspect
the final transmitted contribution, then explicitly confirm. No email body is
copied automatically. AI processing remains unavailable pending the separately
approved provider/data policy. Project grants/connections remain unconfigured.

`CentralDispatchRepository` uses dedicated same-origin CommandGlows routes. The
server retains the authorized decision before attempting project intake and
returns one receipt per destination. Unknown or partial results lock a fresh
proposal until reconciliation; recovery reuses the original opaque identity and
preserves accepted destinations. Private contribution text is kept in the
central/project stores, not client persistent storage. The synthetic demo has
separate fake destinations and simulates lost receipts; it never calls Gmail or
project services.

Contract and remaining activation/privacy evidence:
`shipglows_data/workflow/specs/human-project-dispatch.md`, `contracts/` and each
destination's dedicated project-review-intake documentation. Local tests do not
prove hosted login, project authorization or real dispatch. None has yet occurred.
The operator subsequently requested actual local/cloud use inside ContentGlows
and ShipGlows.app. Both now embed the shared mailbox UI through a verified bearer
bridge. Their private project queues and durable server connection checks are
implemented locally. Gmail OAuth/mailbox configuration, connection grants, hosted
privacy checks and deployment remain to be completed. ContentGlows additionally
has opt-in transient BYOK pre-triage; ShipGlows.app has no authorized shared AI
connection yet. See the owning spec for the current scope and evidence.

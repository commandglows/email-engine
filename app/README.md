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

Focused evidence on 2026-09-23: 9 campaign API tests pass, and the campaign
controls widget test covers incident honesty and explicit reduction confirmation.

Validation: Flutter `analyze` and focused tests. Doppler has no configured project
in this checkout, so no build or interactive app run was attempted. CI also checks
the web artifact. These checks are not a hosted login, real delivery, or
inbox-rendering proof.

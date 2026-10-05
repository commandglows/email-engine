---
artifact: implementation_spec
metadata_schema_version: "1.0"
artifact_version: "1.6.0"
updated_at: "2026-10-05T21:39:10Z"
project: email-sidebar-app
created_at: "2026-10-05T16:41:35Z"
updated_at: "2026-10-05T21:39:10Z"
created: "2026-10-05"
updated: "2026-10-05"
status: ready
source_skill: 100-sg-spec
source_model: gpt-6
scope: newsletter-link-checker-pre-send-widget
owner: Diane
confidence: high
risk_level: high
security_impact: yes
docs_impact: yes
linked_systems:
  - packages/newsletter_studio_flutter
  - app
  - CommandGlows authenticated email API and Convex campaign service
depends_on:
  - shipglows_data/technical/design-system-authority.md
  - CommandGlows shipglows_data/technical/newsletter-campaign-api.md
supersedes: []
evidence:
  - "Operator-supplied Resend demo video https://cdn.resend.com/posts/link-checker.mp4, inspected at its final review state on 2026-10-05."
  - "Resend Link Checker changelog https://resend.com/changelog/link-checker describes broken, missing/invalid, placeholder and anchor-link findings with editor navigation."
  - "Local NewsletterStudio review, validation models, style tokens and authenticated campaign preflight inspected on 2026-10-05."
next_review: "2026-11-05"
next_step: "Wire a synthetic onCheckLinks callback into demo/lib/main.dart, then verify link findings and compact review rendering"
---

# Title

Newsletter Link Checker and Pre-send Review Widget

## Status

Implementation is present across the Flutter editor and authenticated CommandGlows campaign API. Backend mocked tests/typecheck and Flutter tests/analyze pass without Doppler. The managed synthetic demo starts at port 3012 and the review panel is accessible, but this demo does not provide `onCheckLinks`, so its link-check action is disabled; compact rendering and interactive finding navigation remain unverified. No email was sent and nothing was deployed or released.

## User Story

As an authorized newsletter operator, I can see who will receive the current campaign, inspect its sending readiness and find broken links in one compact review widget, so I can fix problems in the right block before I deliberately approve or schedule the campaign.

## Minimal Behavior Contract

When an operator opens final campaign review for a saved draft revision, the widget shows the current eligible-recipient count and available server preflight status. The operator explicitly starts the link check; it flags broken links returning 404 or another HTTP error, missing or invalid URLs (including empty buttons), placeholder destinations such as `example.com` or `TODO`, and anchor-only links such as `#section`. It reports each result against the responsible block; selecting an issue returns focus to that block and URL field. Definite malformed, placeholder, anchor-only, 404 or 410 links block campaign approval and scheduling; outcomes that cannot be confirmed, such as timeouts or anti-bot denial, remain visible warnings with an explicit operator override. Changes to content invalidate the report. A missing, incomplete, stale or mismatched server report never appears as a successful check and never authorizes campaign approval.

## Success Behavior

- The pre-send surface is a compact right-side panel on wide layouts and an accessible full-width sheet on compact layouts, using the existing review transition and `NewsletterStudioStyle` geometry.
- Its hierarchy follows the supplied reference: a clear readiness heading; recipient/audience summary; concise sending-policy checks; an expandable link-issues group with counts; one row per affected block; and one prominent final send control.
- The panel uses the reference's restrained dark, high-contrast treatment and clear success/warning/error grouping through project-owned semantic theme tokens. It does not copy Resend source code, brand marks, or media assets.
- On the supplied video, the observed link summary is `1 valid, 1 404, 1 unreachable`; issue rows show the destination and short outcome and can be opened to edit the corresponding link.
- Inspect structured blocks before rendering so an empty button can be reported even when the email renderer refuses to produce HTML. For renderable drafts, check all authored destinations represented in the rendered email, including button and source links; do not silently skip a link type.
- Check the system-generated unsubscribe link through its existing authoritative configuration/evidence contract, never by requesting it, because visiting it could unsubscribe an address. Do not classify the system-owned link as an authored destination.
- The final send control is a deliberate slide-to-send gesture. A fully equivalent keyboard and assistive-technology action remains available, exposes its accessible name/state, and reaches the same existing confirmation/challenge path.
- The complete report is bound to authenticated business, campaign, revision and normalized destination digest. It is current only for the reviewed content and its bounded expiry.

## Error Behavior

- During network checking, show a truthful in-progress state; never present unchecked links as valid.
- If some checks time out, are rate-limited, fail DNS, or are refused by a destination, show `Non vérifié` with the reason category. Preserve other link results and permit a clearly labeled override for uncertain results only.
- If validation, API, authorization, or persistence fails, show that the review is incomplete, keep the editor usable, and disable campaign approval and scheduling until a current complete report is available.
- If a destination returns a definite broken-link status, identify its block and disable campaign approval and scheduling until it is fixed or the destination later verifies healthy. Opening an issue focuses the matching URL control; a removed or stale block falls back to a visible general content issue.
- If a send response is ambiguous, preserve the current unknown/refresh-before-retry behavior. The slider must not automatically repeat an approval or send operation.
- The separate authorized test-send action keeps its existing recipient gate and semantics; link findings describe the campaign and do not silently trigger a test message.

## Problem

The newsletter editor already has a pre-send review panel and a validation model, but issues are generic, link destinations are not checked for reachability, and selecting an issue cannot navigate to the responsible block. The supplied Resend widget makes readiness, individual link failures, recovery and final send intent visible together. Its five-second demo shows 404 and unreachable-host outcomes, which a local URL-format check or browser-only request cannot establish reliably.

## Solution

Extend the existing Flutter review surface and validation model, and extend the authenticated CommandGlows campaign boundary with a server-run, bounded link check. Static checks inspect the complete structured draft before rendering; reachability checks inspect every authored destination in the rendered email when rendering succeeds. The server persists a compact report bound to the exact revision and destination digest and returns redacted display details. The existing approval path requires that current report in addition to its current safety preflight and single-use human challenge. Keep campaign link results separate from the existing identity, consent and delivery evidence records.

Translate the visual reference into the existing Flutter theme and newsletter tokens: retain its compact readiness-card silhouette, grouped rows, expandable issue count, strong status contrast and final slide affordance, while respecting host light/dark themes, responsive review behavior, text scaling, keyboard focus and project accessibility rules.

## Scope In

- Pre-send panel layout and states for wide and compact widths, including loading, complete, partial/uncertain, blocked, empty-link and API-error states.
- Summary of the already selected audience and server-provided eligible count; no new audience/topic model.
- Existing verified sender, unsubscribe/footer and current campaign safety checks where the host actually provides those facts; unavailable facts remain unavailable.
- URL syntax and policy checks for missing/invalid destinations, including buttons without URLs, malformed, non-HTTPS and credential-bearing URLs, placeholders such as `example.com`/`TODO`, and anchor-only `#...` links.
- Bounded public HTTPS reachability checks for all authored links in the final email that classify final 2xx, 404 and other HTTP errors, unreachable hosts, and uncertain timeout/refusal outcomes. Keep the system-generated unsubscribe URL out of outbound checking.
- De-duplication of identical normalized destinations while retaining every source block reference for navigation.
- Expand/collapse link issue rows; selecting a row returns to the matching block and focuses its URL field.
- An accessible slide-to-send interaction that invokes the existing authenticated review, single-use challenge and approval sequence once.
- Server-side enforcement that the approval report is complete, fresh, and bound to the saved campaign revision and destination digest; save/content edits invalidate old link results.
- Focused Flutter and mocked server/API proof; responsive rendered proof with synthetic campaigns only.
- Package README/CHANGELOG and CommandGlows campaign API/operations documentation updates when implementation lands.

## Scope Out

- Replacing Newsletter Studio with the React Email editor package or changing the app platform/framework.
- Copying Resend's proprietary implementation, marks or video assets. Reproduce observed behavior and visual intent in project-owned code.
- AI content review, topic subscription controls, or any check the current campaign model/API cannot truthfully supply.
- Changing audience membership, consent, unsubscribe, suppression, sender verification, legal policy, delivery provider, pilot allowlists or real-send activation.
- Crawling pages beyond each linked destination, executing page scripts, parsing recipient-specific personalization, or checking destinations requiring authentication.
- Checking `mailto:`, `tel:`, non-HTTPS, private intranet or arbitrary-port URLs by making requests.
- Automatic retries of campaign approval, resending, production configuration, deployment or live-email proof.

## Constraints

- Product and user outcome: prevent avoidable broken campaign destinations and make the last send decision understandable. Preserve the authenticated operator, selected audience and existing server-owned send authority.
- Source of truth: editable blocks come from the saved campaign revision; eligible counts and existing policy checks come from the authenticated campaign API; the server link report is authoritative for reachability. Browser-local checks may supplement syntax detection but cannot mark an HTTP destination reachable.
- UI/design authority: `shipglows_data/technical/design-system-authority.md`, `NewsletterStudioStyle`, `NewsletterStudioColors`, and host `ThemeData`. No one-off screen colors, dimensions, radii, typography or motion values.
- Accessibility: WCAG 2.2 AA intent, visible focus, logical Tab order, semantic status announcements, minimum practical touch target, keyboard-operable equivalent to dragging, and reduced-motion-safe transitions.
- Data: persist block IDs, outcome category, response status where safe, check time/expiry, campaign revision, and destination digest. Do not persist full query strings or URL fragments in report diagnostics. The editor already owns the destination and may display its host/path with sensitive query/fragment values redacted.
- Request budget: at most one check per distinct destination in a saved revision; cap at the current maximum of 60 campaign blocks, limit concurrency, response size, redirect count and total wall time. A run must terminate within a bounded deadline and cannot hold a database transaction open over network I/O.
- Redirects: revalidate every hop and resolved address. Only public routable HTTPS destinations on port 443 are eligible. Reject credentials, localhost, private, loopback, link-local, multicast, reserved IP ranges, unsafe DNS answers and redirects to those destinations. Do not attach cookies, auth headers or operator/session data.
- HTTP: send HEAD first. Only when the destination responds that HEAD is unsupported (405 or 501), send one bounded GET fallback with `Range: bytes=0-0`; cancel reading after response headers or the first byte and enforce a strict response cap if Range is ignored. Never retry other failures with GET. Do not attach cookies, auth headers or operator/session data. A GET may still trigger a destination-side effect; disclose this beside the operator-triggered check. Treat a final 404/410 as definitely broken and blocking. Treat all other non-2xx final statuses, DNS/TLS/refusal/timeouts and partial results as uncertain, visibly reported and overridable only through the explicit audited override.
- External destinations: after seeing the disclosure about external requests and possible destination-side effects, the operator explicitly starts the check; it may make unauthenticated requests to the campaign's explicit public HTTPS destinations. Do not send any recipient list, recipient identity or session credential to those hosts. Never log full destination URLs or response bodies.
- Link-check reports and challenges are campaign/business/revision scoped. A stale report, another business' report, changed destination set or reused challenge cannot approve the campaign.
- The rendered unsubscribe destination can trigger a state change. Validate its presence and ownership from the existing renderer/preflight contract without making an HTTP request to it.
- Test messages remain separate from broadcast approval and continue to require the existing explicit server-approved test recipient.

## Test Contract

Surface: `newsletter_studio_flutter` package, the real `app` adapter and the authenticated CommandGlows campaign API/service. Use fake public hosts and mocked network responses; no test makes requests to arbitrary Internet destinations or sends email.

Automated proof covers the acceptance criteria, link classifications, changed revisions, duplicate URLs, stale/partial reports, authorization, request limits, redirects/SSRF defenses, timeout recovery, keyboard slide equivalent and app-to-API mapping. Rendered browser proof covers a synthetic desktop review at the established wide workspace and a compact/mobile sheet at 390x844, including dark theme and enlarged text. Do not claim hosted authentication, live destination health, delivery, inbox rendering or production activation from those checks.

## Dependencies

- Existing `NewsletterDraft.blocks`, `NewsletterValidationIssue`, review panel, `NewsletterStudioStyle`, campaign repository and same-origin authenticated admin API.
- Existing campaign revision, server evidence preflight, `report_id`, scoped single-use approval challenge and fail-closed send path in CommandGlows.
- A server-side bounded outbound HTTP checker in the CommandGlows operator API; the Convex mutation layer does not perform network I/O.
- Mock HTTP/DNS/redirect seams for deterministic security and status proof.

## Invariants

- A URL that was never checked is never shown as healthy.
- A broken-link blocker or incomplete/stale report cannot be bypassed by calling the approval endpoint directly.
- A definitely broken destination must be corrected and rechecked before scheduling or approving a broadcast. Uncertain reachability stays visibly uncertain and requires a deliberate override.
- Every result navigates by stable block ID, never by list index or URL string alone.
- Report status is invalidated when content or any normalized destination changes; recipient membership changes continue to use the existing independent snapshot rules.
- Human confirmation, challenge binding, idempotency, `unknown` outcome recovery, consent, suppression and allowlist checks remain enforced.
- No destination receives recipient data, identity data, cookies, credentials or full response content.
- The widget never invents unsubscribe, topic, AI-review, audience, sender or success facts absent from authoritative data.

## Links & Consequences

Reference: [Resend Link Checker demo](https://cdn.resend.com/posts/link-checker.mp4) and [Resend changelog](https://resend.com/changelog/link-checker). The demo's observed final state groups a passing recipient check, unsubscribe/topic warnings, an expandable `1 valid / 1 404 / 1 unreachable` summary, destination-level reasons and a slide-to-send control.

Upstream: current newsletter draft and server-controlled campaign data. Downstream: the Flutter package/app, authenticated Astro admin route, CommandGlows Convex campaign review/approval records and API contract. Adding a durable network result and a new send blocker changes the server API and approval invariant; it must be delivered as one compatible frontend/backend contract. No provider migration is involved.

Product decision trace: user request on 2026-10-05 to prepare a spec copying the Resend link-checker widget. No Atlas or stable product-function ID was found in the inspected repository; the spec is the first local contract for this bounded capability.

## Documentation Coherence

Implementation must update `packages/newsletter_studio_flutter/README.md` and `CHANGELOG.md`, the app README if the API adapter changes, `shipglows_data/technical/code-docs-map.md` if ownership changes, and CommandGlows `shipglows_data/technical/newsletter-campaign-api.md` plus operational/security guidance for outbound link requests. Update `design-system-authority.md` only if a reusable token or component authority changes; prefer existing tokens.

## Edge Cases

ZOMBIES: zero authored links shows a truthful no-link state; one link and 60 distinct destinations remain bounded; duplicates report once but navigate to every corresponding block; a missing button URL is reported before rendering; malformed/non-HTTPS URLs, `example.com`, `TODO` and `#anchor` are flagged; 404/410 block and every other HTTP error is surfaced as uncertain; a valid HTTPS redirect stays public and bounded; redirect to private IP is rejected; DNS failure, timeout, 401/403/429, other 4xx and 5xx remain uncertain without false success; only 405/501 from HEAD permits one bounded GET fallback; the generated unsubscribe link is checked structurally but never fetched; editing or deleting a block invalidates its result; draft save during a check makes the response stale; two checks for different revisions cannot overwrite current state; cross-business report IDs fail closed; approval replay is rejected by the existing challenge/idempotency boundary; a lost approval response requires status refresh rather than blind retry; compact width, large text, keyboard-only use and reduced motion remain usable.

## OWASP Security Gate

Applicable Top 10:2025 categories: A01 Broken Access Control (business/campaign scoping); A02 Security Misconfiguration (outbound network boundary); A03 Software Supply Chain (no dependency required unless justified); A05 Injection/SSRF (attacker-controlled URLs, DNS rebinding, redirects); A06 Insecure Design (GET side effects, budgets, fail-closed approval); A08 Software/Data Integrity (revision/digest binding and report replay); A09 Security Logging (redacted URLs and response bodies); A10 Exceptional Conditions (timeouts, partial results, cancellation and ambiguous approval).

Trust boundary: authenticated operator draft -> same-origin admin route -> arbitrary public destination -> scoped campaign/report storage -> Convex approval. Server authorization is rechecked on every route. The checker resolves and validates addresses before every outbound hop, rejects non-public destinations, imposes bounded concurrency/time/bytes/redirects, uses no user credentials, and emits only redacted status evidence. Never rely on Flutter restrictions as the security control. Selected ASVS requirement: `v5.0.0-1.3.6` (SSRF prevention by allowlisting protocols, domains, paths and ports and sanitizing untrusted input). Residual risk: the single bounded GET fallback to an operator-selected public URL can still produce that site's externally visible request or trigger unsafe GET behavior; HEAD-first behavior, restriction to 405/501, the visible disclosure, HTTPS-only policy, request budget and no credential forwarding bound but do not eliminate that inherent network effect.

## Implementation Tasks

1. **Freeze the check/result contract.** Target: CommandGlows API docs and this spec. Define typed statuses, redacted report fields, current-revision/destination-digest binding, expiry, blocking versus overridable outcomes, and error mapping. User-story link: authoritative, understandable link results. Dependency: this draft and the readiness/security review. Validation: independently compare Flutter JSON mapping, API schema and Convex approval expectations; reject any field that permits a client to assert success.
2. **Add the bounded server checker.** Target: authenticated CommandGlows admin route plus a separate campaign link-report record/mutation. User-story link: reliable 404/unreachable findings. Dependency: task 1. Validation: mocked DNS/HTTP coverage for status classes, redirects, private-address rejection, timeouts, concurrency and size limits; prove campaign/business authorization and report freshness at approval. No deployed secret/config change or external email.
3. **Add the Flutter result model and recovery navigation.** Target: `packages/newsletter_studio_flutter/lib/src/newsletter_studio_models.dart` and `newsletter_studio.dart`. User-story link: understand and fix each issue. Dependency: tasks 1–2. Validation: package-level widget cases for grouped findings, expanded/collapsed rows, stable block navigation, save/recheck, loading/error/uncertain states, responsive theme, focus and accessible gesture equivalent.
4. **Wire the real app flow.** Target: `app/lib/campaign_repository.dart` and `app/lib/main.dart` plus CommandGlows API contract. User-story link: see checks for the real saved revision and preserve current server send gates. Dependency: tasks 1–3. Validation: adapter tests for current revision/report binding; prove approval is blocked server-side on stale or definite-broken reports and ambiguous outcomes are refreshed rather than retried.
5. **Review and document the integrated journey.** Target: package/API docs, synthetic demo if needed, and this spec's flow. User-story link: confident correction and intentional send. Dependency: tasks 1–4. Validation: source/API review, automated package/backend checks, then rendered browser comparison at desktop and 390x844 with a synthetic campaign. No live recipient, arbitrary external request, actual send, deployment or activation is part of this spec's proof.

## Acceptance Criteria

- Opening pre-send review for a saved campaign checks each distinct eligible public HTTPS destination once within the defined request budget and associates each result with every block that uses it.
- The widget presents recipient/audience readiness, available existing safety checks and link counts/results in a compact, navigable panel matching the reference's hierarchy and affordances through project tokens.
- The checker flags all four reference categories: broken links returning 404 or another HTTP error; missing/invalid URLs such as empty buttons; placeholders such as `example.com` or `TODO`; and anchor links such as `#section`.
- Static checks identify missing/invalid, placeholder and anchor-only links without network calls, including on drafts that cannot yet render. For renderable drafts, every authored URL in the actual email is checked and mapped back to its block; the generated unsubscribe URL is validated structurally without an HTTP request.
- Server status distinguishes valid destinations, 404/other HTTP errors, unreachable hosts and unverifiable outcomes; no failed or skipped check is presented as valid.
- Selecting an issue moves focus to the exact URL field and remains correct after reordering/removing other blocks.
- Missing/invalid, placeholder, anchor-only and final 404/410 findings disable schedule/approval in the UI and are rejected by the authenticated server route/Convex approval path even if the client is modified. All other non-2xx HTTP statuses and unverifiable results are never labeled valid and proceed only through an explicit, auditable override.
- Any content, link, campaign revision, report expiry, business mismatch, or partial check prevents stale results from authorizing approval; a new check is required.
- Only public HTTPS:443 requests without credentials are sent. Unsafe IP ranges are rejected before and after redirects/DNS resolution; redirects, concurrency, time, response bytes and URL count are bounded; no cookies, auth headers, recipients, logs or response bodies are forwarded/persisted.
- The slide gesture triggers the existing challenge/approval flow once; a keyboard/screen-reader alternative has equivalent deliberate intent. Unknown approval outcomes require status refresh and never auto-resend.
- Test sending keeps its existing allowlisted-recipient and truthful receipt behavior. No other preflight check, consent, suppression, sender or provider invariant regresses.
- At wide and compact widths, in supported light/dark themes and enlarged text, the widget has no clipped issue rows or lost controls; focus and status are perceivable without color alone.
- Automated proof uses mocked destinations and sends no email; rendered proof uses synthetic data. No hosted/authenticated, provider, inbox, deployment or production claim is made.

## Test Strategy

1. Unit-test URL extraction and classification without network: missing button URL, malformed, non-HTTPS, credentials, `example.com`, `TODO`, `#anchor`, duplicates, CTA/source destinations, and separate structural validation of the unsubscribe destination.
2. Test the server checker with a fully mocked resolver and transport: 2xx, 3xx, 404, 410 and other HTTP errors, unsupported HEAD fallback, DNS/TLS/refusal/timeouts, redirects to public and private ranges, DNS rebinding, response-size limits, concurrency, cancellation and wall deadline. Assert that the unsubscribe URL is never requested.
3. Test report persistence and approval binding across current/stale revision, changed destination digest, expired/partial result, wrong business, replay, duplicate command and unknown approval receipt.
4. Test Flutter states and block focus navigation with zero/one/many/duplicate links, API unavailable, uncertain warning, blockers, editing during a check, stale test receipt, keyboard control and responsive/text scaling.
5. Render the real synthetic web host at the established desktop layout and 390x844, compare the readiness hierarchy and link issue detail to the supplied video, and inspect focus, contrast, overflow, dark theme and reduced motion. No test contacts external URLs.

## Risks

- Outbound URL checks add a new server-side request boundary; SSRF, DNS rebinding, malicious redirects, high latency and destination-side GET effects need security review.
- Anti-bot, authentication, geolocation and rate-limit behavior can look unhealthy to a server checker. Preserve uncertainty as uncertainty and do not claim recipient reachability.
- The link report is short-lived evidence about one request path at one time; a link can change after checking or behave differently for recipients.
- Treating false positives as hard blockers harms legitimate sends; treating definite errors as warnings harms recipient trust. Keep the classification and override policy explicit in API and UI.
- Frontend-only UI without server enforcement would be bypassable. Implementation is incomplete until the backend revision-bound approval gate is proven.
- The inspected demo shows one desktop send-review moment only; mobile composition and unseen loading/expanded interaction details are adapted from the existing Flutter review pattern and must be validated during implementation.

## Execution Notes

Primary implementation surface: `packages/newsletter_studio_flutter` plus `app`; backend contract lives in CommandGlows `commandglows_site`. Link checks are operator-triggered, run against the saved revision, use bounded HEAD-first requests with one disclosed GET fallback only on 405/501, redact destination paths/query values in persisted evidence, and enforce blocked findings or a separate audited uncertain-result override at approval. Invalid authored URLs are retained in drafts for diagnostics but omitted as unsafe preview links. Backend tests use mocked resolver/transport only. Existing challenge, idempotency and unknown-outcome rules are inherited. Flutter package (20 tests), app (14 tests), and both Flutter analyses pass without Doppler. Managed demo `s start -ProjectPath ...\demo -FlutterDevice web-server` starts at `http://127.0.0.1:3012`; browser accessibility inspection confirmed the newsletter editor and review surface. The demo's `NewsletterStudio` omits `onCheckLinks`, so its check button is disabled and it cannot demonstrate findings or navigation; screenshot capture timed out and compact rendering was not verified. No external destinations were checked, no email was sent and no deployment occurred.

## Open Questions

None. Operator decision recorded: HEAD first; one bounded GET fallback only for 405/501, with visible disclosure; 404/410 block; other non-2xx outcomes remain uncertain and require an explicit audited override to proceed.

## Skill Run History

| Date UTC | Skill | Model | Action | Result | Next step |
|----------|-------|-------|--------|--------|-----------|
| 2026-10-05 | 100-sg-spec | gpt-6 | Inspect Resend video and local campaign/review contracts; draft link-checker widget spec | Draft persisted; readiness/security review pending | `/101-sg-ready newsletter link checker widget` |
| 2026-10-05 | 100-sg-spec | gpt-6 | Incorporate the four requested link issue categories and rendered-email coverage | Spec updated to v1.1.0; draft remains pending readiness/security review | `/101-sg-ready newsletter link checker widget` |
| 2026-10-05 | 101-sg-ready | gpt-6 | Review user story, UI authority, cross-system consequences and outbound-check security gate | Not ready: outbound GET policy and non-404/410 HTTP severity remain material operator decisions | Resolve the two questions above, then repeat readiness review |
| 2026-10-05 | 100-sg-spec | gpt-6 | Record operator choice for bounded GET fallback and HTTP severity | Updated spec to v1.3.0 with exact request and override policy | `/101-sg-ready newsletter link checker widget` |
| 2026-10-05 | 101-sg-ready | gpt-6 | Recheck baseline, approved security policy, UI authority, API consequences and proof contract | Ready for implementation; no blocking ambiguity remains in the spec | `/102-sg-start newsletter link checker widget` |
| 2026-10-05 | 102-sg-start | gpt-6 | Start the ready-spec implementation; inspect frontend and backend ownership and preserve sequential write isolation | Implementation underway; two independent read-only reconnaissance passes complete | Complete backend and Flutter slices in delegated sequence, then integrate and run focused checks |
| 2026-10-05 | 102-sg-start | gpt-6 | Implement bounded backend checker, revision-bound approval gate, invalid-link persistence, Flutter review widget and client adapter in sequential delegated slices | Backend mock suites (61 tests after invalid-URL regression) and CommandGlows typecheck pass; Flutter package (20 tests), app (14 tests), and both analyzes pass without Doppler; editor/review surfaces visible in managed demo, link checker disabled because demo callback is absent | Wire synthetic callback and verify findings plus compact layout |

## Current Chantier Flow

### Intake and draft — 2026-10-05

- Outcome: reproduce the useful Resend pre-send link-checking widget in the existing authenticated Flutter newsletter editor.
- Reference observed: compact dark readiness panel, recipient row, warning rows, expandable valid/404/unreachable link summary and slide-to-send control.
- Project translation: preserve the Flutter studio, its token authority, existing audience/sender facts, authenticated campaign API, approval challenge and unknown-outcome recovery.
- Clarification: flag 404 and other HTTP errors, missing/invalid URLs including empty buttons, placeholder `example.com`/`TODO` destinations, and anchor-only links; inspect all authored links in the rendered email and never fetch the side-effecting unsubscribe URL.
- Operator decision: HEAD first; use one bounded GET with `Range: bytes=0-0` only after 405/501, disclose the possible destination-side effect, block on 404/410, and require explicit audited override for other non-2xx or unverifiable outcomes.
- Readiness result: ready for implementation; API, UI and approval tasks preserve the same severity and override contract.
- Implementation: bounded server checker, separate revision-bound report, server-enforced block/override approval, invalid-link draft persistence, Flutter review widget, stable block navigation, accessible slide-to-send equivalent, client adapter and docs are present in both repositories.
- Verification: CommandGlows focused mocked suites and typecheck pass; metadata and whitespace checks pass; Flutter files were formatted. Without Doppler, the Flutter package's 20 tests and app's 14 tests pass, and both analyses are clean. Managed synthetic demo starts on assigned port 3012; browser accessibility inspection reaches the editor and review panel. Its `NewsletterStudio` does not supply `onCheckLinks`, leaving that control disabled; compact review and link finding navigation remain unverified. Screenshot capture timed out.
- Boundary: no real destination requests, sends, deployment, release, or hosted/authenticated proof.
- Next: wire a deterministic synthetic link report into `demo/lib/main.dart`, then render and verify expanded findings, stable-block navigation, and compact 390x844 layout.

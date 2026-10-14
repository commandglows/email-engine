---
artifact: handoff
metadata_schema_version: "1.0"
artifact_version: "1.1.0"
project: email-engine
created: "2026-10-14"
updated: "2026-10-14"
status: in_progress
source_skill: shipglows
scope: dynamic-dispatch-destinations
owner: Diane
confidence: medium
risk_level: high
security_impact: yes
docs_impact: yes
linked_systems: [CommandGlows, ContentGlows, ShipGlows.app, ShipGlows CLI, shipglows-private]
depends_on:
  - artifact: shipglows_data/workflow/specs/human-project-dispatch.md
    required_status: active
next_step: Diane reviews the five branches, applies migrations (ContentGlows 015/016), deploys, then runs batch 5 (activation) in person
---

> **État 2026-10-14 (implémentation autonome).** Les lots 0 à 4 sont implémentés
> sur des branches locales, tests verts, rien n'est déployé ni activé :
> - ContentGlows `fix/idea-pool-ownership` (lot 0) et
>   `feat/contentglows-dispatch-targets` (dispatch-targets + intake v2).
> - shipglows-private `feat/projects-registry-json` (registry.json, 19 entrées).
> - ShipGlows runner `feat/runner-dispatch-targets` (dispatch-targets,
>   grants en table, intake v2).
> - CommandGlows `feat/dispatch-destinations-catalog` (catalogue Convex,
>   lecteur unique, recheck autorité au claim, écran d'activation).
> - Moteur `feat/intake-v2-dispatch-panel` (contrat v2, panneau groupé,
>   fraîcheur).
>
> **Décisions actées (autonomes, révocables) :**
> 1. Cibles ContentGlows : ébauches **et** Idea Pool.
> 2. États récepteurs d'ébauche : `todo` et `in_progress` (pas `generated`).
> 3. Slug `shipglows-private` = clé canonique ; `projects/registry.json` créé.
> 4. « Actif » = non archivé + `accessState=available` (colonne `is_archived`
>    ajoutée côté runner, filtre `archivedAt` côté ContentGlows).
> 5. Activation explicite une par une dans CommandGlows (jamais automatique) ;
>    les découvertes arrivent en `candidate`.
>
> La réponse `dispatch/context` reste `schema_version: 1` avec champs additifs
> optionnels (`kind`, `project_label`, `generated_at`). Reste pour Diane :
> migrations ContentGlows 015/016 (plan puis apply), variables Convex
> (`EMAIL_DISPATCH_HOST_ALLOWLIST`, tokens), déploiements, bump du pin moteur,
> puis lot 5 (flags + consentement Google, en personne).

# Handoff — dynamic dispatch destinations

## Outcome

When Diane reads an email in the shared mailbox (ShipGlows.app or ContentGlows),
she can send a reviewed contribution to:

- **a ContentGlows content draft** (an "ébauche"), not merely a project;
- **a connected, active ShipGlows project**, consistent with her private
  portfolio registry (`C:\Users\Diane\ShipGlows\shipglows-private\projects\index.md`).

Destinations are discovered dynamically and refreshed periodically. They are
not hand-written into an environment variable. Every dispatch still requires an
explicit human choice of the message and its destinations.

## Starting state (verified 2026-10-14)

- Identity: one canonical global user links Diane's Firebase (ShipGlows.app),
  Auth0 (ContentGlows) and Clerk admin (CommandGlows) identities. The link was
  proven live with a session-bound pairing code; fingerprints match in both apps.
- Intake endpoints are deployed but empty. ContentGlows API
  `/api/projects/{id}/review-intake` is enabled and authenticated. The ShipGlows
  runner intake exists but is disabled (no grants).
- CommandGlows dispatch is closed: no `EMAIL_PROJECT_DESTINATIONS`, no
  `EMAIL_PROJECT_DISPATCH_ENABLED`, no `EMAIL_PRIVATE_DATA_TELEMETRY_VERIFIED`.
  Gmail consent and AI triage are also closed.
- Audit sources for this handoff: four read-only audits (ContentGlows drafts,
  ShipGlows runner projects, shipglows-private registry, and the CommandGlows
  dispatch registry).

## Findings by system

### CommandGlows (dispatcher)

- The registry is static JSON in env (`dispatch/api.ts:18-38`). It is parsed
  in three places that must converge: `dispatch/api.ts`,
  `contentReviewAuthority.ts:25-32` and `userMailbox.ts:375-381`.
- Durable receipts snapshot `destination_id`, `project_id` and `origin` at
  confirm, and are re-checked at claim. The fingerprint covers the destination
  set.
- **Gap:** the send path never rechecks review authority or entitlement. That
  check happens only on the ContentGlows side, through
  `CONTENTGLOWS_REVIEW_CONNECTION_AUTHORITY_URL`.
- Ledger rows live in `emailSupportRecords` (kinds `dispatch:*`). A 90-day
  purge runs every 5 minutes.

### ContentGlows (destination: drafts)

- Draft-like entity: `content_records` (project-scoped, owner via project).
  Lifecycle has no `draft` value; candidates are `todo`, `in_progress` and
  `generated`. The listing API is `GET /api/status/content`, limited to owned
  projects.
- Idea Pool (`idea_pool`) is the other natural target for email inspiration,
  but it has no link to content records.
- The current review intake targets a project only, holds a single state
  (`pending_review`) and has **no accept or reject path**. Targeting a draft
  needs a nullable `target_content_id`, uniqueness including the target, and an
  accept route that appends through the existing CAS body write
  (`save_content_body_cas`).
- **Security gap found, to fix first:** `POST /api/ideas` and bulk ingest never
  verify `project_id` ownership. Idea get, patch and delete skip the owner check
  when `user_id` is NULL (`lab/api/routers/idea_pool.py:52-69, 110, 128,
  151, 157-170`).

### ShipGlows.app runner (destination: projects)

- Projects are runner IDs (`prj_*`, `local_*`, `github_*`) with memberships
  (`read` or `mutate`). Lists come from `GET /v1/local-projects`,
  `/v1/cloud-projects` and `/v1/cockpit`, all authenticated with a Firebase
  bearer.
- "Connected" means `accessState=available`; "active" means not archived (or
  cloud status online). No single field combines both.
- Intake grants are static env (`RUNNER_REVIEW_INTAKE_GRANTS`) with a bearer
  per grant. No route lets an external dispatcher enumerate projects.
- The cross-system bridge is `project_identity_bindings`
  (`GET /v1/projects/resolve?sourceSystem&sourceProjectId`). The GitHub numeric
  repository ID is the most stable natural key; owner/repo is not.

### shipglows-private (portfolio registry)

- `projects/index.md` is a human pitch registry: 26 entries, no slug, ID or
  status, and nothing parses it. Nine per-project fiches (`projects/<slug>.md`)
  carry a frontmatter `slug`, which is the best candidate key.
- Keys diverge: folder vs slug vs repo (`shipglows_app` vs `shipglows-app`,
  `commandglows/*` vs `dianedef/*`). The DevServer registry keys on filesystem
  path. The repository is private and governed by the `sg-private` contract.

## Proposed architecture

1. **One canonical project key.** Add a machine-readable registry to
   shipglows-private, for example `projects/registry.json` with
   `{slug, display_name, github_repo_id, repos[], status: active|paused|archived,
   contentglows_project_ids[], runner_project_ids[]}`. `index.md` remains the
   human view. Only `sg-private` and the CLI write it.
2. **Host-side destination catalogs.** Each host exposes an owner-scoped,
   service-authenticated list endpoint that returns only what the owner may
   receive:
   - ContentGlows: `GET /api/dispatch-targets`, listing projects plus their
     open drafts (`todo`/`in_progress`/`generated`) and optionally the Idea
     Pool, with stable IDs and labels.
   - Runner: `GET /v1/dispatch-targets`, listing non-archived projects where
     the owner has `mutate`, bound to the registry slug via
     `project_identity_bindings`.
3. **CommandGlows catalog.** A Convex table in the ledger deployment, keyed by
   `(globalUserId, destinationId)`. It is refreshed by cron and on demand when
   the mailbox context opens (rate-limited). Origins come from a fixed host
   allowlist, never from host responses. Discovered rows start as `candidate`;
   Diane explicitly activates them once, in a CommandGlows settings screen.
   This replaces the static env registry in all three parsers.
4. **Host credentials.** One service credential per host (env), not per
   destination. The host enforces per-project and per-draft ownership on every
   POST. CommandGlows rechecks `authorizeReviewConnection` plus entitlement
   before every claim, which closes the known gap.
5. **Intake v2 contract** (`contracts/project-review-intake-v2`): add an
   optional `target` (`{kind: project|content_draft|idea_pool, id}`). Hosts
   add accept/reject routes. Accepting a draft target appends to the draft
   through the existing CAS write; nothing is published or generated implicitly.
6. **UI.** The shared Flutter dispatch panel groups destinations by project,
   then draft. It shows freshness ("liste mise à jour il y a N min") and keeps
   the exact payload preview and explicit confirmation.

## Decisions for Diane (before implementation)

1. ContentGlows targets: drafts only, or drafts plus Idea Pool?
2. Which draft states may receive (`todo`, `in_progress`, `generated`)?
3. Is the shipglows-private slug the canonical project key? Is a new
   `registry.json` accepted in that private repository?
4. ShipGlows "active" means non-archived and connected (`accessState=available`).
   Is that correct?
5. One-time activation of discovered destinations in CommandGlows, or automatic
   activation of everything the hosts list?

## Execution plan (orchestrator)

Batches with independent write scopes, run in order:

0. **Security fix (ContentGlows):** Idea Pool ownership checks. Ship
   independently.
1. **Registry:** `registry.json` schema, `sg-private` writer, and a CLI reader.
2. **Hosts:** ContentGlows `dispatch-targets` plus intake v2 (target, accept,
   reject); runner `dispatch-targets`, grant table and intake v2. Two agents,
   one per repository.
3. **CommandGlows:** Convex catalog, refresh cron, activation UI, single
   registry reader, and authority recheck at claim.
4. **Engine:** contract v2, dispatch panel grouping and freshness. Bump the
   engine pin in both apps.
5. **Activation with Diane present:** enable flags, then visible Google
   consent. The first real dispatch requires an explicitly chosen message and
   destinations.

Each batch runs its repository's local lint and tests before any PR (CI is
manual). It deploys through the declared recipes: Vercel for the apps and
CommandGlows; `npx convex deploy` for Convex; SSH on the managed host with a
recorded rollback for the ContentGlows API and the runner (production installs
use `lab/requirements.lock`; npm 12 blocks native install scripts, so native
builds such as `node-pty` must be approved or rebuilt).

## Invariants (must not regress)

- No email-address identity inference; no client-supplied URLs, tokens or
  project IDs beyond selection from the server catalog.
- No raw email body in receipts or host stores; 90-day payload expiry with
  tombstones.
- Reading or triage never dispatches; dispatch never modifies Gmail.
- Authorization is rechecked at send time; destination changes never mutate an
  existing dispatch.
- No secret or private registry content in public repositories or chat.

## Known operational debts

- PM2 logs on the managed host have no rotation.
- The account settings page on commandglows.com does not display the pairing
  fingerprint after success, although the server links correctly.
- Vercel did not auto-deploy CommandGlows PR #16; it was deployed from a clean
  `main` checkout with the CLI.
- `convex/emailSupport.ts` still uses the unsupported `Query.count()` on
  `main`. The fix sits on local branch `fix/convex-email-support-count`.

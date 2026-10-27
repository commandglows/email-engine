# Shared mailbox client

Reusable `CentralEmailApi`, `CentralSupportRepository` and
`CentralDispatchRepository` adapters for the standalone email operator and
embedded Flutter hosts. UI/contracts remain in `newsletter_studio_flutter`.

The default transport uses the host's existing HTTP session client and
`/api/admin/email`. Embedded hosts may inject a short-lived user bearer supplier
and a separately configured trusted server origin/API prefix. A supplier that
returns no session fails before network transmission. Tokens are supplied per
request, never persisted or logged. This client provides no issuer compatibility,
mailbox authority, project ownership or provider credentials; servers must verify
all of those boundaries.

The source lives in this repository. Hosts can compile local or cloud artifacts
from a reviewed sibling workspace. Reproducible CI must check out the exact
reviewed sources at the declared paths and record both repository identities.
No package publication is required; no unpublished Git revision is assumed to
be remotely available. Artifact compilation does not prove hosted activation.

## Product-update campaigns

`CentralCampaignBridgeApi` talks to the CommandGlows Firebase campaign bridge at
`/api/bridge/email-campaigns/firebase`. It reuses `CentralEmailApi`, so bearer
injection, the no-redirect rule, the 1 MiB response cap and Idempotency-Key
handling are the same. An identical uncertain command reuses its key; an edited
one gets a new key.

Operations: `context`, `listCampaigns`, `status`, `preview`, `create`, `revise`,
`snapshot`, `pause`, `cancel` and `delete`. Approval, challenge and resume are
never sent. The bridge answers them with `EmailApiException('console_required')`,
and the host sends the operator to `ProductUpdateContext.consoleUri`.

`CentralCampaignBridgeRepository` implements `NewsletterCampaignRepository` for
one business and audience, so `CampaignWorkspace` can list and create drafts. The
bridge has no state filter, so a status filter applies to the loaded page only.

`ProductUpdateDraft` checks the bridge's content rules in French before a
request: title 160, subject 200, preheader 300, no control characters and no
provider placeholder syntax. It splits Markdown on blank lines into `rich_text`
blocks of at most 20,000 characters, and refuses more than 60 blocks or more
than 48,000 characters of block JSON.

## Identity link

`IdentityLinkRepository` implements `IdentityLinkGateway` over the bridge
`identity/status`, `identity/link-code` and `identity/link-confirm` routes. It
validates each response strictly (schema version 1, fingerprint format, code
length 1 to 512, parseable expiry). Any invalid shape throws `EmailApiException`
with code `invalid_response`. Pasted codes are trimmed, and empty or oversized
codes are refused before any request. Requests use the same per-request user
bearer and idempotency handling as the other repositories.

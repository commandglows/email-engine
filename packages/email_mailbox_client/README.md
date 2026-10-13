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

## Identity link

`IdentityLinkRepository` implements `IdentityLinkGateway` over the bridge
`identity/status`, `identity/link-code` and `identity/link-confirm` routes. It
validates each response strictly (schema version 1, fingerprint format, code
length 1 to 512, parseable expiry). Any invalid shape throws `EmailApiException`
with code `invalid_response`. Pasted codes are trimmed, and empty or oversized
codes are refused before any request. Requests use the same per-request user
bearer and idempotency handling as the other repositories.

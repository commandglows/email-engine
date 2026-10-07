# newsletter_studio_flutter

A provider-neutral, keyboard-first Flutter workspace for turning selected
sources into a reviewable newsletter draft. The package owns composition,
source provenance, preview states, delivery review, adaptive layouts, and the
interaction contract. The host owns storage, authorization, audience consent,
HTML rendering, provider adapters, delivery, and analytics.

The component never stores provider credentials, downloads remote email HTML,
or sends a message by itself. Every external effect crosses a typed callback.

```dart
NewsletterStudio(
  draft: draft,
  availableSources: sources,
  audience: audienceSummary,
  sender: senderSummary,
  design: designSummary,
  capabilities: const NewsletterStudioCapabilities(
    canTest: true,
    canSchedule: true,
    canSend: true,
  ),
  onDraftChanged: updateLocalDraft,
  onSaveDraft: saveDraft,
  onResolveAudience: resolveEligibleAudience,
  onValidateDraft: validateOnServer,
  onCheckLinks: checkSavedRevisionLinks,
  onRenderPreview: renderProviderNeutralPreview,
  onSendTest: requestTestDelivery,
  onSchedule: requestSchedule,
  onSend: requestImmediateDelivery,
  onLoadDeliveryStatus: loadDeliveryStatus,
  onLoadAnalytics: loadAggregateAnalytics,
)
```

Consumers should pin an immutable Git commit:

```yaml
newsletter_studio_flutter:
  git:
    url: https://github.com/commandglows/email-sidebar-app.git
    ref: <commit-sha>
    path: packages/newsletter_studio_flutter
```

## Host boundary

The supplied `NewsletterDraft` is controlled host state. The package keeps an
optimistic working copy, reports every edit through `onDraftChanged`, and can
debounce `onSaveDraft`. Revision-aware test receipts become stale as soon as
the draft changes. Local checks are merged with authoritative host validation
before the review drawer opens.

Link checking is a separate operator-triggered hook. Review shows the external
request and possible bounded-GET side-effect disclosure before invoking
`onCheckLinks`; opening review never contacts destinations. The host returns a
typed, revision-bound report. The widget blocks approval on missing/stale or
incomplete reports and definite link errors, and requires a distinct explicit
override action for uncertain outcomes. Findings navigate by stable block ID
and focus the corresponding URL field. The host remains responsible for
server-side authorization and approval enforcement.

`onSchedule` and `onSend` are reachable only after review and a second explicit
confirmation. Keyboard commands can open review but never trigger either
delivery callback directly. The host must repeat authorization, consent,
sender, suppression, idempotency, and revision checks server-side.

Remote source content must be sanitized before it enters the models. Keep
recipient identities, credentials, unsubscribe records, raw tracking data, and
provider payloads out of this public presentation package.

## Keyboard contract

- `J` / `K` or arrow keys: navigate sources and reclaim row focus.
- `X`: attach or detach the selected source.
- Enter: open the selected source through the host callback.
- F6 / Shift+F6: move among source, editor, inspector, and action zones.
- Ctrl/Command+P: toggle preview.
- Ctrl/Command+Shift+T: request a test delivery.
- Ctrl/Command+Enter: open delivery review.
- Ctrl/Command+0: reset workspace zoom.
- Escape: close the current transient surface.
- `?`: show keyboard help.

Alphabetic commands are ignored while an editable control owns focus. Every
binding is replaceable or disableable through `NewsletterStudioShortcuts`.

## Styling and responsive behavior

Hosts map semantic colors and layout tokens through `NewsletterStudioStyle`.
The default experience uses three panes at expanded widths, source and
inspector rails at medium widths, and a bottom navigation on compact screens.
Ctrl/Command+mouse wheel scales the whole workspace while Flutter text scaling
continues to operate independently.

The in-app preview is intentionally marked approximate. Received-client HTML,
dark-mode behavior, remote-image policy, unsubscribe behavior, and
deliverability require separate backend and inbox proof.

## Campaign workspace

`CampaignWorkspace(repository: repository, onOpenCampaign: openCampaign)` lists
bounded pages of 25 campaigns, filters status, creates a named draft and delegates
opening to the host. Optional `businessLabel`, `onBack`, `canCreate` and
`disabledReason` support a scoped operator host. `NewsletterCampaignRepository`
contains only `list({cursor, status, limit})` and `create({required title})`.
The host must enforce these limits and business scope; presentation is not an
access-control boundary. Failed creation asks the operator to refresh before
retrying an outcome that may be ambiguous.

The studio accepts controlled `availableAudiences`, `onAudienceChanged` and
`onScheduleChanged`. The schedule picker converts local device time to an explicit
UTC instant. Supply `canEdit: false` for immutable campaigns, and disable send/test
capabilities when configuration is unavailable. Button blocks expose HTTPS links.

Autosave serializes writes, coalesces edits received during a write, and carries
the returned revision into the next snapshot. Return the authoritative revision
from `onSaveDraft`. Throw `NewsletterSaveConflict` for optimistic concurrency
failure; the UI retains edits and stops writes until a server reload. Other
failures retain the draft and show a generic recovery message. Test and review
wait for saved content. Every content change invalidates the local test receipt.
Host callbacks must still validate revisions, consent and idempotency server-side.

Labels are French, including campaign delivery states. Submitted and unknown are
separate from delivered and failed; provider acceptance is not inbox delivery.
The preview remains approximate and must not be described as email-client proof.

Validation: `flutter analyze` and `flutter test` from this package. Widget coverage
includes bounded paging, redacted failure recovery, narrow dark layouts with large
text, disabled creation, serialized saves, keyboard navigation and send review.
# Shared cockpit and service client

`EmailCockpit` owns navigation and lazily retains visited workspaces. Its builder
receives `EmailSection.sources`, `support` or `diffusion`. It keeps child state
through responsive reparenting; it does not fetch or authenticate providers.
`SupportWorkspace(repository:, onConnect:)` owns the conversation journey.
Hosts implement `SupportRepository`; never pass OAuth tokens to presentation.
Unknown reply outcomes block repeated sends; successful submission is not delivery.
Support models also carry optional sanitized HTML, attachment metadata, Cc and
server-derived reply-all eligibility/recipients. The authenticated operator owns
enriched rendering, authenticated downloads, file selection and confirmations;
the presentation models never accept provider credentials.
Support repositories also carry Gmail-confirmed `isUnread` and `isArchived`
state, a metadata mutation, and bounded incoming observability. Null provider
state remains unknown. Observability models keep window counts, sampled hashed
IDs, freshness, and redacted failure metadata distinct so the UI does not infer
totals from an incomplete sample.

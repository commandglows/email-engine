# ShipGlows Email Engine

The default interface is one shared email list and reader: **Sources** (Readwise Reader),
**Service client** (owned Gmail accounts with Mutant Mail relay routing), and
**Diffusion** (Postmark campaigns). The three groups appear in this order in one
scrolling list. A single sidebar jumps to each group; contextual reader actions
handle support replies and campaign editing. There is no separate overview.
The demo at `/` uses fictional data.
The authenticated `app` has server-backed adapters with explicit configuration
states. No provider connection or successful delivery is implied by the preview.

This public repository owns two native, provider-neutral Flutter presentation
packages for host applications: `source_sidebar_flutter` for
collecting and reading sources, and `newsletter_studio_flutter` for turning
selected sources into a reviewable newsletter draft. Neither package is a
WebView wrapper.

The newsletter package now includes a campaign workspace, version-aware editing,
audience selection, review, scheduling and delivery status. `app/` is the real
operator web application: it calls the same-origin, Clerk-protected CommandGlows
campaign API. The central backend retains ownership of audiences, consent,
suppression, frozen approval snapshots and Postmark delivery. See
[`app/README.md`](app/README.md) for the deployment boundary.

Select **Diffusion**, open a campaign in the shared reader, then open its editor.
The preview's sample campaigns and sending hooks remain explicitly
synthetic. Neither this preview nor passing tests proves hosted login or real
email receipt. Production activation and real recipient tests are separate.

The Flutter Web demo consumes both real packages with synthetic data and typed
simulated hooks. It contains no Readwise or delivery-provider token, performs
no network mutation, and cannot alter a real library or send an email.

The original v0/React prototype remains available in Git history as the initial
interaction reference; it is no longer an active application or deployment.

The shared visual grammar uses a 64 px global header, Gmail-like navigation,
dense desktop information layouts, compact mobile navigation, visible keyboard
focus, semantic categories, and restrained blue focus and selection states.

## Visual proof

The source proof images below were generated from the real Flutter preview with
only synthetic sources. Newsletter Studio visual proof still requires an
authorized hosted preview after CI; the implementation must not be represented
as inbox-rendering or deliverability proof.

![Desktop source list](shipglows_data/visual-proof/desktop-list.png)

![Mobile reader](shipglows_data/visual-proof/mobile-reader.png)

## Repository layout

- `packages/source_sidebar_flutter`: reusable Flutter presentation package.
- `packages/newsletter_studio_flutter`: reusable newsletter composition and
  review package with provider-neutral host hooks.
- `demo`: unified Flutter Web preview consuming both packages by local path.
- `app`: same-origin authenticated newsletter operator; no provider credentials.
- `scripts/install-operator-web.ps1`: install an already-built operator artifact
  into a validated local CommandGlows site checkout without deploying it.
- `scripts/vercel-build.sh`: reproducible Vercel build with Flutter 3.41.7.
- `shipglows_data/visual-proof`: inspected desktop and mobile reference
  captures for the current Flutter implementation.

## Run the preview locally

```bash
cd demo
flutter pub get
s start -ProjectPath <absolute-path-to-demo> -FlutterDevice web-server
```

## Validate

```bash
cd packages/source_sidebar_flutter
flutter analyze
flutter test

cd ../newsletter_studio_flutter
flutter analyze
flutter test

cd ../../demo
flutter analyze
flutter test
flutter build web --release

cd ../app
flutter pub get
flutter analyze
flutter test
flutter build web --release --base-href /email-engine/
```

Licensed under the MIT License.

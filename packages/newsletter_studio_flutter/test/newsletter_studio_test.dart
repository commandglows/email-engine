import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';

void main() {
  void useExpandedViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  final source = NewsletterSourceReference(
    id: 'source-one',
    title: 'A useful source',
    publisher: 'Synthetic publisher',
    excerpt: 'A sanitized excerpt.',
    canonicalUrl: Uri.https('example.test', '/source'),
  );

  NewsletterDraft draft({List<NewsletterSourceReference> sources = const []}) {
    return NewsletterDraft(
      id: 'draft-one',
      revision: 3,
      title: 'Weekly draft',
      subject: 'A useful subject',
      preheader: 'A useful preheader',
      sources: sources,
      blocks: const [
        NewsletterBlock(
          id: 'opening',
          type: NewsletterBlockType.text,
          text: 'Draft body.',
        ),
      ],
    );
  }

  testWidgets('J reclaims source focus and X attaches the selected source', (
    tester,
  ) async {
    useExpandedViewport(tester);
    NewsletterDraft? changed;
    await tester.pumpWidget(
      _Harness(
        draft: draft(),
        sources: [source],
        onDraftChanged: (value) => changed = value,
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    final previousFocus = FocusManager.instance.primaryFocus;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();

    final row = tester.widget<InkWell>(
      find
          .ancestor(
            of: find.text('A useful source'),
            matching: find.byType(InkWell),
          )
          .first,
    );
    expect(row.focusNode?.hasPrimaryFocus, isTrue);
    expect(FocusManager.instance.primaryFocus, isNot(same(previousFocus)));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pump();
    expect(changed?.sources.single.id, 'source-one');
  });

  testWidgets('send requires review and explicit confirmation', (tester) async {
    useExpandedViewport(tester);
    var sent = false;
    await tester.pumpWidget(
      _Harness(
        draft: draft(),
        sources: [source],
        audience: const NewsletterAudienceSummary(
          id: 'audience',
          label: 'Eligible readers',
          eligibleCount: 12,
        ),
        sender: const NewsletterSenderSummary(
          name: 'Verified sender',
          address: 'sender@example.test',
          replyTo: 'reply@example.test',
          isVerified: true,
        ),
        capabilities: const NewsletterStudioCapabilities(canSend: true),
        onSend: (value) async {
          sent = true;
          return NewsletterOperationReceipt(
            operationId: 'send-one',
            draftRevision: value.revision,
            message: 'Accepted.',
          );
        },
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Vérifier'), findsWidgets);
    expect(sent, isFalse);

    await tester.drag(find.byType(Slider), const Offset(1000, 0));
    await tester.pumpAndSettle();
    expect(find.text('Envoyer cette newsletter maintenant ?'), findsOneWidget);
    expect(sent, isFalse);

    await tester.tap(find.text('Confirmer l’envoi'));
    await tester.pumpAndSettle();
    expect(sent, isTrue);
  });

  testWidgets('accessible send action confirms once and ignores a duplicate', (
    tester,
  ) async {
    useExpandedViewport(tester);
    var sendCount = 0;
    await tester.pumpWidget(
      _Harness(
        draft: draft(),
        sources: const [],
        audience: const NewsletterAudienceSummary(
          id: 'audience',
          label: 'Eligible readers',
          eligibleCount: 4,
        ),
        sender: const NewsletterSenderSummary(
          name: 'Verified sender',
          address: 'sender@example.test',
          replyTo: 'reply@example.test',
          isVerified: true,
        ),
        capabilities: const NewsletterStudioCapabilities(canSend: true),
        onSend: (value) async {
          sendCount++;
          return NewsletterOperationReceipt(
            operationId: 'send-once',
            draftRevision: value.revision,
            message: 'Accepted.',
          );
        },
      ),
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    const accessibleSend =
        'Envoyer maintenant au clavier ou avec un lecteur d’écran';
    await tester.tap(find.text(accessibleSend));
    await tester.pumpAndSettle();
    expect(sendCount, 0);
    await tester.tap(find.text('Confirmer l’envoi'));
    await tester.pumpAndSettle();
    expect(sendCount, 1);
  });

  testWidgets('Ctrl+wheel zooms the complete studio and Ctrl+0 resets it', (
    tester,
  ) async {
    useExpandedViewport(tester);
    await tester.pumpWidget(_Harness(draft: draft(), sources: [source]));
    await tester.pump();

    double workspaceScale() {
      final viewport = tester.getSize(
        find.byKey(const ValueKey('newsletter-studio-zoom')),
      );
      final content = tester.getSize(
        find.byKey(const ValueKey('newsletter-studio-zoom-content')),
      );
      return viewport.width / content.width;
    }

    expect(workspaceScale(), 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(600, 400),
        scrollDelta: Offset(0, -100),
      ),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(workspaceScale(), greaterThan(1));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(workspaceScale(), 1);
  });

  testWidgets('link finding opens its stable block and focuses the URL field', (
    tester,
  ) async {
    useExpandedViewport(tester);
    final linkDraft = draft().copyWith(
      blocks: const [
        NewsletterBlock(
          id: 'cta-stable-id',
          type: NewsletterBlockType.button,
          text: 'Read more',
          label: 'Read more',
          rawUrl: '',
        ),
      ],
    );
    final report = NewsletterLinkCheckReport(
      id: 'link-report-one',
      campaignId: linkDraft.id,
      revision: linkDraft.revision,
      serverRevision: linkDraft.revision,
      destinationDigest: 'digest-one',
      checkedAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      status: NewsletterLinkReportStatus.blocked,
      blockingCount: 1,
      uncertainCount: 0,
      validCount: 0,
      findings: const [
        NewsletterLinkFinding(
          blockIds: ['cta-stable-id'],
          host: '',
          status: NewsletterLinkFindingStatus.staticBlocker,
          reason: 'missing_url',
        ),
      ],
      disclosure: const NewsletterLinkCheckDisclosure(
        externalRequests: true,
        possibleDestinationSideEffect: true,
        methodPolicy: 'HEAD then bounded GET fallback',
      ),
    );
    var approved = false;
    await tester.pumpWidget(
      _Harness(
        draft: linkDraft,
        sources: const [],
        linkReport: report,
        onCheckLinks: (_) async => report,
        capabilities: const NewsletterStudioCapabilities(canSend: true),
        onSendWithLinkReport:
            (draft, report, {required overrideUncertain}) async {
              approved = true;
              return NewsletterOperationReceipt(
                operationId: 'unused',
                draftRevision: draft.revision,
                message: 'unused',
              );
            },
      ),
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('1 lien(s) à corriger'), findsOneWidget);
    final sendButton = tester.widget<FilledButton>(
      find
          .ancestor(
            of: find.text('Envoyer maintenant'),
            matching: find.byType(FilledButton),
          )
          .first,
    );
    expect(sendButton.onPressed, isNull);
    expect(approved, isFalse);
    await tester.tap(find.text('1 destinations contrôlées'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Corriger le lien · cta-stable-id'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Corriger le lien · cta-stable-id'));
    await tester.pumpAndSettle();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Newsletter link cta-stable-id',
    );
  });

  testWidgets('uncertain result needs the explicit override action', (
    tester,
  ) async {
    useExpandedViewport(tester);
    final currentDraft = draft().copyWith(
      blocks: [
        NewsletterBlock(
          id: 'button-one',
          type: NewsletterBlockType.button,
          text: 'Read',
          label: 'Read',
          url: Uri(scheme: 'https', host: 'links.example.test'),
        ),
      ],
    );
    final report = NewsletterLinkCheckReport(
      id: 'link-report-uncertain',
      campaignId: currentDraft.id,
      revision: currentDraft.revision,
      serverRevision: currentDraft.revision,
      destinationDigest: 'digest-uncertain',
      checkedAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      status: NewsletterLinkReportStatus.uncertain,
      blockingCount: 0,
      uncertainCount: 1,
      validCount: 0,
      findings: const [
        NewsletterLinkFinding(
          blockIds: ['button-one'],
          host: 'links.example.test',
          status: NewsletterLinkFindingStatus.uncertain,
          reason: 'timeout',
        ),
      ],
      disclosure: const NewsletterLinkCheckDisclosure(
        externalRequests: true,
        possibleDestinationSideEffect: true,
        methodPolicy: 'HEAD then bounded GET fallback',
      ),
    );
    var overrideUsed = false;
    await tester.pumpWidget(
      _Harness(
        draft: currentDraft,
        sources: const [],
        audience: const NewsletterAudienceSummary(
          id: 'audience',
          label: 'Eligible readers',
          eligibleCount: 10,
        ),
        sender: const NewsletterSenderSummary(
          name: 'Verified sender',
          address: 'sender@example.test',
          replyTo: 'reply@example.test',
          isVerified: true,
        ),
        linkReport: report,
        onCheckLinks: (_) async => report,
        capabilities: const NewsletterStudioCapabilities(canSend: true),
        onSendWithLinkReport:
            (draft, report, {required overrideUncertain}) async {
              overrideUsed = overrideUncertain;
              return NewsletterOperationReceipt(
                operationId: 'approval',
                draftRevision: draft.revision,
                message: 'Requested.',
              );
            },
      ),
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    final normalSend = tester.widget<FilledButton>(
      find
          .ancestor(
            of: find.text('Envoyer maintenant'),
            matching: find.byType(FilledButton),
          )
          .first,
    );
    expect(normalSend.onPressed, isNull);
    const accessibleOverride =
        'Déroger et envoyer au clavier ou avec un lecteur d’écran';
    expect(find.text(accessibleOverride), findsOneWidget);
    await tester.tap(find.text(accessibleOverride));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Déroger et envoyer'),
      ),
    );
    await tester.pumpAndSettle();
    expect(overrideUsed, isTrue);
  });
}

class _Harness extends StatelessWidget {
  const _Harness({
    required this.draft,
    required this.sources,
    this.onDraftChanged,
    this.audience,
    this.sender,
    this.capabilities = const NewsletterStudioCapabilities(),
    this.onSend,
    this.linkReport,
    this.onCheckLinks,
    this.onSendWithLinkReport,
  });

  final NewsletterDraft draft;
  final List<NewsletterSourceReference> sources;
  final ValueChanged<NewsletterDraft>? onDraftChanged;
  final NewsletterAudienceSummary? audience;
  final NewsletterSenderSummary? sender;
  final NewsletterStudioCapabilities capabilities;
  final NewsletterSender? onSend;
  final NewsletterLinkCheckReport? linkReport;
  final NewsletterLinkChecker? onCheckLinks;
  final NewsletterLinkReportSender? onSendWithLinkReport;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: SizedBox(
        width: 1280,
        height: 900,
        child: NewsletterStudio(
          draft: draft,
          availableSources: sources,
          audience: audience,
          sender: sender,
          capabilities: capabilities,
          linkReport: linkReport,
          onCheckLinks: onCheckLinks,
          onSendWithLinkReport: onSendWithLinkReport,
          onDraftChanged: onDraftChanged ?? (_) {},
          onSend: onSend,
        ),
      ),
    );
  }
}

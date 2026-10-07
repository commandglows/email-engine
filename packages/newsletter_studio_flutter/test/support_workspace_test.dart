import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newsletter_studio_flutter/src/support_models.dart';
import 'package:newsletter_studio_flutter/src/support_workspace.dart';

class FakeSupportRepository implements SupportRepository {
  bool configured = true, connected = true, failReply = false;
  SupportReplyResult result = SupportReplyResult.submitted;
  int sends = 0;
  String? sentBody;
  SupportStatus status = SupportStatus.pending;
  bool isUnread = true, isArchived = false;
  @override
  Future<SupportContext> context() async => SupportContext(
    configured: configured,
    canReply: true,
    mailboxes: [
      SupportMailbox(
        id: 'own',
        email: 'moi@example.test',
        connected: connected,
        canModify: true,
      ),
    ],
  );
  @override
  Future<Uri> connect(String mailboxId) async =>
      Uri.parse('https://accounts.google.com/o/oauth2/v2/auth');
  @override
  Future<Uri> addMailbox({String? returnOrigin}) async =>
      Uri.parse('https://accounts.google.com/o/oauth2/v2/auth');
  @override
  Future<void> trashThread(
    String mailboxId,
    String threadId, {
    required String expectedMessageId,
  }) async {}
  @override
  Future<SupportPage> threads(String mailboxId, {String? cursor}) async =>
      SupportPage(
        items: [
          SupportThreadSummary(
            id: 't1',
            subject: 'Besoin d’aide',
            from: 'Camille',
            snippet: 'Mon accès',
            status: status,
            isUnread: isUnread,
            isArchived: isArchived,
          ),
        ],
      );
  @override
  Future<SupportThread> thread(String mailboxId, String threadId) async =>
      SupportThread(
        id: 't1',
        subject: 'Besoin d’aide',
        status: status,
        latestMessageId: 'm1',
        canReply: true,
        isUnread: isUnread,
        isArchived: isArchived,
        replyTo: 'relay@exemple.test',
        messages: const [
          SupportMessage(
            id: 'm1',
            from: 'Camille',
            to: 'support@exemple.test',
            text: '<script>Texte affiché sans HTML</script>',
          ),
        ],
      );
  @override
  Future<void> setStatus(
    String mailboxId,
    String threadId,
    SupportStatus value,
  ) async {
    status = value;
  }

  @override
  Future<SupportThread> setGmailMetadata(
    String mailboxId,
    String threadId, {
    required String expectedMessageId,
    required bool isUnread,
    required bool isArchived,
  }) async {
    this.isUnread = isUnread;
    this.isArchived = isArchived;
    return thread(mailboxId, threadId);
  }

  @override
  Future<SupportObservability> observability(
    String mailboxId,
    String window,
  ) async => const SupportObservability(
    coverage: 'partial',
    source: 'operator_mailbox_paging',
    window: '24h',
    observedCount: 0,
    sampledCount: 0,
    sampleLimit: 50,
    sampleTruncated: false,
    countsByState: {},
    stateCountsAvailable: true,
    lastObservedAt: null,
    oldestSampleAt: null,
    sample: [],
    sampleAvailable: true,
    failures: [],
    failuresAvailable: true,
  );

  @override
  Future<SupportReplyResult> reply(
    String mailboxId,
    String threadId, {
    required String body,
    required String expectedMessageId,
  }) async {
    sends++;
    sentBody = body;
    if (failReply) throw const SupportException('Envoi refusé.');
    return result;
  }
}

Future<void> openThread(WidgetTester tester, FakeSupportRepository repo) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SupportWorkspace(repository: repo)),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Besoin d’aide'));
  await tester.pumpAndSettle();
}

Future<void> compose(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.widgetWithText(TextField, 'Votre réponse'),
    240,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey('support-detail-scroll')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'Votre réponse'),
    'Bonjour Camille, voici votre accès.',
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Relire et envoyer'));
  await tester.tap(find.text('Relire et envoyer'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('OAuth connects only the selected allowed mailbox', (
    tester,
  ) async {
    final repo = FakeSupportRepository()..connected = false;
    Uri? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SupportWorkspace(
            repository: repo,
            onConnect: (uri) async {
              opened = uri;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connecter Gmail'));
    await tester.pumpAndSettle();
    expect(opened?.host, 'accounts.google.com');
    expect(
      find.text('Terminez la connexion Google, puis actualisez les boîtes.'),
      findsOneWidget,
    );
    expect(repo.sends, 0);
  });
  testWidgets('narrow dark support list fits with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: SupportWorkspace(
              repository: FakeSupportRepository(),
              userMailboxMode: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Service client'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('unconfigured context is honest and does not offer send', (
    tester,
  ) async {
    final repo = FakeSupportRepository()..configured = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SupportWorkspace(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Gmail reste à connecter'), findsOneWidget);
    expect(find.text('Relire et envoyer'), findsNothing);
  });
  testWidgets('known reply failure preserves draft and allows explicit retry', (
    tester,
  ) async {
    final repo = FakeSupportRepository()..failReply = true;
    await openThread(tester, repo);
    await compose(tester);
    expect(repo.sends, 0);
    await tester.tap(find.text('Confirmer l’envoi'));
    await tester.pumpAndSettle();
    expect(repo.sends, 1);
    expect(find.text('Envoi refusé.'), findsOneWidget);
    expect(find.text('Bonjour Camille, voici votre accès.'), findsOneWidget);
    final send = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Relire et envoyer'),
    );
    expect(send.onPressed, isNotNull);
  });
  testWidgets('unknown reply blocks repeat and preserves draft', (
    tester,
  ) async {
    final repo = FakeSupportRepository()..result = SupportReplyResult.unknown;
    await openThread(tester, repo);
    await compose(tester);
    await tester.tap(find.text('Confirmer l’envoi'));
    await tester.pumpAndSettle();
    expect(repo.sends, 1);
    expect(find.text('Bonjour Camille, voici votre accès.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Relire et envoyer'),
      150,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('support-detail-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Relire et envoyer'),
          )
          .onPressed,
      isNull,
    );
  });
  testWidgets('mobile detail returns to conversations and retains draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeSupportRepository();
    await openThread(tester, repo);
    await tester.scrollUntilVisible(
      find.widgetWithText(TextField, 'Votre réponse'),
      240,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('support-detail-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Votre réponse'),
      'Brouillon mobile',
    );
    await tester.scrollUntilVisible(
      find.text('Conversations'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Conversations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Besoin d’aide'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(TextField, 'Votre réponse'),
      240,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('support-detail-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Brouillon mobile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';

class _ReadOnlyFixture implements SupportRepository {
  int observabilityCalls = 0;
  @override
  Future<SupportContext> context() async => const SupportContext(
    configured: true,
    canReply: true,
    mailboxes: [
      SupportMailbox(
        id: 'synthetic-box',
        email: 'synthetic@example.test',
        connected: true,
        canModify: true,
      ),
    ],
  );
  @override
  Future<SupportPage> threads(String mailboxId, {String? cursor}) async =>
      const SupportPage(
        items: [
          SupportThreadSummary(
            id: 'synthetic-thread',
            subject: 'Synthetic subject',
            from: 'Synthetic sender',
            snippet: 'Synthetic',
            status: SupportStatus.pending,
          ),
        ],
      );
  @override
  Future<SupportThread> thread(String mailboxId, String threadId) async =>
      const SupportThread(
        id: 'synthetic-thread',
        subject: 'Synthetic subject',
        status: SupportStatus.pending,
        latestMessageId: 'synthetic-message',
        canReply: true,
        isUnread: true,
        isArchived: false,
        messages: [
          SupportMessage(
            id: 'synthetic-message',
            from: 'synthetic@example.test',
            to: 'operator@example.test',
            text: 'Synthetic email only',
          ),
        ],
      );
  @override
  Future<SupportObservability> observability(String mailboxId, String window) {
    observabilityCalls++;
    throw StateError('Not admitted by reader bridge');
  }

  @override
  Future<Uri> connect(String mailboxId) async =>
      throw StateError('No OAuth action');
  @override
  Future<Uri> addMailbox({String? returnOrigin}) async =>
      throw StateError('No OAuth action');
  @override
  Future<void> trashThread(
    String mailboxId,
    String threadId, {
    required String expectedMessageId,
  }) async => throw StateError('No modify action');
  @override
  Future<void> setStatus(
    String mailboxId,
    String threadId,
    SupportStatus status,
  ) async => throw StateError('No status action');
  @override
  Future<SupportThread> setGmailMetadata(
    String mailboxId,
    String threadId, {
    required String expectedMessageId,
    required bool isUnread,
    required bool isArchived,
  }) async => throw StateError('No Gmail action');
  @override
  Future<SupportReplyResult> reply(
    String mailboxId,
    String threadId, {
    required String body,
    required String expectedMessageId,
  }) async => throw StateError('No reply');
}

void main() {
  testWidgets(
    'embedded reader hides mutations even if backend reports reply and modify capabilities',
    (tester) async {
      final repository = _ReadOnlyFixture();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SupportWorkspace(
              repository: repository,
              mailboxReadOnly: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.observabilityCalls, 0);
      await tester.tap(find.text('Synthetic subject'));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic email only'), findsOneWidget);
      expect(find.text('Relire et envoyer'), findsNothing);
      expect(find.text('Archiver dans Gmail'), findsNothing);
      expect(find.text('Marquer comme lu'), findsNothing);
      expect(find.text('Connecter Gmail'), findsNothing);
      for (final chip in tester.widgetList<ChoiceChip>(
        find.byType(ChoiceChip),
      )) {
        expect(chip.onSelected, isNull);
      }
      expect(tester.takeException(), isNull);
    },
  );
}

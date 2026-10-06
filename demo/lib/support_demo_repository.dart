import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';

/// In-memory fictional data. Never connects to Gmail or submits an email.
class DemoSupportRepository implements SupportRepository {
  final Map<String, SupportStatus> _statuses = {};
  static const _subjects = [
    'Accès à mon espace ContentGlows',
    'Retrouver une facture',
    'Une idée pour le prochain atelier',
  ];
  @override
  Future<SupportContext> context() async => const SupportContext(
    configured: true,
    canReply: false,
    mailboxes: [
      SupportMailbox(
        id: 'demo',
        email: 'support@exemple.test · Démonstration',
        connected: true,
      ),
    ],
  );
  @override
  Future<Uri> connect(String mailboxId) async => throw const SupportException(
    'Cette démonstration ne connecte aucune boîte Gmail.',
  );
  @override
  Future<SupportPage> threads(String mailboxId, {String? cursor}) async =>
      SupportPage(
        items: List.generate(
          3,
          (i) => SupportThreadSummary(
            id: '$i',
            subject: _subjects[i],
            from: ['Camille', 'Alex', 'Lou'][i],
            snippet: [
              'Bonjour, comment retrouver mon espace ?',
              'Merci pour votre aide avec la facture.',
              'Pourrait-on parler de création de contenu ?',
            ][i],
            status: _statuses['$i'] ?? SupportStatus.values[i],
            updatedAt: DateTime(2026, 9, 8, 10 - i),
          ),
        ),
      );
  @override
  Future<SupportThread> thread(String mailboxId, String threadId) async {
    final item = (await threads(
      mailboxId,
    )).items.firstWhere((t) => t.id == threadId);
    return SupportThread(
      id: item.id,
      subject: item.subject,
      status: item.status,
      latestMessageId: 'demo-$threadId',
      canReply: false,
      replyDisabledReason: 'synthetic_demo',
      replyTo: 'relais-exemple@exemple.test',
      messages: [
        SupportMessage(
          id: 'demo-$threadId',
          from: '${item.from} <client@exemple.test>',
          to: 'support@exemple.test',
          text:
              '${item.snippet}\n\nCette conversation est fictive. Aucun compte Gmail n’est connecté.',
          date: item.updatedAt,
        ),
      ],
    );
  }

  @override
  Future<void> setStatus(
    String mailboxId,
    String threadId,
    SupportStatus status,
  ) async {
    _statuses[threadId] = status;
  }

  @override
  Future<SupportReplyResult> reply(
    String mailboxId,
    String threadId, {
    required String body,
    required String expectedMessageId,
  }) async => throw const SupportException(
    'La démonstration ne peut pas envoyer de réponse.',
  );
}

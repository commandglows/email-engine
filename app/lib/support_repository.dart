import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';
import 'central_email_api.dart';

class CentralSupportRepository implements SupportRepository {
  CentralSupportRepository(this.api);
  final CentralEmailApi api;

  Future<T> _guard<T>(
    Future<T> Function() action, {
    bool sending = false,
  }) async {
    try {
      return await action();
    } on EmailApiException catch (error) {
      final unknown =
          sending &&
          !const {
            'auth_required',
            'forbidden',
            'admin_required',
            'mailbox_not_connected',
            'gmail_reconnect_required',
            'configuration_unavailable',
            'support_not_configured',
            'rate_limited',
            'version_conflict',
            'stale_thread',
            'conflict',
            'reply_not_allowed',
            'reply_disabled',
            'invalid_input',
            'thread_changed',
            'relay_not_verified',
            'reconnect_required',
            'mailbox_not_allowed',
            'consent_incomplete',
            'thread_too_large',
          }.contains(error.code);
      throw SupportException(switch (error.code) {
        'auth_required' =>
          'Votre session a expiré. Reconnectez-vous à CommandGlows.',
        'forbidden' ||
        'admin_required' ||
        'mailbox_not_allowed' => 'Votre compte n’a pas accès à cette boîte.',
        'mailbox_not_connected' ||
        'gmail_reconnect_required' ||
        'reconnect_required' =>
          'Reconnectez cette boîte Gmail, puis actualisez les conversations.',
        'configuration_unavailable' || 'support_not_configured' =>
          'La connexion Gmail doit être configurée sur le serveur.',
        'rate_limited' =>
          'Trop de demandes rapprochées. Patientez avant de réessayer.',
        'version_conflict' ||
        'stale_thread' ||
        'conflict' ||
        'thread_changed' =>
          'La conversation a changé. Actualisez-la avant de répondre.',
        'reply_not_allowed' || 'reply_disabled' =>
          'Les réponses sont désactivées pour cette conversation.',
        'invalid_input' => 'Vérifiez le contenu de la réponse.',
        'relay_not_verified' =>
          'Le routage de cette adresse doit être vérifié avant de répondre.',
        'consent_incomplete' =>
          'La connexion Google nécessite les autorisations de lecture et de réponse.',
        'thread_too_large' =>
          'Cette conversation dépasse la limite de lecture du cockpit. Ouvrez-la dans Gmail.',
        'reply_already_attempted' =>
          'Une réponse a déjà été tentée. Vérifiez cette conversation dans Gmail.',
        _ =>
          unknown
              ? 'Résultat incertain. Vérifiez les messages envoyés dans Gmail. Aucun nouvel envoi automatique.'
              : 'Le service client est momentanément indisponible. Votre brouillon reste conservé.',
      }, outcomeUnknown: unknown);
    } catch (_) {
      throw SupportException(
        sending
            ? 'Résultat incertain. Vérifiez les messages envoyés dans Gmail.'
            : 'La réponse du service client est invalide. Réessayez plus tard.',
        outcomeUnknown: sending,
      );
    }
  }

  @override
  Future<SupportContext> context() => _guard(() async {
    final data = await api.get('support/context');
    return SupportContext(
      configured: data['configured'] == true,
      canReply: data['can_reply'] == true,
      disabledReason: data['disabled_reason'] as String?,
      mailboxes: (data['mailboxes'] as List)
          .map(
            (m) => SupportMailbox(
              id: m['id'] as String,
              email: m['email'] as String,
              connected: m['connected'] == true,
            ),
          )
          .toList(),
    );
  });
  @override
  Future<Uri> connect(String mailboxId) => _guard(() async {
    final data = await api.post('support/oauth/start', {
      'mailbox_id': mailboxId,
    });
    final uri = Uri.parse(data['authorization_url'] as String);
    if (uri.scheme != 'https' ||
        uri.host != 'accounts.google.com' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const FormatException();
    }
    return uri;
  });
  SupportStatus _status(dynamic value) =>
      SupportStatus.values.firstWhere((s) => s.name == value);
  @override
  Future<SupportPage> threads(String mailboxId, {String? cursor}) =>
      _guard(() async {
        final data = await api.get('support/threads', {
          'mailbox_id': mailboxId,
          'cursor': ?cursor,
        });
        return SupportPage(
          nextCursor: data['next_cursor'] as String?,
          items: (data['threads'] as List)
              .map(
                (t) => SupportThreadSummary(
                  id: t['id'] as String,
                  subject: t['subject'] as String? ?? '',
                  from: t['from'] as String? ?? '',
                  snippet: t['snippet'] as String? ?? '',
                  status: _status(t['status']),
                  updatedAt: DateTime.tryParse('${t['updated_at']}'),
                ),
              )
              .toList(),
        );
      });
  @override
  Future<SupportThread> thread(String mailboxId, String threadId) =>
      _guard(() async {
        final data = await api.get('support/threads/$threadId', {
          'mailbox_id': mailboxId,
        });
        final t = data['thread'] as Map;
        return SupportThread(
          id: t['id'] as String,
          subject: t['subject'] as String? ?? '',
          status: _status(t['status']),
          latestMessageId: t['latest_message_id'] as String,
          canReply: t['can_reply'] == true,
          replyTo: t['reply_to'] as String?,
          replyDisabledReason: t['reply_disabled_reason'] as String?,
          messages: (t['messages'] as List)
              .map(
                (m) => SupportMessage(
                  id: m['id'] as String,
                  from: m['from'] as String? ?? '',
                  to: m['to'] is List
                      ? (m['to'] as List).join(', ')
                      : m['to'] as String? ?? '',
                  text: m['text'] as String? ?? '',
                  date: DateTime.tryParse('${m['date']}'),
                ),
              )
              .toList(),
        );
      });
  @override
  Future<void> setStatus(
    String mailboxId,
    String threadId,
    SupportStatus status,
  ) => _guard(() async {
    await api.post('support/threads/$threadId/status', {
      'mailbox_id': mailboxId,
      'status': status.name,
    });
  });
  @override
  Future<SupportReplyResult> reply(
    String mailboxId,
    String threadId, {
    required String body,
    required String expectedMessageId,
  }) => _guard(() async {
    final data = await api.post('support/threads/$threadId/reply', {
      'mailbox_id': mailboxId,
      'body': body,
      'expected_message_id': expectedMessageId,
      'confirmed': true,
    });
    return switch (data['state']) {
      'submitted' => SupportReplyResult.submitted,
      'unknown' => SupportReplyResult.unknown,
      _ => throw const FormatException(),
    };
  }, sending: true);
}

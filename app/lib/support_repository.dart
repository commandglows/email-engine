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
  @override
  Future<Uri> addMailbox({String? returnOrigin}) => _guard(() async {
    final data = await api.post('connections/start', {
      if (returnOrigin != null && returnOrigin.trim().isNotEmpty)
        'return_origin': returnOrigin.trim(),
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
  @override
  Future<void> trashThread(
    String mailboxId,
    String threadId, {
    required String expectedMessageId,
  }) => _guard(() async {
    final data = await api.post('support/threads/$threadId/trash', {
      'mailbox_id': mailboxId,
      'expected_message_id': expectedMessageId,
      'confirmed': true,
    });
    if (data['state'] != 'trashed' || data['thread_id'] != threadId) {
      throw const FormatException();
    }
  }, sending: true);

  SupportStatus _status(dynamic value) =>
      SupportStatus.values.firstWhere((s) => s.name == value);
  DateTime? _date(dynamic value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    }
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

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
                  isUnread: t['is_unread'] is bool
                      ? t['is_unread'] as bool
                      : null,
                  isArchived: t['is_archived'] is bool
                      ? t['is_archived'] as bool
                      : null,
                ),
              )
              .toList(),
        );
      });
  @override
  Future<SupportThread> thread(String mailboxId, String threadId) => _guard(
    () async {
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
        isUnread: t['is_unread'] is bool ? t['is_unread'] as bool : null,
        isArchived: t['is_archived'] is bool ? t['is_archived'] as bool : null,
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
    },
  );
  @override
  Future<SupportThread> setGmailMetadata(
    String mailboxId,
    String threadId, {
    required String expectedMessageId,
    required bool isUnread,
    required bool isArchived,
  }) => _guard(() async {
    final data = await api.post('support/threads/$threadId/metadata', {
      'mailbox_id': mailboxId,
      'expected_message_id': expectedMessageId,
      'is_unread': isUnread,
      'is_archived': isArchived,
    });
    final confirmed = data['thread'] as Map;
    if (confirmed['id'] != threadId ||
        confirmed['latest_message_id'] != expectedMessageId ||
        confirmed['is_unread'] != isUnread ||
        confirmed['is_archived'] != isArchived) {
      throw const FormatException();
    }
    final refreshed = await thread(mailboxId, threadId);
    if (refreshed.latestMessageId != expectedMessageId ||
        refreshed.isUnread != isUnread ||
        refreshed.isArchived != isArchived) {
      throw const FormatException();
    }
    return refreshed;
  });

  @override
  Future<SupportObservability> observability(String mailboxId, String window) =>
      _guard(() async {
        final data = await api.get('support/observability', {
          'mailbox_id': mailboxId,
          'window_hours': switch (window) {
            '24h' => '24',
            '7d' => '168',
            '30d' => '720',
            '90d' => '2160',
            _ => '24',
          },
        });
        final counts = data['counts'] as Map?;
        final byState = counts?['by_state'] as Map?;
        final freshness = data['freshness'] as Map?;
        return SupportObservability(
          coverage: data['coverage'] as String? ?? 'unknown',
          source: data['source'] as String? ?? 'unknown',
          window: window,
          observedCount: counts?['observed_in_window'] is num
              ? (counts!['observed_in_window'] as num).toInt()
              : null,
          sampledCount: counts?['sampled_count'] is num
              ? (counts!['sampled_count'] as num).toInt()
              : null,
          sampleLimit: counts?['sample_limit'] is num
              ? (counts!['sample_limit'] as num).toInt()
              : null,
          sampleTruncated: counts?['truncated'] is bool
              ? counts!['truncated'] as bool
              : null,
          countsByState: byState == null
              ? const {}
              : byState.map(
                  (key, value) => MapEntry(
                    key.toString(),
                    value is num ? value.toInt() : null,
                  ),
                ),
          stateCountsAvailable: byState != null,
          lastObservedAt: _date(freshness?['last_observed_at']),
          oldestSampleAt: _date(freshness?['oldest_sample_at']),
          sample: ((data['sample'] as List?) ?? const [])
              .map(
                (item) => SupportObservation(
                  messageIdHash: item['message_id_hash'] as String? ?? '',
                  observedAt: _date(item['observed_at']),
                  state: item['state'] as String? ?? 'unknown',
                ),
              )
              .toList(),
          sampleAvailable: data['sample'] is List,
          failures: ((data['failures'] as List?) ?? const [])
              .map(
                (item) => SupportOperationalFailure(
                  stage: item['stage'] as String? ?? 'unknown',
                  code: item['code'] as String? ?? 'unknown',
                  count: item['count'] is num
                      ? (item['count'] as num).toInt()
                      : null,
                  firstAt: _date(item['first_at']),
                  lastAt: _date(item['last_at']),
                  retryable: item['retryable'] is bool
                      ? item['retryable'] as bool
                      : null,
                ),
              )
              .toList(),
          failuresAvailable: data['failures'] is List,
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

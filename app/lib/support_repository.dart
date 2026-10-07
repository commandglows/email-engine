import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';
import 'central_email_api.dart';
import 'dart:convert';
import 'dart:typed_data';

/// Provider filenames are display data, never filesystem paths.
String safeDownloadName(String name) {
  var safe = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'[. ]+$'), '')
      .trim();
  if (safe.isEmpty || safe == '.' || safe == '..') {
    safe = 'piece-jointe';
  }
  if (RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
    caseSensitive: false,
  ).hasMatch(safe)) {
    safe = 'piece-jointe_$safe';
  }
  return safe.length > 200 ? safe.substring(0, 200) : safe;
}

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
            'invalid_request',
            'invalid_attachments',
            'attachments_too_large',
            'reply_all_unverified_recipients',
            'modify_scope_required',
            'metadata_update_failed',
          }.contains(error.code);
      throw SupportException(
        switch (error.code) {
          'auth_required' =>
            'Votre session a expiré. Reconnectez-vous à CommandGlows.',
          'forbidden' ||
          'admin_required' ||
          'mailbox_not_allowed' => 'Votre compte n’a pas accès à cette boîte.',
          'mailbox_not_connected' ||
          'gmail_reconnect_required' ||
          'reconnect_required' =>
            'Reconnectez cette boîte Gmail, puis actualisez les conversations.',
          'modify_scope_required' =>
            'Cette connexion Gmail est en lecture seule. Reconnectez la boîte pour autoriser la modification.',
          'metadata_update_failed' =>
            'Gmail n’a pas confirmé la modification. Actualisez la conversation avant de réessayer.',
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
          'invalid_input' ||
          'invalid_request' => 'Vérifiez le contenu de la réponse.',
          'invalid_attachments' =>
            'Vérifiez le nom et le contenu des pièces jointes.',
          'attachments_too_large' || 'attachment_too_large' =>
            'Les pièces jointes sont limitées à 3 Mio. Réduisez le fichier ou consultez Gmail.',
          'attachment_not_found' =>
            'Cette pièce jointe est indisponible. Actualisez la conversation.',
          'reply_all_unverified_recipients' =>
            'Le routage de certains participants doit être vérifié. Choisissez une réponse simple.',
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
        },
        outcomeUnknown: unknown,
        code: error.code,
      );
    } on SupportException {
      rethrow;
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
              canModify: m['can_modify'] is bool
                  ? m['can_modify'] as bool
                  : null,
              reconnectRequired: m['reconnect_required'] == true,
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
  DateTime? _date(dynamic value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    }
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  @override
  Future<SupportPage> threads(
    String mailboxId, {
    String? cursor,
    String? query,
  }) => _guard(() async {
    final data = await api.get('support/threads', {
      'mailbox_id': mailboxId,
      'cursor': ?cursor,
      if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
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
              isUnread: t['is_unread'] is bool ? t['is_unread'] as bool : null,
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
        canReplyAll: t['can_reply_all'] == true,
        replyAllDisabledReason: t['reply_all_disabled_reason'] as String?,
        replyAllRecipients: (t['reply_all_recipients'] as List? ?? [])
            .cast<String>(),
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
                html: m['html'] as String?,
                cc: m['cc'] as String? ?? '',
                attachments: (m['attachments'] as List? ?? [])
                    .map(
                      (a) => SupportAttachment(
                        id: a['id'] as String,
                        name: a['name'] as String,
                        mimeType: a['mime_type'] as String,
                        size: (a['size'] as num).toInt(),
                      ),
                    )
                    .toList(),
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
      throw const SupportException(
        'Gmail n’a pas confirmé le nouvel état. Actualisez la conversation.',
      );
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
    bool replyAll = false,
    List<SupportReplyAttachment> attachments = const [],
  }) => _guard(() async {
    final data = await api.post('support/threads/$threadId/reply', {
      'mailbox_id': mailboxId,
      'body': body,
      'expected_message_id': expectedMessageId,
      'confirmed': true,
      'reply_mode': replyAll ? 'reply_all' : 'reply',
      'attachments': attachments
          .map(
            (a) => {
              'name': a.name,
              'mime_type': a.mimeType,
              'data_base64': a.dataBase64,
            },
          )
          .toList(),
    });
    return switch (data['state']) {
      'submitted' => SupportReplyResult.submitted,
      'unknown' => SupportReplyResult.unknown,
      _ => throw const FormatException(),
    };
  }, sending: true);

  Future<Uint8List> download(
    String mailboxId,
    String threadId,
    String messageId,
    SupportAttachment attachment,
  ) => _guard(() async {
    final data = await api.getAttachment(
      'support/threads/$threadId/messages/$messageId/attachments/${attachment.id}',
      {'mailbox_id': mailboxId},
    );
    final record = data['attachment'] as Map;
    if (record['id'] != attachment.id || record['size'] != attachment.size) {
      throw const FormatException();
    }
    final bytes = base64Decode(record['data_base64'] as String);
    if (bytes.length != attachment.size || bytes.length > 3 * 1024 * 1024) {
      throw const FormatException();
    }
    return bytes;
  });
}

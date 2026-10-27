import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';

typedef EmailAccessTokenProvider = Future<String?> Function();

/// Loopback hosts that may use plain HTTP during local development. `Uri.host`
/// returns an IPv6 literal without brackets, so `::1` is the spelling that
/// matches a parsed URI; `[::1]` is accepted too for a caller that passes it raw.
bool isLoopbackHost(String host) =>
    const {'localhost', '127.0.0.1', '::1', '[::1]'}.contains(host);

/// User session client. Provider and service credentials remain server-owned.
class CentralEmailApi {
  CentralEmailApi({
    required this.origin,
    required http.Client client,
    this.accessTokenProvider,
    this.apiBasePath = '/api/admin/email',
  }) : _client = client {
    if (origin.userInfo.isNotEmpty ||
        (origin.path.isNotEmpty && origin.path != '/') ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.scheme != 'https' &&
            !(origin.scheme == 'http' && isLoopbackHost(origin.host)))) {
      throw ArgumentError('A secure host origin is required.');
    }
    if (!RegExp(r'^/[a-zA-Z0-9_/-]+$').hasMatch(apiBasePath) ||
        apiBasePath.contains('..') ||
        apiBasePath.endsWith('/')) {
      throw ArgumentError('A bounded API prefix is required.');
    }
  }

  final Uri origin;
  final EmailAccessTokenProvider? accessTokenProvider;
  final String apiBasePath;
  final http.Client _client;
  static const timeout = Duration(seconds: 20);
  static const maxResponseBytes = 1024 * 1024;
  static const maxPendingCommands = 128;
  // 503 codes the server gives before any work: the key may be released.
  static const _definitiveUnavailable = <String>{
    'configuration_unavailable',
    'sequences_unavailable',
    'public_subscribe_unavailable',
    'transport_not_enabled',
  };
  final Map<String, String> _pendingKeys = {};
  final List<int> _intentFingerprintKey = List.generate(
    32,
    (_) => Random.secure().nextInt(256),
  );

  static String _key() {
    final random = Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<Map<String, dynamic>> get(String path, [Map<String, String>? query]) =>
      _request('GET', path, query: query);

  /// Only the authenticated support attachment contract may use the larger
  /// response allowance. Ordinary campaign and mailbox receipts remain bounded.
  Future<Map<String, dynamic>> getAttachment(
    String path,
    Map<String, String> query,
  ) {
    if (!RegExp(
      r'^support/threads/[a-zA-Z0-9_-]+/messages/[a-zA-Z0-9_-]+/attachments/[a-zA-Z0-9_.-]+$',
    ).hasMatch(path)) {
      throw const EmailApiException('invalid_input');
    }
    return _request('GET', path, query: query, responseLimit: 4_400_000);
  }

  /// A retry of the exact uncertain command reuses its identity. Edits represent
  /// a different intent and therefore receive a different key. No automatic retry.
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) => _request('POST', path, body: body, requestTimeout: timeout);

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    int responseLimit = maxResponseBytes,
    Duration? requestTimeout,
  }) async {
    final attachmentPath = RegExp(
      r'^support/threads/[a-zA-Z0-9_-]+/messages/[a-zA-Z0-9_-]+/attachments/[a-zA-Z0-9_.-]+$',
    ).hasMatch(path);
    if ((!RegExp(r'^[a-zA-Z0-9_/-]+$').hasMatch(path) && !attachmentPath) ||
        path.contains('..')) {
      throw const EmailApiException('invalid_input');
    }
    final uri = origin.replace(
      path: '$apiBasePath/$path',
      queryParameters: query,
    );
    final encoded = body == null ? '' : jsonEncode(body);
    final intent = '$method:$path:$encoded';
    final intentFingerprint = Hmac(
      sha256,
      _intentFingerprintKey,
    ).convert(utf8.encode(intent)).toString();
    final abort = Completer<void>();
    final request =
        http.AbortableRequest(method, uri, abortTrigger: abort.future)
          ..followRedirects = false
          ..headers['Accept'] = 'application/json';
    if (body != null &&
        !_pendingKeys.containsKey(intentFingerprint) &&
        _pendingKeys.length >= maxPendingCommands) {
      throw const EmailApiException('pending_commands_limit');
    }
    final supplier = accessTokenProvider;
    if (supplier != null) {
      String? token;
      try {
        token = await supplier();
      } catch (_) {
        throw const EmailApiException('auth_required');
      }
      if (token == null ||
          token.trim().isEmpty ||
          token.contains('\r') ||
          token.contains('\n')) {
        throw const EmailApiException('auth_required');
      }
      request.headers['Authorization'] = 'Bearer $token';
    }
    // The key is registered only once the request is ready to leave: a refused
    // token therefore never leaves a pending command behind.
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.headers['Idempotency-Key'] = _pendingKeys.putIfAbsent(
        intentFingerprint,
        _key,
      );
      request.body = encoded;
    }
    final timer = Timer(requestTimeout ?? timeout, () => abort.complete());
    try {
      final response = await _client.send(request);
      final status = response.statusCode;
      if (status >= 300 && status < 400) {
        _release(method, intentFingerprint);
        throw const EmailApiException('auth_required');
      }
      final bytes = <int>[];
      var overflow = false;
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > responseLimit) {
          overflow = true;
          break;
        }
        bytes.addAll(chunk);
      }
      // Status first: a refusal or an outage may come with a non-JSON body, and
      // the caller must still receive its typed error, not a decoding failure.
      if (status == 401) {
        _release(method, intentFingerprint);
        throw const EmailApiException('auth_required');
      }
      if (status == 403) {
        _release(method, intentFingerprint);
        throw EmailApiException(
          _errorCode(bytes) == 'console_required'
              ? 'console_required'
              : 'forbidden',
        );
      }
      if (status < 200 || status >= 300) {
        final code = _failureCode(status, bytes);
        // Refusals (4xx, 429) and the 503s that name a definitive unavailability
        // happen before any work, so the key is released. Other outages (502,
        // 504, unknown 5xx) may have run: their key stays, and an identical
        // retry replays the same receipt.
        if (status < 500 ||
            (status == 503 && _definitiveUnavailable.contains(code))) {
          _release(method, intentFingerprint);
        }
        throw EmailApiException(
          code,
          retryAfter: status == 429 ? _retryAfter(response.headers) : null,
        );
      }
      if (overflow) throw const EmailApiException('invalid_backend_receipt');
      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      } catch (_) {
        // A 2xx that is not JSON means the command ran: its key stays pending.
        throw const EmailApiException('invalid_backend_receipt');
      }
      _release(method, intentFingerprint);
      return payload;
    } on EmailApiException {
      rethrow;
    } on http.RequestAbortedException {
      throw EmailApiException(method == 'POST' ? 'outcome_unknown' : 'timeout');
    } catch (_) {
      throw EmailApiException(
        method == 'POST' ? 'outcome_unknown' : 'service_unavailable',
      );
    } finally {
      timer.cancel();
    }
  }

  void _release(String method, String intentFingerprint) {
    if (method == 'POST') _pendingKeys.remove(intentFingerprint);
  }

  /// The machine code of a JSON error body, or null when the body is not one.
  static String? _errorCode(List<int> bytes) {
    try {
      final payload = jsonDecode(utf8.decode(bytes));
      final error = payload is Map ? payload['error'] : null;
      final code = error is Map ? error['code'] : error;
      return code is String && code.isNotEmpty ? code : null;
    } on FormatException {
      return null;
    }
  }

  /// The server's code when it gave one, otherwise a code that follows from
  /// the status alone.
  static String _failureCode(int status, List<int> bytes) {
    final code = _errorCode(bytes);
    if (code != null) return code;
    return switch (status) {
      413 => 'payload_too_large',
      429 => 'rate_limited',
      _ => 'service_unavailable',
    };
  }

  /// Retry-After in whole seconds, capped at one hour. Header names are matched
  /// case-insensitively because the client does not normalise them.
  static Duration? _retryAfter(Map<String, String> headers) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() != 'retry-after') continue;
      final seconds = int.tryParse(entry.value.trim());
      if (seconds != null && seconds >= 0) {
        return Duration(seconds: min(seconds, 3600));
      }
    }
    return null;
  }

  void close() {
    _client.close();
    _pendingKeys.clear();
    _intentFingerprintKey.fillRange(0, _intentFingerprintKey.length, 0);
  }
}

String _rateLimitedMessage(Duration? retryAfter) => retryAfter == null
    ? 'Trop de demandes rapprochées. Attendez un instant avant de réessayer.'
    : 'Trop de demandes rapprochées. Réessayez dans ${max(1, retryAfter.inSeconds)} s.';

/// French wording of `invalid_state`, which depends on the refused operation.
String _invalidStateMessage(String? operation) => switch (operation) {
  'create' || 'revise' =>
    'Cette mise à jour ne peut plus être modifiée dans son état actuel. Actualisez-la pour voir son statut.',
  'snapshot' =>
    'La préparation n’est possible que pour un brouillon ou une campagne suspendue.',
  'pause' =>
    'Cette mise à jour ne peut pas être mise en pause dans son état actuel.',
  'cancel' => 'Cette mise à jour est déjà terminée ou annulée.',
  'delete' => 'Seul un brouillon peut être supprimé.',
  _ => 'Cette action n’est pas possible dans l’état actuel de la mise à jour.',
};

class EmailApiException implements Exception, CodedFailure {
  const EmailApiException(this.code, {this.operation, this.retryAfter});
  @override
  final String code;

  /// The bridge operation that was refused, when the caller knows it. It picks
  /// the wording of `invalid_state`.
  final String? operation;

  /// Wait requested by a 429 (`Retry-After`), when the server gave one.
  final Duration? retryAfter;

  String get message => switch (code) {
    'auth_required' =>
      'Votre session a expiré. Reconnectez-vous à CommandGlows, puis réessayez.',
    'forbidden' ||
    'admin_required' => 'Votre compte n’a pas accès à ces campagnes.',
    'console_required' =>
      'Cette étape se valide dans la console CommandGlows, pas dans cette application.',
    'version_conflict' || 'conflict' || 'stale_version' =>
      'Cette campagne a changé dans une autre fenêtre. Rechargez-la avant de continuer.',
    'outcome_unknown' =>
      'La réponse a été interrompue. Vérifiez le statut de la campagne avant de renouveler l’action.',
    'invalid_input' =>
      'Vérifiez le contenu, l’audience et la date de la campagne.',
    'invalid_state' => _invalidStateMessage(operation),
    'review_required' =>
      'La préparation doit être refaite avant l’approbation. Préparez à nouveau la mise à jour.',
    'idempotency_conflict' =>
      'Cette action a déjà été envoyée avec un autre contenu. Actualisez la mise à jour avant de recommencer.',
    'payload_too_large' =>
      'Le contenu dépasse la limite de la passerelle (64 Ko). Raccourcissez le message.',
    'snapshot_page_limit' =>
      'La préparation prend plus de temps que prévu. Relancez « Préparer » : l’avancement est conservé.',
    'link_check_required' =>
      'Vérifiez les liens de cette version avant de programmer ou d’envoyer.',
    'preflight_blocked' =>
      'Le préflight bloque cette action. Actualisez le contrôle et consultez les contrôles manquants.',
    'human_authority_required' || 'challenge_rejected' =>
      'La confirmation humaine a expiré ou ne correspond plus à cette session. Vérifiez de nouveau la campagne.',
    'configuration_unavailable' =>
      'L’envoi n’est pas encore configuré pour cet espace. Vos brouillons restent disponibles.',
    'reduction_selection_unavailable' =>
      'La liste complète des références à réduire est trop grande ou a changé. Rechargez la campagne avant de réessayer.',
    'incident_read_unavailable' =>
      'Le registre d’incidents n’est pas disponible pour cette campagne.',
    'rate_limited' => _rateLimitedMessage(retryAfter),
    'pending_commands_limit' =>
      'Trop d’actions ont un résultat incertain. Vérifiez leur état avant de recharger l’application et de reprendre.',
    _ =>
      'Le service est momentanément indisponible. Vos modifications restent dans l’éditeur.',
  };
  @override
  String toString() => message;
}

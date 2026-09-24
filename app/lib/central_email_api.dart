import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// Same-origin session client. It never accepts a provider or service credential.
class CentralEmailApi {
  CentralEmailApi({required this.origin, required http.Client client})
    : _client = client {
    if (origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.scheme != 'https' &&
            !(origin.scheme == 'http' &&
                const [
                  'localhost',
                  '127.0.0.1',
                  '[::1]',
                ].contains(origin.host)))) {
      throw ArgumentError('A secure host origin is required.');
    }
  }

  final Uri origin;
  final http.Client _client;
  static const timeout = Duration(seconds: 20);
  static const maxResponseBytes = 1024 * 1024;
  final Map<String, String> _pendingKeys = {};

  static String _key() {
    final random = Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<Map<String, dynamic>> get(String path, [Map<String, String>? query]) =>
      _request('GET', path, query: query);

  /// A retry of the exact uncertain command reuses its identity. Edits represent
  /// a different intent and therefore receive a different key. No automatic retry.
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) =>
      _request('POST', path, body: body);

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    if (!RegExp(r'^[a-zA-Z0-9_/-]+$').hasMatch(path) || path.contains('..')) {
      throw const EmailApiException('invalid_input');
    }
    final uri = origin.replace(
      path: '/api/admin/email/$path',
      queryParameters: query,
    );
    final encoded = body == null ? '' : jsonEncode(body);
    final intent = '$method:$path:$encoded';
    final abort = Completer<void>();
    final request =
        http.AbortableRequest(method, uri, abortTrigger: abort.future)
          ..followRedirects = false
          ..headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.headers['Idempotency-Key'] = _pendingKeys.putIfAbsent(
        intent,
        _key,
      );
      request.body = encoded;
    }
    final timer = Timer(timeout, () => abort.complete());
    try {
      final response = await _client.send(request);
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw const EmailApiException('auth_required');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > maxResponseBytes) {
          throw const EmailApiException('invalid_backend_receipt');
        }
        bytes.addAll(chunk);
      }
      if (response.statusCode == 401) {
        throw const EmailApiException('auth_required');
      }
      if (response.statusCode == 403) {
        throw const EmailApiException('forbidden');
      }
      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      } catch (_) {
        throw const EmailApiException('invalid_backend_receipt');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = payload['error'];
        final code = error is Map ? error['code'] : error;
        if (response.statusCode < 500) _pendingKeys.remove(intent);
        throw EmailApiException(code is String ? code : 'service_unavailable');
      }
      _pendingKeys.remove(intent);
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

  void close() => _client.close();
}

class EmailApiException implements Exception {
  const EmailApiException(this.code);
  final String code;
  String get message => switch (code) {
    'auth_required' =>
      'Votre session a expiré. Reconnectez-vous à CommandGlows, puis réessayez.',
    'forbidden' ||
    'admin_required' => 'Votre compte n’a pas accès à ces campagnes.',
    'version_conflict' || 'conflict' || 'stale_version' =>
      'Cette campagne a changé dans une autre fenêtre. Rechargez-la avant de continuer.',
    'outcome_unknown' =>
      'La réponse a été interrompue. Vérifiez le statut de la campagne avant de renouveler l’action.',
    'invalid_input' =>
      'Vérifiez le contenu, l’audience et la date de la campagne.',
    'invalid_state' || 'review_required' =>
      'La campagne doit être revue à nouveau avant cet envoi.',
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
    'rate_limited' =>
      'Trop de demandes rapprochées. Attendez un instant avant de réessayer.',
    _ =>
      'Le service est momentanément indisponible. Vos modifications restent dans l’éditeur.',
  };
  @override
  String toString() => message;
}

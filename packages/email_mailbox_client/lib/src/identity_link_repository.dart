import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';

import 'central_email_api.dart';

/// Account-link bridge calls. Every response is validated strictly, and any
/// invalid shape throws [EmailApiException] with code `invalid_response`.
class IdentityLinkRepository implements IdentityLinkGateway {
  IdentityLinkRepository(this.api);

  final CentralEmailApi api;

  static const _maxCodeLength = 512;
  static final _fingerprint = RegExp(
    r'^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$',
  );

  @override
  Future<IdentityLinkStatus> status() async =>
      _parseStatus(await api.get('identity/status'));

  @override
  Future<IdentityLinkCode> createLinkCode() async =>
      _parseCode(await api.post('identity/link-code', const {}));

  @override
  Future<IdentityLinkStatus> confirmLinkCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty || trimmed.length > _maxCodeLength) {
      throw const EmailApiException('invalid_input');
    }
    final status = _parseStatus(
      await api.post('identity/link-confirm', {'code': trimmed}),
    );
    if (!status.linked) throw const EmailApiException('invalid_response');
    return status;
  }

  static void _requireSchema(Map<String, dynamic> body) {
    final version = body['schema_version'];
    if (version is! int || version != 1) {
      throw const EmailApiException('invalid_response');
    }
  }

  static IdentityLinkStatus _parseStatus(Map<String, dynamic> body) {
    _requireSchema(body);
    final linked = body['linked'];
    final fingerprint = body['fingerprint'];
    if (linked is! bool) throw const EmailApiException('invalid_response');
    if (fingerprint != null &&
        (fingerprint is! String || !_fingerprint.hasMatch(fingerprint))) {
      throw const EmailApiException('invalid_response');
    }
    // A link always carries its fingerprint. A provisioned but unlinked
    // account also has one; only an unknown identity has none.
    if (linked && fingerprint == null) {
      throw const EmailApiException('invalid_response');
    }
    return IdentityLinkStatus(
      linked: linked,
      fingerprint: fingerprint as String?,
    );
  }

  static IdentityLinkCode _parseCode(Map<String, dynamic> body) {
    _requireSchema(body);
    final code = body['code'];
    final expiresAt = body['expires_at'];
    if (code is! String ||
        code.isEmpty ||
        code.length > _maxCodeLength ||
        expiresAt is! String) {
      throw const EmailApiException('invalid_response');
    }
    final parsed = DateTime.tryParse(expiresAt);
    if (parsed == null) throw const EmailApiException('invalid_response');
    return IdentityLinkCode(code: code, expiresAt: parsed.toUtc());
  }
}

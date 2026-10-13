import 'dart:convert';

import 'package:email_mailbox_client/email_mailbox_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';

const _bridge = '/api/bridge/email-mailbox/firebase';
const _fingerprint = 'ABCD-EFGH';

CentralEmailApi _api(http.Client client) => CentralEmailApi(
  origin: Uri.parse('https://synthetic.test'),
  accessTokenProvider: () async => 'synthetic-user-session',
  apiBasePath: _bridge,
  client: client,
);

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _status({
  Object? schema = 1,
  Object? linked = true,
  Object? fingerprint = _fingerprint,
}) => {'schema_version': schema, 'linked': linked, 'fingerprint': fingerprint};

Map<String, dynamic> _code({
  Object? schema = 1,
  Object? code = 'SYN-CODE-123',
  Object? expiresAt = '2026-10-13T12:05:00Z',
}) => {'schema_version': schema, 'code': code, 'expires_at': expiresAt};

final _invalidResponse = throwsA(
  isA<EmailApiException>().having((e) => e.code, 'code', 'invalid_response'),
);

void main() {
  group('status', () {
    test('parses linked and unlinked responses from the bridge', () async {
      final requests = <http.BaseRequest>[];
      final bodies = [_status(), _status(linked: false, fingerprint: null)];
      final repository = IdentityLinkRepository(
        _api(
          MockClient((request) async {
            requests.add(request);
            return _json(bodies.removeAt(0));
          }),
        ),
      );

      expect(
        await repository.status(),
        const IdentityLinkStatus(linked: true, fingerprint: _fingerprint),
      );
      expect(
        await repository.status(),
        const IdentityLinkStatus(linked: false),
      );
      expect(requests.first.method, 'GET');
      expect(requests.first.url.path, '$_bridge/identity/status');
      expect(
        requests.first.headers['Authorization'],
        'Bearer synthetic-user-session',
      );
    });

    test('rejects an unknown schema version', () async {
      final repository = IdentityLinkRepository(
        _api(MockClient((_) async => _json(_status(schema: 2)))),
      );
      await expectLater(repository.status(), _invalidResponse);
    });

    test(
      'rejects a float schema version even when numerically equal',
      () async {
        final repository = IdentityLinkRepository(
          _api(MockClient((_) async => _json(_status(schema: 1.0)))),
        );
        await expectLater(repository.status(), _invalidResponse);
      },
    );

    test('rejects malformed or lowercase fingerprints', () async {
      for (final bad in ['abcd-efgh', 'ABCD-EFGI', 'ABCDEFGH', 'ABC-DEFGH']) {
        final repository = IdentityLinkRepository(
          _api(MockClient((_) async => _json(_status(fingerprint: bad)))),
        );
        await expectLater(repository.status(), _invalidResponse);
      }
    });

    test(
      'rejects a linked state without fingerprint or a fingerprint without link',
      () async {
        final missing = IdentityLinkRepository(
          _api(MockClient((_) async => _json(_status(fingerprint: null)))),
        );
        await expectLater(missing.status(), _invalidResponse);

        final unexpected = IdentityLinkRepository(
          _api(MockClient((_) async => _json(_status(linked: false)))),
        );
        await expectLater(unexpected.status(), _invalidResponse);
      },
    );
  });

  group('createLinkCode', () {
    test('posts an empty body and parses the code as UTC', () async {
      late http.BaseRequest sent;
      final repository = IdentityLinkRepository(
        _api(
          MockClient((request) async {
            sent = request;
            return _json(_code(expiresAt: '2026-10-13T14:05:00+02:00'));
          }),
        ),
      );

      final issued = await repository.createLinkCode();

      expect(sent.url.path, '$_bridge/identity/link-code');
      expect(sent.method, 'POST');
      expect(sent.headers['Idempotency-Key'], isNotEmpty);
      expect((sent as http.Request).body, '{}');
      expect(issued.code, 'SYN-CODE-123');
      expect(issued.expiresAt, DateTime.utc(2026, 10, 13, 12, 5));
      expect(issued.expiresAt.isUtc, isTrue);
    });

    test('rejects empty, oversized, untyped or undated codes', () async {
      for (final body in [
        _code(code: ''),
        _code(code: 'x' * 513),
        _code(code: 42),
        _code(expiresAt: 'not-a-date'),
        _code(expiresAt: null),
        _code(schema: null),
      ]) {
        final repository = IdentityLinkRepository(
          _api(MockClient((_) async => _json(body))),
        );
        await expectLater(repository.createLinkCode(), _invalidResponse);
      }
    });

    test('accepts a code of exactly 512 characters', () async {
      final repository = IdentityLinkRepository(
        _api(MockClient((_) async => _json(_code(code: 'x' * 512)))),
      );
      expect((await repository.createLinkCode()).code, hasLength(512));
    });
  });

  group('confirmLinkCode', () {
    test('trims the pasted code and sends exactly the code key', () async {
      late http.Request sent;
      final repository = IdentityLinkRepository(
        _api(
          MockClient((request) async {
            sent = request;
            return _json({
              'schema_version': 1,
              'linked': true,
              'fingerprint': _fingerprint,
            });
          }),
        ),
      );

      final status = await repository.confirmLinkCode('  SYN-CODE-123\n');

      expect(sent.url.path, '$_bridge/identity/link-confirm');
      expect(jsonDecode(sent.body), {'code': 'SYN-CODE-123'});
      expect(
        status,
        const IdentityLinkStatus(linked: true, fingerprint: _fingerprint),
      );
    });

    test('rejects empty or oversized input without any request', () async {
      var requests = 0;
      final repository = IdentityLinkRepository(
        _api(
          MockClient((_) async {
            requests++;
            return _json({});
          }),
        ),
      );

      for (final input in ['', '   ', 'x' * 513, '  ${'x' * 513}  ']) {
        await expectLater(
          repository.confirmLinkCode(input),
          throwsA(
            isA<EmailApiException>().having(
              (e) => e.code,
              'code',
              'invalid_input',
            ),
          ),
        );
      }
      expect(requests, 0);
    });

    test('accepts 512 characters after trimming', () async {
      late http.Request sent;
      final repository = IdentityLinkRepository(
        _api(
          MockClient((request) async {
            sent = request;
            return _json({
              'schema_version': 1,
              'linked': true,
              'fingerprint': _fingerprint,
            });
          }),
        ),
      );

      await repository.confirmLinkCode('  ${'x' * 512}  ');

      expect(jsonDecode(sent.body), {'code': 'x' * 512});
    });

    test('rejects a success response that is not linked', () async {
      final repository = IdentityLinkRepository(
        _api(
          MockClient(
            (_) async => _json({
              'schema_version': 1,
              'linked': false,
              'fingerprint': null,
            }),
          ),
        ),
      );
      await expectLater(
        repository.confirmLinkCode('SYN-CODE-123'),
        _invalidResponse,
      );
    });

    test('keeps the server error code for a rejected link', () async {
      final repository = IdentityLinkRepository(
        _api(
          MockClient(
            (_) async => _json({
              'error': {'code': 'link_code_invalid'},
            }, 400),
          ),
        ),
      );
      await expectLater(
        repository.confirmLinkCode('SYN-CODE-123'),
        throwsA(
          isA<EmailApiException>().having(
            (e) => e.code,
            'code',
            'link_code_invalid',
          ),
        ),
      );
    });
  });
}

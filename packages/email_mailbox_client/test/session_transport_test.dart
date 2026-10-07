import 'dart:convert';

import 'package:email_mailbox_client/email_mailbox_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('missing embedded session prevents any request', () async {
    var requests = 0;
    final api = CentralEmailApi(
      origin: Uri.parse('https://synthetic.test'),
      accessTokenProvider: () async => null,
      apiBasePath: '/api/bridge/email-mailbox/firebase',
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      api.get('support/context'),
      throwsA(
        isA<EmailApiException>().having((e) => e.code, 'code', 'auth_required'),
      ),
    );
    expect(requests, 0);
    api.close();
  });
  test('configured bridge receives only the supplied user session', () async {
    final api = CentralEmailApi(
      origin: Uri.parse('https://synthetic.test'),
      accessTokenProvider: () async => 'synthetic-user-session',
      apiBasePath: '/api/bridge/email-mailbox/firebase',
      client: MockClient((r) async {
        expect(
          r.url.path,
          '/api/bridge/email-mailbox/firebase/support/context',
        );
        expect(r.headers['Authorization'], 'Bearer synthetic-user-session');
        expect(r.followRedirects, false);
        return http.Response(jsonEncode({'configured': false}), 200);
      }),
    );
    expect(await api.get('support/context'), {'configured': false});
    api.close();
  });
  test('server redirect never forwards bearer credentials', () async {
    var requests = 0;
    final api = CentralEmailApi(
      origin: Uri.parse('https://synthetic.test'),
      accessTokenProvider: () async => 'synthetic-user-session',
      client: MockClient((_) async {
        requests++;
        return http.Response(
          '',
          302,
          headers: {'location': 'https://other-synthetic.test'},
        );
      }),
    );
    await expectLater(
      api.get('support/context'),
      throwsA(
        isA<EmailApiException>().having((e) => e.code, 'code', 'auth_required'),
      ),
    );
    expect(requests, 1);
    api.close();
  });
}

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';
import 'package:shipglows_email_engine_app/central_email_api.dart';
import 'package:shipglows_email_engine_app/support_repository.dart';
import 'package:shipglows_email_engine_app/support_reader.dart';

void main() {
  test(
    'provider filenames cannot become paths or Windows reserved devices',
    () {
      expect(safeDownloadName('../secret.txt'), '.._secret.txt');
      expect(safeDownloadName('CON.txt'), 'piece-jointe_CON.txt');
      expect(safeDownloadName('...'), 'piece-jointe');
      expect(safeDownloadName('normal.pdf'), 'normal.pdf');
    },
  );
  test(
    'server search carries query and cursor, rich thread maps all capabilities',
    () async {
      final requests = <http.Request>[];
      final api = CentralEmailApi(
        origin: Uri.https('example.test'),
        client: MockClient((request) async {
          requests.add(request);
          final list = request.url.path.endsWith('/threads');
          return http.Response(
            jsonEncode(
              list
                  ? {'threads': [], 'next_cursor': 'next'}
                  : {
                      'thread': {
                        'id': 't',
                        'subject': 'Question',
                        'status': 'pending',
                        'latest_message_id': 'm',
                        'can_reply': true,
                        'reply_to': 'one@relay.test',
                        'can_reply_all': true,
                        'reply_all_recipients': [
                          'one@relay.test',
                          'two@relay.test',
                        ],
                        'messages': [
                          {
                            'id': 'm',
                            'from': 'Client',
                            'to': 'Owner',
                            'cc': 'Team',
                            'text': 'Texte',
                            'html': '<p><strong>Enrichi</strong></p>',
                            'attachments': [
                              {
                                'id': 'a',
                                'name': 'receipt.pdf',
                                'mime_type': 'application/pdf',
                                'size': 3,
                              },
                            ],
                          },
                        ],
                      },
                    },
            ),
            200,
          );
        }),
      );
      final repository = CentralSupportRepository(api);
      final page = await repository.threads(
        'own',
        query: 'has:attachment',
        cursor: 'old',
      );
      expect(page.nextCursor, 'next');
      expect(requests.first.url.queryParameters, {
        'mailbox_id': 'own',
        'query': 'has:attachment',
        'cursor': 'old',
      });
      final thread = await repository.thread('own', 't');
      expect(thread.canReplyAll, isTrue);
      expect(thread.replyAllRecipients, ['one@relay.test', 'two@relay.test']);
      expect(thread.messages.single.html, contains('<strong>'));
      expect(thread.messages.single.cc, 'Team');
      expect(thread.messages.single.attachments.single.size, 3);
      api.close();
    },
  );

  test('reply-all sends mode and files, never client recipients', () async {
    final api = CentralEmailApi(
      origin: Uri.https('example.test'),
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        expect(body['reply_mode'], 'reply_all');
        expect(body['attachments'], [
          {
            'name': 'receipt.pdf',
            'mime_type': 'application/pdf',
            'data_base64': 'AQID',
          },
        ]);
        expect(body.keys, isNot(contains('recipient')));
        expect(body.keys, isNot(contains('recipients')));
        expect(body['expected_message_id'], 'm');
        expect(body['confirmed'], true);
        return http.Response('{"state":"submitted"}', 200);
      }),
    );
    expect(
      await CentralSupportRepository(api).reply(
        'own',
        't',
        body: 'Bonjour',
        expectedMessageId: 'm',
        replyAll: true,
        attachments: const [
          SupportReplyAttachment(
            name: 'receipt.pdf',
            mimeType: 'application/pdf',
            dataBase64: 'AQID',
            size: 3,
          ),
        ],
      ),
      SupportReplyResult.submitted,
    );
    api.close();
  });

  test('download validates size and identity before saving', () async {
    final api = CentralEmailApi(
      origin: Uri.https('example.test'),
      client: MockClient((request) async {
        final attachmentId = request.url.pathSegments.last;
        expect(
          request.url.path,
          '/api/admin/email/support/threads/t/messages/m/attachments/$attachmentId',
        );
        expect(request.url.queryParameters['mailbox_id'], 'own');
        return http.Response(
          '{"attachment":{"id":"$attachmentId","size":3,"data_base64":"AQID"}}',
          200,
        );
      }),
    );
    final repository = CentralSupportRepository(api);
    final bytes = await repository.download(
      'own',
      't',
      'm',
      const SupportAttachment(
        id: 'a',
        name: 'receipt.pdf',
        mimeType: 'application/pdf',
        size: 3,
      ),
    );
    expect(bytes, [1, 2, 3]);
    expect(
      await repository.download(
        'own',
        't',
        'm',
        const SupportAttachment(
          id: 'inline_0.1',
          name: 'inline.txt',
          mimeType: 'text/plain',
          size: 3,
        ),
      ),
      [1, 2, 3],
    );
    await expectLater(
      repository.download(
        'own',
        't',
        'm',
        const SupportAttachment(
          id: 'a',
          name: 'receipt.pdf',
          mimeType: 'application/pdf',
          size: 4,
        ),
      ),
      throwsA(isA<SupportException>()),
    );
    expect(
      () => api.getAttachment('campaigns/t', {}),
      throwsA(isA<EmailApiException>()),
    );
    api.close();
  });

  test(
    'HTML defense removes active content and tracking but preserves formatting',
    () {
      final result = safeEmailHtml('''<script>alert(1)</script><style>x</style>
      <p onclick="evil()" style="background:url(https://track.test)">Hello <b>team</b></p>
      <iframe src="https://evil.test"></iframe><img src="https://track.test" alt="Logo">
      <a href="javascript:alert(1)">Bad</a><a href="https://example.test/path">Good</a>
      <table><tr><td>Receipt</td></tr></table>''');
      expect(result, contains('<b>team</b>'));
      expect(result, contains('<table>'));
      expect(result, contains('href="https://example.test/path"'));
      for (final forbidden in [
        'script',
        'iframe',
        'onclick',
        'background:',
        'javascript:',
        'https://track.test',
      ]) {
        expect(result, isNot(contains(forbidden)));
      }
    },
  );
}

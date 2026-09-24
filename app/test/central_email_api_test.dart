import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shipglows_email_engine_app/central_email_api.dart';
import 'package:shipglows_email_engine_app/campaign_repository.dart';
import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';

void main() {
  final business = EmailBusiness({
    'id': 'studio',
    'brand': 'Studio',
    'from': 'sender@example.test',
    'audiences': [
      {'id': 'news', 'purpose': 'marketing'},
    ],
    'capabilities': {'can_test': true, 'can_approve': true},
    'test_recipients': ['reader@example.test'],
  });

  Map<String, dynamic> campaign({
    int version = 1,
    String state = 'draft',
    String blockReason = '',
  }) => {
    'id': 'campaign-a',
    'business_id': 'studio',
    'title': 'Draft',
    'subject': 'Subject',
    'preheader': '',
    'audience_id': 'news',
    'locale': 'fr',
    'blocks': <Object>[],
    'version': version,
    'state': state,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
    'counters': <String, int>{
      'queued': 0,
      'submitted': 0,
      'delivered': 0,
      'failed': 0,
      'unknown': 0,
    },
    if (blockReason.isNotEmpty) 'block_reason': blockReason,
  };

  test('rejects insecure remote origins and credential URLs', () {
    for (final url in [
      'http://example.com',
      'https://user:secret@example.com',
      'https://example.com?token=secret',
    ]) {
      expect(
        () => CentralEmailApi(
          origin: Uri.parse(url),
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
        throwsArgumentError,
      );
    }
  });

  test(
    'uncertain command retry retains its key and does not auto retry',
    () async {
      final requests = <http.Request>[];
      final api = CentralEmailApi(
        origin: Uri.parse('https://example.test'),
        client: MockClient((request) async {
          requests.add(request);
          if (requests.length == 1) {
            throw http.ClientException('sensitive raw response');
          }
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        api.post('campaigns/a/approve', {'expected_version': 2}),
        throwsA(
          isA<EmailApiException>().having(
            (e) => e.code,
            'code',
            'outcome_unknown',
          ),
        ),
      );
      expect(requests, hasLength(1));
      await api.post('campaigns/a/approve', {'expected_version': 2});
      expect(
        requests[0].headers['Idempotency-Key'],
        requests[1].headers['Idempotency-Key'],
      );
      expect(requests[0].followRedirects, isFalse);
      expect(
        requests[0].headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
    },
  );

  test(
    'rejects redirected login and malformed success with safe errors',
    () async {
      for (final status in [302, 200]) {
        final api = CentralEmailApi(
          origin: Uri.parse('https://example.test'),
          client: MockClient(
            (_) async => http.Response('<html>private detail</html>', status),
          ),
        );
        await expectLater(
          api.get('context'),
          throwsA(
            isA<EmailApiException>().having(
              (e) => e.toString(),
              'message',
              isNot(contains('private')),
            ),
          ),
        );
      }
    },
  );

  test('rejects oversized server response', () async {
    final api = CentralEmailApi(
      origin: Uri.parse('https://example.test'),
      client: MockClient(
        (_) async =>
            http.Response('x' * (CentralEmailApi.maxResponseBytes + 1), 200),
      ),
    );
    await expectLater(api.get('context'), throwsA(isA<EmailApiException>()));
  });

  test('serializes draft writes with authoritative server versions', () async {
    var version = 1;
    final expected = <int>[];
    final record = <String, dynamic>{
      'id': 'a',
      'business_id': 'b',
      'title': 'Draft',
      'subject': '',
      'preheader': '',
      'audience_id': 'readers',
      'locale': 'fr',
      'blocks': [],
      'version': version,
      'state': 'draft',
    };
    final api = CentralEmailApi(
      origin: Uri.parse('https://example.test'),
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        expected.add(body['expected_version'] as int);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        version++;
        return http.Response(
          jsonEncode({
            'campaign': {...record, 'version': version},
          }),
          200,
        );
      }),
    );
    final business = EmailBusiness({
      'id': 'b',
      'brand': 'Brand',
      'from': 'sender@example.test',
      'audiences': [
        {'id': 'readers', 'purpose': 'marketing'},
      ],
      'capabilities': {},
    });
    final session = CampaignEditorSession(api, business, record);
    final first = session.draft.copyWith(subject: 'First', revision: 10);
    final second = first.copyWith(subject: 'Second', revision: 11);
    final saves = await Future.wait([
      session.save(first),
      session.save(second),
    ]);
    expect(expected, [1, 2]);
    expect(saves.last.revision, 11);
    expect(saves.last.saveState, NewsletterSaveState.saved);
    expect(session.version, 3);
  });

  test(
    'campaign list consumes the HTTP campaign shape and paused mapping',
    () async {
      final api = CentralEmailApi(
        origin: Uri.parse('https://example.test'),
        client: MockClient((request) async {
          expect(request.url.path, '/api/admin/email/campaigns');
          expect(request.url.queryParameters['state'], 'suspended');
          return http.Response(
            jsonEncode({
              'campaigns': [campaign(version: 7, state: 'suspended')],
              'next_cursor': 'next',
            }),
            200,
          );
        }),
      );
      final repository = CentralCampaignRepository(api, business);
      final page = await repository.list(
        status: NewsletterCampaignStatus.suspended,
      );
      expect(page.items.single.status, NewsletterCampaignStatus.suspended);
      expect(page.items.single.revision, 7);
      expect(page.nextCursor, 'next');
    },
  );

  test(
    'approval sends report and server-issued session challenge after a clear preflight',
    () async {
      final requests = <http.Request>[];
      final api = CentralEmailApi(
        origin: Uri.parse('https://example.test'),
        client: MockClient((request) async {
          requests.add(request);
          final path = request.url.path;
          if (path.endsWith('/save')) {
            return http.Response(
              jsonEncode({'campaign': campaign(version: 2)}),
              200,
            );
          }
          if (path.endsWith('/review')) {
            return http.Response(
              jsonEncode({
                'campaign': campaign(version: 2),
                'review': {
                  'id': 'campaign-a:2',
                  'version': 2,
                  'eligible_count': 1,
                  'complete': true,
                  'report_id': 'report-fresh',
                  'expires_at': DateTime.now().millisecondsSinceEpoch + 120000,
                  'blocking_checks': <Object>[],
                },
              }),
              200,
            );
          }
          if (path.endsWith('/challenge')) {
            return http.Response(
              jsonEncode({
                'campaign': campaign(version: 2),
                'challenge': {'id': 'challenge-issued'},
              }),
              200,
            );
          }
          if (path.endsWith('/approve')) {
            return http.Response(
              jsonEncode({'campaign': campaign(version: 2, state: 'sending')}),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );
      final session = CampaignEditorSession(api, business, campaign());
      final draft = session.draft;
      await session.resolve(draft);
      expect(session.preflightIssues(), isEmpty);
      await session.approve(draft);

      final challengeRequest = requests.singleWhere(
        (r) => r.url.path.endsWith('/challenge'),
      );
      final challengeBody = jsonDecode(challengeRequest.body) as Map;
      expect(challengeBody['action'], 'approve');
      expect(challengeBody['report_id'], 'report-fresh');
      expect(challengeBody['expected_version'], 2);
      final approveRequest = requests.singleWhere(
        (r) => r.url.path.endsWith('/approve'),
      );
      expect(jsonDecode(approveRequest.body), {
        'business_id': 'studio',
        'expected_version': 2,
        'review_id': 'campaign-a:2',
        'report_id': 'report-fresh',
        'challenge_id': 'challenge-issued',
      });
    },
  );

  test(
    'resume refreshes preflight and consumes a separate resume challenge',
    () async {
      final requests = <http.Request>[];
      final api = CentralEmailApi(
        origin: Uri.parse('https://example.test'),
        client: MockClient((request) async {
          requests.add(request);
          final path = request.url.path;
          if (path.endsWith('/review')) {
            return http.Response(
              jsonEncode({
                'campaign': campaign(version: 3, state: 'suspended'),
                'review': {
                  'id': 'campaign-a:3',
                  'version': 3,
                  'eligible_count': 1,
                  'complete': true,
                  'report_id': 'report-after-pause',
                  'expires_at': DateTime.now().millisecondsSinceEpoch + 120000,
                  'blocking_checks': <Object>[],
                },
              }),
              200,
            );
          }
          if (path.endsWith('/challenge')) {
            return http.Response(
              jsonEncode({
                'campaign': campaign(version: 3, state: 'suspended'),
                'challenge': {'id': 'resume-challenge'},
              }),
              200,
            );
          }
          if (path.endsWith('/resume')) {
            return http.Response(
              jsonEncode({'campaign': campaign(version: 3, state: 'sending')}),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );
      final session = CampaignEditorSession(
        api,
        business,
        campaign(
          version: 3,
          state: 'suspended',
          blockReason: 'operator_paused',
        ),
      );
      await session.refreshForResume();
      expect(session.preflightIssues(), isEmpty);
      await session.resume();
      expect(requests.map((r) => r.url.path.split('/').last), [
        'review',
        'challenge',
        'resume',
      ]);
      final challengeBody = jsonDecode(requests[1].body) as Map;
      expect(challengeBody['action'], 'resume');
      expect(challengeBody['report_id'], 'report-after-pause');
      final resumeBody = jsonDecode(requests[2].body) as Map;
      expect(resumeBody['challenge_id'], 'resume-challenge');
      expect(resumeBody['report_id'], 'report-after-pause');
    },
  );

  test(
    'pause is a distinct stop and reduction sends only opaque references',
    () async {
      final requests = <http.Request>[];
      final api = CentralEmailApi(
        origin: Uri.parse('https://example.test'),
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({'campaign': campaign(version: 5, state: 'suspended')}),
            200,
          );
        }),
      );
      final session = CampaignEditorSession(
        api,
        business,
        campaign(version: 5, state: 'sending'),
      );
      await session.pause();
      expect(requests.single.url.path.endsWith('/pause'), isTrue);
      expect((jsonDecode(requests.single.body) as Map)['expected_version'], 5);
      await session.reduceRemainingPlan(['opaque-recipient-reference']);
      final reduce = requests.last;
      expect(reduce.url.path.endsWith('/reduce'), isTrue);
      expect(jsonDecode(reduce.body), {
        'business_id': 'studio',
        'expected_version': 5,
        'recipient_ids': ['opaque-recipient-reference'],
      });
    },
  );
}

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
    expect(saves.last.revision, 3);
    expect(saves.last.saveState, NewsletterSaveState.saved);
    expect(session.version, 3);
  });

  test(
    'link check follows the authoritative version after edited content saves',
    () async {
      final requests = <http.Request>[];
      final api = CentralEmailApi(
        origin: Uri.parse('https://example.test'),
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/save')) {
            expect((jsonDecode(request.body) as Map)['expected_version'], 1);
            return http.Response(
              jsonEncode({'campaign': campaign(version: 2)}),
              200,
            );
          }
          if (request.url.path.endsWith('/links/check')) {
            expect(jsonDecode(request.body), {
              'business_id': 'studio',
              'expected_version': 2,
            });
            return http.Response(
              jsonEncode({
                'link_report': {
                  '_id': 'link-report-v2',
                  'campaignId': 'campaign-a',
                  'versionId': 'campaign-a:2',
                  'revision': 2,
                  'destinationDigest': 'digest-v2',
                  'checkedAt': DateTime.now().millisecondsSinceEpoch,
                  'expiresAt': DateTime.now().millisecondsSinceEpoch + 600000,
                  'status': 'clear',
                  'blockingCount': 0,
                  'uncertainCount': 0,
                  'validCount': 0,
                  'findings': <Object>[],
                },
                'disclosure': {
                  'external_requests': true,
                  'possible_destination_side_effect': true,
                  'method_policy': 'HEAD then bounded GET after 405/501',
                },
              }),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );
      final session = CampaignEditorSession(
        api,
        business,
        campaign(version: 1),
      );
      final edited = session.draft.copyWith(subject: 'Changed subject');
      final report = await session.checkLinks(edited);

      expect(session.version, 2);
      expect(report.revision, 2);
      expect(report.serverRevision, 2);
      expect(report.isCurrentFor(edited.copyWith(revision: 2)), isTrue);
      expect(requests.map((request) => request.url.path.split('/').last), [
        'save',
        'check',
      ]);
    },
  );

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
          if (path.endsWith('/links/check')) {
            expect(
              request.url.path,
              '/api/admin/email/campaigns/campaign-a/links/check',
            );
            expect(jsonDecode(request.body), {
              'business_id': 'studio',
              'expected_version': 2,
            });
            expect(request.body, isNot(contains('https://')));
            return http.Response(
              jsonEncode({
                'link_report': {
                  '_id': 'link-report-fresh',
                  'campaignId': 'campaign-a',
                  'versionId': 'campaign-a:2',
                  'revision': 2,
                  'destinationDigest': 'digest-123',
                  'requestKey': 'opaque-key',
                  'checkedBy': 'operator',
                  'checkedAt': DateTime.now().millisecondsSinceEpoch,
                  'expiresAt': DateTime.now().millisecondsSinceEpoch + 600000,
                  'status': 'clear',
                  'blockingCount': 0,
                  'uncertainCount': 0,
                  'validCount': 0,
                  'findings': <Object>[],
                },
                'disclosure': {
                  'external_requests': true,
                  'possible_destination_side_effect': true,
                  'method_policy': 'HEAD first; bounded GET after 405/501',
                },
              }),
              200,
            );
          }
          if (path.endsWith('/challenge')) {
            return http.Response(
              jsonEncode({
                'campaign': campaign(version: 2),
                'challenge': {
                  'id': 'challenge-issued',
                  'report_id': 'report-fresh',
                  'link_report_id': 'link-report-fresh',
                },
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
      final linkReport = await session.checkLinks(draft);
      expect(linkReport.status, NewsletterLinkReportStatus.clear);
      await session.approve(draft);

      final challengeRequest = requests.singleWhere(
        (r) => r.url.path.endsWith('/challenge'),
      );
      final challengeBody = jsonDecode(challengeRequest.body) as Map;
      expect(challengeBody['action'], 'approve');
      expect(challengeBody['report_id'], 'report-fresh');
      expect(challengeBody['link_report_id'], 'link-report-fresh');
      expect(challengeBody['expected_version'], 2);
      final approveRequest = requests.singleWhere(
        (r) => r.url.path.endsWith('/approve'),
      );
      expect(jsonDecode(approveRequest.body), {
        'business_id': 'studio',
        'expected_version': 2,
        'review_id': 'campaign-a:2',
        'report_id': 'report-fresh',
        'link_report_id': 'link-report-fresh',
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

  test('uncertain links require the audited override challenge', () async {
    final requests = <http.Request>[];
    final api = CentralEmailApi(
      origin: Uri.parse('https://example.test'),
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/save')) {
          return http.Response(
            jsonEncode({'campaign': campaign(version: 2)}),
            200,
          );
        }
        if (request.url.path.endsWith('/review')) {
          return http.Response(
            jsonEncode({
              'campaign': campaign(version: 2),
              'review': {
                'id': 'review-a2',
                'version': 2,
                'eligible_count': 1,
                'complete': true,
                'report_id': 'preflight-a2',
                'expires_at': DateTime.now().millisecondsSinceEpoch + 600000,
                'blocking_checks': <Object>[],
              },
            }),
            200,
          );
        }
        final body = jsonDecode(request.body) as Map;
        if (request.url.path.endsWith('/challenge')) {
          expect(body['action'], 'approve_link_override');
          expect(body['link_report_id'], 'links-a2');
          return http.Response(
            jsonEncode({
              'campaign': campaign(version: 2),
              'challenge': {
                'id': 'challenge-override',
                'report_id': 'preflight-a2',
                'link_report_id': 'links-a2',
              },
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/approve')) {
          expect(body['link_report_id'], 'links-a2');
          expect(body['override_link_report_id'], 'links-a2');
          expect(body['challenge_id'], 'challenge-override');
          return http.Response(
            jsonEncode({'campaign': campaign(version: 2, state: 'sending')}),
            200,
          );
        }
        return http.Response('{}', 404);
      }),
    );
    final session = CampaignEditorSession(api, business, campaign(version: 2));
    final draft = session.draft;
    await session.resolve(draft);
    session.linkReport = NewsletterLinkCheckReport(
      id: 'links-a2',
      campaignId: draft.id,
      revision: draft.revision,
      serverRevision: 2,
      destinationDigest: 'digest-a2',
      checkedAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      status: NewsletterLinkReportStatus.uncertain,
      blockingCount: 0,
      uncertainCount: 1,
      validCount: 0,
      findings: const [
        NewsletterLinkFinding(
          blockIds: ['button-a'],
          host: 'destination.example',
          status: NewsletterLinkFindingStatus.uncertain,
          reason: 'timeout',
        ),
      ],
      disclosure: const NewsletterLinkCheckDisclosure(
        externalRequests: true,
        possibleDestinationSideEffect: true,
        methodPolicy: 'HEAD; bounded GET only on 405/501',
      ),
    );
    await expectLater(
      session.approve(draft),
      throwsA(isA<EmailApiException>()),
    );
    expect(
      requests.where((request) => request.url.path.endsWith('/challenge')),
      isEmpty,
    );
    await session.approveWithLinkReport(draft, overrideUncertainLinks: true);
    expect(
      requests.map((request) => request.url.path.split('/').last),
      containsAllInOrder(['challenge', 'approve']),
    );
  });

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

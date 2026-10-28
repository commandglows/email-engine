import 'dart:convert';

import 'package:email_mailbox_client/email_mailbox_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';

const _base = '/api/bridge/email-campaigns/firebase';
const _token = 'synthetic-firebase-token';

/// UTF-8 body: `http.Response(String)` would encode accented text as Latin-1.
http.Response _response(String body, int status) => http.Response.bytes(
  utf8.encode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> _campaign({
  String id = 'camp_1',
  int version = 3,
  String state = 'draft',
  String body = 'Corps',
}) => {
  'campaign': {
    'id': id,
    'version': version,
    'business_id': 'shipglows',
    'title': 'Nouveauté',
    'audience_id': 'product-updates',
    'locale': 'fr',
    'subject': 'Objet',
    'preheader': '',
    'blocks': [
      {'id': 'body-1', 'type': 'rich_text', 'text': body},
    ],
    'state': state,
    'scheduled_at': null,
    'updated_at': '2026-10-01T10:00:00.000Z',
    'counters': {'queued': 0, 'delivered': 0, 'submitted': 0},
    'eligible_count': 0,
    'excluded_count': 0,
  },
  'campaign_id': id,
  'state': state,
  'block_reason': null,
};

/// A completed receipt whose counters record one delivery.
Map<String, dynamic> _completedWithDelivery() {
  final receipt = _campaign(id: 'camp_b', state: 'completed');
  (receipt['campaign'] as Map<String, dynamic>)['counters'] = {'delivered': 2};
  return receipt;
}

/// A receipt whose review reports how far the snapshot has got.
Map<String, dynamic> _snapshotReceipt({
  required bool complete,
  int eligible = 0,
  int version = 3,
}) => {
  ..._campaign(version: version),
  'review': {
    'id': 'camp_1:3',
    'complete': complete,
    'eligible_count': eligible,
    'excluded_count': 0,
    'report_id': 'rep_1',
    'text': 'Aperçu',
    'blocking_checks': <Object>[],
  },
};

CentralCampaignBridgeApi _api(
  Future<http.Response> Function(http.Request request) handler, {
  String? token = _token,
}) => CentralCampaignBridgeApi.create(
  origin: Uri.parse('https://synthetic.test'),
  accessTokenProvider: () async => token,
  client: MockClient(handler),
);

void main() {
  test('context parses granted businesses and a secure console URL', () async {
    final api = _api((request) async {
      expect(request.url.path, '$_base/context');
      expect(request.headers['Authorization'], 'Bearer $_token');
      expect(request.followRedirects, isFalse);
      return _response(
        jsonEncode({
          'businesses': [
            {
              'id': 'shipglows',
              'brand': 'ShipGlows',
              'audiences': [
                {'id': 'product-updates', 'purpose': 'Mises à jour'},
              ],
            },
            {'id': 'contentglows', 'brand': 'ContentGlows', 'audiences': []},
          ],
          'console_url': 'https://commandglows.test/email-engine/',
        }),
        200,
      );
    });
    final context = await api.context();
    expect(context.businesses.map((b) => b.brand), [
      'ShipGlows',
      'ContentGlows',
    ]);
    expect(context.businesses.first.defaultAudience?.id, 'product-updates');
    expect(context.businesses.last.defaultAudience, isNull);
    expect(context.consoleUri.host, 'commandglows.test');
    api.api.close();
  });

  test('context refuses a console URL that is not HTTPS', () async {
    final api = _api(
      (_) async => _response(
        jsonEncode({
          'businesses': <Object>[],
          'console_url': 'http://commandglows.test/',
        }),
        200,
      ),
    );
    await expectLater(
      api.context(),
      throwsA(
        isA<EmailApiException>().having(
          (e) => e.code,
          'code',
          'invalid_backend_receipt',
        ),
      ),
    );
    api.api.close();
  });

  test('a missing bearer sends nothing', () async {
    var requests = 0;
    final api = _api((_) async {
      requests++;
      return _response('{}', 200);
    }, token: null);
    await expectLater(
      api.listCampaigns(businessId: 'shipglows'),
      throwsA(
        isA<EmailApiException>().having((e) => e.code, 'code', 'auth_required'),
      ),
    );
    expect(requests, 0);
    api.api.close();
  });

  test('list sends the business and parses the page and cursor', () async {
    final api = _api((request) async {
      expect(request.url.path, '$_base/campaigns');
      expect(request.url.queryParameters['business_id'], 'shipglows');
      expect(request.url.queryParameters['view'], 'list');
      expect(request.url.queryParameters['cursor'], 'next-1');
      return _response(
        jsonEncode({
          'page': [_campaign()],
          'cursor': 'next-2',
          'complete': false,
        }),
        200,
      );
    });
    final page = await api.listCampaigns(
      businessId: 'shipglows',
      cursor: 'next-1',
    );
    expect(page.items.single.id, 'camp_1');
    expect(page.items.single.counters['delivered'], 0);
    expect(page.cursor, 'next-2');
    api.api.close();
  });

  test(
    'create posts a machine create with a bounded idempotency key',
    () async {
      late Map<String, dynamic> sent;
      final api = _api((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '$_base/campaigns');
        final key = request.headers['Idempotency-Key']!;
        expect(key.length, inInclusiveRange(16, 128));
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return _response(jsonEncode(_campaign()), 200);
      });
      final receipt = await api.create(
        businessId: 'shipglows',
        audienceId: 'product-updates',
        draft: const ProductUpdateDraft(title: 'Nouveauté'),
      );
      expect(sent['operation'], 'create');
      expect(sent.containsKey('expected_version'), isFalse);
      expect(sent['audience_id'], 'product-updates');
      expect(sent['locale'], 'fr');
      expect(receipt.campaign.version, 3);
      api.api.close();
    },
  );

  test('revise and snapshot carry the expected version', () async {
    final operations = <String>[];
    final api = _api((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      operations.add('${body['operation']}:${body['expected_version']}');
      if (body['operation'] == 'snapshot') {
        return _response(
          jsonEncode({
            ..._campaign(version: 4),
            'review': {
              'id': 'review_1',
              'complete': true,
              'eligible_count': 12,
              'excluded_count': 1,
              'text': 'Aperçu',
              'report_id': 'report_1',
              'expires_at': 1790000000000,
              'blocking_checks': <Object>[],
            },
          }),
          200,
        );
      }
      return _response(jsonEncode(_campaign(version: 4)), 200);
    });
    await api.revise(
      businessId: 'shipglows',
      campaignId: 'camp_1',
      expectedVersion: 3,
      audienceId: 'product-updates',
      draft: const ProductUpdateDraft(
        title: 'Nouveauté',
        subject: 'Objet',
        bodyMarkdown: 'Corps',
      ),
    );
    final snapshot = await api.snapshot(
      businessId: 'shipglows',
      campaignId: 'camp_1',
      expectedVersion: 4,
    );
    expect(operations, ['revise:3', 'snapshot:4']);
    expect(snapshot.review?.eligibleCount, 12);
    expect(snapshot.review?.blockingCount, 0);
    api.api.close();
  });

  test('approval refusal keeps console_required, not forbidden', () async {
    final api = _api(
      (_) async => _response(
        jsonEncode({
          'error': {'code': 'console_required'},
        }),
        403,
      ),
    );
    await expectLater(
      api.snapshot(
        businessId: 'shipglows',
        campaignId: 'camp_1',
        expectedVersion: 1,
      ),
      throwsA(
        isA<EmailApiException>().having(
          (e) => e.code,
          'code',
          'console_required',
        ),
      ),
    );
    api.api.close();
  });

  test('a 403 without a known code stays forbidden', () async {
    final api = _api(
      (_) async => _response(
        jsonEncode({
          'error': {'code': 'forbidden'},
        }),
        403,
      ),
    );
    await expectLater(
      api.status(businessId: 'shipglows', campaignId: 'camp_1'),
      throwsA(
        isA<EmailApiException>().having((e) => e.code, 'code', 'forbidden'),
      ),
    );
    api.api.close();
  });

  test('delete requires the server confirmation', () async {
    final api = _api((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['operation'], 'delete');
      return _response(jsonEncode({'deleted': true}), 200);
    });
    await api.delete(
      businessId: 'shipglows',
      campaignId: 'camp_1',
      expectedVersion: 1,
    );
    api.api.close();
  });

  test(
    'repository filters the loaded page and refuses an empty title',
    () async {
      final api = _api((request) async {
        return _response(
          jsonEncode({
            'page': [_campaign(id: 'camp_a'), _completedWithDelivery()],
            'cursor': null,
            'complete': true,
          }),
          200,
        );
      });
      final repository = CentralCampaignBridgeRepository(
        api: api,
        businessId: 'shipglows',
        audienceId: 'product-updates',
      );
      final drafts = await repository.list(
        status: NewsletterCampaignStatus.draft,
      );
      expect(drafts.items.map((c) => c.id), ['camp_a']);
      final delivered = await repository.list(
        status: NewsletterCampaignStatus.delivered,
      );
      expect(delivered.items.map((c) => c.id), ['camp_b']);
      await expectLater(
        repository.create(title: '   '),
        throwsA(
          isA<EmailApiException>().having(
            (e) => e.code,
            'code',
            'invalid_input',
          ),
        ),
      );
      api.api.close();
    },
  );

  group('ProductUpdateDraft', () {
    test('splits Markdown on blank lines into rich_text blocks', () {
      final long = List.filled(3000, 'mot').join(' ');
      final blocks = ProductUpdateDraft(
        title: 'Nouveauté',
        bodyMarkdown: 'Premier\n\n$long\n\n$long\n\n\nDernier',
      ).richTextBlocks();
      expect(blocks.map((b) => b.type).toSet(), {'rich_text'});
      expect(blocks.map((b) => b.id), ['body-1', 'body-2']);
      expect(
        blocks.every((b) => b.text.length <= productUpdateRichTextLimit),
        isTrue,
      );
      expect(blocks.last.text.endsWith('Dernier'), isTrue);
    });

    test('reports French issues for each refused rule', () {
      expect(
        const ProductUpdateDraft(title: '').validate(),
        contains('Le nom interne est requis.'),
      );
      expect(
        const ProductUpdateDraft(
          title: 'Nouveauté',
          subject: 'Objet\nligne deux',
        ).validate(),
        contains('Un champ contient des caractères interdits.'),
      );
      expect(
        const ProductUpdateDraft(
          title: 'Nouveauté',
          bodyMarkdown: 'Bonjour {{ name }}',
        ).validate(),
        contains('Le corps contient des caractères interdits.'),
      );
      expect(
        const ProductUpdateDraft(
          title: 'Nouveauté',
          bodyMarkdown: 'Corps',
        ).validate(forPreparation: true),
        contains('L’objet est requis avant de préparer la mise à jour.'),
      );
      final huge = List.filled(5000, 'x'.padRight(10, 'x')).join('\n\n');
      expect(
        ProductUpdateDraft(title: 'Nouveauté', bodyMarkdown: huge).validate(),
        contains('Le corps dépasse la limite de 48 000 caractères.'),
      );
    });

    test('a valid draft produces the bridge content fields', () {
      const draft = ProductUpdateDraft(
        title: ' Nouveauté ',
        subject: 'Objet',
        preheader: 'Aperçu',
        bodyMarkdown: 'Un paragraphe.',
      );
      expect(draft.validate(forPreparation: true), isEmpty);
      final fields = draft.contentFields(audienceId: 'product-updates');
      expect(fields['title'], 'Nouveauté');
      expect(fields['blocks'], [
        {'id': 'body-1', 'type': 'rich_text', 'text': 'Un paragraphe.'},
      ]);
    });
  });

  group('campaign bridge contract', () {
    test(
      'snapshotUntilComplete pages to the end with a fresh key per page',
      () async {
        final keys = <String>[];
        final versions = <Object?>[];
        var calls = 0;
        final api = _api((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['operation'], 'snapshot');
          versions.add(body['expected_version']);
          keys.add(request.headers['Idempotency-Key']!);
          calls += 1;
          // Each page leaves the campaign one version further on.
          return _response(
            jsonEncode(
              _snapshotReceipt(
                complete: calls == 3,
                eligible: calls,
                version: 3 + calls,
              ),
            ),
            200,
          );
        });
        final progress = <int>[];
        final receipt = await api.snapshotUntilComplete(
          businessId: 'shipglows',
          campaignId: 'camp_1',
          expectedVersion: 3,
          onProgress: (page, _) => progress.add(page),
        );
        expect(receipt.review!.complete, isTrue);
        expect(receipt.review!.eligibleCount, 3);
        expect(progress, [1, 2, 3]);
        // The version carried forward is the one each receipt reported.
        expect(versions, [3, 4, 5]);
        expect(keys.toSet(), hasLength(3));
        api.api.close();
      },
    );

    test('snapshotUntilComplete stops at the page cap', () async {
      var calls = 0;
      final api = _api((_) async {
        calls += 1;
        return _response(jsonEncode(_snapshotReceipt(complete: false)), 200);
      });
      await expectLater(
        api.snapshotUntilComplete(
          businessId: 'shipglows',
          campaignId: 'camp_1',
          expectedVersion: 3,
          maxPages: 2,
        ),
        throwsA(
          isA<EmailApiException>().having(
            (e) => e.code,
            'code',
            'snapshot_page_limit',
          ),
        ),
      );
      expect(calls, 2);
      api.api.close();
    });

    test('a 429 waits for Retry-After and retries the same page', () async {
      var calls = 0;
      final waits = <Duration>[];
      final api = _api((_) async {
        calls += 1;
        if (calls == 1) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'error': {'code': 'rate_limited'},
              }),
            ),
            429,
            headers: {
              'content-type': 'application/json; charset=utf-8',
              'Retry-After': '7',
            },
          );
        }
        return _response(jsonEncode(_snapshotReceipt(complete: true)), 200);
      });
      final receipt = await api.snapshotUntilComplete(
        businessId: 'shipglows',
        campaignId: 'camp_1',
        expectedVersion: 3,
        wait: (delay) async => waits.add(delay),
      );
      expect(receipt.review!.complete, isTrue);
      expect(calls, 2);
      expect(waits, [const Duration(seconds: 7)]);
      api.api.close();
    });

    test('a 429 with a non-JSON body is a typed rate limit', () async {
      final api = _api(
        (_) async => http.Response(
          '<html>busy</html>',
          429,
          headers: {'Retry-After': '12'},
        ),
      );
      await expectLater(
        api.snapshot(
          businessId: 'shipglows',
          campaignId: 'camp_1',
          expectedVersion: 1,
        ),
        throwsA(
          isA<EmailApiException>()
              .having((e) => e.code, 'code', 'rate_limited')
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(seconds: 12),
              ),
        ),
      );
      api.api.close();
    });

    test(
      'a 5xx with a non-JSON body is an outage that keeps its key',
      () async {
        final keys = <String>[];
        var calls = 0;
        final api = _api((request) async {
          keys.add(request.headers['Idempotency-Key']!);
          calls += 1;
          if (calls == 1) return http.Response('<html>oops</html>', 502);
          return _response(jsonEncode(_snapshotReceipt(complete: true)), 200);
        });
        await expectLater(
          api.snapshot(
            businessId: 'shipglows',
            campaignId: 'camp_1',
            expectedVersion: 1,
          ),
          throwsA(
            isA<EmailApiException>().having(
              (e) => e.code,
              'code',
              'service_unavailable',
            ),
          ),
        );
        // The identical retry reuses the key: the first attempt may have run.
        await api.snapshot(
          businessId: 'shipglows',
          campaignId: 'camp_1',
          expectedVersion: 1,
        );
        expect(keys[1], keys[0]);
        api.api.close();
      },
    );

    test(
      'a refusal releases its key, so an identical retry gets a new one',
      () async {
        final keys = <String>[];
        var calls = 0;
        final api = _api((request) async {
          keys.add(request.headers['Idempotency-Key']!);
          calls += 1;
          if (calls == 1) {
            return _response(
              jsonEncode({
                'error': {'code': 'invalid_input'},
              }),
              422,
            );
          }
          return _response(jsonEncode(_snapshotReceipt(complete: true)), 200);
        });
        await expectLater(
          api.snapshot(
            businessId: 'shipglows',
            campaignId: 'camp_1',
            expectedVersion: 1,
          ),
          throwsA(isA<EmailApiException>()),
        );
        await api.snapshot(
          businessId: 'shipglows',
          campaignId: 'camp_1',
          expectedVersion: 1,
        );
        expect(keys[1], isNot(keys[0]));
        api.api.close();
      },
    );

    test('a token failure leaves no pending command behind', () async {
      final api = _api((_) async => _response('{}', 200), token: null);
      // Each call names another campaign, so each would hold its own key. Had
      // the keys stayed pending, the 128-command limit would trip.
      for (var i = 0; i < 130; i++) {
        await expectLater(
          api.snapshot(
            businessId: 'shipglows',
            campaignId: 'camp_$i',
            expectedVersion: 1,
          ),
          throwsA(
            isA<EmailApiException>().having(
              (e) => e.code,
              'code',
              'auth_required',
            ),
          ),
        );
      }
      api.api.close();
    });

    test(
      'an oversized command is refused before any request, in UTF-8 bytes',
      () async {
        var requests = 0;
        final api = _api((_) async {
          requests += 1;
          return _response('{}', 200);
        });
        // Three 20 000-character blocks pass the character limits, but each euro
        // sign takes three bytes: the body is far over the 64 KiB bridge cap.
        final euro = '€' * 20000;
        await expectLater(
          api.revise(
            businessId: 'shipglows',
            campaignId: 'camp_1',
            expectedVersion: 1,
            audienceId: 'product-updates',
            draft: ProductUpdateDraft(
              title: 'Nouveauté',
              bodyMarkdown: [euro, euro, euro].join('\n\n'),
            ),
          ),
          throwsA(
            isA<EmailApiException>().having(
              (e) => e.code,
              'code',
              'payload_too_large',
            ),
          ),
        );
        expect(requests, 0);
        api.api.close();
      },
    );

    test('the draft validator counts blocks in UTF-16 units', () {
      // 18 002 characters are 18 002 UTF-16 units: under the 48 000 cap.
      final euro = '€' * 9000;
      expect(
        ProductUpdateDraft(
          title: 'Nouveauté',
          bodyMarkdown: '$euro\n\n$euro',
        ).validate(),
        isNot(contains('Le corps dépasse la limite de 48 000 caractères.')),
      );
      // Six 9 000-character paragraphs: 54 000 units once serialized, over the cap.
      final long = 'x' * 9000;
      expect(
        ProductUpdateDraft(
          title: 'Nouveauté',
          bodyMarkdown: List.filled(6, long).join('\n\n'),
        ).validate(),
        contains('Le corps dépasse la limite de 48 000 caractères.'),
      );
    });

    test('a server 413 maps to payload_too_large', () async {
      final api = _api((_) async => http.Response('too large', 413));
      await expectLater(
        api.snapshot(
          businessId: 'shipglows',
          campaignId: 'camp_1',
          expectedVersion: 1,
        ),
        throwsA(
          isA<EmailApiException>().having(
            (e) => e.code,
            'code',
            'payload_too_large',
          ),
        ),
      );
      api.api.close();
    });

    test('list asks for at most ten campaigns', () async {
      final limits = <String?>[];
      final api = _api((request) async {
        limits.add(request.url.queryParameters['limit']);
        return _response(jsonEncode({'page': <Object>[], 'cursor': null}), 200);
      });
      await api.listCampaigns(businessId: 'shipglows');
      await api.listCampaigns(businessId: 'shipglows', limit: 50);
      expect(limits, ['10', '10']);
      api.api.close();
    });

    test(
      'the default audience is the product-updates one, never a fallback',
      () {
        const newsletter = ProductUpdateAudience(
          id: 'newsletter',
          purpose: 'Infolettre',
        );
        const updates = ProductUpdateAudience(
          id: 'product-updates',
          purpose: 'Mises à jour produit',
        );
        const byPurpose = ProductUpdateAudience(
          id: 'maj',
          purpose: 'Product_Updates',
        );
        ProductUpdateBusiness business(List<ProductUpdateAudience> audiences) =>
            ProductUpdateBusiness(
              id: 'shipglows',
              brand: 'ShipGlows',
              audiences: audiences,
            );

        expect(business([]).defaultAudience, isNull);
        expect(business([newsletter]).defaultAudience, isNull);
        expect(
          business([newsletter, updates]).defaultAudience?.id,
          'product-updates',
        );
        expect(business([newsletter, byPurpose]).defaultAudience?.id, 'maj');
      },
    );

    test(
      'a 503 that names a definitive unavailability releases its key',
      () async {
        final keys = <String>[];
        var calls = 0;
        final api = _api((request) async {
          keys.add(request.headers['Idempotency-Key']!);
          calls += 1;
          if (calls == 1) {
            return _response(
              jsonEncode({
                'error': {'code': 'configuration_unavailable'},
              }),
              503,
            );
          }
          return _response(jsonEncode(_snapshotReceipt(complete: true)), 200);
        });
        await expectLater(
          api.snapshot(
            businessId: 'shipglows',
            campaignId: 'camp_1',
            expectedVersion: 1,
          ),
          throwsA(
            isA<EmailApiException>().having(
              (e) => e.code,
              'code',
              'configuration_unavailable',
            ),
          ),
        );
        // Refused before any work: the identical retry gets a fresh key.
        await api.snapshot(
          businessId: 'shipglows',
          campaignId: 'camp_1',
          expectedVersion: 1,
        );
        expect(keys[1], isNot(keys[0]));
        api.api.close();
      },
    );

    test('campaignStatus carries the snapshot state of the status receipt', () async {
      final api = _api((request) async {
        expect(request.url.queryParameters['view'], 'status');
        return _response(
          jsonEncode({
            ..._campaign(),
            'snapshot': {'complete': true, 'eligible': 3, 'excluded': 0},
          }),
          200,
        );
      });
      final status = await api.campaignStatus(
        businessId: 'shipglows',
        campaignId: 'camp_1',
      );
      expect(status.snapshotComplete, isTrue);
      expect(status.campaign.id, 'camp_1');
      expect(status.campaign.version, 3);
      api.api.close();
    });

    test('campaign states map to the studio statuses', () {
      NewsletterCampaignStatus statusOf(String state) => newsletterStatusOf(
        productUpdateCampaignFromJson(_campaign(state: state)),
      );

      expect(statusOf('draft'), NewsletterCampaignStatus.draft);
      expect(statusOf('scheduled'), NewsletterCampaignStatus.scheduled);
      expect(statusOf('sending'), NewsletterCampaignStatus.sending);
      expect(statusOf('running'), NewsletterCampaignStatus.sending);
      expect(statusOf('fanout_complete'), NewsletterCampaignStatus.sending);
      expect(statusOf('paused'), NewsletterCampaignStatus.suspended);
      expect(statusOf('suspended'), NewsletterCampaignStatus.suspended);
      expect(statusOf('cancelled'), NewsletterCampaignStatus.cancelled);
      expect(statusOf('completed'), NewsletterCampaignStatus.completed);
      expect(statusOf('failed'), NewsletterCampaignStatus.failed);
      expect(
        statusOf('partially_failed'),
        NewsletterCampaignStatus.partiallyDelivered,
      );
      expect(statusOf('something_new'), NewsletterCampaignStatus.unknown);
      expect(
        newsletterStatusOf(
          productUpdateCampaignFromJson(_completedWithDelivery()),
        ),
        NewsletterCampaignStatus.delivered,
      );
    });

    test(
      'loopback origins accept IPv6 loopback and nothing else over HTTP',
      () {
        for (final origin in [
          'http://[::1]:8787',
          'http://localhost:3000',
          'http://127.0.0.1:3000',
        ]) {
          expect(
            () => CentralCampaignBridgeApi.create(
              origin: Uri.parse(origin),
              client: MockClient((_) async => _response('{}', 200)),
            ),
            returnsNormally,
            reason: origin,
          );
        }
        expect(
          () => CentralCampaignBridgeApi.create(
            origin: Uri.parse('http://example.test'),
            client: MockClient((_) async => _response('{}', 200)),
          ),
          throwsArgumentError,
        );
      },
    );

    test('a console URL on IPv6 loopback is accepted', () async {
      final api = _api(
        (_) async => _response(
          jsonEncode({
            'businesses': <Object>[],
            'console_url': 'http://[::1]:8787/console/',
          }),
          200,
        ),
      );
      final context = await api.context();
      expect(context.consoleUri.host, '::1');
      api.api.close();
    });

    test('refusals carry their own French wording', () async {
      final api = _api(
        (_) async => _response(
          jsonEncode({
            'error': {'code': 'invalid_state'},
          }),
          409,
        ),
      );
      await expectLater(
        api.cancel(
          businessId: 'shipglows',
          campaignId: 'camp_1',
          expectedVersion: 1,
        ),
        throwsA(
          isA<EmailApiException>().having(
            (e) => e.message,
            'message',
            'Cette mise à jour est déjà terminée ou annulée.',
          ),
        ),
      );
      api.api.close();

      expect(
        const EmailApiException('invalid_state', operation: 'snapshot').message,
        contains('brouillon'),
      );
      expect(
        const EmailApiException('invalid_state').message,
        'Cette action n’est pas possible dans l’état actuel de la mise à jour.',
      );
      expect(
        const EmailApiException('review_required').message,
        contains('préparation doit être refaite'),
      );
      expect(
        const EmailApiException('idempotency_conflict').message,
        contains('autre contenu'),
      );
      expect(
        const EmailApiException('payload_too_large').message,
        contains('64 Ko'),
      );
      expect(
        EmailApiException(
          'rate_limited',
          retryAfter: const Duration(seconds: 30),
        ).message,
        contains('30 s'),
      );
      expect(
        const EmailApiException('console_required').message,
        contains('console CommandGlows'),
      );
      expect(
        const EmailApiException('snapshot_page_limit').message,
        contains('Relancez'),
      );
    });
  });

  group('bridge provider route', () {
    test('the default provider is firebase', () {
      final api = CentralCampaignBridgeApi.create(
        origin: Uri.parse('https://synthetic.test'),
        client: MockClient((_) async => _response('{}', 200)),
      );
      expect(api.provider, CampaignBridgeProvider.firebase);
      expect(api.api.apiBasePath, _base);
      api.api.close();
    });

    test(
      'shipglows_clerk targets its own route with the Clerk bearer',
      () async {
        const clerkBase = '/api/bridge/email-campaigns/shipglows_clerk';
        final api = CentralCampaignBridgeApi.create(
          origin: Uri.parse('https://synthetic.test'),
          provider: CampaignBridgeProvider.shipglowsClerk,
          accessTokenProvider: () async => _token,
          client: MockClient((request) async {
            expect(request.url.path, '$clerkBase/context');
            expect(request.headers['Authorization'], 'Bearer $_token');
            return _response(
              jsonEncode({
                'businesses': <Object>[],
                'console_url': 'https://commandglows.test/email-engine/',
              }),
              200,
            );
          }),
        );
        expect(api.provider, CampaignBridgeProvider.shipglowsClerk);
        await api.context();
        api.api.close();
      },
    );

    test('a constructed api on another route is refused', () {
      final client = MockClient((_) async => _response('{}', 200));
      final firebaseApi = CentralEmailApi(
        origin: Uri.parse('https://synthetic.test'),
        client: client,
        apiBasePath: _base,
      );
      expect(
        () => CentralCampaignBridgeApi(
          firebaseApi,
          provider: CampaignBridgeProvider.shipglowsClerk,
        ),
        throwsArgumentError,
      );
      firebaseApi.close();
    });
  });
}

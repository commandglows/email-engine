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
    expect(context.businesses.map((b) => b.brand), ['ShipGlows', 'ContentGlows']);
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

  test('create posts a machine create with a bounded idempotency key', () async {
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
  });

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

  test('repository filters the loaded page and refuses an empty title', () async {
    final api = _api((request) async {
      return _response(
        jsonEncode({
          'page': [
            _campaign(id: 'camp_a'),
            _completedWithDelivery(),
          ],
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
    final drafts = await repository.list(status: NewsletterCampaignStatus.draft);
    expect(drafts.items.map((c) => c.id), ['camp_a']);
    final delivered = await repository.list(
      status: NewsletterCampaignStatus.delivered,
    );
    expect(delivered.items.map((c) => c.id), ['camp_b']);
    await expectLater(
      repository.create(title: '   '),
      throwsA(
        isA<EmailApiException>().having((e) => e.code, 'code', 'invalid_input'),
      ),
    );
    api.api.close();
  });

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
}

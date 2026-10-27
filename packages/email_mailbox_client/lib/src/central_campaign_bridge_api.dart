import 'package:http/http.dart' as http;
import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';

import 'campaign_bridge_models.dart';
import 'central_email_api.dart';

/// Product-update campaigns through the Firebase-authenticated CommandGlows
/// bridge. Transport, bearer injection, the no-redirect rule, the response cap
/// and Idempotency-Key handling are those of [CentralEmailApi]: one identical
/// uncertain command reuses its key, and an edited command gets a new one.
///
/// Approval, challenge and resume are not offered here. The bridge refuses them
/// with `console_required`, and the app sends the operator to the console.
class CentralCampaignBridgeApi {
  CentralCampaignBridgeApi(this.api);

  /// Factory for hosts: an injectable [http.Client] and a short-lived bearer
  /// supplier. The origin rules are those of [CentralEmailApi].
  factory CentralCampaignBridgeApi.create({
    required Uri origin,
    required http.Client client,
    EmailAccessTokenProvider? accessTokenProvider,
  }) => CentralCampaignBridgeApi(
    CentralEmailApi(
      origin: origin,
      client: client,
      accessTokenProvider: accessTokenProvider,
      apiBasePath: apiBasePath,
    ),
  );

  static const apiBasePath = '/api/bridge/email-campaigns/firebase';

  final CentralEmailApi api;

  Future<ProductUpdateContext> context() async =>
      productUpdateContextFromJson(await api.get('context'));

  /// Newest first. The bridge has no state filter, so the workspace filters
  /// the returned page only.
  Future<ProductUpdateCampaignPage> listCampaigns({
    required String businessId,
    String? cursor,
    int limit = 25,
  }) async {
    final json = await api.get('campaigns', {
      'business_id': businessId,
      'view': 'list',
      'limit': '${limit.clamp(1, 100)}',
      'cursor': ?cursor,
    });
    final rows = json['page'];
    final next = json['cursor'];
    if (rows is! List || (next != null && next is! String)) {
      throw const EmailApiException('invalid_backend_receipt');
    }
    return ProductUpdateCampaignPage(
      items: [
        for (final row in rows)
          if (row is Map<String, dynamic>)
            productUpdateCampaignFromJson(row)
          else
            throw const EmailApiException('invalid_backend_receipt'),
      ],
      cursor: next as String?,
    );
  }

  Future<ProductUpdateCampaign> status({
    required String businessId,
    required String campaignId,
  }) async => productUpdateCampaignFromJson(
    await api.get('campaigns', {
      'business_id': businessId,
      'view': 'status',
      'campaign_id': campaignId,
    }),
  );

  /// Rendered plain text of the stored version, for review before approval.
  Future<String> preview({
    required String businessId,
    required String campaignId,
  }) async {
    final json = await api.get('campaigns', {
      'business_id': businessId,
      'view': 'preview',
      'campaign_id': campaignId,
    });
    final rendered = json['rendered'];
    if (rendered is! Map || rendered['text'] is! String) {
      throw const EmailApiException('invalid_backend_receipt');
    }
    return rendered['text'] as String;
  }

  Future<ProductUpdateReceipt> create({
    required String businessId,
    required String audienceId,
    required ProductUpdateDraft draft,
  }) async {
    final json = await _command('create', {
      'business_id': businessId,
      ...draft.contentFields(audienceId: audienceId),
    });
    return productUpdateReceiptFromJson(json);
  }

  /// Optimistic: [expectedVersion] must be the version last received.
  Future<ProductUpdateReceipt> revise({
    required String businessId,
    required String campaignId,
    required int expectedVersion,
    required String audienceId,
    required ProductUpdateDraft draft,
  }) async {
    final json = await _command('revise', {
      'business_id': businessId,
      'campaign_id': campaignId,
      'expected_version': expectedVersion,
      ...draft.contentFields(audienceId: audienceId),
    });
    return productUpdateReceiptFromJson(json);
  }

  /// Evaluates the audience and returns the review that the console approves.
  Future<ProductUpdateReceipt> snapshot({
    required String businessId,
    required String campaignId,
    required int expectedVersion,
  }) async => productUpdateReceiptFromJson(
    await _command('snapshot', {
      'business_id': businessId,
      'campaign_id': campaignId,
      'expected_version': expectedVersion,
    }),
  );

  Future<ProductUpdateReceipt> pause({
    required String businessId,
    required String campaignId,
    required int expectedVersion,
  }) async => productUpdateReceiptFromJson(
    await _command('pause', {
      'business_id': businessId,
      'campaign_id': campaignId,
      'expected_version': expectedVersion,
    }),
  );

  Future<ProductUpdateReceipt> cancel({
    required String businessId,
    required String campaignId,
    required int expectedVersion,
  }) async => productUpdateReceiptFromJson(
    await _command('cancel', {
      'business_id': businessId,
      'campaign_id': campaignId,
      'expected_version': expectedVersion,
    }),
  );

  /// Only a draft can be deleted; the server answers `{deleted: true}`.
  Future<void> delete({
    required String businessId,
    required String campaignId,
    required int expectedVersion,
  }) async {
    final json = await _command('delete', {
      'business_id': businessId,
      'campaign_id': campaignId,
      'expected_version': expectedVersion,
    });
    if (json['deleted'] != true) {
      throw const EmailApiException('invalid_backend_receipt');
    }
  }

  Future<Map<String, dynamic>> _command(
    String operation,
    Map<String, dynamic> fields,
  ) => api.post('campaigns', {'operation': operation, ...fields});
}

/// One business's campaigns, shaped for the shared [CampaignWorkspace].
class CentralCampaignBridgeRepository implements NewsletterCampaignRepository {
  CentralCampaignBridgeRepository({
    required this.api,
    required this.businessId,
    required this.audienceId,
  });

  final CentralCampaignBridgeApi api;
  final String businessId;
  final String audienceId;

  @override
  Future<NewsletterCampaignPage> list({
    String? cursor,
    NewsletterCampaignStatus? status,
    int limit = 25,
  }) async {
    final page = await api.listCampaigns(
      businessId: businessId,
      cursor: cursor,
      limit: limit,
    );
    return NewsletterCampaignPage(
      items: [
        for (final campaign in page.items)
          if (status == null || newsletterStatusOf(campaign) == status)
            newsletterCampaignOf(campaign),
      ],
      nextCursor: page.cursor,
    );
  }

  @override
  Future<NewsletterCampaign> create({required String title}) async {
    final draft = ProductUpdateDraft(title: title);
    if (draft.validate().isNotEmpty) {
      throw const EmailApiException('invalid_input');
    }
    final receipt = await api.create(
      businessId: businessId,
      audienceId: audienceId,
      draft: draft,
    );
    return newsletterCampaignOf(receipt.campaign);
  }
}

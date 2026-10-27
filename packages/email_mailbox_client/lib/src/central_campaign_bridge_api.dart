import 'dart:convert';

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

  /// Newest first, at most [productUpdateListLimit] campaigns per page: a larger
  /// request is clamped. The bridge has no state filter, so the workspace filters
  /// the returned page only.
  Future<ProductUpdateCampaignPage> listCampaigns({
    required String businessId,
    String? cursor,
    int limit = productUpdateListLimit,
  }) async {
    final json = await api.get('campaigns', {
      'business_id': businessId,
      'view': 'list',
      'limit': '${limit.clamp(1, productUpdateListLimit)}',
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

  /// Evaluates one page of the audience and returns the review so far. The
  /// review is complete only when every page has been evaluated; see
  /// [snapshotUntilComplete]. The version does not change between pages.
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

  /// Runs `snapshot` page after page until the server reports the audience fully
  /// evaluated (`review.complete`), and returns that receipt. Only a complete
  /// review may be approved in the console.
  ///
  /// Every page is its own command with its own idempotency key: the transport
  /// releases a key once its command succeeds, so the next identical page gets a
  /// fresh one. A 429 is a refusal before work, so the same page is retried after
  /// the server's Retry-After, up to [maxRateRetries] times in a row. Progress is
  /// reported after each page through [onProgress]. Re-running after an error
  /// resumes where the server left off.
  Future<ProductUpdateReceipt> snapshotUntilComplete({
    required String businessId,
    required String campaignId,
    required int expectedVersion,
    void Function(int page, ProductUpdateReceipt receipt)? onProgress,
    int maxPages = productUpdateSnapshotPageCap,
    int maxRateRetries = 5,
    Future<void> Function(Duration delay)? wait,
  }) async {
    final sleep = wait ?? (delay) => Future<void>.delayed(delay);
    var rateRetries = 0;
    var page = 1;
    while (page <= maxPages) {
      final ProductUpdateReceipt receipt;
      try {
        receipt = await snapshot(
          businessId: businessId,
          campaignId: campaignId,
          expectedVersion: expectedVersion,
        );
      } on EmailApiException catch (error) {
        if (error.code != 'rate_limited' || rateRetries >= maxRateRetries) {
          rethrow;
        }
        rateRetries += 1;
        await sleep(error.retryAfter ?? const Duration(seconds: 2));
        continue;
      }
      rateRetries = 0;
      final review = receipt.review;
      if (review == null) {
        throw const EmailApiException('invalid_backend_receipt');
      }
      onProgress?.call(page, receipt);
      if (review.complete) return receipt;
      page += 1;
    }
    throw const EmailApiException('snapshot_page_limit');
  }

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

  /// Sends one machine command. The whole JSON body is capped at 64 KiB of
  /// UTF-8 before anything leaves the device, as the bridge caps it. A refusal
  /// keeps the operation name, so `invalid_state` gets its own wording.
  Future<Map<String, dynamic>> _command(
    String operation,
    Map<String, dynamic> fields,
  ) async {
    final body = {'operation': operation, ...fields};
    if (utf8.encode(jsonEncode(body)).length > productUpdateBridgeBodyBytes) {
      throw EmailApiException('payload_too_large', operation: operation);
    }
    try {
      return await api.post('campaigns', body);
    } on EmailApiException catch (error) {
      throw EmailApiException(
        error.code,
        operation: operation,
        retryAfter: error.retryAfter,
      );
    }
  }
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
    int limit = productUpdateListLimit,
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

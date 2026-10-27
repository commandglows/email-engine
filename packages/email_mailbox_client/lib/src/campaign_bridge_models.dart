import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';

import 'central_email_api.dart';

/// Content limits mirrored from the CommandGlows campaign validator. The
/// server stays authoritative; these checks only give early French feedback.
const productUpdateLocale = 'fr';
const productUpdateTitleLimit = 160;
const productUpdateSubjectLimit = 200;
const productUpdatePreheaderLimit = 300;
const productUpdateRichTextLimit = 20000;
const productUpdateMaxBlocks = 60;
const productUpdateBlocksJsonLimit = 48000;

/// Audience id that product updates target, one per business.
const productUpdateAudienceId = 'product-updates';

final _singleLineControl = RegExp(
  r'[\u0000-\u001f\u007f-\u009f  ‪-‮⁦-⁩]',
);
final _blockControl = RegExp(
  r'[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f‪-‮⁦-⁩]',
);
final _providerSyntax = RegExp(r'\{\{|\}\}');

EmailApiException _invalidReceipt() =>
    const EmailApiException('invalid_backend_receipt');

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) throw _invalidReceipt();
  return value;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) throw _invalidReceipt();
  return value;
}

Map<String, dynamic> _requiredMap(Object? value) {
  if (value is! Map) throw _invalidReceipt();
  return value.cast<String, dynamic>();
}

List<Object?> _requiredList(Object? value) {
  if (value is! List) throw _invalidReceipt();
  return value.cast<Object?>();
}

DateTime _instant(Object? value) {
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toUtc();
  }
  throw _invalidReceipt();
}

/// A relayed Uri only when it is HTTPS, or loopback HTTP for local development.
Uri? _secureUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasAuthority || uri.userInfo.isNotEmpty) return null;
  final loopback = const ['localhost', '127.0.0.1', '::1'].contains(uri.host);
  if (uri.scheme == 'https' || (uri.scheme == 'http' && loopback)) return uri;
  return null;
}

@immutable
class ProductUpdateAudience {
  const ProductUpdateAudience({required this.id, required this.purpose});
  final String id;
  final String purpose;
}

@immutable
class ProductUpdateBusiness {
  const ProductUpdateBusiness({
    required this.id,
    required this.brand,
    required this.audiences,
  });
  final String id;
  final String brand;
  final List<ProductUpdateAudience> audiences;

  /// The `product-updates` audience when granted, otherwise the first one.
  ProductUpdateAudience? get defaultAudience {
    for (final audience in audiences) {
      if (audience.id == productUpdateAudienceId) return audience;
    }
    return audiences.isEmpty ? null : audiences.first;
  }
}

@immutable
class ProductUpdateContext {
  const ProductUpdateContext({required this.businesses, required this.consoleUri});
  final List<ProductUpdateBusiness> businesses;

  /// Where approval, challenge and resume happen. Never approved from the app.
  final Uri consoleUri;
}

ProductUpdateContext productUpdateContextFromJson(Map<String, dynamic> json) {
  final rows = _requiredList(json['businesses']);
  final console = _secureUri(_requiredString(json, 'console_url'));
  if (console == null) throw _invalidReceipt();
  final businesses = <ProductUpdateBusiness>[];
  for (final raw in rows) {
    final row = _requiredMap(raw);
    final audiences = [
      for (final audience in _requiredList(row['audiences']))
        ProductUpdateAudience(
          id: _requiredString(_requiredMap(audience), 'id'),
          purpose: _requiredMap(audience)['purpose'] as String? ?? '',
        ),
    ];
    businesses.add(
      ProductUpdateBusiness(
        id: _requiredString(row, 'id'),
        brand: _requiredString(row, 'brand'),
        audiences: audiences,
      ),
    );
  }
  return ProductUpdateContext(businesses: businesses, consoleUri: console);
}

@immutable
class ProductUpdateBlock {
  const ProductUpdateBlock({
    required this.id,
    required this.type,
    required this.text,
  });
  final String id;
  final String type;
  final String text;
}

@immutable
class ProductUpdateReview {
  const ProductUpdateReview({
    required this.id,
    required this.complete,
    required this.eligibleCount,
    required this.excludedCount,
    required this.reportId,
    required this.blockingCount,
    required this.text,
    this.expiresAt,
  });
  final String id;
  final bool complete;
  final int eligibleCount;
  final int excludedCount;
  final String reportId;
  final int blockingCount;
  final String text;
  final DateTime? expiresAt;
}

ProductUpdateReview productUpdateReviewFromJson(Map<String, dynamic> json) {
  final blocking = _requiredList(json['blocking_checks']);
  return ProductUpdateReview(
    id: _requiredString(json, 'id'),
    complete: json['complete'] == true,
    eligibleCount: _requiredInt(json, 'eligible_count'),
    excludedCount: _requiredInt(json, 'excluded_count'),
    reportId: _requiredString(json, 'report_id'),
    blockingCount: blocking.length,
    text: json['text'] as String? ?? '',
    expiresAt: json['expires_at'] == null ? null : _instant(json['expires_at']),
  );
}

@immutable
class ProductUpdateCampaign {
  const ProductUpdateCampaign({
    required this.id,
    required this.version,
    required this.businessId,
    required this.title,
    required this.subject,
    required this.preheader,
    required this.audienceId,
    required this.state,
    required this.updatedAt,
    required this.eligibleCount,
    required this.counters,
    required this.blocks,
    this.blockReason,
    this.scheduledAt,
  });

  final String id;
  final int version;
  final String businessId;
  final String title;
  final String subject;
  final String preheader;
  final String audienceId;

  /// Machine state such as `draft`, `scheduled`, `paused` or `completed`.
  final String state;
  final String? blockReason;
  final DateTime updatedAt;
  final DateTime? scheduledAt;
  final int eligibleCount;
  final Map<String, int> counters;
  final List<ProductUpdateBlock> blocks;

  /// Rich-text blocks rejoined in order, the same text the editor wrote.
  String get bodyMarkdown => blocks
      .where((block) => block.type == 'rich_text')
      .map((block) => block.text)
      .join('\n\n');
}

ProductUpdateCampaign productUpdateCampaignFromJson(Map<String, dynamic> json) {
  final campaign = _requiredMap(json['campaign']);
  final counters = <String, int>{};
  final rawCounters = campaign['counters'];
  if (rawCounters is Map) {
    for (final entry in rawCounters.entries) {
      final value = entry.value;
      if (entry.key is String && value is num) {
        counters[entry.key as String] = value.toInt();
      }
    }
  }
  final blocks = [
    for (final raw in _requiredList(campaign['blocks']))
      ProductUpdateBlock(
        id: _requiredString(_requiredMap(raw), 'id'),
        type: _requiredString(_requiredMap(raw), 'type'),
        text: _requiredMap(raw)['text'] as String? ?? '',
      ),
  ];
  return ProductUpdateCampaign(
    id: _requiredString(campaign, 'id'),
    version: _requiredInt(campaign, 'version'),
    businessId: _requiredString(campaign, 'business_id'),
    title: _requiredString(campaign, 'title'),
    subject: campaign['subject'] as String? ?? '',
    preheader: campaign['preheader'] as String? ?? '',
    audienceId: campaign['audience_id'] as String? ?? '',
    state: _requiredString(campaign, 'state'),
    blockReason: json['block_reason'] as String?,
    updatedAt: _instant(campaign['updated_at']),
    scheduledAt: campaign['scheduled_at'] == null
        ? null
        : _instant(campaign['scheduled_at']),
    eligibleCount: (campaign['eligible_count'] as num?)?.toInt() ?? 0,
    counters: counters,
    blocks: blocks,
  );
}

/// A write or status receipt: the campaign, plus a review after a snapshot.
@immutable
class ProductUpdateReceipt {
  const ProductUpdateReceipt({required this.campaign, this.review});
  final ProductUpdateCampaign campaign;
  final ProductUpdateReview? review;
}

ProductUpdateReceipt productUpdateReceiptFromJson(Map<String, dynamic> json) {
  final review = json['review'];
  return ProductUpdateReceipt(
    campaign: productUpdateCampaignFromJson(json),
    review: review == null
        ? null
        : productUpdateReviewFromJson(_requiredMap(review)),
  );
}

@immutable
class ProductUpdateCampaignPage {
  const ProductUpdateCampaignPage({required this.items, this.cursor});
  final List<ProductUpdateCampaign> items;
  final String? cursor;
}

/// Content of one product update. Blocks are `rich_text` only.
@immutable
class ProductUpdateDraft {
  const ProductUpdateDraft({
    this.title = '',
    this.subject = '',
    this.preheader = '',
    this.bodyMarkdown = '',
  });

  final String title;
  final String subject;
  final String preheader;
  final String bodyMarkdown;

  /// French messages for every rule the bridge would refuse. Empty means the
  /// draft can be saved. `forPreparation` adds the requirements of approval.
  List<String> validate({bool forPreparation = false}) {
    final issues = <String>[];
    final name = title.trim();
    if (name.isEmpty) {
      issues.add('Le nom interne est requis.');
    } else if (name.length > productUpdateTitleLimit) {
      issues.add('Le nom interne dépasse $productUpdateTitleLimit caractères.');
    }
    final cleanSubject = subject.trim();
    if (cleanSubject.length > productUpdateSubjectLimit) {
      issues.add('L’objet dépasse $productUpdateSubjectLimit caractères.');
    }
    if (forPreparation && cleanSubject.isEmpty) {
      issues.add('L’objet est requis avant de préparer la mise à jour.');
    }
    final cleanPreheader = preheader.trim();
    if (cleanPreheader.length > productUpdatePreheaderLimit) {
      issues.add(
        'Le texte d’aperçu dépasse $productUpdatePreheaderLimit caractères.',
      );
    }
    for (final value in [name, cleanSubject, cleanPreheader]) {
      if (_singleLineControl.hasMatch(value) || _providerSyntax.hasMatch(value)) {
        issues.add('Un champ contient des caractères interdits.');
        break;
      }
    }
    final body = bodyMarkdown.trim();
    if (forPreparation && body.isEmpty) {
      issues.add('Le corps du message est requis avant de le préparer.');
    }
    final blocks = richTextBlocks();
    if (blocks.length > productUpdateMaxBlocks) {
      issues.add('Le message dépasse $productUpdateMaxBlocks blocs.');
    }
    if (blocks.any((block) => block.text.length > productUpdateRichTextLimit)) {
      issues.add(
        'Un paragraphe dépasse $productUpdateRichTextLimit caractères. Raccourcissez-le.',
      );
    }
    if (blocks.any(
      (block) =>
          _blockControl.hasMatch(block.text) ||
          _providerSyntax.hasMatch(block.text),
    )) {
      issues.add('Le corps contient des caractères interdits.');
    }
    if (blocks.isNotEmpty &&
        jsonEncode([for (final block in blocks) _blockJson(block)]).length >
            productUpdateBlocksJsonLimit) {
      issues.add('Le corps dépasse la limite de 48 000 caractères.');
    }
    return issues;
  }

  /// Splits the Markdown on blank lines into `rich_text` blocks, each at most
  /// [productUpdateRichTextLimit] characters. Oversized paragraphs stay whole
  /// here and are refused by [validate].
  List<ProductUpdateBlock> richTextBlocks() {
    final normalized = bodyMarkdown.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) return const [];
    final paragraphs = normalized
        .split(RegExp(r'\n[ \t]*\n'))
        .map((paragraph) => paragraph.trim())
        .where((paragraph) => paragraph.isNotEmpty);
    final chunks = <String>[];
    var current = '';
    for (final paragraph in paragraphs) {
      final candidate = current.isEmpty ? paragraph : '$current\n\n$paragraph';
      if (candidate.length <= productUpdateRichTextLimit) {
        current = candidate;
        continue;
      }
      if (current.isNotEmpty) chunks.add(current);
      current = paragraph;
    }
    if (current.isNotEmpty) chunks.add(current);
    return [
      for (var i = 0; i < chunks.length; i++)
        ProductUpdateBlock(
          id: 'body-${i + 1}',
          type: 'rich_text',
          text: chunks[i],
        ),
    ];
  }

  /// Request fields shared by `create` and `revise`. Never includes the
  /// idempotency key, which the transport owns.
  Map<String, dynamic> contentFields({required String audienceId}) => {
    'audience_id': audienceId,
    'locale': productUpdateLocale,
    'title': title.trim(),
    'subject': subject.trim(),
    'preheader': preheader.trim(),
    'blocks': [for (final block in richTextBlocks()) _blockJson(block)],
  };

  static Map<String, dynamic> _blockJson(ProductUpdateBlock block) => {
    'id': block.id,
    'type': block.type,
    'text': block.text,
  };
}

/// Maps a machine state onto the shared studio status labels.
NewsletterCampaignStatus newsletterStatusOf(ProductUpdateCampaign campaign) {
  int count(String key) => campaign.counters[key] ?? 0;
  return switch (campaign.state) {
    'draft' => NewsletterCampaignStatus.draft,
    'scheduled' => NewsletterCampaignStatus.scheduled,
    'paused' || 'suspended' => NewsletterCampaignStatus.suspended,
    'cancelled' => NewsletterCampaignStatus.cancelled,
    'running' || 'queued' || 'fanout_complete' => NewsletterCampaignStatus.sending,
    'delivered' => NewsletterCampaignStatus.delivered,
    'failed' => NewsletterCampaignStatus.failed,
    'completed' =>
      count('unknown') > 0
          ? NewsletterCampaignStatus.unknown
          : count('failed') > 0
          ? (count('delivered') > 0 || count('submitted') > 0
                ? NewsletterCampaignStatus.partiallyDelivered
                : NewsletterCampaignStatus.failed)
          : count('submitted') > 0
          ? NewsletterCampaignStatus.submitted
          : count('delivered') > 0
          ? NewsletterCampaignStatus.delivered
          : NewsletterCampaignStatus.completed,
    _ => NewsletterCampaignStatus.unknown,
  };
}

NewsletterCampaign newsletterCampaignOf(ProductUpdateCampaign campaign) =>
    NewsletterCampaign(
      id: campaign.id,
      title: campaign.title,
      subject: campaign.subject,
      revision: campaign.version,
      status: newsletterStatusOf(campaign),
      updatedAt: campaign.updatedAt,
      scheduledAt: campaign.scheduledAt,
      audienceLabel: campaign.audienceId,
      eligibleCount: campaign.eligibleCount,
      submittedCount: campaign.counters['submitted'] ?? 0,
      deliveredCount: campaign.counters['delivered'] ?? 0,
      failedCount: campaign.counters['failed'] ?? 0,
      unknownCount: campaign.counters['unknown'] ?? 0,
    );

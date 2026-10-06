import 'dart:async';
import 'dart:convert';

import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';

import 'central_email_api.dart';

class EmailBusiness {
  EmailBusiness(Map<String, dynamic> json)
    : id = json['id'] as String,
      brand = json['brand'] as String,
      from = json['from'] as String,
      audiences = (json['audiences'] as List).cast<Map<String, dynamic>>(),
      canTest = (json['capabilities'] as Map)['can_test'] == true,
      canApprove = (json['capabilities'] as Map)['can_approve'] == true,
      disabledReason =
          (json['capabilities'] as Map)['disabled_reason'] as String?,
      testRecipients = ((json['test_recipients'] as List?) ?? [])
          .cast<String>();

  final String id, brand, from;
  final List<Map<String, dynamic>> audiences;
  final bool canTest, canApprove;
  final String? disabledReason;
  final List<String> testRecipients;
}

NewsletterCampaign campaignFromJson(Map<String, dynamic> json) {
  final counters = (json['counters'] as Map?) ?? {};
  final status = NewsletterCampaignStatus.values.where(
    (s) => s.name == json['state'],
  );
  return NewsletterCampaign(
    id: json['id'] as String,
    title: json['title'] as String,
    subject: json['subject'] as String,
    revision: json['version'] as int,
    status: json['state'] == 'completed'
        ? _completedStatus(counters)
        : json['state'] == 'paused'
        ? NewsletterCampaignStatus.suspended
        : ['running', 'fanout_complete', 'queued'].contains(json['state'])
        ? NewsletterCampaignStatus.sending
        : status.isEmpty
        ? NewsletterCampaignStatus.unknown
        : status.first,
    updatedAt: DateTime.parse(json['updated_at'] as String),
    scheduledAt: json['scheduled_at'] == null
        ? null
        : DateTime.parse(json['scheduled_at'] as String),
    audienceLabel: json['audience_id'] as String,
    eligibleCount:
        (json['eligible_count'] as num?)?.toInt() ??
        counters.values.whereType<num>().fold<int>(
          0,
          (sum, n) => sum + n.toInt(),
        ),
    submittedCount: (counters['submitted'] as num?)?.toInt() ?? 0,
    deliveredCount: (counters['delivered'] as num?)?.toInt() ?? 0,
    failedCount: (counters['failed'] as num?)?.toInt() ?? 0,
    unknownCount: (counters['unknown'] as num?)?.toInt() ?? 0,
  );
}

DateTime _linkReportTime(Object? value) {
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }
  if (value is String) return DateTime.parse(value).toUtc();
  throw const EmailApiException('invalid_backend_receipt');
}

NewsletterLinkCheckReport _linkReportFromJson(
  Map<String, dynamic> json,
  Map<String, dynamic> disclosure, {
  required int draftRevision,
}) {
  if (json['findings'] is! List) {
    throw const EmailApiException('invalid_backend_receipt');
  }
  final status = switch (json['status']) {
    'clear' => NewsletterLinkReportStatus.clear,
    'blocked' => NewsletterLinkReportStatus.blocked,
    'uncertain' => NewsletterLinkReportStatus.uncertain,
    _ => throw const EmailApiException('invalid_backend_receipt'),
  };
  final findings = <NewsletterLinkFinding>[];
  for (final raw in json['findings'] as List) {
    if (raw is! Map<String, dynamic> || raw['blockIds'] is! List) {
      throw const EmailApiException('invalid_backend_receipt');
    }
    final findingStatus = switch (raw['status']) {
      'valid' => NewsletterLinkFindingStatus.valid,
      'broken' => NewsletterLinkFindingStatus.broken,
      'uncertain' => NewsletterLinkFindingStatus.uncertain,
      'static_blocker' => NewsletterLinkFindingStatus.staticBlocker,
      _ => throw const EmailApiException('invalid_backend_receipt'),
    };
    findings.add(
      NewsletterLinkFinding(
        blockIds: (raw['blockIds'] as List).cast<String>(),
        host: raw['host'] as String? ?? '',
        destinationHash: raw['destinationHash'] as String?,
        status: findingStatus,
        httpStatus: (raw['httpStatus'] as num?)?.toInt(),
        reason: raw['reason'] as String?,
        method: raw['method'] as String?,
        redirects: (raw['redirects'] as num?)?.toInt() ?? 0,
      ),
    );
  }
  return NewsletterLinkCheckReport(
    id: json['_id'] as String? ?? '',
    campaignId: json['campaignId'] as String? ?? '',
    revision: draftRevision,
    serverRevision: (json['revision'] as num?)?.toInt() ?? -1,
    destinationDigest: json['destinationDigest'] as String? ?? '',
    checkedAt: _linkReportTime(json['checkedAt']),
    expiresAt: _linkReportTime(json['expiresAt']),
    status: status,
    blockingCount: (json['blockingCount'] as num?)?.toInt() ?? -1,
    uncertainCount: (json['uncertainCount'] as num?)?.toInt() ?? -1,
    validCount: (json['validCount'] as num?)?.toInt() ?? -1,
    findings: findings,
    disclosure: NewsletterLinkCheckDisclosure(
      externalRequests: disclosure['external_requests'] == true,
      possibleDestinationSideEffect:
          disclosure['possible_destination_side_effect'] == true,
      methodPolicy: disclosure['method_policy'] as String? ?? '',
    ),
  );
}

NewsletterCampaignStatus _completedStatus(Map counters) {
  int count(String key) => (counters[key] as num?)?.toInt() ?? 0;
  if (count('unknown') > 0) return NewsletterCampaignStatus.unknown;
  if (count('failed') > 0) {
    return count('delivered') > 0 || count('submitted') > 0
        ? NewsletterCampaignStatus.partiallyDelivered
        : NewsletterCampaignStatus.failed;
  }
  if (count('submitted') > 0) return NewsletterCampaignStatus.submitted;
  if (count('delivered') > 0) return NewsletterCampaignStatus.delivered;
  return NewsletterCampaignStatus.completed;
}

class NewsletterReductionSnapshot {
  const NewsletterReductionSnapshot({
    required this.version,
    required this.reducibleRecipients,
    required this.protectedCount,
    required this.lockedCount,
  });

  final int version;
  final List<Map<String, dynamic>> reducibleRecipients;
  final int protectedCount;
  final int lockedCount;
}

class CentralCampaignRepository implements NewsletterCampaignRepository {
  CentralCampaignRepository(this.api, this.business);
  final CentralEmailApi api;
  final EmailBusiness business;

  @override
  Future<NewsletterCampaignPage> list({
    String? cursor,
    NewsletterCampaignStatus? status,
    int limit = 25,
  }) async {
    final json = await api.get('campaigns', {
      'business_id': business.id,
      'cursor': ?cursor,
      if (status != null) 'state': status.name,
      'limit': limit.clamp(1, 25).toString(),
    });
    return NewsletterCampaignPage(
      items: (json['campaigns'] as List)
          .map((v) => campaignFromJson(v as Map<String, dynamic>))
          .toList(),
      nextCursor: json['next_cursor'] as String?,
    );
  }

  @override
  Future<NewsletterCampaign> create({required String title}) async {
    if (business.audiences.isEmpty) {
      throw const EmailApiException('configuration_unavailable');
    }
    final json = await api.post('campaigns', {
      'business_id': business.id,
      'title': title,
      'audience_id': business.audiences.first['id'],
      'locale': 'fr',
      'subject': '',
      'preheader': '',
      'blocks': <Object>[],
    });
    return campaignFromJson(json['campaign'] as Map<String, dynamic>);
  }

  Future<CampaignEditorSession> open(String id) async {
    final json = await api.get('campaigns/$id', {'business_id': business.id});
    return CampaignEditorSession(
      api,
      business,
      json['campaign'] as Map<String, dynamic>,
      rendered: json['rendered'] as Map<String, dynamic>?,
    );
  }
}

/// Owns server revision independently from optimistic keystroke revisions.
class CampaignEditorSession {
  CampaignEditorSession(this.api, this.business, this.record, {this.rendered});
  final CentralEmailApi api;
  final EmailBusiness business;
  Map<String, dynamic> record;
  Map<String, dynamic>? review;
  NewsletterLinkCheckReport? linkReport;
  Map<String, dynamic>? rendered;
  String get id => record['id'] as String;
  int get version => record['version'] as int;
  String get state => record['state'] as String;
  String get audienceId => record['audience_id'] as String;
  String? get blockReasonLabel => switch (record['block_reason']) {
    'operator_paused' => 'Arrêt manuel activé',
    'remaining_plan_reduced' =>
      'Plan réduit : nouveau préflight et nouvelle approbation requis',
    'first_lot_observation_required' =>
      'Premier lot terminé : décision humaine requise après observation',
    'operator_cancelled' => 'Campagne annulée par l’opératrice',
    _ => null,
  };
  String? _savedSignature;
  Future<void> _writes = Future.value();

  Future<T> _serial<T>(Future<T> Function() work) {
    final result = _writes.then((_) => work());
    _writes = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  NewsletterDraft get draft => NewsletterDraft(
    id: id,
    revision: version,
    title: record['title'] as String,
    subject: record['subject'] as String,
    preheader: record['preheader'] as String,
    blocks: (record['blocks'] as List).map((raw) {
      final b = raw as Map<String, dynamic>;
      final type = NewsletterBlockType.values.byName(b['type'] as String);
      return NewsletterBlock(
        id: b['id'] as String,
        type: type,
        text: b['text'] as String? ?? '',
        label: type == NewsletterBlockType.button ? b['text'] as String? : null,
        url: b['url'] == null ? null : Uri.tryParse(b['url'] as String),
        rawUrl: b['url'] as String?,
        sourceId: b['source_id'] as String?,
      );
    }).toList(),
    sources: const [],
    status: state == 'draft'
        ? NewsletterDraftStatus.draft
        : state == 'scheduled'
        ? NewsletterDraftStatus.scheduled
        : state == 'suspended'
        ? NewsletterDraftStatus.scheduled
        : NewsletterDraftStatus.sent,
  );

  Map<String, dynamic> _content(NewsletterDraft draft) => {
    'title': draft.title,
    'subject': draft.subject,
    'preheader': draft.preheader,
    'audience_id': audienceId,
    'locale': record['locale'],
    'blocks': draft.blocks
        .map(
          (b) => {
            'id': b.id,
            'type': b.type.name,
            'text': b.type == NewsletterBlockType.button
                ? b.label ?? b.text
                : b.text,
            if (b.rawUrl != null)
              'url': b.rawUrl
            else if (b.url != null)
              'url': b.url.toString(),
            if (b.sourceId != null) 'source_id': b.sourceId,
          },
        )
        .toList(),
  };

  Future<Map<String, dynamic>> command(
    String action, [
    Map<String, dynamic> extra = const {},
  ]) async {
    final result = await api.post('campaigns/$id/$action', {
      'business_id': business.id,
      'expected_version': version,
      ...extra,
    });
    if (result['campaign'] is Map<String, dynamic>) {
      record = result['campaign'] as Map<String, dynamic>;
    }
    return result;
  }

  Future<NewsletterDraft> save(NewsletterDraft value) => _serial(() async {
    final content = _content(value);
    final signature = jsonEncode(content);
    if (signature != _savedSignature) {
      await command('save', content);
      _savedSignature = signature;
      review = null;
      linkReport = null;
    }
    return value.copyWith(
      revision: version,
      saveState: NewsletterSaveState.saved,
    );
  });

  Future<void> selectAudience(String audience, NewsletterDraft value) =>
      _serial(() async {
        if (!business.audiences.any((a) => a['id'] == audience)) {
          throw const EmailApiException('invalid_input');
        }
        final result = await command('save', {
          ..._content(value),
          'audience_id': audience,
        });
        record = result['campaign'] as Map<String, dynamic>;
        _savedSignature = jsonEncode(_content(value));
        review = null;
        linkReport = null;
      });

  Future<NewsletterAudienceSummary> resolve(NewsletterDraft value) async {
    await save(value);
    return _resolveSavedAudience();
  }

  Future<NewsletterLinkCheckReport> checkLinks(NewsletterDraft value) async {
    final saved = await save(value);
    if (state != 'draft' || saved.revision != version) {
      throw const EmailApiException('version_conflict');
    }
    final response = await api.post('campaigns/$id/links/check', {
      'business_id': business.id,
      'expected_version': version,
    });
    final rawReport = response['link_report'];
    final disclosure = response['disclosure'];
    if (rawReport is! Map<String, dynamic> ||
        disclosure is! Map<String, dynamic>) {
      throw const EmailApiException('invalid_backend_receipt');
    }
    final report = _linkReportFromJson(
      rawReport,
      disclosure,
      draftRevision: saved.revision,
    );
    if (report.campaignId != id ||
        report.serverRevision != version ||
        !report.isCurrentFor(saved)) {
      throw const EmailApiException('invalid_backend_receipt');
    }
    linkReport = report;
    return report;
  }

  Future<NewsletterAudienceSummary> _resolveSavedAudience() async {
    // Progress bounded server pages without monopolizing the UI. A larger list
    // remains resumable through Refresh, with no fabricated exact total.
    for (var page = 0; page < 10; page++) {
      final result = await command('review');
      review = result['review'] as Map<String, dynamic>;
      if (review!['complete'] == true) break;
    }
    final complete = review!['complete'] == true;
    return NewsletterAudienceSummary(
      id: audienceId,
      label: complete ? audienceId : '$audienceId · estimation partielle',
      eligibleCount: review!['eligible_count'] as int,
      isResolved: complete,
    );
  }

  Future<NewsletterReductionSnapshot> loadReductionSnapshot() async {
    if (!const {
      'scheduled',
      'sending',
      'running',
      'fanout_complete',
      'suspended',
      'paused',
    }.contains(state)) {
      throw const EmailApiException('invalid_state');
    }
    final expectedVersion = version;
    final reducible = <Map<String, dynamic>>[];
    var protectedCount = 0;
    var lockedCount = 0;
    String? cursor;
    var complete = false;
    for (var page = 0; page < 20; page++) {
      final result = await api.get('campaigns/$id/recipients', {
        'business_id': business.id,
        'limit': '50',
        'cursor': ?cursor,
      });
      final campaign = result['campaign'];
      if (campaign is! Map || campaign['version'] != expectedVersion) {
        throw const EmailApiException('version_conflict');
      }
      final rows = result['recipients'];
      if (rows is! List) {
        throw const EmailApiException('reduction_selection_unavailable');
      }
      for (final value in rows) {
        if (value is! Map<String, dynamic> ||
            value['recipient_reference'] is! String) {
          throw const EmailApiException('invalid_backend_receipt');
        }
        if (value['reducible'] == true) {
          reducible.add(value);
        } else {
          lockedCount++;
          if (value['protected'] == true) protectedCount++;
        }
      }
      final next = result['next_cursor'];
      if (next == null) {
        complete = true;
        break;
      }
      if (next is! String || next == cursor) {
        throw const EmailApiException('invalid_backend_receipt');
      }
      cursor = next;
    }
    if (!complete) {
      throw const EmailApiException('reduction_selection_unavailable');
    }
    return NewsletterReductionSnapshot(
      version: expectedVersion,
      reducibleRecipients: reducible,
      protectedCount: protectedCount,
      lockedCount: lockedCount,
    );
  }

  Future<List<Map<String, dynamic>>> loadIncidents() async {
    final incidents = <Map<String, dynamic>>[];
    String? cursor;
    var complete = false;
    for (var page = 0; page < 20; page++) {
      final result = await api.get('campaigns/$id/incidents', {
        'business_id': business.id,
        'limit': '50',
        'cursor': ?cursor,
      });
      final rows = result['incidents'];
      if (rows is! List) {
        throw const EmailApiException('incident_read_unavailable');
      }
      for (final value in rows) {
        if (value is! Map<String, dynamic>) {
          throw const EmailApiException('invalid_backend_receipt');
        }
        incidents.add(value);
      }
      final next = result['cursor'];
      if (next == null) {
        complete = true;
        break;
      }
      if (next is! String || next == cursor) {
        throw const EmailApiException('invalid_backend_receipt');
      }
      cursor = next;
    }
    if (!complete) throw const EmailApiException('incident_read_unavailable');
    return incidents;
  }

  List<NewsletterValidationIssue> preflightIssues() {
    final current = review;
    final now = DateTime.now().millisecondsSinceEpoch;
    final blockers = current?['blocking_checks'];
    if (current == null || current['version'] != version) {
      return const [
        NewsletterValidationIssue(
          id: 'preflight_missing',
          severity: NewsletterIssueSeverity.blocker,
          title: 'Préflight requis',
          message: 'Actualisez le contrôle serveur avant toute validation.',
        ),
      ];
    }
    if (current['complete'] != true ||
        current['report_id'] is! String ||
        current['expires_at'] is! num ||
        (current['expires_at'] as num).toInt() <= now ||
        blockers is! List ||
        blockers.isNotEmpty) {
      return const [
        NewsletterValidationIssue(
          id: 'preflight_blocked',
          severity: NewsletterIssueSeverity.blocker,
          title: 'Préflight non valide',
          message:
              'Les contrôles serveur sont incomplets, bloqués ou expirés. Consultez l’état de la campagne et relancez la vérification.',
        ),
      ];
    }
    return const [];
  }

  Future<NewsletterPreview> preview(
    NewsletterDraft value,
    NewsletterPreviewViewport viewport,
  ) async {
    var saved = value;
    if (state == 'draft') {
      saved = await save(value);
      await _resolveSavedAudience();
    } else if (rendered == null) {
      final json = await api.get('campaigns/$id', {'business_id': business.id});
      rendered = json['rendered'] as Map<String, dynamic>?;
    }
    final content = state == 'draft' ? review : rendered;
    if (content == null) {
      throw const EmailApiException('invalid_backend_receipt');
    }
    return NewsletterPreview(
      revision: saved.revision,
      viewport: viewport,
      subject: value.subject,
      preheader: value.preheader,
      plainText: content['text'] as String,
    );
  }

  Future<NewsletterTestReceipt> test(
    NewsletterDraft value,
    String recipient,
  ) async {
    final saved = await save(value);
    final result = await command('test', {'recipient': recipient});
    final receipt = result['test'] as Map<String, dynamic>;
    return NewsletterTestReceipt(
      operationId: receipt['message_id'] as String,
      draftRevision: saved.revision,
      message: 'Email test placé dans la file. Sa réception reste à vérifier.',
      recipientLabel: recipient,
      sentAt: DateTime.now(),
    );
  }

  Future<NewsletterOperationReceipt> approve(
    NewsletterDraft value, [
    NewsletterSchedule? schedule,
  ]) async {
    return _approve(value, schedule, allowUncertainLinks: false);
  }

  Future<NewsletterOperationReceipt> approveWithLinkReport(
    NewsletterDraft value, {
    NewsletterSchedule? schedule,
    required bool overrideUncertainLinks,
  }) => _approve(value, schedule, allowUncertainLinks: overrideUncertainLinks);

  Future<NewsletterOperationReceipt> _approve(
    NewsletterDraft value,
    NewsletterSchedule? schedule, {
    required bool allowUncertainLinks,
  }) async {
    final saved = await save(value);
    if (preflightIssues().isNotEmpty) {
      throw const EmailApiException('review_required');
    }
    final linkReport = this.linkReport;
    if (linkReport == null ||
        !linkReport.isCurrentFor(saved) ||
        linkReport.serverRevision != version ||
        linkReport.hasBlockers ||
        (linkReport.requiresOverride != allowUncertainLinks)) {
      throw const EmailApiException('link_check_required');
    }
    final reportId = review!['report_id'] as String;
    final issued = await command('challenge', {
      'action': allowUncertainLinks ? 'approve_link_override' : 'approve',
      'report_id': reportId,
      'link_report_id': linkReport.id,
    });
    final challenge = issued['challenge'];
    if (challenge is! Map ||
        challenge['id'] is! String ||
        challenge['report_id'] != reportId ||
        challenge['link_report_id'] != linkReport.id) {
      throw const EmailApiException('invalid_backend_receipt');
    }
    await command('approve', {
      'review_id': review!['id'],
      'report_id': reportId,
      'link_report_id': linkReport.id,
      if (allowUncertainLinks) 'override_link_report_id': linkReport.id,
      'challenge_id': challenge['id'],
      if (schedule != null)
        'scheduled_at': schedule.sendAt.toUtc().toIso8601String(),
    });
    return NewsletterOperationReceipt(
      operationId: id,
      draftRevision: saved.revision,
      message: schedule == null
          ? 'Campagne mise en file. Les livraisons apparaîtront dans le suivi.'
          : 'Campagne programmée.',
    );
  }

  Future<void> cancel() async {
    await command('cancel');
  }

  Future<void> pause() async {
    await command('pause');
  }

  Future<NewsletterAudienceSummary> refreshForResume() async {
    if (state != 'suspended' ||
        record['block_reason'] == 'remaining_plan_reduced') {
      throw const EmailApiException('invalid_state');
    }
    return _resolveSavedAudience();
  }

  Future<NewsletterAudienceSummary> refreshForReducedPlan() async {
    if (state != 'suspended' ||
        record['block_reason'] != 'remaining_plan_reduced') {
      throw const EmailApiException('invalid_state');
    }
    return _resolveSavedAudience();
  }

  Future<void> approveReducedPlan() async {
    if (state != 'suspended' ||
        record['block_reason'] != 'remaining_plan_reduced' ||
        preflightIssues().isNotEmpty) {
      throw const EmailApiException('preflight_blocked');
    }
    final reportId = review!['report_id'] as String;
    final issued = await command('challenge', {
      'action': 'approve',
      'report_id': reportId,
    });
    final challenge = issued['challenge'];
    if (challenge is! Map || challenge['id'] is! String) {
      throw const EmailApiException('invalid_backend_receipt');
    }
    await command('approve', {
      'review_id': review!['id'],
      'report_id': reportId,
      'challenge_id': challenge['id'],
    });
  }

  Future<void> resume() async {
    if (preflightIssues().isNotEmpty) {
      throw const EmailApiException('preflight_blocked');
    }
    final reportId = review!['report_id'] as String;
    final issued = await command('challenge', {
      'action': 'resume',
      'report_id': reportId,
    });
    final challenge = issued['challenge'];
    if (challenge is! Map || challenge['id'] is! String) {
      throw const EmailApiException('invalid_backend_receipt');
    }
    await command('resume', {
      'report_id': reportId,
      'challenge_id': challenge['id'],
    });
  }

  Future<void> reduceRemainingPlan(
    List<String> recipientReferences, {
    int? expectedVersion,
  }) async {
    if (recipientReferences.isEmpty || recipientReferences.length > 1000) {
      throw const EmailApiException('invalid_input');
    }
    if (expectedVersion != null && expectedVersion != version) {
      throw const EmailApiException('version_conflict');
    }
    await command('reduce', {
      'recipient_ids': recipientReferences,
      'expected_version': ?expectedVersion,
    });
  }

  Future<NewsletterDeliveryStatus> delivery() async {
    final json = await api.get('campaigns/$id', {'business_id': business.id});
    record = json['campaign'] as Map<String, dynamic>;
    rendered = json['rendered'] as Map<String, dynamic>?;
    final counters = record['counters'] as Map;
    return NewsletterDeliveryStatus(
      state: switch (state) {
        'draft' => NewsletterDeliveryState.draft,
        'scheduled' => NewsletterDeliveryState.scheduled,
        'suspended' => NewsletterDeliveryState.paused,
        'cancelled' => NewsletterDeliveryState.cancelled,
        'delivered' => NewsletterDeliveryState.delivered,
        'failed' => NewsletterDeliveryState.failed,
        'completed' => switch (_completedStatus(counters)) {
          NewsletterCampaignStatus.delivered =>
            NewsletterDeliveryState.delivered,
          NewsletterCampaignStatus.submitted =>
            NewsletterDeliveryState.submitted,
          NewsletterCampaignStatus.failed => NewsletterDeliveryState.failed,
          NewsletterCampaignStatus.unknown => NewsletterDeliveryState.unknown,
          NewsletterCampaignStatus.partiallyDelivered =>
            NewsletterDeliveryState.partiallyDelivered,
          _ => NewsletterDeliveryState.completed,
        },
        _ => NewsletterDeliveryState.sending,
      },
      message:
          '${counters['submitted'] ?? 0} acceptés · ${counters['delivered'] ?? 0} livrés · ${counters['failed'] ?? 0} échecs · ${counters['unknown'] ?? 0} résultats incertains${blockReasonLabel == null ? '' : ' · $blockReasonLabel'}',
      updatedAt: DateTime.parse(record['updated_at'] as String),
      operationId: id,
    );
  }
}

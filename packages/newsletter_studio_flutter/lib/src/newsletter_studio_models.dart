import 'package:flutter/foundation.dart';

enum NewsletterBlockType { heading, text, button, divider, source }

enum NewsletterDraftStatus { draft, review, scheduled, sent }

enum NewsletterSaveState {
  clean,
  dirty,
  saving,
  saved,
  conflict,
  offline,
  failed,
}

enum NewsletterIssueSeverity { blocker, warning }

enum NewsletterPreviewViewport { desktop, mobile, plainText }

enum NewsletterOperationKind {
  idle,
  validating,
  previewing,
  testing,
  scheduling,
  unscheduling,
  sending,
  loadingStatus,
  loadingAnalytics,
  failed,
}

enum NewsletterDeliveryState {
  completed,
  queued,
  submitted,
  unknown,
  draft,
  scheduled,
  paused,
  sending,
  delivered,
  partiallyDelivered,
  failed,
  cancelled,
}

@immutable
class NewsletterSourceReference {
  const NewsletterSourceReference({
    required this.id,
    required this.title,
    required this.publisher,
    required this.excerpt,
    this.canonicalUrl,
  });

  final String id;
  final String title;
  final String publisher;
  final String excerpt;
  final Uri? canonicalUrl;
}

@immutable
class NewsletterBlock {
  const NewsletterBlock({
    required this.id,
    required this.type,
    this.text = '',
    this.label,
    this.url,
    this.rawUrl,
    this.sourceId,
    this.isProtected = false,
  });

  final String id;
  final NewsletterBlockType type;
  final String text;
  final String? label;
  final Uri? url;

  /// Preserves the authored input when it is empty or cannot be parsed.
  final String? rawUrl;
  final String? sourceId;
  final bool isProtected;

  NewsletterBlock copyWith({
    NewsletterBlockType? type,
    String? text,
    String? label,
    Uri? url,
    String? rawUrl,
    String? sourceId,
    bool? isProtected,
  }) {
    return NewsletterBlock(
      id: id,
      type: type ?? this.type,
      text: text ?? this.text,
      label: label ?? this.label,
      url: url ?? this.url,
      rawUrl: rawUrl ?? this.rawUrl,
      sourceId: sourceId ?? this.sourceId,
      isProtected: isProtected ?? this.isProtected,
    );
  }
}

@immutable
class NewsletterDraft {
  const NewsletterDraft({
    required this.id,
    required this.revision,
    required this.title,
    required this.subject,
    required this.preheader,
    required this.blocks,
    required this.sources,
    this.status = NewsletterDraftStatus.draft,
    this.saveState = NewsletterSaveState.clean,
  });

  final String id;
  final int revision;
  final String title;
  final String subject;
  final String preheader;
  final List<NewsletterBlock> blocks;
  final List<NewsletterSourceReference> sources;
  final NewsletterDraftStatus status;
  final NewsletterSaveState saveState;

  Set<String> get usedSourceIds =>
      blocks.map((block) => block.sourceId).whereType<String>().toSet();

  NewsletterDraft copyWith({
    int? revision,
    String? title,
    String? subject,
    String? preheader,
    List<NewsletterBlock>? blocks,
    List<NewsletterSourceReference>? sources,
    NewsletterDraftStatus? status,
    NewsletterSaveState? saveState,
  }) {
    return NewsletterDraft(
      id: id,
      revision: revision ?? this.revision,
      title: title ?? this.title,
      subject: subject ?? this.subject,
      preheader: preheader ?? this.preheader,
      blocks: blocks ?? this.blocks,
      sources: sources ?? this.sources,
      status: status ?? this.status,
      saveState: saveState ?? this.saveState,
    );
  }
}

@immutable
class NewsletterAudienceSummary {
  const NewsletterAudienceSummary({
    required this.id,
    required this.label,
    required this.eligibleCount,
    this.excludedCount = 0,
    this.isResolved = true,
    this.isStale = false,
  });

  final String id;
  final String label;
  final int eligibleCount;
  final int excludedCount;
  final bool isResolved;
  final bool isStale;
}

@immutable
class NewsletterSenderSummary {
  const NewsletterSenderSummary({
    required this.name,
    required this.address,
    required this.replyTo,
    required this.isVerified,
  });

  final String name;
  final String address;
  final String replyTo;
  final bool isVerified;
}

@immutable
class NewsletterDesignSummary {
  const NewsletterDesignSummary({
    required this.templateName,
    required this.brandName,
    this.language = 'fr',
    this.direction = 'ltr',
    this.hasPlainTextAlternative = true,
  });

  final String templateName;
  final String brandName;
  final String language;
  final String direction;
  final bool hasPlainTextAlternative;
}

@immutable
class NewsletterValidationIssue {
  const NewsletterValidationIssue({
    required this.id,
    required this.severity,
    required this.title,
    required this.message,
    this.target,
  });

  final String id;
  final NewsletterIssueSeverity severity;
  final String title;
  final String message;
  final String? target;
}

enum NewsletterLinkReportStatus { clear, blocked, uncertain }

enum NewsletterLinkFindingStatus { valid, broken, uncertain, staticBlocker }

@immutable
class NewsletterLinkFinding {
  const NewsletterLinkFinding({
    required this.blockIds,
    required this.host,
    required this.status,
    this.destinationHash,
    this.httpStatus,
    this.reason,
    this.method,
    this.redirects = 0,
  });

  final List<String> blockIds;
  final String host;
  final String? destinationHash;
  final NewsletterLinkFindingStatus status;
  final int? httpStatus;
  final String? reason;
  final String? method;
  final int redirects;
}

@immutable
class NewsletterLinkCheckDisclosure {
  const NewsletterLinkCheckDisclosure({
    required this.externalRequests,
    required this.possibleDestinationSideEffect,
    required this.methodPolicy,
  });

  final bool externalRequests;
  final bool possibleDestinationSideEffect;
  final String methodPolicy;
}

@immutable
class NewsletterLinkCheckReport {
  const NewsletterLinkCheckReport({
    required this.id,
    required this.campaignId,
    required this.revision,
    required this.serverRevision,
    required this.destinationDigest,
    required this.checkedAt,
    required this.expiresAt,
    required this.status,
    required this.blockingCount,
    required this.uncertainCount,
    required this.validCount,
    required this.findings,
    required this.disclosure,
  });

  final String id;
  final String campaignId;
  final int revision;
  final int serverRevision;
  final String destinationDigest;
  final DateTime checkedAt;
  final DateTime expiresAt;
  final NewsletterLinkReportStatus status;
  final int blockingCount;
  final int uncertainCount;
  final int validCount;
  final List<NewsletterLinkFinding> findings;
  final NewsletterLinkCheckDisclosure disclosure;

  bool isCurrentFor(NewsletterDraft draft, {DateTime? now}) {
    final instant = now ?? DateTime.now();
    final countsValid =
        blockingCount >= 0 &&
        uncertainCount >= 0 &&
        validCount >= 0 &&
        findings.length == blockingCount + uncertainCount + validCount &&
        switch (status) {
          NewsletterLinkReportStatus.clear =>
            blockingCount == 0 && uncertainCount == 0,
          NewsletterLinkReportStatus.blocked => blockingCount > 0,
          NewsletterLinkReportStatus.uncertain =>
            blockingCount == 0 && uncertainCount > 0,
        };
    return id.isNotEmpty &&
        campaignId == draft.id &&
        revision == draft.revision &&
        destinationDigest.isNotEmpty &&
        checkedAt.isBefore(instant.add(const Duration(minutes: 1))) &&
        expiresAt.isAfter(instant) &&
        countsValid;
  }

  bool get hasBlockers =>
      blockingCount > 0 || status == NewsletterLinkReportStatus.blocked;
  bool get requiresOverride =>
      status == NewsletterLinkReportStatus.uncertain || uncertainCount > 0;
}

@immutable
class NewsletterPreview {
  const NewsletterPreview({
    required this.revision,
    required this.viewport,
    required this.subject,
    required this.preheader,
    required this.plainText,
    this.isApproximate = true,
  });

  final int revision;
  final NewsletterPreviewViewport viewport;
  final String subject;
  final String preheader;
  final String plainText;
  final bool isApproximate;
}

@immutable
class NewsletterSchedule {
  const NewsletterSchedule({required this.sendAt, required this.timezoneLabel});

  final DateTime sendAt;
  final String timezoneLabel;
}

@immutable
class NewsletterOperationReceipt {
  const NewsletterOperationReceipt({
    required this.operationId,
    required this.draftRevision,
    required this.message,
  });

  final String operationId;
  final int draftRevision;
  final String message;
}

@immutable
class NewsletterDeliveryStatus {
  const NewsletterDeliveryStatus({
    required this.state,
    required this.message,
    required this.updatedAt,
    this.operationId,
  });

  final NewsletterDeliveryState state;
  final String message;
  final DateTime updatedAt;
  final String? operationId;
}

@immutable
class NewsletterTestReceipt extends NewsletterOperationReceipt {
  const NewsletterTestReceipt({
    required super.operationId,
    required super.draftRevision,
    required super.message,
    required this.recipientLabel,
    required this.sentAt,
  });

  final String recipientLabel;
  final DateTime sentAt;
}

@immutable
class NewsletterStudioCapabilities {
  const NewsletterStudioCapabilities({
    this.canEdit = true,
    this.canPreview = true,
    this.canTest = false,
    this.canSchedule = false,
    this.canSend = false,
    this.canUnschedule = false,
    this.canViewDeliveryStatus = false,
    this.canViewAnalytics = false,
    this.analyticsUnavailableReason,
  });

  final bool canEdit;
  final bool canPreview;
  final bool canTest;
  final bool canSchedule;
  final bool canSend;
  final bool canUnschedule;
  final bool canViewDeliveryStatus;
  final bool canViewAnalytics;
  final String? analyticsUnavailableReason;
}

extension NewsletterBlockTypeLabel on NewsletterBlockType {
  String get label => switch (this) {
    NewsletterBlockType.heading => 'Titre',
    NewsletterBlockType.text => 'Texte',
    NewsletterBlockType.button => 'Bouton',
    NewsletterBlockType.divider => 'Séparateur',
    NewsletterBlockType.source => 'Source',
  };
}

extension NewsletterDeliveryStateLabel on NewsletterDeliveryState {
  String get label => switch (this) {
    NewsletterDeliveryState.completed => 'Terminée',
    NewsletterDeliveryState.draft => 'Brouillon',
    NewsletterDeliveryState.queued => 'En attente',
    NewsletterDeliveryState.submitted => 'Transmis au prestataire',
    NewsletterDeliveryState.unknown => 'Résultat incertain',
    NewsletterDeliveryState.scheduled => 'Programmé',
    NewsletterDeliveryState.paused => 'Suspendue',
    NewsletterDeliveryState.sending => 'Envoi en cours',
    NewsletterDeliveryState.delivered => 'Livré',
    NewsletterDeliveryState.partiallyDelivered => 'Livraison partielle',
    NewsletterDeliveryState.failed => 'Échec',
    NewsletterDeliveryState.cancelled => 'Annulé',
  };
}

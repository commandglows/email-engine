import 'package:flutter/foundation.dart';

enum NewsletterCampaignStatus {
  completed,
  draft,
  scheduled,
  suspended,
  queued,
  sending,
  submitted,
  delivered,
  partiallyDelivered,
  failed,
  unknown,
  cancelled;

  String get label => switch (this) {
    completed => 'Terminée',
    draft => 'Brouillon',
    scheduled => 'Programmée',
    suspended => 'Suspendue',
    queued => 'En attente',
    sending => 'Envoi en cours',
    submitted => 'Transmise',
    delivered => 'Livrée',
    partiallyDelivered => 'Livraison partielle',
    failed => 'Échec',
    unknown => 'Résultat incertain',
    cancelled => 'Annulée',
  };
}

@immutable
class NewsletterCampaign {
  const NewsletterCampaign({
    required this.id,
    required this.title,
    required this.subject,
    required this.revision,
    required this.status,
    required this.updatedAt,
    this.scheduledAt,
    this.audienceLabel,
    this.eligibleCount = 0,
    this.submittedCount = 0,
    this.deliveredCount = 0,
    this.failedCount = 0,
    this.unknownCount = 0,
  });
  final String id, title, subject;
  final int revision;
  final NewsletterCampaignStatus status;
  final DateTime updatedAt;
  final DateTime? scheduledAt;
  final String? audienceLabel;
  final int eligibleCount,
      submittedCount,
      deliveredCount,
      failedCount,
      unknownCount;
}

@immutable
class NewsletterCampaignPage {
  const NewsletterCampaignPage({required this.items, this.nextCursor});
  final List<NewsletterCampaign> items;
  final String? nextCursor;
}

/// Host-owned persistence. Implementations enforce authentication, authorization,
/// bounded pages and server-side business scope; this UI holds no credentials.
abstract class NewsletterCampaignRepository {
  Future<NewsletterCampaignPage> list({
    String? cursor,
    NewsletterCampaignStatus? status,
    int limit = 25,
  });
  Future<NewsletterCampaign> create({required String title});
}

/// A safe classification, never a raw transport response or exception message.
class NewsletterSaveConflict implements Exception {
  const NewsletterSaveConflict();
}

/// The operator dismissed a host dialog before any request was submitted.
class NewsletterActionCancelled implements Exception {
  const NewsletterActionCancelled();
}

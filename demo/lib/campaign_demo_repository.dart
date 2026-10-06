import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';

/// Synthetic, in-memory preview only. No HTTP, storage or real recipient.
class CampaignDemoRepository implements NewsletterCampaignRepository {
  final Map<String, NewsletterDraft> drafts = {};
  final List<NewsletterCampaign> campaigns = [
    NewsletterCampaign(
      id: 'weekly',
      title: 'Les nouvelles de la semaine',
      subject: 'Des idées à garder, des projets qui avancent',
      revision: 1,
      status: NewsletterCampaignStatus.draft,
      updatedAt: DateTime(2026, 9, 8, 10),
      audienceLabel: 'Lecteurs ShipGlows',
    ),
    NewsletterCampaign(
      id: 'launch',
      title: 'Dans les coulisses de ContentGlows',
      subject: 'Une nouvelle façon de créer, ensemble',
      revision: 3,
      status: NewsletterCampaignStatus.scheduled,
      updatedAt: DateTime(2026, 9, 7, 16),
      scheduledAt: DateTime(2026, 9, 15, 9),
      audienceLabel: 'Créateurs',
      eligibleCount: 248,
    ),
    NewsletterCampaign(
      id: 'august',
      title: 'Le carnet d’août',
      subject: 'Ce que nous avons appris cet été',
      revision: 4,
      status: NewsletterCampaignStatus.delivered,
      updatedAt: DateTime(2026, 8, 28, 9),
      audienceLabel: 'Lecteurs ShipGlows',
      eligibleCount: 180,
      deliveredCount: 180,
    ),
    NewsletterCampaign(
      id: 'digest',
      title: 'Votre dose d’inspiration',
      subject: 'Trois découvertes pour votre prochain projet',
      revision: 2,
      status: NewsletterCampaignStatus.partiallyDelivered,
      updatedAt: DateTime(2026, 8, 21, 9),
      audienceLabel: 'Créateurs',
      eligibleCount: 246,
      deliveredCount: 242,
      failedCount: 4,
    ),
  ];

  @override
  Future<NewsletterCampaignPage> list({
    String? cursor,
    NewsletterCampaignStatus? status,
    int limit = 25,
  }) async {
    final values = campaigns
        .where(
          (c) =>
              status == null ||
              c.status == status ||
              (status == NewsletterCampaignStatus.completed &&
                  const [
                    NewsletterCampaignStatus.delivered,
                    NewsletterCampaignStatus.partiallyDelivered,
                    NewsletterCampaignStatus.failed,
                    NewsletterCampaignStatus.submitted,
                    NewsletterCampaignStatus.unknown,
                  ].contains(c.status)),
        )
        .toList();
    final start = int.tryParse(cursor ?? '') ?? 0;
    final end = (start + limit).clamp(0, values.length);
    return NewsletterCampaignPage(
      items: values.sublist(start.clamp(0, end), end),
      nextCursor: end < values.length ? '$end' : null,
    );
  }

  @override
  Future<NewsletterCampaign> create({required String title}) async {
    final campaign = NewsletterCampaign(
      id: 'synthetic-${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      subject: '',
      revision: 1,
      status: NewsletterCampaignStatus.draft,
      updatedAt: DateTime.now(),
      audienceLabel: 'Lecteurs ShipGlows',
    );
    campaigns.insert(0, campaign);
    return campaign;
  }

  void save(NewsletterDraft draft) {
    drafts[draft.id] = draft;
    final index = campaigns.indexWhere((c) => c.id == draft.id);
    if (index < 0) return;
    final previous = campaigns[index];
    campaigns[index] = NewsletterCampaign(
      id: draft.id,
      title: draft.title,
      subject: draft.subject,
      revision: draft.revision,
      status: previous.status,
      updatedAt: DateTime.now(),
      audienceLabel: previous.audienceLabel,
    );
  }
}

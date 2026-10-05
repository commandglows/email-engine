import 'newsletter_studio_models.dart';

typedef NewsletterDraftChanged = void Function(NewsletterDraft draft);
typedef NewsletterDraftSave =
    Future<NewsletterDraft> Function(NewsletterDraft draft);
typedef NewsletterSourcesAttacher =
    Future<NewsletterDraft> Function(
      NewsletterDraft draft,
      List<NewsletterSourceReference> sources,
    );
typedef NewsletterAudienceResolver =
    Future<NewsletterAudienceSummary> Function(NewsletterDraft draft);
typedef NewsletterDraftValidator =
    Future<List<NewsletterValidationIssue>> Function(
      NewsletterDraft draft,
      NewsletterAudienceSummary? audience,
    );
typedef NewsletterLinkChecker =
    Future<NewsletterLinkCheckReport> Function(NewsletterDraft draft);
typedef NewsletterPreviewRenderer =
    Future<NewsletterPreview> Function(
      NewsletterDraft draft,
      NewsletterPreviewViewport viewport,
    );
typedef NewsletterTestSender =
    Future<NewsletterTestReceipt> Function(NewsletterDraft draft);
typedef NewsletterScheduler =
    Future<NewsletterOperationReceipt> Function(
      NewsletterDraft draft,
      NewsletterSchedule schedule,
    );
typedef NewsletterLinkReportSender =
    Future<NewsletterOperationReceipt> Function(
      NewsletterDraft draft,
      NewsletterLinkCheckReport report, {
      required bool overrideUncertain,
    });
typedef NewsletterLinkReportScheduler =
    Future<NewsletterOperationReceipt> Function(
      NewsletterDraft draft,
      NewsletterSchedule schedule,
      NewsletterLinkCheckReport report, {
      required bool overrideUncertain,
    });
typedef NewsletterSender =
    Future<NewsletterOperationReceipt> Function(NewsletterDraft draft);
typedef NewsletterUnscheduler = Future<void> Function(String draftId);
typedef NewsletterSourceOpener = Future<void> Function(String sourceId);
typedef NewsletterDeliveryStatusLoader =
    Future<NewsletterDeliveryStatus> Function(String draftId);
typedef NewsletterAnalyticsLoader =
    Future<Map<String, num>> Function(String draftId);

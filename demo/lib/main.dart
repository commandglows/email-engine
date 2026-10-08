import 'package:flutter/material.dart';
import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';
import 'package:source_sidebar_flutter/source_sidebar_flutter.dart';

import 'preview_theme.dart';
import 'campaign_demo_repository.dart';
import 'support_demo_repository.dart';
import 'dispatch_demo_repository.dart';

void main() => runApp(const SourceSidebarPreviewApp());

class SourceSidebarPreviewApp extends StatefulWidget {
  const SourceSidebarPreviewApp({super.key, this.showCockpit = true});
  final bool showCockpit;

  @override
  State<SourceSidebarPreviewApp> createState() =>
      _SourceSidebarPreviewAppState();
}

class _SourceSidebarPreviewAppState extends State<SourceSidebarPreviewApp> {
  ThemeMode _themeMode = ThemeMode.light;
  final _campaigns = CampaignDemoRepository();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ShipGlows · Email Engine',
      theme: PreviewTheme.light(),
      darkTheme: PreviewTheme.dark(),
      themeMode: _themeMode,
      home: SourceLibraryDemo(
        unified: widget.showCockpit,
        campaigns: _campaigns,
        darkMode: _themeMode == ThemeMode.dark,
        onThemeChanged: (darkMode) => setState(
          () => _themeMode = darkMode ? ThemeMode.dark : ThemeMode.light,
        ),
      ),
    );
  }
}

class SourceLibraryDemo extends StatefulWidget {
  const SourceLibraryDemo({
    required this.darkMode,
    required this.onThemeChanged,
    this.campaignsOnly = false,
    this.campaigns,
    this.unified = false,
    super.key,
  });

  final bool darkMode;
  final ValueChanged<bool> onThemeChanged;
  final bool campaignsOnly;
  final CampaignDemoRepository? campaigns;
  final bool unified;

  @override
  State<SourceLibraryDemo> createState() => _SourceLibraryDemoState();
}

class _SourceLibraryDemoState extends State<SourceLibraryDemo> {
  static const _moveDestinations = [
    SourceMoveDestination(id: 'later', label: 'Later'),
    SourceMoveDestination(id: 'reference', label: 'Reference'),
    SourceMoveDestination(id: 'archive', label: 'Archived'),
  ];
  static const _accounts = [
    SourceAccount(id: 'work', label: 'Work account'),
    SourceAccount(id: 'research', label: 'Research account'),
  ];
  static const _projects = [
    SourceProjectDestination(id: 'shipglows', label: 'ShipGlows'),
    SourceProjectDestination(id: 'contentglows', label: 'ContentGlows'),
    SourceProjectDestination(id: 'newsletter', label: 'Health newsletter'),
  ];

  late List<SourceSidebarItem> _items;
  late NewsletterDraft _newsletterDraft;
  late List<NewsletterSourceReference> _newsletterSources;
  late NewsletterSchedule? _newsletterSchedule;
  String? _selectedId;
  String _accountId = 'work';
  bool _loading = false;
  _DemoWorkspace _workspace = _DemoWorkspace.sources;
  NewsletterAudienceSummary? _audience;
  NewsletterTestReceipt? _testReceipt;
  late final _campaigns = widget.campaigns ?? CampaignDemoRepository();
  bool _fromCampaigns = false;
  final _support = DemoSupportRepository();
  final _dispatch = DemoDispatchRepository();
  final Map<String, SupportThread> _supportThreads = {};
  final Map<String, NewsletterCampaign> _campaignItems = {};
  final Map<String, String> _sections = {};
  final _sectionKeys = {
    for (final id in ['sources', 'support', 'diffusion']) id: GlobalKey(),
  };
  final _replyControllers = <String, TextEditingController>{};

  @override
  void dispose() {
    for (final controller in _replyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.campaignsOnly) {
      _workspace = _DemoWorkspace.campaigns;
    }
    _items = _previewSources();
    _newsletterSources = _items
        .where((item) => item.location != 'archive')
        .map(_newsletterSourceFromItem)
        .toList(growable: false);
    _newsletterDraft = _previewNewsletter(_newsletterSources);
    _newsletterSchedule = NewsletterSchedule(
      sendAt: DateTime.now().add(const Duration(days: 1)),
      timezoneLabel: 'Europe/Paris',
    );
    _audience = const NewsletterAudienceSummary(
      id: 'contentglows-health-readers',
      label: 'Health project · engaged readers',
      eligibleCount: 1284,
      excludedCount: 37,
    );
    if (widget.unified) _loadOtherFacets();
  }

  Future<void> _loadOtherFacets() async {
    final support = await _support.threads('demo');
    final campaigns = await _campaigns.list();
    final otherItems = <SourceSidebarItem>[];
    for (final summary in support.items) {
      final thread = await _support.thread('demo', summary.id);
      final id = 'support:${summary.id}';
      _supportThreads[id] = thread;
      _sections[id] = 'support';
      otherItems.add(
        SourceSidebarItem(
          id: id,
          title: summary.subject,
          authorOrPublisher: summary.from,
          summary: summary.snippet,
          publishedAt: summary.updatedAt ?? DateTime(2026, 9, 8),
          sourceType: 'Service client',
          content: thread.messages
              .map((m) => '${m.from}\n${m.text}')
              .join('\n\n'),
          tags: [summary.status.label],
          seen: summary.status != SupportStatus.pending,
          signalKind: SourceSidebarSignalKind.urgency,
          signalStrength: _supportUrgency(summary.status),
        ),
      );
    }
    for (final campaign in campaigns.items) {
      final id = 'campaign:${campaign.id}';
      _campaignItems[id] = campaign;
      _sections[id] = 'diffusion';
      final draft = _campaigns.drafts[campaign.id];
      otherItems.add(
        SourceSidebarItem(
          id: id,
          title: campaign.title,
          authorOrPublisher: 'ShipGlows',
          summary: campaign.subject,
          publishedAt: campaign.updatedAt,
          sourceType: 'Diffusion',
          content:
              '${campaign.subject}\n\n${draft?.blocks.map((b) => b.text).join('\n\n') ?? 'Ce brouillon est prêt à être travaillé dans l’éditeur.'}',
          tags: [campaign.status.label],
          seen: true,
          attention: _campaignAttention(campaign, draft != null),
          signalKind: SourceSidebarSignalKind.urgency,
          signalStrength: _campaignUrgency(campaign),
        ),
      );
    }
    if (!mounted) return;
    setState(() {
      _items.removeWhere((item) => _sections.containsKey(item.id));
      _items.addAll(otherItems);
    });
  }

  SourceSidebarAttention _campaignAttention(
    NewsletterCampaign campaign,
    bool hasEditableDraft,
  ) {
    final scheduledAt = campaign.scheduledAt;
    if (campaign.status == NewsletterCampaignStatus.failed ||
        campaign.status == NewsletterCampaignStatus.partiallyDelivered ||
        campaign.status == NewsletterCampaignStatus.unknown ||
        (scheduledAt != null &&
            scheduledAt.isBefore(
              DateTime.now().add(const Duration(days: 2)),
            ))) {
      return SourceSidebarAttention.needsReview;
    }
    if (campaign.status == NewsletterCampaignStatus.draft &&
        (hasEditableDraft || campaign.subject.trim().isNotEmpty)) {
      return SourceSidebarAttention.readyToSend;
    }
    return SourceSidebarAttention.none;
  }

  double _supportUrgency(SupportStatus status) => switch (status) {
    SupportStatus.pending => 0.78,
    SupportStatus.waiting => 0.35,
    SupportStatus.resolved => 0.08,
  };

  double _campaignUrgency(NewsletterCampaign campaign) {
    if (campaign.status == NewsletterCampaignStatus.failed ||
        campaign.status == NewsletterCampaignStatus.partiallyDelivered ||
        campaign.status == NewsletterCampaignStatus.unknown) {
      return 0.96;
    }
    if (campaign.status == NewsletterCampaignStatus.draft &&
        campaign.subject.trim().isNotEmpty) {
      return 0.72;
    }
    return 0.2;
  }

  void _openCampaign(NewsletterCampaign campaign) {
    final sample = _previewNewsletter(_newsletterSources);
    setState(() {
      _newsletterDraft =
          _campaigns.drafts[campaign.id] ??
          NewsletterDraft(
            id: campaign.id,
            revision: campaign.revision,
            title: campaign.title,
            subject: campaign.subject,
            preheader: '',
            blocks: sample.blocks,
            sources: sample.sources,
          );
      _fromCampaigns = true;
      _workspace = _DemoWorkspace.newsletter;
    });
  }

  Widget? get _facetActions {
    final thread = _supportThreads[_selectedId];
    final campaign = _campaignItems[_selectedId];
    if (thread != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Démonstration synthétique · aucun dispatch réel.'),
          DispatchPanel(
            key: ValueKey(
              'dispatch-demo/${thread.id}/${thread.latestMessageId}',
            ),
            repository: _dispatch,
            mailboxId: 'demo',
            threadId: thread.id,
            messageId: thread.latestMessageId,
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final status in SupportStatus.values)
                ChoiceChip(
                  label: Text(status.label),
                  selected: thread.status == status,
                  onSelected: (_) async {
                    await _support.setStatus('demo', thread.id, status);
                    await _loadOtherFacets();
                  },
                ),
            ],
          ),
          TextField(
            controller: _replyControllers.putIfAbsent(
              thread.id,
              TextEditingController.new,
            ),
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(labelText: 'Votre réponse'),
          ),
          const Text('Démonstration · aucun email réel ne sera envoyé.'),
        ],
      );
    }
    if (campaign != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: () => _openCampaign(campaign),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Ouvrir l’éditeur'),
        ),
      );
    }
    return null;
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    if (!mounted) return;
    setState(() {
      _items = _previewSources();
      _selectedId = null;
      _loading = false;
    });
    if (widget.unified) await _loadOtherFacets();
    _notify('Demo library refreshed.');
  }

  Future<void> _ingest(SourceSidebarItem item) async {
    _replace(item, processingState: SourceProcessingState.processing);
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    if (!mounted) return;
    _replace(
      item,
      processingState: SourceProcessingState.processed,
      tags: {...item.tags, 'demo-processed'}.toList(),
    );
    _notify('Sent to the selected project (simulated).');
  }

  Future<void> _selectAccount(SourceAccount account) async {
    setState(() {
      _accountId = account.id;
      _selectedId = null;
    });
    _notify('Switched to ${account.label} (simulated).');
  }

  Future<void> _summarize(SourceSidebarItem item) async {
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    if (!mounted) return;
    _replace(item, tags: {...item.tags, 'synthetic-summary'}.toList());
    _notify('Synthetic summary ready: ${item.summary}');
  }

  Future<void> _distribute(
    SourceSidebarItem item,
    List<SourceProjectDestination> projects,
  ) async {
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    if (!mounted) return;
    _replace(
      item,
      processingState: SourceProcessingState.processed,
      tags: {...item.tags, ...projects.map((project) => project.id)}.toList(),
    );
    _notify(
      'Sent to ${projects.map((project) => project.label).join(', ')} (simulated).',
    );
  }

  Future<void> _markSeen(SourceSidebarItem item) async {
    _replace(item, seen: true);
    _notify('Marked as seen in this demo.');
  }

  Future<void> _archive(SourceSidebarItem item) async {
    _replace(item, location: 'archive');
    setState(() => _selectedId = null);
    _notify('Moved to Archived in this demo.');
  }

  Future<void> _move(
    SourceSidebarItem item,
    SourceMoveDestination destination,
  ) async {
    _replace(item, location: destination.id);
    setState(() => _selectedId = null);
    _notify('Moved to ${destination.label} in this demo.');
  }

  Future<void> _delete(SourceSidebarItem item) async {
    setState(() {
      _items = _items.where((candidate) => candidate.id != item.id).toList();
      _selectedId = null;
    });
    _notify('Deleted from this demo. Refresh to restore it.');
  }

  Future<void> _openExternal(SourceSidebarItem item) async {
    _notify('External Reader links are disabled in the public demo.');
  }

  Future<void> _openLibrary() async {
    _notify('Readwise is disconnected from this synthetic public demo.');
  }

  void _replace(
    SourceSidebarItem source, {
    bool? seen,
    String? location,
    List<String>? tags,
    SourceProcessingState? processingState,
  }) {
    setState(() {
      _items = _items
          .map(
            (item) => item.id == source.id
                ? SourceSidebarItem(
                    id: item.id,
                    title: item.title,
                    authorOrPublisher: item.authorOrPublisher,
                    summary: item.summary,
                    publishedAt: item.publishedAt,
                    sourceType: item.sourceType,
                    content: item.content,
                    tags: tags ?? item.tags,
                    seen: seen ?? item.seen,
                    location: location ?? item.location,
                    processingState: processingState ?? item.processingState,
                    canonicalExternalUrl: item.canonicalExternalUrl,
                  )
                : item,
          )
          .toList(growable: false);
    });
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<NewsletterDraft> _saveNewsletter(NewsletterDraft draft) async {
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    _campaigns.save(draft);
    return draft.copyWith(
      revision: draft.revision + 1,
      saveState: NewsletterSaveState.saved,
    );
  }

  Future<NewsletterAudienceSummary> _resolveNewsletterAudience(
    NewsletterDraft draft,
  ) async {
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    return _audience!;
  }

  Future<List<NewsletterValidationIssue>> _validateNewsletter(
    NewsletterDraft draft,
    NewsletterAudienceSummary? audience,
  ) async {
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    return const [
      NewsletterValidationIssue(
        id: 'dark-mode-review',
        severity: NewsletterIssueSeverity.warning,
        title: 'Dark-mode inbox proof deferred',
        message:
            'The synthetic preview cannot prove received-client rendering.',
        target: 'design',
      ),
    ];
  }

  Future<NewsletterPreview> _renderNewsletterPreview(
    NewsletterDraft draft,
    NewsletterPreviewViewport viewport,
  ) async {
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    return NewsletterPreview(
      revision: draft.revision,
      viewport: viewport,
      subject: draft.subject,
      preheader: draft.preheader,
      plainText: draft.blocks
          .where((block) => block.type != NewsletterBlockType.divider)
          .map((block) => block.text)
          .join('\n\n'),
    );
  }

  Future<NewsletterTestReceipt> _sendNewsletterTest(
    NewsletterDraft draft,
  ) async {
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    final receipt = NewsletterTestReceipt(
      operationId: 'demo-test-${draft.revision}',
      draftRevision: draft.revision,
      message: 'Synthetic test completed.',
      recipientLabel: 'Diane · demo inbox',
      sentAt: DateTime.now(),
    );
    setState(() => _testReceipt = receipt);
    _notify('Synthetic test completed. No email was sent.');
    return receipt;
  }

  Future<NewsletterOperationReceipt> _scheduleNewsletter(
    NewsletterDraft draft,
    NewsletterSchedule schedule,
  ) async {
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    if (mounted) {
      setState(() => _newsletterSchedule = schedule);
      _notify('Schedule accepted by the synthetic demo only.');
    }
    return NewsletterOperationReceipt(
      operationId: 'demo-schedule-${draft.revision}',
      draftRevision: draft.revision,
      message: 'Synthetic schedule accepted.',
    );
  }

  Future<void> _unscheduleNewsletter(String draftId) async {
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    if (!mounted) return;
    setState(() => _newsletterSchedule = null);
    _notify('Synthetic schedule removed. No provider was contacted.');
  }

  Future<NewsletterDeliveryStatus> _loadNewsletterDeliveryStatus(
    String draftId,
  ) async {
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    return NewsletterDeliveryStatus(
      state: _newsletterSchedule == null
          ? NewsletterDeliveryState.draft
          : NewsletterDeliveryState.scheduled,
      message: _newsletterSchedule == null
          ? 'Synthetic draft has no active delivery.'
          : 'Synthetic schedule is ready for host reconciliation.',
      updatedAt: DateTime.now(),
      operationId: 'demo-status-${_newsletterDraft.revision}',
    );
  }

  Future<Map<String, num>> _loadNewsletterAnalytics(String draftId) async {
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    return const {'Delivered': 0, 'Unique opens': 0, 'Unique clicks': 0};
  }

  Future<NewsletterOperationReceipt> _sendNewsletter(
    NewsletterDraft draft,
  ) async {
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    _notify('Send accepted by the synthetic demo. No email was sent.');
    return NewsletterOperationReceipt(
      operationId: 'demo-send-${draft.revision}',
      draftRevision: draft.revision,
      message: 'Synthetic send accepted.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: switch (_workspace) {
          _DemoWorkspace.campaigns => CampaignWorkspace(
            repository: _campaigns,
            style: PreviewTheme.newsletterStyle(widget.darkMode),
            businessLabel: 'ShipGlows · démonstration',
            disabledReason:
                'Données fictives · aucun email réel ne sera envoyé.',
            onOpenCampaign: (campaign) async {
              final sample = _previewNewsletter(_newsletterSources);
              setState(() {
                _newsletterDraft =
                    _campaigns.drafts[campaign.id] ??
                    NewsletterDraft(
                      id: campaign.id,
                      revision: campaign.revision,
                      title: campaign.title,
                      subject: campaign.subject,
                      preheader: 'Le carnet de bord des projets ShipGlows.',
                      blocks: sample.blocks,
                      sources: sample.sources,
                    );
                _fromCampaigns = true;
                _workspace = _DemoWorkspace.newsletter;
              });
            },
          ),
          _DemoWorkspace.sources => SourceSidebar(
            title: widget.unified ? 'ShipGlows Email Engine' : 'Sources',
            itemSectionIds: widget.unified
                ? {
                    for (final item in _items)
                      item.id: _sections[item.id] ?? 'sources',
                  }
                : const {},
            sectionLabels: widget.unified
                ? const {
                    'sources': 'Sources',
                    'support': 'Service client',
                    'diffusion': 'Idées et brouillons de diffusion',
                  }
                : const {},
            sectionKeys: widget.unified ? _sectionKeys : const {},
            readerFooter: widget.unified ? _facetActions : null,
            items: _items,
            selectedId: _selectedId,
            isLoading: _loading,
            style: PreviewTheme.sidebarStyle(widget.darkMode),
            categories: PreviewTheme.categories(widget.darkMode),
            topBarActions: [
              if (!widget.unified)
                IconButton(
                  tooltip: 'Campagnes',
                  onPressed: () =>
                      setState(() => _workspace = _DemoWorkspace.campaigns),
                  icon: const Icon(Icons.campaign_outlined),
                ),
              if (!widget.unified)
                IconButton(
                  tooltip: 'Open Newsletter Studio',
                  onPressed: () {
                    setState(() => _workspace = _DemoWorkspace.newsletter);
                  },
                  icon: const Icon(Icons.edit_note_outlined),
                ),
              IconButton(
                tooltip: widget.darkMode ? 'Use light theme' : 'Use dark theme',
                onPressed: () => widget.onThemeChanged(!widget.darkMode),
                icon: Icon(
                  widget.darkMode
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: CircleAvatar(radius: 16, child: Text('D')),
              ),
            ],
            onSelected: (id) => setState(() => _selectedId = id),
            onRefresh: _refresh,
            refreshTooltip: widget.unified
                ? 'Actualiser la boîte'
                : 'Refresh sources',
            onOpenLibrary: widget.unified ? null : _openLibrary,
            onIngest: _sections.containsKey(_selectedId) ? null : _ingest,
            onMarkSeen: _sections.containsKey(_selectedId) ? null : _markSeen,
            onArchive: _sections.containsKey(_selectedId) ? null : _archive,
            onDelete: _sections.containsKey(_selectedId) ? null : _delete,
            onOpenExternal: _sections.containsKey(_selectedId)
                ? null
                : _openExternal,
            moveDestinations: _moveDestinations,
            laterDestinationId: 'later',
            onMove: _sections.containsKey(_selectedId) ? null : _move,
            accounts: _accounts,
            currentAccountId: _accountId,
            onAccountSelected: _selectAccount,
            onSummarize: _sections.containsKey(_selectedId) ? null : _summarize,
            projectDestinations: _projects,
            onDistribute: _sections.containsKey(_selectedId)
                ? null
                : _distribute,
            onActionError: (error) => _notify('Action failed: $error'),
          ),
          _DemoWorkspace.newsletter => NewsletterStudio(
            draft: _newsletterDraft,
            availableSources: _newsletterSources,
            audience: _audience,
            sender: const NewsletterSenderSummary(
              name: 'ContentGlows Health',
              address: 'newsletter@example.test',
              replyTo: 'hello@example.test',
              isVerified: true,
            ),
            design: const NewsletterDesignSummary(
              templateName: 'Editorial focus',
              brandName: 'Synthetic ContentGlows',
            ),
            schedule: _newsletterSchedule,
            testReceipt: _testReceipt,
            capabilities: const NewsletterStudioCapabilities(
              canTest: true,
              canSchedule: true,
              canSend: true,
              canUnschedule: true,
              canViewDeliveryStatus: true,
              canViewAnalytics: true,
            ),
            style: PreviewTheme.newsletterStyle(widget.darkMode),
            onDraftChanged: (draft) {
              setState(() => _newsletterDraft = draft);
            },
            onSaveDraft: _saveNewsletter,
            onResolveAudience: _resolveNewsletterAudience,
            onValidateDraft: _validateNewsletter,
            onRenderPreview: _renderNewsletterPreview,
            onSendTest: _sendNewsletterTest,
            onSchedule: _scheduleNewsletter,
            onSend: _sendNewsletter,
            onUnschedule: _unscheduleNewsletter,
            onLoadDeliveryStatus: _loadNewsletterDeliveryStatus,
            onLoadAnalytics: _loadNewsletterAnalytics,
            onOpenSource: (sourceId) async {
              final source = _newsletterSources.firstWhere(
                (candidate) => candidate.id == sourceId,
              );
              _notify('Opened ${source.title} in the synthetic source tray.');
            },
            onBack: () {
              setState(
                () => _workspace = _fromCampaigns && !widget.unified
                    ? _DemoWorkspace.campaigns
                    : _DemoWorkspace.sources,
              );
              if (widget.unified) _loadOtherFacets();
            },
            topBarActions: [
              IconButton(
                tooltip: widget.darkMode ? 'Use light theme' : 'Use dark theme',
                onPressed: () => widget.onThemeChanged(!widget.darkMode),
                icon: Icon(
                  widget.darkMode
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                ),
              ),
            ],
          ),
        },
      ),
    );
  }
}

enum _DemoWorkspace { sources, newsletter, campaigns }

NewsletterSourceReference _newsletterSourceFromItem(SourceSidebarItem item) {
  return NewsletterSourceReference(
    id: item.id,
    title: item.title,
    publisher: item.authorOrPublisher,
    excerpt: item.summary,
    canonicalUrl: item.canonicalExternalUrl,
  );
}

NewsletterDraft _previewNewsletter(List<NewsletterSourceReference> sources) {
  final selectedSources = sources.take(3).toList(growable: false);
  return NewsletterDraft(
    id: 'demo-health-weekly',
    revision: 1,
    title: 'Health Signals · Weekly draft',
    subject: 'Three health stories worth understanding this week',
    preheader: 'Evidence-led ideas, with every source kept in reach.',
    sources: selectedSources,
    blocks: [
      const NewsletterBlock(
        id: 'heading-opening',
        type: NewsletterBlockType.heading,
        text: 'A calmer way to read this week’s health signals',
        isProtected: true,
      ),
      const NewsletterBlock(
        id: 'text-opening',
        type: NewsletterBlockType.text,
        text:
            'This synthetic draft demonstrates how sources, writing, audience checks and delivery review can stay in one focused workspace.',
      ),
      if (selectedSources.isNotEmpty)
        NewsletterBlock(
          id: 'source-${selectedSources.first.id}',
          type: NewsletterBlockType.source,
          text: selectedSources.first.excerpt,
          label: selectedSources.first.title,
          sourceId: selectedSources.first.id,
        ),
      const NewsletterBlock(
        id: 'divider-one',
        type: NewsletterBlockType.divider,
      ),
      const NewsletterBlock(
        id: 'text-close',
        type: NewsletterBlockType.text,
        text:
            'The public demo never contacts a provider. ContentGlows will own persistence, consent, rendering and delivery.',
      ),
    ],
  );
}

List<SourceSidebarItem> _previewSources() => [
  _source(
    id: 'flutter-architecture',
    publisher: 'Flutter Engineering Weekly',
    title: 'Designing resilient Flutter application boundaries',
    summary: 'Keep product decisions separate from provider adapters.',
    day: 25,
    tags: const ['shipglows-ready', 'flutter'],
    relevance: 0.92,
    content:
        '''A resilient Flutter application keeps presentation, domain decisions, and external providers behind clear boundaries.

This synthetic article demonstrates the long-form reading state. Select text, search the library, switch themes, and send the source to a project to evaluate the complete interaction.''',
  ),
  _source(
    id: 'security-roundup',
    publisher: 'Practical AppSec Dispatch',
    title: 'Security signals worth tracking this week',
    summary: 'Authentication, provenance, and prompt-injection boundaries.',
    day: 24,
    tags: const ['shipglows-ready', 'security'],
    relevance: 0.84,
  ),
  _source(
    id: 'content-systems',
    publisher: 'Editorial Systems',
    title: 'Repurposing research without losing provenance',
    summary: 'One source library can feed distinct project workflows.',
    day: 23,
    tags: const ['contentglows-ready', 'workflow'],
    relevance: 0.66,
    seen: true,
  ),
  _source(
    id: 'dependency-health',
    publisher: 'Dependency Health',
    title: 'The maintenance signals hidden in release notes',
    summary: 'What to extract before an upgrade becomes urgent.',
    day: 22,
    tags: const ['shipglows-ready', 'maintenance'],
    relevance: 0.78,
  ),
  _source(
    id: 'reader-workflow',
    publisher: 'Knowledge Ops Notes',
    title: 'A calmer workflow for newsletter research',
    summary: 'Capture once, review deliberately, distribute when useful.',
    day: 21,
    tags: const ['research', 'reader'],
    relevance: 0.42,
    seen: true,
  ),
  _source(
    id: 'health-storytelling',
    publisher: 'Health Narrative Lab',
    title: 'Turning expert interviews into trustworthy stories',
    summary: 'A provenance-first framework for health content.',
    day: 20,
    tags: const ['contentglows-ready', 'health'],
    relevance: 0.7,
    seen: true,
  ),
  _source(
    id: 'browser-security',
    publisher: 'Browser Security Brief',
    title: 'Passkeys, sessions, and safer recovery flows',
    summary: 'Practical implementation notes from production teams.',
    day: 19,
    tags: const ['shipglows-ready', 'security'],
    relevance: 0.82,
  ),
  _source(
    id: 'editorial-angles',
    publisher: 'The Editorial Operator',
    title: 'Seven ways to find a sharper content angle',
    summary: 'Move from collected sources to defensible points of view.',
    day: 18,
    tags: const ['contentglows-ready', 'research'],
    relevance: 0.64,
    processed: true,
  ),
  _source(
    id: 'flutter-performance',
    publisher: 'Flutter Performance Notes',
    title: 'Frame budgets for dense information interfaces',
    summary: 'Keep scrolling smooth without flattening the experience.',
    day: 17,
    tags: const ['shipglows-ready', 'flutter'],
    relevance: 0.46,
    seen: true,
  ),
  _source(
    id: 'business-models',
    publisher: 'Independent Business Review',
    title: 'Where small software products gain leverage',
    summary: 'Distribution and workflow advantages worth studying.',
    day: 16,
    tags: const ['contentglows-ready', 'business'],
    relevance: 0.73,
  ),
  _source(
    id: 'supply-chain',
    publisher: 'Secure Supply Chain',
    title: 'A field checklist for package provenance',
    summary: 'Attestations, lockfiles, and the controls between them.',
    day: 15,
    tags: const ['shipglows-ready', 'security'],
    relevance: 0.52,
    processed: true,
    seen: true,
  ),
  _source(
    id: 'archived-example',
    publisher: 'Product Systems Archive',
    title: 'A source already reviewed and archived',
    summary: 'Synthetic data for testing the archive navigation state.',
    day: 14,
    tags: const ['workflow'],
    location: 'archive',
    seen: true,
  ),
];

SourceSidebarItem _source({
  required String id,
  required String publisher,
  required String title,
  required String summary,
  required int day,
  required List<String> tags,
  String? content,
  bool seen = false,
  bool processed = false,
  double relevance = 0,
  String location = 'new',
}) {
  return SourceSidebarItem(
    id: id,
    title: title,
    authorOrPublisher: publisher,
    summary: summary,
    publishedAt: DateTime.utc(2026, 8, day),
    sourceType: 'newsletter',
    content:
        content ??
        '''This synthetic newsletter entry is included to test the density, reading rhythm, and project handoff of the shared Flutter source interface.

Production applications provide sanitized content and decide what “Send to project” means. The shared package remains independent from Readwise and from either product architecture.''',
    tags: tags,
    seen: seen,
    signalStrength: relevance,
    location: location,
    processingState: processed
        ? SourceProcessingState.processed
        : SourceProcessingState.idle,
    canonicalExternalUrl: Uri.https('readwise.io', '/reader'),
  );
}

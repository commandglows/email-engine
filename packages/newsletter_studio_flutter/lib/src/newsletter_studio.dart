import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'newsletter_studio_hooks.dart';
import 'newsletter_campaign_models.dart';
import 'newsletter_studio_models.dart';
import 'newsletter_studio_shortcuts.dart';
import 'newsletter_studio_style.dart';

class NewsletterStudio extends StatefulWidget {
  const NewsletterStudio({
    required this.draft,
    required this.onDraftChanged,
    super.key,
    this.availableSources = const <NewsletterSourceReference>[],
    this.audience,
    this.availableAudiences = const [],
    this.onAudienceChanged,
    this.onScheduleChanged,
    this.sender,
    this.design,
    this.schedule,
    this.testReceipt,
    this.deliveryStatus,
    this.validationIssues = const <NewsletterValidationIssue>[],
    this.linkReport,
    this.capabilities = const NewsletterStudioCapabilities(),
    this.style = const NewsletterStudioStyle(),
    this.shortcuts = const NewsletterStudioShortcuts(),
    this.onSaveDraft,
    this.onAttachSources,
    this.onResolveAudience,
    this.onValidateDraft,
    this.onCheckLinks,
    this.onRenderPreview,
    this.onSendTest,
    this.onSchedule,
    this.onSend,
    this.onSendWithLinkReport,
    this.onScheduleWithLinkReport,
    this.onUnschedule,
    this.onOpenSource,
    this.onLoadDeliveryStatus,
    this.onLoadAnalytics,
    this.onBack,
    this.topBarActions = const <Widget>[],
  });
  final NewsletterDraft draft;
  final NewsletterDraftChanged onDraftChanged;
  final List<NewsletterSourceReference> availableSources;
  final List<NewsletterAudienceSummary> availableAudiences;
  final ValueChanged<NewsletterAudienceSummary>? onAudienceChanged;
  final ValueChanged<NewsletterSchedule?>? onScheduleChanged;
  final NewsletterAudienceSummary? audience;
  final NewsletterSenderSummary? sender;
  final NewsletterDesignSummary? design;
  final NewsletterSchedule? schedule;
  final NewsletterTestReceipt? testReceipt;
  final NewsletterDeliveryStatus? deliveryStatus;
  final List<NewsletterValidationIssue> validationIssues;
  final NewsletterLinkCheckReport? linkReport;
  final NewsletterStudioCapabilities capabilities;
  final NewsletterStudioStyle style;
  final NewsletterStudioShortcuts shortcuts;
  final NewsletterDraftSave? onSaveDraft;
  final NewsletterSourcesAttacher? onAttachSources;
  final NewsletterAudienceResolver? onResolveAudience;
  final NewsletterDraftValidator? onValidateDraft;
  final NewsletterLinkChecker? onCheckLinks;
  final NewsletterPreviewRenderer? onRenderPreview;
  final NewsletterTestSender? onSendTest;
  final NewsletterScheduler? onSchedule;
  final NewsletterSender? onSend;
  final NewsletterLinkReportSender? onSendWithLinkReport;
  final NewsletterLinkReportScheduler? onScheduleWithLinkReport;
  final NewsletterUnscheduler? onUnschedule;
  final NewsletterSourceOpener? onOpenSource;
  final NewsletterDeliveryStatusLoader? onLoadDeliveryStatus;
  final NewsletterAnalyticsLoader? onLoadAnalytics;
  final VoidCallback? onBack;
  final List<Widget> topBarActions;
  @override
  State<NewsletterStudio> createState() => _NewsletterStudioState();
}

class _NewsletterStudioState extends State<NewsletterStudio> {
  final _workspaceFocus = FocusNode(debugLabel: 'Newsletter studio workspace');
  final _sourcesFocus = FocusNode(debugLabel: 'Newsletter sources zone');
  final _editorFocus = FocusNode(debugLabel: 'Newsletter editor zone');
  final _inspectorFocus = FocusNode(debugLabel: 'Newsletter inspector zone');
  final _actionsFocus = FocusNode(debugLabel: 'Newsletter actions zone');
  final _subjectFocus = FocusNode(debugLabel: 'Newsletter subject');
  final _sourceFocusNodes = <String, FocusNode>{};
  final _sourceKeys = <String, GlobalKey>{};
  final _blockKeys = <String, GlobalKey>{};
  final _blockUrlFocusNodes = <String, FocusNode>{};
  final _titleController = TextEditingController();
  final _subjectController = TextEditingController();
  final _preheaderController = TextEditingController();
  late NewsletterDraft _draft;
  NewsletterAudienceSummary? _audience;
  NewsletterPreview? _preview;
  NewsletterTestReceipt? _testReceipt;
  NewsletterDeliveryStatus? _deliveryStatus;
  Map<String, num>? _analytics;
  NewsletterOperationKind _operation = NewsletterOperationKind.idle;
  _InspectorTab _inspectorTab = _InspectorTab.content;
  _CompactPage _compactPage = _CompactPage.write;
  Timer? _autosaveTimer;
  int _editSerial = 0;
  Future<bool>? _saveInFlight;
  bool _saveRequested = false;
  String? _selectedSourceId;
  String? _selectedBlockId;
  String? _lastError;
  bool _showPreview = false;
  late double _zoom;
  NewsletterStudioColors get _colors =>
      widget.style.colors ??
      NewsletterStudioColors.fromColorScheme(Theme.of(context).colorScheme);
  bool get _isEditingText {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    return focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool get _canEdit => widget.capabilities.canEdit && !_isBusy;

  bool get _isBusy =>
      _operation != NewsletterOperationKind.idle &&
      _operation != NewsletterOperationKind.failed;
  @override
  void initState() {
    super.initState();
    _draft = widget.draft;
    _audience = widget.audience;
    _testReceipt = widget.testReceipt;
    _deliveryStatus = widget.deliveryStatus;
    _zoom = widget.style.initialZoom;
    _syncControllers();
    if (_draft.sources.isNotEmpty) {
      _selectedSourceId = _draft.sources.first.id;
    } else if (widget.availableSources.isNotEmpty) {
      _selectedSourceId = widget.availableSources.first.id;
    }
    if (_draft.blocks.isNotEmpty) {
      _selectedBlockId = _draft.blocks.first.id;
    }
  }

  @override
  void didUpdateWidget(covariant NewsletterStudio oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incomingIsNewer =
        widget.draft.id != _draft.id || widget.draft.revision > _draft.revision;
    if (incomingIsNewer) {
      if (widget.draft.id != _draft.id) {
        _autosaveTimer?.cancel();
        _saveRequested = false;
        _editSerial += 1;
      }
      _draft = widget.draft;
      _syncControllers();
    }
    if (widget.audience != oldWidget.audience) {
      _audience = widget.audience;
    }
    if (widget.testReceipt != oldWidget.testReceipt) {
      _testReceipt = widget.testReceipt;
    }
    if (widget.deliveryStatus != oldWidget.deliveryStatus) {
      _deliveryStatus = widget.deliveryStatus;
    }
    _zoom = _zoom
        .clamp(widget.style.minimumZoom, widget.style.maximumZoom)
        .toDouble();
    final sourceIds = widget.availableSources
        .map((source) => source.id)
        .toSet();
    final removed = _sourceFocusNodes.keys
        .where((id) => !sourceIds.contains(id))
        .toList(growable: false);
    for (final id in removed) {
      _sourceFocusNodes.remove(id)?.dispose();
      _sourceKeys.remove(id);
    }
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _workspaceFocus.dispose();
    _sourcesFocus.dispose();
    _editorFocus.dispose();
    _inspectorFocus.dispose();
    _actionsFocus.dispose();
    _subjectFocus.dispose();
    _titleController.dispose();
    _subjectController.dispose();
    _preheaderController.dispose();
    for (final node in _sourceFocusNodes.values) {
      node.dispose();
    }
    for (final node in _blockUrlFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncControllers() {
    if (_titleController.text != _draft.title) {
      _titleController.text = _draft.title;
    }
    if (_subjectController.text != _draft.subject) {
      _subjectController.value = TextEditingValue(
        text: _draft.subject,
        selection: TextSelection.collapsed(offset: _draft.subject.length),
      );
    }
    if (_preheaderController.text != _draft.preheader) {
      _preheaderController.value = TextEditingValue(
        text: _draft.preheader,
        selection: TextSelection.collapsed(offset: _draft.preheader.length),
      );
    }
  }

  void _replaceDraft(NewsletterDraft next, {bool autosave = true}) {
    _editSerial += 1;
    final dirty = next.copyWith(
      saveState: _draft.saveState == NewsletterSaveState.conflict
          ? NewsletterSaveState.conflict
          : NewsletterSaveState.dirty,
    );
    setState(() {
      _draft = dirty;
      _preview = null;
      _testReceipt = null;
      _lastError = null;
    });
    final liveBlockIds = dirty.blocks.map((block) => block.id).toSet();
    for (final id in _blockUrlFocusNodes.keys.toList()) {
      if (!liveBlockIds.contains(id)) {
        _blockUrlFocusNodes.remove(id)?.dispose();
        _blockKeys.remove(id);
      }
    }
    widget.onDraftChanged(dirty);
    if (autosave) _scheduleAutosave();
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    if (widget.onSaveDraft == null) return;
    _autosaveTimer = Timer(widget.style.autosaveDelay, _flushSave);
  }

  Future<bool> _flushSave() async {
    _autosaveTimer?.cancel();
    final save = widget.onSaveDraft;
    if (save == null) return true;
    if (_draft.saveState == NewsletterSaveState.conflict) return false;
    _saveRequested = true;
    if (_saveInFlight != null) return _saveInFlight!;
    final completion = Completer<bool>();
    _saveInFlight = completion.future;
    var success = true;
    while (_saveRequested && mounted) {
      _saveRequested = false;
      if (_draft.saveState == NewsletterSaveState.saved ||
          _draft.saveState == NewsletterSaveState.clean) {
        break;
      }
      final serial = _editSerial;
      final snapshot = _draft;
      setState(
        () => _draft = _draft.copyWith(saveState: NewsletterSaveState.saving),
      );
      widget.onDraftChanged(_draft);
      try {
        final saved = await save(snapshot);
        if (!mounted || _draft.id != snapshot.id) {
          success = false;
          break;
        }
        setState(() {
          if (serial == _editSerial) {
            _draft = saved.copyWith(saveState: NewsletterSaveState.saved);
          } else {
            _draft = _draft.copyWith(
              revision: saved.revision,
              saveState: NewsletterSaveState.dirty,
            );
            _saveRequested = true;
          }
        });
        widget.onDraftChanged(_draft);
      } catch (error) {
        if (!mounted) {
          success = false;
          break;
        }
        final conflict = error is NewsletterSaveConflict;
        setState(() {
          _draft = _draft.copyWith(
            saveState: conflict
                ? NewsletterSaveState.conflict
                : NewsletterSaveState.failed,
          );
          _lastError = conflict
              ? 'Ce brouillon a été modifié ailleurs. Conservez vos changements et rechargez la campagne.'
              : 'Enregistrement impossible. Vos modifications restent ici ; vérifiez votre connexion puis réessayez.';
        });
        widget.onDraftChanged(_draft);
        _saveRequested = false;
        success = false;
        break;
      }
    }
    _saveInFlight = null;
    completion.complete(success);
    return success;
  }

  NewsletterSourceReference? get _selectedSource {
    final id = _selectedSourceId;
    if (id == null) return null;
    for (final source in widget.availableSources) {
      if (source.id == id) return source;
    }
    return null;
  }

  NewsletterBlock? get _selectedBlock {
    final id = _selectedBlockId;
    if (id == null) return null;
    for (final block in _draft.blocks) {
      if (block.id == id) return block;
    }
    return null;
  }

  void _moveSourceSelection(int delta) {
    if (_isEditingText || widget.availableSources.isEmpty) return;
    final current = widget.availableSources.indexWhere(
      (source) => source.id == _selectedSourceId,
    );
    final next = current < 0
        ? 0
        : !_sourcesFocus.hasFocus
        ? current
        : (current + delta)
              .clamp(0, widget.availableSources.length - 1)
              .toInt();
    setState(() => _selectedSourceId = widget.availableSources[next].id);
    _focusSelectedSource();
  }

  void _focusSelectedSource() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final id = _selectedSourceId;
      _sourceFocusNodes[id]?.requestFocus();
      final rowContext = _sourceKeys[id]?.currentContext;
      if (rowContext != null && rowContext.mounted) {
        Scrollable.ensureVisible(
          rowContext,
          alignment: 0.5,
          duration: widget.style.focusScrollDuration,
        );
      }
    });
  }

  Future<void> _toggleSelectedSource() async {
    if (_isEditingText || !_canEdit) return;
    final source = _selectedSource;
    if (source == null) return;
    final attached = _draft.sources.any(
      (candidate) => candidate.id == source.id,
    );
    if (attached && _draft.usedSourceIds.contains(source.id)) {
      setState(() {
        _lastError = 'Supprimez le bloc associé avant de retirer cette source.';
      });
      return;
    }
    final sources = attached
        ? _draft.sources
              .where((candidate) => candidate.id != source.id)
              .toList()
        : [..._draft.sources, source];
    final attach = widget.onAttachSources;
    if (attach == null) {
      _replaceDraft(_draft.copyWith(sources: sources));
      return;
    }
    try {
      final next = await attach(_draft, sources);
      if (!mounted) return;
      _replaceDraft(next);
    } catch (error) {
      if (mounted) {
        setState(
          () => _lastError =
              'Opération non confirmée. Actualisez son état avant de réessayer.',
        );
      }
    }
  }

  void _insertSelectedSource() {
    if (!_canEdit) return;
    final source = _selectedSource;
    if (source == null) return;
    final sources = _draft.sources.any((item) => item.id == source.id)
        ? _draft.sources
        : [..._draft.sources, source];
    final block = NewsletterBlock(
      id: 'source-${source.id}-${_draft.blocks.length}',
      type: NewsletterBlockType.source,
      text: source.excerpt,
      label: source.title,
      sourceId: source.id,
    );
    _selectedBlockId = block.id;
    _replaceDraft(
      _draft.copyWith(sources: sources, blocks: [..._draft.blocks, block]),
    );
  }

  void _addBlock(NewsletterBlockType type) {
    if (!_canEdit) return;
    final index = _draft.blocks.length;
    final block = NewsletterBlock(
      id: '${type.name}-$index-${_draft.revision}',
      type: type,
      text: switch (type) {
        NewsletterBlockType.heading => 'Nouvelle section',
        NewsletterBlockType.button => 'En savoir plus',
        NewsletterBlockType.divider => '',
        NewsletterBlockType.source => 'Extrait de la source',
        NewsletterBlockType.text => 'Commencez à écrire…',
      },
      label: type == NewsletterBlockType.button ? 'Button label' : null,
    );
    _selectedBlockId = block.id;
    _replaceDraft(_draft.copyWith(blocks: [..._draft.blocks, block]));
  }

  void _updateBlock(NewsletterBlock block) {
    _replaceDraft(
      _draft.copyWith(
        blocks: [
          for (final candidate in _draft.blocks)
            if (candidate.id == block.id) block else candidate,
        ],
      ),
    );
  }

  void _moveBlock(NewsletterBlock block, int delta) {
    if (block.isProtected) return;
    final current = _draft.blocks.indexWhere(
      (candidate) => candidate.id == block.id,
    );
    if (current < 0) return;
    final next = (current + delta).clamp(0, _draft.blocks.length - 1).toInt();
    if (next == current) return;
    final blocks = [..._draft.blocks];
    blocks.removeAt(current);
    blocks.insert(next, block);
    _replaceDraft(_draft.copyWith(blocks: blocks));
  }

  void _removeBlock(NewsletterBlock block) {
    if (block.isProtected) return;
    final blocks = _draft.blocks
        .where((candidate) => candidate.id != block.id)
        .toList(growable: false);
    _selectedBlockId = blocks.isEmpty ? null : blocks.first.id;
    _replaceDraft(_draft.copyWith(blocks: blocks));
  }

  Future<void> _openSelectedSource() async {
    if (_isEditingText) return;
    final source = _selectedSource;
    final open = widget.onOpenSource;
    if (source == null || open == null) return;
    try {
      await open(source.id);
    } catch (error) {
      if (mounted) {
        setState(
          () => _lastError =
              'Opération non confirmée. Actualisez son état avant de réessayer.',
        );
      }
    }
  }

  Future<void> _resolveAudience() async {
    final resolve = widget.onResolveAudience;
    if (resolve == null) return;
    setState(() {
      _operation = NewsletterOperationKind.validating;
      _lastError = null;
    });
    try {
      final audience = await resolve(_draft);
      if (!mounted) return;
      setState(() {
        _audience = audience;
        _operation = NewsletterOperationKind.idle;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _operation = NewsletterOperationKind.failed;
        _lastError =
            'Opération non confirmée. Actualisez son état avant de réessayer.';
      });
    }
  }

  Future<void> _togglePreview() async {
    if (!widget.capabilities.canPreview) return;
    if (_showPreview) {
      setState(() => _showPreview = false);
      return;
    }
    final renderer = widget.onRenderPreview;
    if (renderer == null) {
      setState(() {
        _preview = _localPreview(NewsletterPreviewViewport.desktop);
        _showPreview = true;
      });
      return;
    }
    setState(() {
      _operation = NewsletterOperationKind.previewing;
      _lastError = null;
    });
    try {
      final preview = await renderer(_draft, NewsletterPreviewViewport.desktop);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _showPreview = true;
        _operation = NewsletterOperationKind.idle;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _operation = NewsletterOperationKind.failed;
        _lastError =
            'Opération non confirmée. Actualisez son état avant de réessayer.';
      });
    }
  }

  NewsletterPreview _localPreview(NewsletterPreviewViewport viewport) {
    final text = _draft.blocks
        .where((block) => block.type != NewsletterBlockType.divider)
        .map((block) => block.text)
        .where((value) => value.trim().isNotEmpty)
        .join('\n\n');
    return NewsletterPreview(
      revision: _draft.revision,
      viewport: viewport,
      subject: _draft.subject,
      preheader: _draft.preheader,
      plainText: text,
    );
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: widget.schedule?.sendAt.toLocal().isAfter(now) == true
          ? widget.schedule!.sendAt.toLocal()
          : now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (!mounted || time == null) return;
    final instant = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!instant.isAfter(DateTime.now())) {
      setState(() => _lastError = 'Choisissez une date dans le futur.');
      return;
    }
    widget.onScheduleChanged!(
      NewsletterSchedule(sendAt: instant.toUtc(), timezoneLabel: 'UTC'),
    );
  }

  Future<void> _sendTest() async {
    final send = widget.onSendTest;
    if (!widget.capabilities.canTest || send == null || _isBusy) return;
    if (!await _flushSave() || !mounted) return;
    setState(() {
      _operation = NewsletterOperationKind.testing;
      _lastError = null;
    });
    try {
      final receipt = await send(_draft);
      if (!mounted) return;
      setState(() {
        _testReceipt = receipt;
        _operation = NewsletterOperationKind.idle;
        _inspectorTab = _InspectorTab.send;
      });
    } on NewsletterActionCancelled {
      if (!mounted) return;
      setState(() {
        _operation = NewsletterOperationKind.idle;
        _lastError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _operation = NewsletterOperationKind.failed;
        _lastError =
            'Opération non confirmée. Actualisez son état avant de réessayer.';
      });
    }
  }

  Future<void> _unschedule() async {
    final unschedule = widget.onUnschedule;
    if (!widget.capabilities.canUnschedule || unschedule == null || _isBusy) {
      return;
    }
    setState(() {
      _operation = NewsletterOperationKind.unscheduling;
      _lastError = null;
    });
    try {
      await unschedule(_draft.id);
      if (!mounted) return;
      setState(() => _operation = NewsletterOperationKind.idle);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _operation = NewsletterOperationKind.failed;
        _lastError =
            'Opération non confirmée. Actualisez son état avant de réessayer.';
      });
    }
  }

  Future<void> _loadAnalytics() async {
    final load = widget.onLoadAnalytics;
    if (!widget.capabilities.canViewAnalytics || load == null || _isBusy) {
      return;
    }
    setState(() {
      _operation = NewsletterOperationKind.loadingAnalytics;
      _lastError = null;
    });
    try {
      final analytics = await load(_draft.id);
      if (!mounted) return;
      setState(() {
        _analytics = analytics;
        _operation = NewsletterOperationKind.idle;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _operation = NewsletterOperationKind.failed;
        _lastError =
            'Opération non confirmée. Actualisez son état avant de réessayer.';
      });
    }
  }

  Future<void> _loadDeliveryStatus() async {
    final load = widget.onLoadDeliveryStatus;
    if (!widget.capabilities.canViewDeliveryStatus || load == null || _isBusy) {
      return;
    }
    setState(() {
      _operation = NewsletterOperationKind.loadingStatus;
      _lastError = null;
    });
    try {
      final deliveryStatus = await load(_draft.id);
      if (!mounted) return;
      setState(() {
        _deliveryStatus = deliveryStatus;
        _operation = NewsletterOperationKind.idle;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _operation = NewsletterOperationKind.failed;
        _lastError =
            'Opération non confirmée. Actualisez son état avant de réessayer.';
      });
    }
  }

  List<NewsletterValidationIssue> _localIssues() {
    final issues = <NewsletterValidationIssue>[...widget.validationIssues];
    void add(NewsletterValidationIssue issue) {
      if (!issues.any((candidate) => candidate.id == issue.id)) {
        issues.add(issue);
      }
    }

    if (_draft.subject.trim().isEmpty) {
      add(
        const NewsletterValidationIssue(
          id: 'subject-empty',
          severity: NewsletterIssueSeverity.blocker,
          title: 'Objet requis',
          message: 'Ajoutez un objet avant de vérifier l’envoi.',
          target: 'subject',
        ),
      );
    }
    final hasContent = _draft.blocks.any(
      (block) =>
          block.type != NewsletterBlockType.divider &&
          (block.type == NewsletterBlockType.button
              ? (block.label ?? block.text).trim().isNotEmpty
              : block.text.trim().isNotEmpty),
    );
    if (!hasContent) {
      add(
        const NewsletterValidationIssue(
          id: 'content-empty',
          severity: NewsletterIssueSeverity.blocker,
          title: 'Contenu requis',
          message: 'Ajoutez au moins un bloc de contenu.',
          target: 'content',
        ),
      );
    }
    if (_audience == null ||
        _audience?.isResolved != true ||
        (_audience?.eligibleCount ?? 0) == 0) {
      add(
        const NewsletterValidationIssue(
          id: 'audience-unresolved',
          severity: NewsletterIssueSeverity.blocker,
          title: 'Audience à vérifier',
          message: 'Vérifiez l’audience avant de programmer ou d’envoyer.',
          target: 'audience',
        ),
      );
    }
    if (widget.sender?.isVerified != true) {
      add(
        const NewsletterValidationIssue(
          id: 'sender-unverified',
          severity: NewsletterIssueSeverity.blocker,
          title: 'Expéditeur non vérifié',
          message: 'L’identité de l’expéditeur doit être vérifiée.',
          target: 'sender',
        ),
      );
    }
    if (_draft.preheader.trim().isEmpty) {
      add(
        const NewsletterValidationIssue(
          id: 'preheader-empty',
          severity: NewsletterIssueSeverity.warning,
          title: 'Texte d’aperçu manquant',
          message: 'Ajoutez un court texte qui complète l’objet.',
          target: 'preheader',
        ),
      );
    }
    if (widget.design?.hasPlainTextAlternative == false) {
      add(
        const NewsletterValidationIssue(
          id: 'plain-text-missing',
          severity: NewsletterIssueSeverity.blocker,
          title: 'Version texte manquante',
          message: 'Une version texte équivalente est requise.',
          target: 'design',
        ),
      );
    }
    final receipt = _testReceipt;
    if (receipt == null || receipt.draftRevision != _draft.revision) {
      add(
        const NewsletterValidationIssue(
          id: 'test-stale',
          severity: NewsletterIssueSeverity.warning,
          title: 'Version actuelle non testée',
          message: 'Envoyez un test de cette version du brouillon.',
          target: 'test',
        ),
      );
    }
    return issues;
  }

  Future<List<NewsletterValidationIssue>> _validate() async {
    final validate = widget.onValidateDraft;
    if (validate == null && widget.onResolveAudience == null) {
      return _localIssues();
    }
    setState(() {
      _operation = NewsletterOperationKind.validating;
      _lastError = null;
    });
    try {
      final resolve = widget.onResolveAudience;
      if (resolve != null) {
        final resolved = await resolve(_draft);
        if (!mounted) return _localIssues();
        setState(() => _audience = resolved);
      }
      final hostIssues = validate == null
          ? const <NewsletterValidationIssue>[]
          : await validate(_draft, _audience);
      if (!mounted) return _localIssues();
      setState(() => _operation = NewsletterOperationKind.idle);
      final merged = [..._localIssues()];
      for (final issue in hostIssues) {
        final index = merged.indexWhere(
          (candidate) => candidate.id == issue.id,
        );
        if (index < 0) {
          merged.add(issue);
        } else {
          merged[index] = issue;
        }
      }
      return merged;
    } catch (error) {
      if (mounted) {
        setState(() {
          _operation = NewsletterOperationKind.failed;
          _lastError =
              'Opération non confirmée. Actualisez son état avant de réessayer.';
        });
      }
      return [
        ..._localIssues(),
        NewsletterValidationIssue(
          id: 'host-validation-failed',
          severity: NewsletterIssueSeverity.blocker,
          title: 'Validation indisponible',
          message:
              'Opération non confirmée. Actualisez son état avant de réessayer.',
        ),
      ];
    }
  }

  Future<void> _openReview() async {
    if (_isBusy) return;
    if (!await _flushSave() || !mounted) return;
    var issues = await _validate();
    if (!mounted) return;
    _linkReportInReview = widget.linkReport;
    _linkCheckError = null;
    setState(() => _compactPage = _CompactPage.review);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close newsletter review',
      transitionDuration: widget.style.reviewTransitionDuration,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final width = MediaQuery.sizeOf(dialogContext).width;
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: _colors.surface,
            elevation: widget.style.reviewElevation,
            child: SafeArea(
              child: SizedBox(
                width: width < widget.style.compactBreakpoint
                    ? width
                    : widget.style.reviewPanelWidth,
                height: double.infinity,
                child: StatefulBuilder(
                  builder: (dialogContext, setReviewState) => _ReviewPanel(
                    draft: _draft,
                    audience: _audience,
                    sender: widget.sender,
                    schedule: widget.schedule,
                    testReceipt: _testReceipt,
                    issues: issues,
                    linkReport: _linkReportInReview,
                    onCheckLinks: widget.onCheckLinks == null
                        ? null
                        : () async {
                            final confirmed = await _confirmation(
                              dialogContext,
                              title: 'Vérifier les liens ? ',
                              message:
                                  'Cette vérification enverra des requêtes externes non authentifiées aux destinations du brouillon. Un GET limité peut suivre un HEAD refusé et provoquer un effet sur le site visé.',
                              action: 'Vérifier les liens',
                            );
                            if (!confirmed || !dialogContext.mounted) return;
                            setReviewState(() {
                              _linkCheckBusy = true;
                              _linkCheckError = null;
                            });
                            try {
                              final report = await widget.onCheckLinks!(_draft);
                              if (!dialogContext.mounted) return;
                              setReviewState(() {
                                _linkReportInReview = report;
                                _linkCheckBusy = false;
                              });
                            } catch (_) {
                              if (!dialogContext.mounted) return;
                              setReviewState(() {
                                _linkCheckBusy = false;
                                _linkCheckError =
                                    'La vérification n’a pas abouti. Actualisez son état avant de réessayer.';
                              });
                            }
                          },
                    linkCheckBusy: _linkCheckBusy,
                    linkCheckError: _linkCheckError,
                    onOpenLinkBlock: (blockId) =>
                        _focusLinkBlock(dialogContext, blockId),
                    capabilities: widget.capabilities,
                    style: widget.style,
                    colors: _colors,
                    isBusy: _isBusy,
                    onResolveAudience: widget.onResolveAudience == null
                        ? null
                        : () async {
                            await _resolveAudience();
                            final refreshed = await _validate();
                            if (!dialogContext.mounted) return;
                            setReviewState(() => issues = refreshed);
                          },
                    onSendTest: widget.onSendTest == null
                        ? null
                        : () async {
                            await _sendTest();
                            final refreshed = await _validate();
                            if (!dialogContext.mounted) return;
                            setReviewState(() => issues = refreshed);
                          },
                    onSchedule:
                        widget.schedule == null ||
                            (widget.onSchedule == null &&
                                widget.onScheduleWithLinkReport == null)
                        ? null
                        : ({required bool overrideUncertain}) =>
                              _confirmSchedule(
                                dialogContext,
                                issues,
                                report: _linkReportInReview,
                                overrideUncertain: overrideUncertain,
                              ),
                    onSend:
                        widget.onSend == null &&
                            widget.onSendWithLinkReport == null
                        ? null
                        : ({required bool overrideUncertain}) => _confirmSend(
                            dialogContext,
                            issues,
                            report: _linkReportInReview,
                            overrideUncertain: overrideUncertain,
                          ),
                    onClose: () => Navigator.pop(dialogContext),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: child,
        );
      },
    );
    _restoreWorkspaceFocus();
  }

  bool _linkCheckBusy = false;
  String? _linkCheckError;
  NewsletterLinkCheckReport? _linkReportInReview;

  void _focusLinkBlock(BuildContext reviewContext, String blockId) {
    if (!reviewContext.mounted) return;
    Navigator.pop(reviewContext);
    setState(() {
      _compactPage = _CompactPage.write;
      _showPreview = false;
      _selectedBlockId = blockId;
      _inspectorTab = _InspectorTab.content;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // The review route retains its focus scope until the reverse transition
      // finishes. Wait for it to leave the navigator before focusing the editor.
      await Future<void>.delayed(widget.style.reviewTransitionDuration);
      if (!mounted) return;
      final key = _blockKeys[blockId];
      final target = _blockUrlFocusNodes[blockId];
      final context = key?.currentContext;
      if (context != null && context.mounted) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.35,
          duration: widget.style.focusScrollDuration,
        );
      }
      target?.requestFocus();
    });
  }

  bool _hasBlockers(List<NewsletterValidationIssue> issues) {
    return issues.any(
      (issue) => issue.severity == NewsletterIssueSeverity.blocker,
    );
  }

  Future<void> _confirmSchedule(
    BuildContext reviewContext,
    List<NewsletterValidationIssue> issues, {
    NewsletterLinkCheckReport? report,
    bool overrideUncertain = false,
  }) async {
    if (_hasBlockers(issues) || !widget.capabilities.canSchedule) return;
    if (widget.onCheckLinks != null &&
        (report == null ||
            !report.isCurrentFor(_draft) ||
            report.hasBlockers ||
            (report.requiresOverride != overrideUncertain))) {
      return;
    }
    final schedule = widget.schedule;
    final callback = widget.onSchedule;
    final linkCallback = widget.onScheduleWithLinkReport;
    if (schedule == null || (callback == null && linkCallback == null)) return;
    final confirmed = await _confirmation(
      reviewContext,
      title: overrideUncertain
          ? 'Programmer malgré des liens non vérifiés ?'
          : 'Programmer cette newsletter ?',
      message: overrideUncertain
          ? 'Certains liens restent incertains. Cette dérogation sera enregistrée avec votre approbation.'
          : 'L’envoi sera demandé pour le ${_scheduleLabel(schedule)}.',
      action: overrideUncertain
          ? 'Déroger et programmer'
          : 'Confirmer la programmation',
    );
    if (!confirmed || !mounted || !reviewContext.mounted) return;
    Navigator.pop(reviewContext);
    setState(() => _operation = NewsletterOperationKind.scheduling);
    try {
      if (linkCallback != null && report != null) {
        await linkCallback(
          _draft,
          schedule,
          report,
          overrideUncertain: overrideUncertain,
        );
      } else if (callback != null) {
        await callback(_draft, schedule);
      }
      if (mounted) setState(() => _operation = NewsletterOperationKind.idle);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _operation = NewsletterOperationKind.failed;
        _lastError =
            'Opération non confirmée. Actualisez son état avant de réessayer.';
      });
    }
  }

  Future<void> _confirmSend(
    BuildContext reviewContext,
    List<NewsletterValidationIssue> issues, {
    NewsletterLinkCheckReport? report,
    bool overrideUncertain = false,
  }) async {
    if (_hasBlockers(issues) || !widget.capabilities.canSend) return;
    final callback = widget.onSend;
    final linkCallback = widget.onSendWithLinkReport;
    if (widget.onCheckLinks != null &&
        (report == null ||
            !report.isCurrentFor(_draft) ||
            report.hasBlockers ||
            (report.requiresOverride != overrideUncertain))) {
      return;
    }
    if (callback == null && linkCallback == null) return;
    final confirmed = await _confirmation(
      reviewContext,
      title: overrideUncertain
          ? 'Envoyer malgré des liens non vérifiés ?'
          : 'Envoyer cette newsletter maintenant ?',
      message: overrideUncertain
          ? 'Certains liens restent incertains. Cette dérogation sera enregistrée avec votre approbation.'
          : 'Cette action demande l’envoi à ${_audience?.eligibleCount ?? 0} destinataires éligibles.',
      action: overrideUncertain ? 'Déroger et envoyer' : 'Confirmer l’envoi',
      destructive: true,
    );
    if (!confirmed || !mounted || !reviewContext.mounted) return;
    Navigator.pop(reviewContext);
    setState(() => _operation = NewsletterOperationKind.sending);
    try {
      if (linkCallback != null && report != null) {
        await linkCallback(
          _draft,
          report,
          overrideUncertain: overrideUncertain,
        );
      } else if (callback != null) {
        await callback(_draft);
      }
      if (mounted) setState(() => _operation = NewsletterOperationKind.idle);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _operation = NewsletterOperationKind.failed;
        _lastError =
            'Opération non confirmée. Actualisez son état avant de réessayer.';
      });
    }
  }

  Future<bool> _confirmation(
    BuildContext context, {
    required String title,
    required String message,
    required String action,
    bool destructive = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                style: destructive
                    ? FilledButton.styleFrom(backgroundColor: _colors.danger)
                    : null,
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  String _scheduleLabel(NewsletterSchedule schedule) {
    final value = schedule.sendAt;
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)} ${schedule.timezoneLabel}';
  }

  void _cycleZone(int delta) {
    if (_isEditingText) return;
    final zones = [_sourcesFocus, _editorFocus, _inspectorFocus, _actionsFocus];
    var current = zones.indexWhere((node) => node.hasFocus);
    if (current < 0) current = 0;
    final next = (current + delta) % zones.length;
    zones[next < 0 ? zones.length - 1 : next].requestFocus();
  }

  void _closeTransientSurface() {
    if (_showPreview) {
      setState(() => _showPreview = false);
      return;
    }
    if (_compactPage != _CompactPage.write) {
      setState(() => _compactPage = _CompactPage.write);
      return;
    }
    widget.onBack?.call();
  }

  void _setZoom(double value) {
    final next = value
        .clamp(widget.style.minimumZoom, widget.style.maximumZoom)
        .toDouble();
    if (next == _zoom) return;
    setState(() => _zoom = next);
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        (!HardwareKeyboard.instance.isControlPressed &&
            !HardwareKeyboard.instance.isMetaPressed)) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      final scroll = resolved as PointerScrollEvent;
      if (scroll.scrollDelta.dy == 0) return;
      _setZoom(
        _zoom + (scroll.scrollDelta.dy < 0 ? 1 : -1) * widget.style.zoomStep,
      );
    });
  }

  Future<void> _showKeyboardHelp() async {
    if (_isEditingText) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Raccourcis clavier'),
        content: const SingleChildScrollView(
          child: Text(
            'J / K  Navigate sources\n'
            'X  Attach or detach source\n'
            'Enter  Open source\n'
            'F6 / Shift+F6  Change focus zone\n'
            'Ctrl/⌘+P  Preview\n'
            'Ctrl/⌘+Shift+T  Send test\n'
            'Ctrl/⌘+Enter  Open review\n'
            'Ctrl/⌘+0  Reset zoom\n'
            'Escape  Close current surface\n'
            'Tab / Shift+Tab  Move focus',
          ),
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
    _restoreWorkspaceFocus();
  }

  void _restoreWorkspaceFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _workspaceFocus.requestFocus();
    });
  }

  Map<ShortcutActivator, Intent> get _shortcutMap {
    final result = <ShortcutActivator, Intent>{};
    void bind(List<ShortcutActivator> bindings, Intent intent) {
      for (final binding in bindings) {
        result[binding] = intent;
      }
    }

    bind(widget.shortcuts.next, const _NextIntent());
    bind(widget.shortcuts.previous, const _PreviousIntent());
    bind(widget.shortcuts.toggleSource, const _ToggleSourceIntent());
    bind(widget.shortcuts.open, const _OpenIntent());
    bind(widget.shortcuts.nextZone, const _NextZoneIntent());
    bind(widget.shortcuts.previousZone, const _PreviousZoneIntent());
    bind(widget.shortcuts.preview, const _PreviewIntent());
    bind(widget.shortcuts.sendTest, const _TestIntent());
    bind(widget.shortcuts.review, const _ReviewIntent());
    bind(widget.shortcuts.close, const _CloseIntent());
    bind(widget.shortcuts.resetZoom, const _ResetZoomIntent());
    bind(widget.shortcuts.help, const _HelpIntent());
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: _shortcutMap,
      child: Actions(
        actions: {
          _NextIntent: _GuardedAction<_NextIntent>(
            canInvoke: () => !_isEditingText,
            onInvoke: (_) => _moveSourceSelection(1),
          ),
          _PreviousIntent: _GuardedAction<_PreviousIntent>(
            canInvoke: () => !_isEditingText,
            onInvoke: (_) => _moveSourceSelection(-1),
          ),
          _ToggleSourceIntent: _GuardedAction<_ToggleSourceIntent>(
            canInvoke: () => !_isEditingText,
            onInvoke: (_) => _toggleSelectedSource(),
          ),
          _OpenIntent: _GuardedAction<_OpenIntent>(
            canInvoke: () => !_isEditingText,
            onInvoke: (_) => _openSelectedSource(),
          ),
          _NextZoneIntent: _GuardedAction<_NextZoneIntent>(
            canInvoke: () => !_isEditingText,
            onInvoke: (_) => _cycleZone(1),
          ),
          _PreviousZoneIntent: _GuardedAction<_PreviousZoneIntent>(
            canInvoke: () => !_isEditingText,
            onInvoke: (_) => _cycleZone(-1),
          ),
          _PreviewIntent: CallbackAction<_PreviewIntent>(
            onInvoke: (_) => _togglePreview(),
          ),
          _TestIntent: CallbackAction<_TestIntent>(
            onInvoke: (_) => _sendTest(),
          ),
          _ReviewIntent: CallbackAction<_ReviewIntent>(
            onInvoke: (_) => _openReview(),
          ),
          _CloseIntent: CallbackAction<_CloseIntent>(
            onInvoke: (_) => _closeTransientSurface(),
          ),
          _ResetZoomIntent: CallbackAction<_ResetZoomIntent>(
            onInvoke: (_) => _setZoom(widget.style.initialZoom),
          ),
          _HelpIntent: _GuardedAction<_HelpIntent>(
            canInvoke: () => !_isEditingText,
            onInvoke: (_) => _showKeyboardHelp(),
          ),
        },
        child: Focus(
          focusNode: _workspaceFocus,
          autofocus: true,
          child: _ZoomViewport(
            zoom: _zoom,
            onPointerSignal: _handlePointerSignal,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return _buildWorkspace(constraints.maxWidth);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWorkspace(double width) {
    final compact = width < widget.style.compactBreakpoint;
    final expanded = width >= widget.style.expandedBreakpoint;
    return Material(
      color: _colors.canvas,
      child: Column(
        children: [
          Focus(
            focusNode: _actionsFocus,
            child: _TopBar(
              draft: _draft,
              audience: _audience,
              operation: _operation,
              testReceipt: _testReceipt,
              compact: compact,
              showPreview: _showPreview,
              capabilities: widget.capabilities,
              style: widget.style,
              colors: _colors,
              onBack: widget.onBack,
              onPreview: _togglePreview,
              onTest: _sendTest,
              onReview: _openReview,
              actions: widget.topBarActions,
            ),
          ),
          if (_lastError != null)
            _ErrorBanner(
              message: _lastError!,
              style: widget.style,
              colors: _colors,
              onDismiss: () => setState(() => _lastError = null),
            ),
          Expanded(
            child: compact
                ? _buildCompact()
                : _buildRegular(expanded: expanded),
          ),
        ],
      ),
    );
  }

  Widget _buildRegular({required bool expanded}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (expanded)
          SizedBox(
            width: widget.style.sourcePaneWidth,
            child: _buildSourcesPane(),
          )
        else
          _RailButton(
            tooltip: 'Ouvrir les sources',
            icon: Icons.library_books_outlined,
            style: widget.style,
            colors: _colors,
            onPressed: () => _showPanelSheet(_buildSourcesPane()),
          ),
        VerticalDivider(
          width: widget.style.dividerThickness,
          thickness: widget.style.dividerThickness,
          color: _colors.divider,
        ),
        Expanded(child: _showPreview ? _buildPreview() : _buildEditor()),
        VerticalDivider(
          width: widget.style.dividerThickness,
          thickness: widget.style.dividerThickness,
          color: _colors.divider,
        ),
        if (expanded)
          SizedBox(width: widget.style.inspectorWidth, child: _buildInspector())
        else
          _RailButton(
            tooltip: 'Ouvrir les réglages',
            icon: Icons.tune,
            style: widget.style,
            colors: _colors,
            onPressed: () => _showPanelSheet(_buildInspector()),
          ),
      ],
    );
  }

  Widget _buildCompact() {
    final body = switch (_compactPage) {
      _CompactPage.sources => _buildSourcesPane(),
      _CompactPage.write => _showPreview ? _buildPreview() : _buildEditor(),
      _CompactPage.review => _buildInspector(),
    };
    return Column(
      children: [
        Expanded(child: body),
        NavigationBar(
          height: widget.style.compactActionBarHeight,
          selectedIndex: _compactPage.index,
          onDestinationSelected: (index) {
            setState(() => _compactPage = _CompactPage.values[index]);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.library_books_outlined),
              label: 'Sources',
            ),
            NavigationDestination(
              icon: Icon(Icons.edit_note_outlined),
              label: 'Rédiger',
            ),
            NavigationDestination(
              icon: Icon(Icons.fact_check_outlined),
              label: 'Vérifier',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSourcesPane() {
    final used = _draft.usedSourceIds;
    return Focus(
      focusNode: _sourcesFocus,
      child: ColoredBox(
        color: _colors.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: widget.style.panelPadding,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Sources',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text('${_draft.sources.length} jointes'),
                ],
              ),
            ),
            Divider(
              height: widget.style.dividerThickness,
              thickness: widget.style.dividerThickness,
              color: _colors.divider,
            ),
            Expanded(
              child: widget.availableSources.isEmpty
                  ? _EmptyPanel(
                      icon: Icons.inbox_outlined,
                      title: 'Aucune source disponible',
                      message:
                          'The host has not supplied sources for this draft.',
                      style: widget.style,
                    )
                  : ListView.builder(
                      itemCount: widget.availableSources.length,
                      itemBuilder: (context, index) {
                        final source = widget.availableSources[index];
                        final attached = _draft.sources.any(
                          (candidate) => candidate.id == source.id,
                        );
                        final selected = source.id == _selectedSourceId;
                        final focusNode = _sourceFocusNodes.putIfAbsent(
                          source.id,
                          () => FocusNode(debugLabel: 'Source ${source.id}'),
                        );
                        final key = _sourceKeys.putIfAbsent(
                          source.id,
                          GlobalKey.new,
                        );
                        return _SourceRow(
                          key: key,
                          source: source,
                          selected: selected,
                          attached: attached,
                          used: used.contains(source.id),
                          focusNode: focusNode,
                          style: widget.style,
                          colors: _colors,
                          onSelected: () {
                            setState(() => _selectedSourceId = source.id);
                          },
                          onToggle: _toggleSelectedSource,
                          onInsert: _insertSelectedSource,
                          onOpen: widget.onOpenSource == null
                              ? null
                              : _openSelectedSource,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor() {
    return Focus(
      focusNode: _editorFocus,
      child: SingleChildScrollView(
        padding: widget.style.canvasPadding,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: widget.style.emailCanvasWidth,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _colors.surface,
                border: Border.all(
                  color: _colors.divider,
                  width: widget.style.dividerThickness,
                ),
                borderRadius: BorderRadius.circular(widget.style.panelRadius),
              ),
              child: Padding(
                padding: widget.style.canvasPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _titleController,
                      enabled: _canEdit,
                      maxLength: 160,
                      decoration: const InputDecoration(
                        labelText: 'Nom de la campagne',
                      ),
                      onChanged: (value) =>
                          _replaceDraft(_draft.copyWith(title: value)),
                    ),
                    if (widget.availableAudiences.isNotEmpty)
                      DropdownButtonFormField<String>(
                        initialValue:
                            widget.availableAudiences.any(
                              (item) => item.id == _audience?.id,
                            )
                            ? _audience?.id
                            : null,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Audience',
                        ),
                        items: widget.availableAudiences
                            .map(
                              (item) => DropdownMenuItem(
                                value: item.id,
                                child: Text(
                                  item.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _canEdit && widget.onAudienceChanged != null
                            ? (id) {
                                final selected = widget.availableAudiences
                                    .firstWhere((item) => item.id == id);
                                setState(() => _audience = selected);
                                widget.onAudienceChanged!(selected);
                              }
                            : null,
                      ),
                    if (widget.onScheduleChanged != null)
                      TextButton.icon(
                        onPressed: _canEdit ? _pickSchedule : null,
                        icon: const Icon(Icons.schedule),
                        label: Text(
                          widget.schedule == null
                              ? 'Choisir une date d’envoi'
                              : _scheduleLabel(widget.schedule!),
                        ),
                      ),
                    TextField(
                      controller: _subjectController,
                      focusNode: _subjectFocus,
                      enabled: _canEdit,
                      textInputAction: TextInputAction.next,
                      style: Theme.of(context).textTheme.headlineSmall,
                      decoration: const InputDecoration(
                        labelText: 'Objet',
                        hintText: 'Une bonne raison d’ouvrir cette newsletter',
                        border: InputBorder.none,
                      ),
                      onChanged: (value) {
                        _replaceDraft(_draft.copyWith(subject: value));
                      },
                    ),
                    TextField(
                      controller: _preheaderController,
                      enabled: _canEdit,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Texte d’aperçu',
                        hintText: 'Une phrase qui complète l’objet',
                        border: InputBorder.none,
                      ),
                      onChanged: (value) {
                        _replaceDraft(_draft.copyWith(preheader: value));
                      },
                    ),
                    SizedBox(height: widget.style.largeGap),
                    if (_draft.blocks.isEmpty)
                      _EmptyPanel(
                        icon: Icons.edit_note_outlined,
                        title: 'Commencez par un bloc ou une source',
                        message:
                            'Ajoutez du texte ou insérez un extrait de vos sources.',
                        style: widget.style,
                      )
                    else
                      for (var index = 0; index < _draft.blocks.length; index++)
                        Padding(
                          key: _blockKeys.putIfAbsent(
                            _draft.blocks[index].id,
                            GlobalKey.new,
                          ),
                          padding: EdgeInsets.only(
                            bottom: widget.style.mediumGap,
                          ),
                          child: _BlockCard(
                            block: _draft.blocks[index],
                            urlFocusNode: _blockUrlFocusNodes.putIfAbsent(
                              _draft.blocks[index].id,
                              () => FocusNode(
                                debugLabel:
                                    'Newsletter link ${_draft.blocks[index].id}',
                              ),
                            ),
                            selected:
                                _selectedBlockId == _draft.blocks[index].id,
                            canEdit: _canEdit,
                            canMoveUp: index > 0,
                            canMoveDown: index < _draft.blocks.length - 1,
                            style: widget.style,
                            colors: _colors,
                            onSelected: () {
                              setState(() {
                                _selectedBlockId = _draft.blocks[index].id;
                                _inspectorTab = _InspectorTab.content;
                              });
                            },
                            onChanged: _updateBlock,
                            onMoveUp: () =>
                                _moveBlock(_draft.blocks[index], -1),
                            onMoveDown: () =>
                                _moveBlock(_draft.blocks[index], 1),
                            onDelete: () => _removeBlock(_draft.blocks[index]),
                            onOpenSource:
                                widget.onOpenSource == null ||
                                    _draft.blocks[index].sourceId == null
                                ? null
                                : () async {
                                    await widget.onOpenSource!(
                                      _draft.blocks[index].sourceId!,
                                    );
                                  },
                          ),
                        ),
                    _AddBlockBar(
                      enabled: _canEdit,
                      style: widget.style,
                      onAdd: _addBlock,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final preview =
        _preview ?? _localPreview(NewsletterPreviewViewport.desktop);
    return SingleChildScrollView(
      padding: widget.style.canvasPadding,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.style.emailCanvasWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _colors.surface,
              border: Border.all(
                color: _colors.divider,
                width: widget.style.dividerThickness,
              ),
              borderRadius: BorderRadius.circular(widget.style.panelRadius),
            ),
            child: Padding(
              padding: widget.style.canvasPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.visibility_outlined),
                      SizedBox(width: widget.style.smallGap),
                      const Expanded(child: Text('Aperçu')),
                      Chip(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            widget.style.chipRadius,
                          ),
                        ),
                        label: Text(
                          preview.isApproximate
                              ? 'Aperçu approximatif · version ${preview.revision}'
                              : 'Aperçu généré · version ${preview.revision}',
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: widget.style.extraLargeGap),
                  Text(
                    preview.subject,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (preview.preheader.isNotEmpty) ...[
                    SizedBox(height: widget.style.smallGap),
                    Text(
                      preview.preheader,
                      style: TextStyle(color: _colors.mutedForeground),
                    ),
                  ],
                  SizedBox(height: widget.style.extraLargeGap),
                  SelectableText(preview.plainText),
                  SizedBox(height: widget.style.extraLargeGap),
                  Text(
                    'Vérifiez le rendu final dans votre boîte mail à l’aide d’un envoi test.',
                    style: TextStyle(color: _colors.mutedForeground),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInspector() {
    return Focus(
      focusNode: _inspectorFocus,
      child: ColoredBox(
        color: _colors.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: widget.style.panelPadding,
              child: Wrap(
                spacing: widget.style.smallGap,
                runSpacing: widget.style.smallGap,
                children: [
                  for (final entry in const {
                    _InspectorTab.content: 'Contenu',
                    _InspectorTab.design: 'Apparence',
                    _InspectorTab.audience: 'Audience',
                    _InspectorTab.send: 'Envoi',
                  }.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: _inspectorTab == entry.key,
                      showCheckmark: false,
                      onSelected: (_) =>
                          setState(() => _inspectorTab = entry.key),
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: widget.style.panelPadding,
                child: switch (_inspectorTab) {
                  _InspectorTab.content => _ContentInspector(
                    block: _selectedBlock,
                    sourceCount: _draft.sources.length,
                    usedSourceCount: _draft.usedSourceIds.length,
                    style: widget.style,
                    colors: _colors,
                  ),
                  _InspectorTab.design => _DesignInspector(
                    design: widget.design,
                    style: widget.style,
                    colors: _colors,
                  ),
                  _InspectorTab.audience => _AudienceInspector(
                    audience: _audience,
                    canResolve: widget.onResolveAudience != null,
                    isBusy: _isBusy,
                    style: widget.style,
                    colors: _colors,
                    onResolve: _resolveAudience,
                  ),
                  _InspectorTab.send => _SendInspector(
                    sender: widget.sender,
                    schedule: widget.schedule,
                    testReceipt: _testReceipt,
                    deliveryStatus: _deliveryStatus,
                    analytics: _analytics,
                    analyticsUnavailableReason:
                        widget.capabilities.analyticsUnavailableReason,
                    currentRevision: _draft.revision,
                    canUnschedule:
                        widget.schedule != null &&
                        widget.capabilities.canUnschedule &&
                        widget.onUnschedule != null,
                    canLoadAnalytics:
                        widget.capabilities.canViewAnalytics &&
                        widget.onLoadAnalytics != null,
                    canLoadDeliveryStatus:
                        widget.capabilities.canViewDeliveryStatus &&
                        widget.onLoadDeliveryStatus != null,
                    isBusy: _isBusy,
                    style: widget.style,
                    colors: _colors,
                    onUnschedule: _unschedule,
                    onLoadAnalytics: _loadAnalytics,
                    onLoadDeliveryStatus: _loadDeliveryStatus,
                  ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPanelSheet(Widget child) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height:
              MediaQuery.sizeOf(context).height *
              widget.style.panelSheetHeightFactor,
          child: child,
        ),
      ),
    );
    _restoreWorkspaceFocus();
  }
}

class _ZoomViewport extends StatelessWidget {
  const _ZoomViewport({
    required this.zoom,
    required this.onPointerSignal,
    required this.child,
  });
  final double zoom;
  final ValueChanged<PointerSignalEvent> onPointerSignal;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: onPointerSignal,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
            return child;
          }
          return ClipRect(
            child: FittedBox(
              key: const ValueKey('newsletter-studio-zoom'),
              alignment: Alignment.topLeft,
              fit: BoxFit.fill,
              child: SizedBox(
                key: const ValueKey('newsletter-studio-zoom-content'),
                width: constraints.maxWidth / zoom,
                height: constraints.maxHeight / zoom,
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.draft,
    required this.audience,
    required this.operation,
    required this.testReceipt,
    required this.compact,
    required this.showPreview,
    required this.capabilities,
    required this.style,
    required this.colors,
    required this.onBack,
    required this.onPreview,
    required this.onTest,
    required this.onReview,
    required this.actions,
  });
  final NewsletterDraft draft;
  final NewsletterAudienceSummary? audience;
  final NewsletterOperationKind operation;
  final NewsletterTestReceipt? testReceipt;
  final bool compact;
  final bool showPreview;
  final NewsletterStudioCapabilities capabilities;
  final NewsletterStudioStyle style;
  final NewsletterStudioColors colors;
  final VoidCallback? onBack;
  final VoidCallback onPreview;
  final VoidCallback onTest;
  final VoidCallback onReview;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    return Container(
      height: style.topBarHeight,
      padding: EdgeInsets.symmetric(horizontal: style.largeGap),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(
            color: colors.divider,
            width: style.dividerThickness,
          ),
        ),
      ),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              tooltip: 'Retour aux campagnes',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
            ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  draft.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  _saveLabel(draft.saveState, operation),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          if (!compact && audience != null)
            Padding(
              padding: EdgeInsets.only(right: style.smallGap),
              child: Chip(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(style.chipRadius),
                ),
                avatar: Icon(Icons.group_outlined, size: style.compactIconSize),
                label: Text('${audience!.eligibleCount} destinataires'),
              ),
            ),
          IconButton(
            tooltip: showPreview
                ? 'Return to editor (Ctrl/Command+P)'
                : 'Aperçu (Ctrl/Commande+P)',
            onPressed: capabilities.canPreview ? onPreview : null,
            icon: Icon(
              showPreview ? Icons.edit_outlined : Icons.visibility_outlined,
            ),
          ),
          if (!compact)
            TextButton.icon(
              onPressed: capabilities.canTest ? onTest : null,
              icon: const Icon(Icons.send_outlined),
              label: Text(
                testReceipt?.draftRevision == draft.revision
                    ? 'Test effectué'
                    : 'Test',
              ),
            ),
          SizedBox(width: style.smallGap),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: colors.primaryActionSurface,
              foregroundColor: colors.primaryActionForeground,
            ),
            onPressed: onReview,
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(compact ? 'Vérifier' : 'Vérifier et programmer'),
          ),
          ...actions,
        ],
      ),
    );
  }

  static String _saveLabel(
    NewsletterSaveState saveState,
    NewsletterOperationKind operation,
  ) {
    if (operation != NewsletterOperationKind.idle &&
        operation != NewsletterOperationKind.failed) {
      return switch (operation) {
        NewsletterOperationKind.validating => 'Validation…',
        NewsletterOperationKind.previewing => 'Préparation de l’aperçu…',
        NewsletterOperationKind.testing => 'Envoi du test…',
        NewsletterOperationKind.scheduling => 'Programmation…',
        NewsletterOperationKind.unscheduling =>
          'Annulation de la programmation…',
        NewsletterOperationKind.sending => 'Envoi…',
        NewsletterOperationKind.loadingStatus => 'Chargement de l’état…',
        NewsletterOperationKind.loadingAnalytics => 'Chargement des résultats…',
        _ => 'En cours…',
      };
    }
    return switch (saveState) {
      NewsletterSaveState.clean => 'À jour',
      NewsletterSaveState.dirty => 'Modifications non enregistrées',
      NewsletterSaveState.saving => 'Enregistrement…',
      NewsletterSaveState.saved => 'Enregistré',
      NewsletterSaveState.conflict => 'Conflit de versions',
      NewsletterSaveState.offline => 'Brouillon hors ligne',
      NewsletterSaveState.failed => 'Enregistrement impossible',
    };
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.source,
    required this.selected,
    required this.attached,
    required this.used,
    required this.focusNode,
    required this.style,
    required this.colors,
    required this.onSelected,
    required this.onToggle,
    required this.onInsert,
    required this.onOpen,
    super.key,
  });
  final NewsletterSourceReference source;
  final bool selected;
  final bool attached;
  final bool used;
  final FocusNode focusNode;
  final NewsletterStudioStyle style;
  final NewsletterStudioColors colors;
  final VoidCallback onSelected;
  final VoidCallback onToggle;
  final VoidCallback onInsert;
  final VoidCallback? onOpen;
  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      checked: attached,
      label:
          '${source.title}, ${attached ? 'attached' : 'not attached'}${used ? ', used' : ''}',
      child: Material(
        color: selected ? colors.selectedSurface : colors.surface,
        child: InkWell(
          focusNode: focusNode,
          onTap: onSelected,
          onDoubleTap: onInsert,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: style.largeGap,
              vertical: style.mediumGap,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: attached,
                  onChanged: (_) {
                    onSelected();
                    onToggle();
                  },
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: style.smallGap / 2),
                      Text(
                        source.publisher,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.mutedForeground),
                      ),
                      if (used)
                        Padding(
                          padding: EdgeInsets.only(top: style.smallGap),
                          child: const Text('Utilisée'),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Actions de la source',
                  onSelected: (value) {
                    onSelected();
                    if (value == 'insert') onInsert();
                    if (value == 'open') onOpen?.call();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'insert',
                      child: Text('Insérer un extrait'),
                    ),
                    if (onOpen != null)
                      const PopupMenuItem(
                        value: 'open',
                        child: Text('Ouvrir la source'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({
    required this.block,
    required this.urlFocusNode,
    required this.selected,
    required this.canEdit,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.style,
    required this.colors,
    required this.onSelected,
    required this.onChanged,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
    required this.onOpenSource,
  });
  final NewsletterBlock block;
  final FocusNode urlFocusNode;
  final bool selected;
  final bool canEdit;
  final bool canMoveUp;
  final bool canMoveDown;
  final NewsletterStudioStyle style;
  final NewsletterStudioColors colors;
  final VoidCallback onSelected;
  final ValueChanged<NewsletterBlock> onChanged;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;
  final VoidCallback? onOpenSource;
  @override
  Widget build(BuildContext context) {
    if (block.type == NewsletterBlockType.divider) {
      return _frame(
        context,
        child: Row(
          children: [
            Expanded(
              child: Divider(
                thickness: style.dividerThickness,
                color: colors.divider,
              ),
            ),
            _actions(),
          ],
        ),
      );
    }
    return _frame(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(_iconFor(block.type), size: style.compactIconSize),
              SizedBox(width: style.smallGap),
              Expanded(
                child: Text(
                  block.type.label.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              if (block.isProtected)
                Tooltip(
                  message: 'Bloc protégé',
                  child: Icon(Icons.lock_outline, size: style.compactIconSize),
                ),
              _actions(),
            ],
          ),
          SizedBox(height: style.smallGap),
          TextFormField(
            key: ValueKey('newsletter-block-${block.id}'),
            initialValue: block.text,
            enabled: canEdit && !block.isProtected,
            minLines: block.type == NewsletterBlockType.heading ? 1 : 2,
            maxLines: null,
            style: block.type == NewsletterBlockType.heading
                ? Theme.of(context).textTheme.titleLarge
                : null,
            decoration: InputDecoration(
              hintText: block.type == NewsletterBlockType.source
                  ? 'Extrait de la source'
                  : 'Rédigez votre contenu',
              border: InputBorder.none,
            ),
            onTap: onSelected,
            onChanged: (value) => onChanged(block.copyWith(text: value)),
          ),
          if (block.type == NewsletterBlockType.button) ...[
            TextFormField(
              key: ValueKey('newsletter-label-${block.id}'),
              initialValue: block.label,
              enabled: canEdit && !block.isProtected,
              decoration: const InputDecoration(labelText: 'Texte du bouton'),
              onChanged: (value) => onChanged(block.copyWith(label: value)),
            ),
          ],
          if (block.type == NewsletterBlockType.button ||
              block.type == NewsletterBlockType.source) ...[
            TextFormField(
              key: ValueKey('newsletter-url-${block.id}'),
              focusNode: urlFocusNode,
              initialValue: block.rawUrl ?? block.url?.toString(),
              enabled: canEdit && !block.isProtected,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: block.type == NewsletterBlockType.button
                    ? 'Lien du bouton'
                    : 'Lien de la source',
                hintText: 'https://…',
              ),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (value) {
                final uri = Uri.tryParse(value ?? '');
                return uri != null &&
                        uri.scheme == 'https' &&
                        uri.host.isNotEmpty &&
                        uri.userInfo.isEmpty &&
                        (uri.hasPort == false || uri.port == 443)
                    ? null
                    : 'Indiquez une adresse HTTPS complète.';
              },
              onChanged: (value) => onChanged(
                block.copyWith(
                  url: Uri.tryParse(value) ?? Uri(),
                  rawUrl: value,
                ),
              ),
            ),
          ],
          if (block.type == NewsletterBlockType.source && onOpenSource != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onOpenSource,
                icon: Icon(Icons.open_in_new, size: style.compactIconSize),
                label: Text(block.label ?? 'Ouvrir la source'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _frame(BuildContext context, {required Widget child}) {
    return Semantics(
      selected: selected,
      label: 'Bloc ${block.type.label}${block.isProtected ? ', protégé' : ''}',
      child: InkWell(
        onTap: onSelected,
        borderRadius: BorderRadius.circular(style.blockRadius),
        child: AnimatedContainer(
          duration: style.controlTransitionDuration,
          padding: style.blockPadding,
          decoration: BoxDecoration(
            color: selected ? colors.selectedSurface : colors.subtleSurface,
            border: Border.all(
              color: selected ? colors.focus : colors.divider,
              width: selected ? style.focusWidth : style.dividerThickness,
            ),
            borderRadius: BorderRadius.circular(style.blockRadius),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _actions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Monter le bloc',
          onPressed: canEdit && canMoveUp && !block.isProtected
              ? onMoveUp
              : null,
          icon: const Icon(Icons.keyboard_arrow_up),
        ),
        IconButton(
          tooltip: 'Descendre le bloc',
          onPressed: canEdit && canMoveDown && !block.isProtected
              ? onMoveDown
              : null,
          icon: const Icon(Icons.keyboard_arrow_down),
        ),
        IconButton(
          tooltip: 'Supprimer le bloc',
          onPressed: canEdit && !block.isProtected ? onDelete : null,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }

  static IconData _iconFor(NewsletterBlockType type) {
    return switch (type) {
      NewsletterBlockType.heading => Icons.title,
      NewsletterBlockType.text => Icons.notes,
      NewsletterBlockType.button => Icons.smart_button_outlined,
      NewsletterBlockType.divider => Icons.horizontal_rule,
      NewsletterBlockType.source => Icons.bookmark_outline,
    };
  }
}

class _AddBlockBar extends StatelessWidget {
  const _AddBlockBar({
    required this.enabled,
    required this.style,
    required this.onAdd,
  });
  final bool enabled;
  final NewsletterStudioStyle style;
  final ValueChanged<NewsletterBlockType> onAdd;
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: style.smallGap,
      runSpacing: style.smallGap,
      children: [
        for (final type in const [
          NewsletterBlockType.heading,
          NewsletterBlockType.text,
          NewsletterBlockType.button,
          NewsletterBlockType.divider,
        ])
          ActionChip(
            avatar: Icon(
              _BlockCard._iconFor(type),
              size: style.compactIconSize,
            ),
            label: Text('Ajouter : ${type.label}'),
            onPressed: enabled ? () => onAdd(type) : null,
          ),
      ],
    );
  }
}

class _ContentInspector extends StatelessWidget {
  const _ContentInspector({
    required this.block,
    required this.sourceCount,
    required this.usedSourceCount,
    required this.style,
    required this.colors,
  });
  final NewsletterBlock? block;
  final int sourceCount;
  final int usedSourceCount;
  final NewsletterStudioStyle style;
  final NewsletterStudioColors colors;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Contenu du brouillon',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        SizedBox(height: style.mediumGap),
        _SummaryRow(
          label: 'Sources jointes',
          value: '$sourceCount',
          style: style,
        ),
        _SummaryRow(
          label: 'Sources utilisées',
          value: '$usedSourceCount',
          style: style,
        ),
        SizedBox(height: style.extraLargeGap),
        Text('Bloc sélectionné', style: Theme.of(context).textTheme.titleSmall),
        SizedBox(height: style.smallGap),
        Text(
          block == null
              ? 'Sélectionnez un bloc pour consulter sa source.'
              : '${block!.type.label}${block!.sourceId == null ? '' : ' · lié à une source'}${block!.isProtected ? ' · protégé' : ''}',
          style: TextStyle(color: colors.mutedForeground),
        ),
      ],
    );
  }
}

class _DesignInspector extends StatelessWidget {
  const _DesignInspector({
    required this.design,
    required this.style,
    required this.colors,
  });
  final NewsletterDesignSummary? design;
  final NewsletterStudioStyle style;
  final NewsletterStudioColors colors;
  @override
  Widget build(BuildContext context) {
    final value = design;
    if (value == null) {
      return _EmptyPanel(
        icon: Icons.palette_outlined,
        title: 'Apparence à configurer',
        message:
            'La marque et le modèle d’email ne sont pas encore configurés.',
        style: style,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Apparence de l’email',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        SizedBox(height: style.mediumGap),
        _SummaryRow(label: 'Modèle', value: value.templateName, style: style),
        _SummaryRow(label: 'Marque', value: value.brandName, style: style),
        _SummaryRow(label: 'Langue', value: value.language, style: style),
        _SummaryRow(label: 'Direction', value: value.direction, style: style),
        _SummaryRow(
          label: 'Texte brut',
          value: value.hasPlainTextAlternative ? 'Disponible' : 'Manquant',
          style: style,
        ),
        SizedBox(height: style.largeGap),
        Text(
          'L’aperçu est indicatif. Vérifiez aussi le rendu du message test dans votre boîte mail.',
          style: TextStyle(color: colors.mutedForeground),
        ),
      ],
    );
  }
}

class _AudienceInspector extends StatelessWidget {
  const _AudienceInspector({
    required this.audience,
    required this.canResolve,
    required this.isBusy,
    required this.style,
    required this.colors,
    required this.onResolve,
  });
  final NewsletterAudienceSummary? audience;
  final bool canResolve;
  final bool isBusy;
  final NewsletterStudioStyle style;
  final NewsletterStudioColors colors;
  final VoidCallback onResolve;
  @override
  Widget build(BuildContext context) {
    final value = audience;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Audience', style: Theme.of(context).textTheme.titleMedium),
        SizedBox(height: style.mediumGap),
        if (value == null)
          Text(
            'L’audience n’a pas encore été vérifiée.',
            style: TextStyle(color: colors.mutedForeground),
          )
        else ...[
          _SummaryRow(label: 'Segment', value: value.label, style: style),
          _SummaryRow(
            label: 'Éligibles',
            value: '${value.eligibleCount}',
            style: style,
          ),
          _SummaryRow(
            label: 'Exclus',
            value: '${value.excludedCount}',
            style: style,
          ),
          _SummaryRow(
            label: 'État',
            value: value.isStale
                ? 'À actualiser'
                : value.isResolved
                ? 'Vérifiée'
                : 'En attente',
            style: style,
          ),
        ],
        SizedBox(height: style.largeGap),
        OutlinedButton.icon(
          onPressed: canResolve && !isBusy ? onResolve : null,
          icon: const Icon(Icons.refresh),
          label: const Text('Vérifier l’audience'),
        ),
        SizedBox(height: style.mediumGap),
        Text(
          'Seuls les destinataires éligibles au moment de l’envoi recevront le message.',
          style: TextStyle(color: colors.mutedForeground),
        ),
      ],
    );
  }
}

class _SendInspector extends StatelessWidget {
  const _SendInspector({
    required this.sender,
    required this.schedule,
    required this.testReceipt,
    required this.deliveryStatus,
    required this.analytics,
    required this.analyticsUnavailableReason,
    required this.currentRevision,
    required this.canUnschedule,
    required this.canLoadAnalytics,
    required this.canLoadDeliveryStatus,
    required this.isBusy,
    required this.style,
    required this.colors,
    required this.onUnschedule,
    required this.onLoadAnalytics,
    required this.onLoadDeliveryStatus,
  });
  final NewsletterSenderSummary? sender;
  final NewsletterSchedule? schedule;
  final NewsletterTestReceipt? testReceipt;
  final NewsletterDeliveryStatus? deliveryStatus;
  final Map<String, num>? analytics;
  final String? analyticsUnavailableReason;
  final int currentRevision;
  final bool canUnschedule;
  final bool canLoadAnalytics;
  final bool canLoadDeliveryStatus;
  final bool isBusy;
  final NewsletterStudioStyle style;
  final NewsletterStudioColors colors;
  final VoidCallback onUnschedule;
  final VoidCallback onLoadAnalytics;
  final VoidCallback onLoadDeliveryStatus;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Envoi', style: Theme.of(context).textTheme.titleMedium),
        SizedBox(height: style.mediumGap),
        _SummaryRow(
          label: 'De',
          value: sender?.address ?? 'Non configuré',
          style: style,
        ),
        _SummaryRow(
          label: 'Expéditeur',
          value: sender?.isVerified == true ? 'Vérifié' : 'Non vérifié',
          style: style,
        ),
        _SummaryRow(
          label: 'Test',
          value: testReceipt == null
              ? 'Non envoyé'
              : testReceipt!.draftRevision == currentRevision
              ? 'Version actuelle testée'
              : 'Test à renouveler',
          style: style,
        ),
        _SummaryRow(
          label: 'Programmation',
          value: schedule == null
              ? 'Non choisie'
              : '${schedule!.sendAt.toUtc()} (UTC)',
          style: style,
        ),
        _SummaryRow(
          label: 'État de l’envoi',
          value: deliveryStatus?.state.label ?? 'Non chargé',
          style: style,
        ),
        if (deliveryStatus != null)
          Text(
            deliveryStatus!.message,
            style: TextStyle(color: colors.mutedForeground),
          ),
        if (canLoadDeliveryStatus)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: isBusy ? null : onLoadDeliveryStatus,
              icon: const Icon(Icons.sync_outlined),
              label: Text(
                deliveryStatus == null
                    ? 'Charger l’état de l’envoi'
                    : 'Actualiser l’état de l’envoi',
              ),
            ),
          ),
        if (canUnschedule)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: isBusy ? null : onUnschedule,
              icon: const Icon(Icons.event_busy_outlined),
              label: const Text('Annuler la programmation'),
            ),
          ),
        if (analytics != null) ...[
          SizedBox(height: style.largeGap),
          Text('Résultats', style: Theme.of(context).textTheme.titleSmall),
          SizedBox(height: style.smallGap),
          for (final entry in analytics!.entries)
            _SummaryRow(
              label: entry.key,
              value: '${entry.value}',
              style: style,
            ),
        ],
        if (canLoadAnalytics)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: isBusy ? null : onLoadAnalytics,
              icon: const Icon(Icons.query_stats_outlined),
              label: Text(
                analytics == null
                    ? 'Charger les résultats'
                    : 'Actualiser les résultats',
              ),
            ),
          ),
        if (!canLoadAnalytics && analyticsUnavailableReason != null)
          Text(
            analyticsUnavailableReason!,
            style: TextStyle(color: colors.mutedForeground),
          ),
        SizedBox(height: style.largeGap),
        Text(
          'Vérifiez le récapitulatif avant de confirmer l’envoi.',
          style: TextStyle(color: colors.mutedForeground),
        ),
      ],
    );
  }
}

class _ReviewPanel extends StatelessWidget {
  const _ReviewPanel({
    required this.draft,
    required this.audience,
    required this.sender,
    required this.schedule,
    required this.testReceipt,
    required this.issues,
    required this.linkReport,
    required this.onCheckLinks,
    required this.linkCheckBusy,
    required this.linkCheckError,
    required this.onOpenLinkBlock,
    required this.capabilities,
    required this.style,
    required this.colors,
    required this.isBusy,
    required this.onResolveAudience,
    required this.onSendTest,
    required this.onSchedule,
    required this.onSend,
    required this.onClose,
  });
  final NewsletterDraft draft;
  final NewsletterAudienceSummary? audience;
  final NewsletterSenderSummary? sender;
  final NewsletterSchedule? schedule;
  final NewsletterTestReceipt? testReceipt;
  final List<NewsletterValidationIssue> issues;
  final NewsletterLinkCheckReport? linkReport;
  final Future<void> Function()? onCheckLinks;
  final bool linkCheckBusy;
  final String? linkCheckError;
  final ValueChanged<String> onOpenLinkBlock;
  final NewsletterStudioCapabilities capabilities;
  final NewsletterStudioStyle style;
  final NewsletterStudioColors colors;
  final bool isBusy;
  final VoidCallback? onResolveAudience;
  final VoidCallback? onSendTest;
  final Future<void> Function({required bool overrideUncertain})? onSchedule;
  final Future<void> Function({required bool overrideUncertain})? onSend;
  final VoidCallback onClose;
  bool get hasBlockers =>
      issues.any((issue) => issue.severity == NewsletterIssueSeverity.blocker);
  @override
  Widget build(BuildContext context) {
    final blockers = issues
        .where((issue) => issue.severity == NewsletterIssueSeverity.blocker)
        .toList();
    final warnings = issues
        .where((issue) => issue.severity == NewsletterIssueSeverity.warning)
        .toList();
    final reportCurrent = linkReport?.isCurrentFor(draft) ?? false;
    final linksReady = onCheckLinks == null || reportCurrent;
    final linkBlockers = reportCurrent && linkReport!.hasBlockers;
    final linkUncertain = reportCurrent && linkReport!.requiresOverride;
    final sendBlocked =
        hasBlockers || !linksReady || linkBlockers || linkCheckBusy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: widgetPadding(style),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Vérifier',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Fermer la vérification',
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Divider(
          height: style.dividerThickness,
          thickness: style.dividerThickness,
          color: colors.divider,
        ),
        Expanded(
          child: ListView(
            padding: widgetPadding(style),
            children: [
              _ReviewSummaryCard(
                icon: Icons.subject,
                label: 'Objet',
                value: draft.subject.isEmpty ? 'Manquant' : draft.subject,
                colors: colors,
              ),
              SizedBox(height: style.largeGap),
              _LinkReviewCard(
                report: linkReport,
                reportCurrent: reportCurrent,
                checkBusy: linkCheckBusy,
                checkError: linkCheckError,
                canCheck: onCheckLinks != null && !isBusy && !linkCheckBusy,
                onCheck: onCheckLinks,
                onOpenBlock: onOpenLinkBlock,
                style: style,
                colors: colors,
              ),
              _ReviewSummaryCard(
                icon: Icons.group_outlined,
                label: 'Audience',
                value: audience == null
                    ? 'Non vérifiée'
                    : '${audience!.eligibleCount} éligibles · ${audience!.excludedCount} exclus',
                colors: colors,
                action: onResolveAudience == null
                    ? null
                    : TextButton(
                        onPressed: onResolveAudience,
                        child: const Text('Actualiser'),
                      ),
              ),
              _ReviewSummaryCard(
                icon: Icons.alternate_email,
                label: 'Expéditeur',
                value: sender == null
                    ? 'Non configuré'
                    : '${sender!.name} · ${sender!.address}${sender!.isVerified ? '' : ' · unverified'}',
                colors: colors,
              ),
              _ReviewSummaryCard(
                icon: Icons.mark_email_read_outlined,
                label: 'Test',
                value: testReceipt == null
                    ? 'Non envoyé'
                    : testReceipt!.draftRevision == draft.revision
                    ? 'Version actuelle testée'
                    : 'Test antérieur aux modifications',
                colors: colors,
                action: onSendTest == null
                    ? null
                    : TextButton(
                        onPressed: onSendTest,
                        child: const Text('Envoyer un test'),
                      ),
              ),
              if (blockers.isNotEmpty) ...[
                SizedBox(height: style.largeGap),
                Text(
                  'Points à corriger',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                SizedBox(height: style.smallGap),
                for (final issue in blockers)
                  _IssueTile(issue: issue, colors: colors),
              ],
              if (warnings.isNotEmpty) ...[
                SizedBox(height: style.largeGap),
                Text(
                  'À vérifier',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                SizedBox(height: style.smallGap),
                for (final issue in warnings)
                  _IssueTile(issue: issue, colors: colors),
              ],
            ],
          ),
        ),
        Divider(
          height: style.dividerThickness,
          thickness: style.dividerThickness,
          color: colors.divider,
        ),
        Padding(
          padding: widgetPadding(style),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasBlockers)
                Padding(
                  padding: EdgeInsets.only(bottom: style.smallGap),
                  child: Text(
                    'Corrigez les points bloquants avant l’envoi.',
                    style: TextStyle(color: colors.danger),
                  ),
                ),
              if (linkBlockers)
                Padding(
                  padding: EdgeInsets.only(bottom: style.smallGap),
                  child: Text(
                    'Corrigez les liens bloquants et relancez la vérification.',
                    style: TextStyle(color: colors.danger),
                  ),
                ),
              if (onCheckLinks != null && !linksReady)
                Padding(
                  padding: EdgeInsets.only(bottom: style.smallGap),
                  child: Text(
                    'Une vérification actuelle et complète des liens est requise.',
                    style: TextStyle(color: colors.warning),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          !sendBlocked &&
                              !linkUncertain &&
                              !isBusy &&
                              capabilities.canSchedule
                          ? () => onSchedule?.call(overrideUncertain: false)
                          : null,
                      child: Text(
                        schedule == null
                            ? 'Choisir une date'
                            : 'Confirmer la programmation',
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: style.smallGap),
              if (!sendBlocked &&
                  !linkUncertain &&
                  !isBusy &&
                  capabilities.canSend &&
                  onSend != null)
                _SlideToSend(
                  label: 'Glisser pour envoyer maintenant',
                  accessibleActionLabel:
                      'Envoyer maintenant au clavier ou avec un lecteur d’écran',
                  colors: colors,
                  onComplete: () => onSend!(overrideUncertain: false),
                )
              else
                FilledButton(
                  onPressed: null,
                  child: const Text('Envoyer maintenant'),
                ),
              if (linkUncertain && !linkBlockers && linksReady) ...[
                SizedBox(height: style.smallGap),
                Text(
                  'Des destinations n’ont pas pu être confirmées. La dérogation sera enregistrée côté serveur.',
                  style: TextStyle(color: colors.warning),
                ),
                SizedBox(height: style.smallGap),
                if (capabilities.canSchedule && onSchedule != null)
                  OutlinedButton(
                    onPressed: !isBusy
                        ? () => onSchedule!.call(overrideUncertain: true)
                        : null,
                    child: const Text('Déroger et programmer'),
                  ),
                if (capabilities.canSend && onSend != null)
                  _SlideToSend(
                    label: 'Glisser pour déroger et envoyer',
                    accessibleActionLabel:
                        'Déroger et envoyer au clavier ou avec un lecteur d’écran',
                    colors: colors,
                    warning: true,
                    enabled: !isBusy,
                    onComplete: () => onSend!(overrideUncertain: true),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static EdgeInsetsGeometry widgetPadding(NewsletterStudioStyle style) {
    return style.panelPadding;
  }
}

class _SlideToSend extends StatefulWidget {
  const _SlideToSend({
    required this.label,
    required this.accessibleActionLabel,
    required this.colors,
    required this.onComplete,
    this.warning = false,
    this.enabled = true,
  });

  final String label;
  final String accessibleActionLabel;
  final NewsletterStudioColors colors;
  final Future<void> Function() onComplete;
  final bool warning;
  final bool enabled;

  @override
  State<_SlideToSend> createState() => _SlideToSendState();
}

class _SlideToSendState extends State<_SlideToSend> {
  double _value = 0;
  bool _locked = false;

  Future<void> _activate() async {
    if (!widget.enabled || _locked) return;
    setState(() => _locked = true);
    try {
      await widget.onComplete();
    } finally {
      if (mounted) {
        setState(() {
          _locked = false;
          _value = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final actionColor = widget.warning
        ? widget.colors.warning
        : widget.colors.primaryActionSurface;
    final foreground = widget.warning
        ? widget.colors.foreground
        : widget.colors.primaryActionForeground;
    final enabled = widget.enabled && !_locked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: widget.label,
          value: _value >= 0.98
              ? 'Prêt à confirmer'
              : 'Glissement ${(_value * 100).round()} pour cent',
          hint:
              'Faites glisser le curseur jusqu’au bout pour ouvrir la confirmation.',
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: actionColor,
              inactiveTrackColor: widget.colors.divider,
              thumbColor: actionColor,
              overlayColor: actionColor.withValues(alpha: 0.12),
              trackHeight: 8,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 16),
            ),
            child: Slider(
              value: _value,
              min: 0,
              max: 1,
              divisions: 24,
              semanticFormatterCallback: (value) =>
                  '${widget.label} : ${(value * 100).round()} pour cent',
              onChanged: enabled
                  ? (value) => setState(() => _value = value)
                  : null,
              onChangeEnd: enabled
                  ? (value) {
                      if (value >= 0.98) {
                        _activate();
                      } else {
                        setState(() => _value = 0);
                      }
                    }
                  : null,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: enabled ? _activate : null,
          icon: Icon(
            widget.warning ? Icons.warning_amber_outlined : Icons.send,
          ),
          label: Text(widget.accessibleActionLabel),
          style: TextButton.styleFrom(foregroundColor: foreground),
        ),
      ],
    );
  }
}

class _ReviewSummaryCard extends StatelessWidget {
  const _ReviewSummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
    this.action,
  });
  final IconData icon;
  final String label;
  final String value;
  final NewsletterStudioColors colors;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(value),
      trailing: action,
    );
  }
}

class _LinkReviewCard extends StatelessWidget {
  const _LinkReviewCard({
    required this.report,
    required this.reportCurrent,
    required this.checkBusy,
    required this.checkError,
    required this.canCheck,
    required this.onCheck,
    required this.onOpenBlock,
    required this.style,
    required this.colors,
  });

  final NewsletterLinkCheckReport? report;
  final bool reportCurrent;
  final bool checkBusy;
  final String? checkError;
  final bool canCheck;
  final Future<void> Function()? onCheck;
  final ValueChanged<String> onOpenBlock;
  final NewsletterStudioStyle style;
  final NewsletterStudioColors colors;

  @override
  Widget build(BuildContext context) {
    final status = reportCurrent ? report!.status : null;
    final color = switch (status) {
      NewsletterLinkReportStatus.clear => colors.success,
      NewsletterLinkReportStatus.blocked => colors.danger,
      NewsletterLinkReportStatus.uncertain => colors.warning,
      null => colors.mutedForeground,
    };
    final title = checkBusy
        ? 'Vérification des liens…'
        : !reportCurrent
        ? 'Liens non vérifiés pour cette version'
        : status == NewsletterLinkReportStatus.clear
        ? report!.findings.isEmpty
              ? 'Aucun lien à vérifier'
              : '${report!.validCount} lien(s) valides'
        : status == NewsletterLinkReportStatus.blocked
        ? '${report!.blockingCount} lien(s) à corriger'
        : '${report!.uncertainCount} lien(s) non vérifiés';
    final disclosure = report?.disclosure;

    return Container(
      decoration: BoxDecoration(
        color: colors.subtleSurface,
        borderRadius: BorderRadius.circular(style.panelRadius),
        border: Border.all(color: colors.divider),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(style.panelRadius),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: style.panelPadding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    status == NewsletterLinkReportStatus.clear
                        ? Icons.link
                        : status == NewsletterLinkReportStatus.blocked
                        ? Icons.link_off
                        : Icons.link_outlined,
                    color: color,
                  ),
                  SizedBox(width: style.smallGap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Liens',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        SizedBox(height: style.smallGap / 2),
                        Text(title, style: TextStyle(color: color)),
                        if (reportCurrent && report!.findings.isNotEmpty)
                          Text(
                            '${report!.validCount} valides · ${report!.blockingCount} bloquants · ${report!.uncertainCount} incertains',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        if (disclosure?.externalRequests == true &&
                            reportCurrent)
                          Padding(
                            padding: EdgeInsets.only(top: style.smallGap / 2),
                            child: Text(
                              'Requêtes externes effectuées. Un GET de secours limité peut avoir un effet sur la destination.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: canCheck ? onCheck : null,
                    icon: checkBusy
                        ? SizedBox(
                            width: style.compactIconSize,
                            height: style.compactIconSize,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(reportCurrent ? 'Revérifier' : 'Vérifier'),
                  ),
                ],
              ),
            ),
            if (checkError != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  style.panelPadding.horizontal / 2,
                  0,
                  style.panelPadding.horizontal / 2,
                  style.smallGap,
                ),
                child: Text(
                  checkError!,
                  style: TextStyle(color: colors.danger),
                ),
              ),
            if (reportCurrent && report!.findings.isNotEmpty)
              Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.symmetric(
                    horizontal: style.panelPadding.horizontal / 2,
                  ),
                  childrenPadding: EdgeInsets.fromLTRB(
                    style.panelPadding.horizontal / 2,
                    0,
                    style.panelPadding.horizontal / 2,
                    style.smallGap,
                  ),
                  title: Text(
                    '${report!.findings.length} destinations contrôlées',
                  ),
                  children: [
                    for (final finding in report!.findings)
                      _LinkFindingTile(
                        finding: finding,
                        colors: colors,
                        style: style,
                        onOpenBlock: onOpenBlock,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LinkFindingTile extends StatelessWidget {
  const _LinkFindingTile({
    required this.finding,
    required this.colors,
    required this.style,
    required this.onOpenBlock,
  });

  final NewsletterLinkFinding finding;
  final NewsletterStudioColors colors;
  final NewsletterStudioStyle style;
  final ValueChanged<String> onOpenBlock;

  @override
  Widget build(BuildContext context) {
    final blocker =
        finding.status == NewsletterLinkFindingStatus.broken ||
        finding.status == NewsletterLinkFindingStatus.staticBlocker;
    final uncertain = finding.status == NewsletterLinkFindingStatus.uncertain;
    final color = blocker
        ? colors.danger
        : uncertain
        ? colors.warning
        : colors.success;
    final reason = switch (finding.reason) {
      'missing_url' => 'URL manquante',
      'invalid_url' => 'URL invalide',
      'https_443_required' => 'HTTPS sur le port 443 requis',
      'credentials_not_allowed' => 'Identifiants interdits dans l’URL',
      'placeholder_url' => 'Destination provisoire',
      'anchor_link' =>
        'Lien d’ancre non pris en charge par la plupart des clients email',
      'timeout' ||
      'dns_timeout' ||
      'check_deadline' => 'Délai de vérification dépassé',
      'non_public_address' => 'Destination non publique refusée',
      'too_many_redirects' => 'Trop de redirections',
      _ when finding.httpStatus != null => 'Réponse HTTP ${finding.httpStatus}',
      _ => finding.reason ?? 'Résultat non vérifié',
    };
    final destination = finding.host.isEmpty
        ? 'Destination absente'
        : finding.host;
    return Padding(
      padding: EdgeInsets.only(bottom: style.smallGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              blocker
                  ? Icons.error_outline
                  : uncertain
                  ? Icons.warning_amber_outlined
                  : Icons.check_circle_outline,
              color: color,
            ),
            title: Text(
              destination,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(reason),
            trailing: Text('${finding.blockIds.length} bloc(s)'),
          ),
          Wrap(
            spacing: style.smallGap,
            children: [
              for (final blockId in finding.blockIds)
                TextButton.icon(
                  onPressed: () => onOpenBlock(blockId),
                  icon: const Icon(Icons.edit_outlined),
                  label: Text('Corriger le lien · $blockId'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IssueTile extends StatelessWidget {
  const _IssueTile({required this.issue, required this.colors});
  final NewsletterValidationIssue issue;
  final NewsletterStudioColors colors;
  @override
  Widget build(BuildContext context) {
    final blocker = issue.severity == NewsletterIssueSeverity.blocker;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        blocker ? Icons.error_outline : Icons.warning_amber_outlined,
        color: blocker ? colors.danger : colors.warning,
      ),
      title: Text(issue.title),
      subtitle: Text(issue.message),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    required this.style,
  });
  final String label;
  final String value;
  final NewsletterStudioStyle style;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: style.summaryRowVerticalPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label)),
          SizedBox(width: style.mediumGap),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.tooltip,
    required this.icon,
    required this.style,
    required this.colors,
    required this.onPressed,
  });
  final String tooltip;
  final IconData icon;
  final NewsletterStudioStyle style;
  final NewsletterStudioColors colors;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: colors.surface,
      child: SizedBox(
        width: style.railWidth,
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(top: style.mediumGap),
            child: IconButton(
              tooltip: tooltip,
              onPressed: onPressed,
              icon: Icon(icon),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.style,
    required this.colors,
    required this.onDismiss,
  });
  final String message;
  final NewsletterStudioStyle style;
  final NewsletterStudioColors colors;
  final VoidCallback onDismiss;
  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      backgroundColor: colors.danger.withValues(
        alpha: style.errorSurfaceOpacity,
      ),
      leading: Icon(Icons.error_outline, color: colors.danger),
      content: Text(message),
      actions: [TextButton(onPressed: onDismiss, child: const Text('Fermer'))],
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.message,
    required this.style,
  });
  final IconData icon;
  final String title;
  final String message;
  final NewsletterStudioStyle style;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(style.extraLargeGap),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: style.emptyStateIconSize),
            SizedBox(height: style.mediumGap),
            Text(title, textAlign: TextAlign.center),
            SizedBox(height: style.smallGap),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

enum _InspectorTab { content, design, audience, send }

enum _CompactPage { sources, write, review }

class _NextIntent extends Intent {
  const _NextIntent();
}

class _PreviousIntent extends Intent {
  const _PreviousIntent();
}

class _ToggleSourceIntent extends Intent {
  const _ToggleSourceIntent();
}

class _OpenIntent extends Intent {
  const _OpenIntent();
}

class _NextZoneIntent extends Intent {
  const _NextZoneIntent();
}

class _PreviousZoneIntent extends Intent {
  const _PreviousZoneIntent();
}

class _PreviewIntent extends Intent {
  const _PreviewIntent();
}

class _TestIntent extends Intent {
  const _TestIntent();
}

class _ReviewIntent extends Intent {
  const _ReviewIntent();
}

class _CloseIntent extends Intent {
  const _CloseIntent();
}

class _ResetZoomIntent extends Intent {
  const _ResetZoomIntent();
}

class _HelpIntent extends Intent {
  const _HelpIntent();
}

class _GuardedAction<T extends Intent> extends Action<T> {
  _GuardedAction({required this.canInvoke, required this.onInvoke});
  final bool Function() canInvoke;
  final Object? Function(T intent) onInvoke;
  @override
  bool isEnabled(T intent) => canInvoke();
  @override
  Object? invoke(T intent) => onInvoke(intent);
}

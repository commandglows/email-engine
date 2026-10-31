import 'package:flutter/material.dart';
import 'dispatch_copy.dart';
import 'dispatch_models.dart';
import 'email_cockpit_parts.dart';
import 'email_cockpit_tokens.dart';

/// Private contribution editor. Email body is never copied automatically.
class DispatchPanel extends StatefulWidget {
  const DispatchPanel({
    super.key,
    required this.repository,
    required this.mailboxId,
    required this.threadId,
    required this.messageId,
    this.analyze,
    this.initialAnalysis,
    this.analysisSetupRequired = false,
    this.onAnalysisSetup,
    this.copy = const DispatchPanelCopy(),
    this.collapsed = false,
    this.onToggleCollapsed,
  });

  /// Only the header row is shown; the form keeps its state.
  final bool collapsed;

  /// Shows the fold toggle in the header when the host can fold the panel.
  final VoidCallback? onToggleCollapsed;

  /// The host already knows the analysis needs setup (automatic triage hit a
  /// missing key): the panel explains it instead of a generic failure.
  final bool analysisSetupRequired;

  /// Opens the host's settings where the analysis key is added.
  final VoidCallback? onAnalysisSetup;
  final DispatchRepository repository;
  final String mailboxId, threadId, messageId;
  final DispatchAnalysisCallback? analyze;

  /// A suggestion prepared by automatic triage for [messageId], shown without
  /// asking; ignored when it was made for another message.
  final DispatchAnalysis? initialAnalysis;
  final DispatchPanelCopy copy;
  @override
  State<DispatchPanel> createState() => _DispatchPanelState();
}

class _DispatchPanelState extends State<DispatchPanel> {
  final _summary = TextEditingController(),
      _justification = TextEditingController(),
      _risks = TextEditingController(),
      _confidence = TextEditingController();
  final _selected = <String>{};
  DispatchContext? _context;
  List<ProjectDispatch> _history = [];
  String _type = 'other';
  String? _error;
  DispatchAnalysis? _analysis;
  // The host said the analysis provider needs setup (no API key).
  bool _setupRequired = false;
  bool _busy = true;
  bool _previewing = false;
  // Justification and risks are optional: folded until asked for or filled.
  bool _showDetails = false;
  String _filter = '';
  static const _filterMinDestinations = 12;
  static const _contributionTypes = [
    'newsletter_inspiration',
    'thematic_source',
    'potential_task',
    'other',
  ];
  // Retain only opaque identities while navigating within the current session.
  static final _pendingIds = Expando<Map<String, String>>();
  String get _threadKey => '${widget.mailboxId}/${widget.threadId}';
  Map<String, String> get _pendingByThread =>
      _pendingIds[widget.repository] ??= {};
  String? get _pending => _pendingByThread[_threadKey];
  set _pending(String? id) {
    if (id == null) {
      _pendingByThread.remove(_threadKey);
    } else {
      _pendingByThread[_threadKey] = id;
    }
  }

  bool _ready = false;
  Future<void> _analyze() async {
    if (_locked || !_ready || widget.analyze == null) return;
    final consent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Autoriser le pré-triage IA'),
        content: Text(widget.copy.consentBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Analyser cet email'),
          ),
        ],
      ),
    );
    if (consent != true || !mounted || _locked) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final analysis = await widget.analyze!(
        List.unmodifiable(_context!.destinations),
      );
      if (!mounted) return;
      final allowed = _context!.destinations.map((d) => d.id).toSet();
      if (analysis.sourceRevision != widget.messageId ||
          analysis.summary.trim().isEmpty ||
          analysis.summary.length > 4000 ||
          analysis.candidates.length > 5 ||
          analysis.risks.length > 10 ||
          analysis.risks.any((r) => r.length > 500) ||
          analysis.candidates.any(
            (c) =>
                !allowed.contains(c.destinationId) ||
                !c.confidence.isFinite ||
                c.confidence < 0 ||
                c.confidence > 1 ||
                !const [
                  'newsletter_inspiration',
                  'thematic_source',
                  'potential_task',
                  'other',
                ].contains(c.contributionType) ||
                c.justification.length > 2000 ||
                c.risks.length > 10 ||
                c.risks.any((r) => r.length > 500),
          )) {
        throw const DispatchException(code: 'invalid_analysis');
      }
      setState(() => _analysis = analysis);
    } catch (error) {
      if (error is DispatchException &&
          error.code == 'analysis_setup_required') {
        if (mounted) setState(() => _setupRequired = true);
        return;
      }
      if (mounted) {
        setState(
          () => _error =
              'Le pré-triage IA est indisponible. Vous pouvez préparer une proposition manuelle.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// An automatic analysis made earlier for this exact message, limited to the
  /// destinations still listed. It is only a suggestion, like a manual one.
  DispatchAnalysis? _initialAnalysis(DispatchContext context) {
    final initial = widget.initialAnalysis;
    if (initial == null || initial.sourceRevision != widget.messageId) {
      return null;
    }
    final allowed = context.destinations.map((d) => d.id).toSet();
    return DispatchAnalysis(
      sourceRevision: initial.sourceRevision,
      summary: initial.summary,
      candidates: initial.candidates
          .where((c) => allowed.contains(c.destinationId))
          .take(5)
          .toList(),
      risks: initial.risks.take(10).toList(),
      provider: initial.provider,
      model: initial.model,
      notices: initial.notices,
    );
  }

  void _applyCandidate(DispatchAnalysisCandidate candidate) {
    final destination = _destinationById(candidate.destinationId);
    if (_locked || _analysis == null || destination == null) return;
    setState(() {
      _summary.text = _analysis!.summary;
      _type = candidate.contributionType;
      _justification.text = candidate.justification;
      _confidence.text = candidate.confidence.toString();
      _risks.text = {
        ..._analysis!.risks,
        ...candidate.risks,
      }.take(10).join('\n');
      _showDetails = true;
      if (destination.available &&
          (_selected.contains(destination.id) || _selected.length < 5)) {
        _selected.add(destination.id);
      }
    });
  }

  bool get _locked =>
      _busy || _pending != null || _history.any((d) => d.unresolved);
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DispatchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Automatic triage may finish while this email is already open.
    final loaded = _context;
    if (_analysis == null &&
        loaded != null &&
        widget.initialAnalysis != oldWidget.initialAnalysis) {
      final initial = _initialAnalysis(loaded);
      if (initial != null) setState(() => _analysis = initial);
    }
  }

  @override
  void dispose() {
    for (final c in [_summary, _justification, _risks, _confidence]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _ready = false;
      _error = null;
    });
    try {
      final c = await widget.repository.context(widget.mailboxId);
      final h = await widget.repository.history(
        widget.mailboxId,
        widget.threadId,
      );
      if (mounted) {
        setState(() {
          _context = c;
          _history = h;
          _ready = true;
          _analysis ??= _initialAnalysis(c);
          if (!_filtering) _filter = '';
          if (_pending != null && h.any((d) => d.id == _pending!)) {
            _pending = null;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'La file de revue est indisponible. Actualisez avant de confirmer.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    if (_locked || !_ready) return;
    final confidence = _confidence.text.trim().isEmpty
        ? null
        : double.tryParse(_confidence.text.trim().replaceAll(',', '.'));
    final risks = _risks.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (_summary.text.trim().isEmpty ||
        _summary.text.trim().length > 4000 ||
        _justification.text.trim().length > 2000 ||
        _selected.isEmpty ||
        _selected.length > 5 ||
        risks.length > 10 ||
        risks.any((r) => r.length > 500) ||
        (_confidence.text.trim().isNotEmpty &&
            (confidence == null ||
                !confidence.isFinite ||
                confidence < 0 ||
                confidence > 1))) {
      setState(() => _error = widget.copy.validationError);
      return;
    }
    final p = DispatchProposal(
      dispatchId: DispatchProposal.newId(),
      expectedMessageId: widget.messageId,
      summary: _summary.text.trim(),
      contributionType: _type,
      justification: _justification.text.trim(),
      risks: risks,
      confidence: confidence,
      destinationIds: _selected.toList()..sort(),
    );
    setState(() {
      _busy = true;
      _previewing = true;
    });
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Confirmer le dispatch privé'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.copy.confirmIntro),
              for (final d in _context!.destinations.where(
                (d) => p.destinationIds.contains(d.id),
              ))
                Text('${d.label} · ${d.projectLabel ?? d.projectId}'),
              const Divider(),
              SelectableText(
                'Résumé : ${p.summary}\nType : ${p.contributionType}\nJustification : ${p.justification}\nConfiance : ${p.confidence ?? "non renseignée"}\nRisques : ${p.risks.isEmpty ? "aucun renseigné" : p.risks.join("\n")}',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Corriger'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Valider les destinations'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _previewing = false;
    if (confirmed != true) {
      setState(() => _busy = false);
      return;
    }
    _pending = p.dispatchId;
    await _act(
      () => widget.repository.confirm(widget.mailboxId, widget.threadId, p),
      initialConfirm: true,
    );
  }

  Future<void> _act(
    Future<ProjectDispatch> Function() action, {
    bool initialConfirm = false,
    String? recoveryId,
  }) async {
    var refreshMissing = false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await action();
      if (mounted) {
        setState(() {
          _history.removeWhere((v) => v.id == d.id);
          _history.insert(0, d);
          _pending = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (initialConfirm && e is DispatchException && !e.unknown) {
            _pending = null;
          }
          if (!initialConfirm &&
              e is DispatchException &&
              (e.code == 'not_found' || e.code == 'dispatch_expired') &&
              recoveryId != null &&
              _pending == recoveryId) {
            _pending = null;
            _ready = false;
            refreshMissing = true;
          }
          _error = e is DispatchException && e.code == 'dispatch_expired'
              ? 'Ce dispatch a dépassé sa conservation de 90 jours. Rechargez l’email si vous devez en préparer un nouveau.'
              : 'Résultat à vérifier. Actualisez les reçus ou récupérez le dispatch avant une nouvelle proposition.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (refreshMissing && mounted) await _load();
  }

  Future<void> _recover(String id) => _act(
    () => widget.repository.recover(widget.mailboxId, widget.threadId, id),
    recoveryId: id,
  );

  String _receiptAdvice(DispatchReceipt receipt) {
    final custom = widget.copy.receiptAdvice[receipt.errorCode];
    if (receipt.terminal) return custom ?? widget.copy.terminalAdvice;
    if (custom != null) return custom;
    return switch (receipt.errorCode) {
      'forbidden' => 'Accès refusé. Vérifiez vos droits sur ce projet.',
      'authorization_required' || 'connection_required' =>
        'Reconnectez votre accès à ce projet avant de reprendre.',
      'destination_unavailable' =>
        'La file du projet est indisponible. Reprenez quand elle est accessible.',
      'idempotency_conflict' =>
        'Un conflit est détecté. Vérifiez cette entrée dans la file du projet.',
      'invalid_payload' =>
        'Le projet a refusé cet apport. Vérifiez ses contraintes de revue.',
      'destination_changed' =>
        'La connexion du projet a changé. Vérifiez l’accès avant de reprendre.',
      'outcome_unknown' =>
        'Le résultat reste à vérifier. Réconciliez les reçus avant toute reprise.',
      _ =>
        receipt.state == DispatchReceiptState.failed ||
                receipt.state == DispatchReceiptState.unknown
            ? 'Vérifiez les reçus avant de reprendre cette destination.'
            : '',
    };
  }

  /// Destinations grouped by project in first-seen order. Each group lists the
  /// project-level target first, then new content, then the other sub-targets.
  /// Long lists are filtered; a group without a visible target is dropped.
  List<_DestinationGroup> get _groupedDestinations {
    final byProject = <String, List<DispatchDestination>>{};
    for (final d in _context?.destinations ?? const <DispatchDestination>[]) {
      byProject.putIfAbsent(d.projectId, () => []).add(d);
    }
    final filter = _filtering ? _filter.trim().toLowerCase() : '';
    final groups = <_DestinationGroup>[];
    for (final entry in byProject.entries) {
      final items = [
        ...entry.value.where((d) => d.kind == 'project'),
        ...entry.value.where((d) => d.kind == 'new_content'),
        ...entry.value.where(
          (d) => d.kind != 'project' && d.kind != 'new_content',
        ),
      ].where((d) => _matchesFilter(d, filter)).toList();
      if (items.isEmpty) continue;
      groups.add(
        _DestinationGroup(
          header: _groupHeader(entry.value, entry.key),
          items: items,
        ),
      );
    }
    return groups;
  }

  bool get _filtering =>
      (_context?.destinations.length ?? 0) > _filterMinDestinations;

  /// A checked destination stays visible so the selection is never hidden.
  bool _matchesFilter(DispatchDestination d, String filter) =>
      filter.isEmpty ||
      _selected.contains(d.id) ||
      d.label.toLowerCase().contains(filter) ||
      (d.projectLabel?.toLowerCase().contains(filter) ?? false);

  static String _groupHeader(List<DispatchDestination> items, String fallback) {
    for (final d in items) {
      final label = d.projectLabel;
      if (label != null && label.isNotEmpty) return label;
    }
    return fallback;
  }

  /// Relative age of the destination list, recomputed on every build.
  /// A future timestamp (clock skew) reads as "à l’instant".
  static String _freshnessLabel(DateTime generatedAt) {
    final minutes = DateTime.now()
        .toUtc()
        .difference(generatedAt.toUtc())
        .inMinutes;
    return minutes < 1
        ? 'Liste mise à jour à l’instant'
        : 'Liste mise à jour il y a $minutes min';
  }

  String _kindLabel(String kind) =>
      widget.copy.kindLabels[kind] ??
      DispatchPanelCopy.defaultKindLabels[kind] ??
      'Destination';

  String _contributionTypeLabel(String code) =>
      widget.copy.contributionTypeLabels[code] ??
      DispatchPanelCopy.defaultContributionTypeLabels[code] ??
      code;

  static IconData _kindIcon(String kind) => switch (kind) {
    'content_draft' => Icons.edit_note_outlined,
    'content_in_progress' => Icons.pending_actions_outlined,
    'content_idea' => Icons.tips_and_updates_outlined,
    'idea_pool' => Icons.lightbulb_outline,
    'published_article' => Icons.article_outlined,
    'new_content' => Icons.add_circle_outline,
    'project' => Icons.folder_outlined,
    _ => Icons.inbox_outlined,
  };

  /// The host's `disabled_reason` wins when present; otherwise the subtitle
  /// names the unavailability or the kind so the cue is not colour-only.
  String _destinationSubtitle(DispatchDestination d) {
    final reason = d.disabledReason;
    if (reason != null && reason.isNotEmpty) return reason;
    if (!d.available) return widget.copy.unavailableSubtitle;
    return d.kind == 'project' ? d.projectId : _kindLabel(d.kind);
  }

  /// Null once a refreshed destination list no longer contains the id.
  DispatchDestination? _destinationById(String id) {
    for (final d in _context?.destinations ?? const <DispatchDestination>[]) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// Receipt title: the destination label while the current list still has it.
  String _receiptTitle(DispatchReceipt r) {
    for (final d in _context?.destinations ?? const <DispatchDestination>[]) {
      if (d.id == r.destinationId) {
        return '${d.label} · ${d.projectLabel ?? d.projectId}';
      }
    }
    return '${r.projectId} · ${r.destinationId}';
  }

  String _receiptStateLabel(DispatchReceipt r) => switch (r.state) {
    DispatchReceiptState.accepted => widget.copy.acceptedReceipt,
    DispatchReceiptState.failed =>
      r.terminal ? widget.copy.terminalReceipt : 'Échec',
    DispatchReceiptState.unknown => 'Résultat inconnu',
    DispatchReceiptState.intent => 'En attente',
    DispatchReceiptState.inFlight => 'En cours',
  };

  /// One target as a selectable chip after its project name: the icon shows
  /// its kind, the tooltip names the kind or why it is unavailable.
  Widget _destinationChip(DispatchDestination d) => FilterChip(
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    avatar: Icon(_kindIcon(d.kind), size: 18),
    label: Text(d.label, maxLines: 1, overflow: TextOverflow.ellipsis),
    tooltip: _destinationSubtitle(d),
    selected: _selected.contains(d.id),
    onSelected: _locked || !d.available
        ? null
        : (v) => setState(() {
            if (v) {
              _selected.add(d.id);
            } else {
              _selected.remove(d.id);
            }
          }),
  );

  /// Pre-triage suggestions: a tonal block, one row per candidate destination.
  Widget _analysisBlock(DispatchAnalysis analysis) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: EmailCockpitLayout.smallGap),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(EmailCockpitLayout.tileRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(EmailCockpitLayout.mediumGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Suggestion IA · ${analysis.provider} · ${analysis.model}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: EmailCockpitLayout.smallGap),
              SelectableText(analysis.summary),
              for (final notice in analysis.notices)
                Padding(
                  padding: const EdgeInsets.only(
                    top: EmailCockpitLayout.smallGap,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.bolt_outlined,
                        size: 16,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: EmailCockpitLayout.smallGap),
                      Expanded(child: Text(notice)),
                    ],
                  ),
                ),
              for (final risk in analysis.risks) Text('Risque suggéré : $risk'),
              for (final candidate in analysis.candidates)
                _candidateTile(candidate),
            ],
          ),
        ),
      ),
    );
  }

  Widget _candidateTile(DispatchAnalysisCandidate candidate) {
    final theme = Theme.of(context);
    final destination = _destinationById(candidate.destinationId);
    if (destination == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: EmailCockpitLayout.smallGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(destination.label, style: theme.textTheme.titleSmall),
                Text(
                  [
                    '${_contributionTypeLabel(candidate.contributionType)} · ${(candidate.confidence * 100).round()} %',
                    if (candidate.justification.isNotEmpty)
                      candidate.justification,
                    ...candidate.risks,
                  ].join('\n'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _locked ? null : () => _applyCandidate(candidate),
            child: const Text('Utiliser'),
          ),
        ],
      ),
    );
  }

  /// One earlier dispatch with its receipts and, when unresolved, recovery.
  Widget _historyEntry(ProjectDispatch d) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: EmailCockpitLayout.smallGap),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(EmailCockpitLayout.tileRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(EmailCockpitLayout.mediumGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableText('Dispatch ${d.id}\n${d.summary}'),
              for (final r in d.receipts)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_receiptTitle(r)),
                  subtitle: SelectableText(
                    '${_receiptStateLabel(r)}${r.intakeId == null ? "" : " · ${r.intakeId}"}\n${_receiptAdvice(r)}',
                  ),
                ),
              if (d.unresolved)
                Padding(
                  padding: const EdgeInsets.only(
                    top: EmailCockpitLayout.smallGap,
                  ),
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _recover(d.id),
                    child: const Text(
                      'Réconcilier et reprendre les destinations restantes',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Counters appear only near the limit so empty fields stay one line tall.
  static Widget? _nearLimitCounter(
    BuildContext context, {
    required int currentLength,
    required int? maxLength,
    required bool isFocused,
  }) => maxLength == null || currentLength < maxLength * 0.8
      ? null
      : Text('$currentLength/$maxLength');

  static InputDecoration _dense(String label, {String? hint}) =>
      InputDecoration(isDense: true, labelText: label, hintText: hint);

  /// Fixed one-line header: title, guidance on hover, refresh and, when the
  /// host can fold the panel, the fold toggle. The whole bar toggles. Folded,
  /// it still says whether a suggestion or a selection is waiting.
  Widget _header(ThemeData theme, TextStyle? muted) {
    final collapsed = widget.collapsed;
    final status = !collapsed
        ? null
        : _analysis != null
        ? 'Suggestion IA prête'
        : _selected.isNotEmpty
        ? '${_selected.length} sur 5 au maximum'
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: widget.onToggleCollapsed,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              EmailCockpitLayout.gap,
              4,
              EmailCockpitLayout.smallGap,
              4,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.alt_route,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: EmailCockpitLayout.smallGap),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.copy.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Tooltip(
                        message: widget.copy.intro,
                        child: Icon(
                          Icons.info_outline,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (status != null) ...[
                        const SizedBox(width: EmailCockpitLayout.mediumGap),
                        Flexible(
                          child: Text(
                            status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: muted?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Actualiser les reçus',
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                  onPressed: _busy ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
                if (widget.onToggleCollapsed != null)
                  IconButton(
                    tooltip: collapsed
                        ? 'Déplier le dispatch'
                        : 'Replier le dispatch',
                    visualDensity: VisualDensity.compact,
                    iconSize: 20,
                    onPressed: widget.onToggleCollapsed,
                    icon: Icon(
                      collapsed ? Icons.expand_less : Icons.expand_more,
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Reserved height: the progress line never shifts the layout.
        SizedBox(
          height: 2,
          child: _busy && !_previewing
              ? const LinearProgressIndicator(minHeight: 2)
              : null,
        ),
      ],
    );
  }

  /// One quiet line for the AI state that is not an action: unavailable, or
  /// waiting for the provider key (with the host's shortcut to add it).
  Widget _aiLine(
    ThemeData theme,
    TextStyle? muted, {
    required IconData icon,
    required String text,
    Widget? action,
  }) => Row(
    children: [
      Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
      const SizedBox(width: EmailCockpitLayout.smallGap),
      Expanded(
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: muted,
        ),
      ),
      if (action != null) ...[
        const SizedBox(width: EmailCockpitLayout.smallGap),
        action,
      ],
    ],
  );

  Widget _body(ThemeData theme, TextStyle? muted) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (widget.analyze == null)
        _aiLine(
          theme,
          muted,
          icon: Icons.auto_awesome_outlined,
          text:
              'Analyse IA indisponible. Préparez une proposition manuelle à valider.',
        )
      else if (_setupRequired || widget.analysisSetupRequired)
        _aiLine(
          theme,
          muted,
          icon: Icons.key_outlined,
          text: widget.copy.analysisSetupRequired,
          action: widget.onAnalysisSetup == null
              ? null
              : TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: widget.onAnalysisSetup,
                  child: Text(widget.copy.analysisSetupAction),
                ),
        )
      else
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: _locked || !_ready ? null : _analyze,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Pré-trier cet email avec l’IA'),
          ),
        ),
      if (_analysis case final analysis?) _analysisBlock(analysis),
      if (_error != null) ...[
        const SizedBox(height: EmailCockpitLayout.smallGap),
        EmailNotice(_error!, error: true),
      ],
      if (_pending != null) ...[
        const SizedBox(height: EmailCockpitLayout.smallGap),
        OutlinedButton(
          onPressed: _busy ? null : () => _recover(_pending!),
          child: const Text('Récupérer le résultat incertain'),
        ),
      ],
      for (final d in _history) _historyEntry(d),
      const SizedBox(height: EmailCockpitLayout.mediumGap),
      TextField(
        controller: _summary,
        enabled: !_locked,
        maxLength: 4000,
        buildCounter: _nearLimitCounter,
        minLines: 2,
        maxLines: 6,
        decoration: _dense('Résumé factuel à transmettre'),
      ),
      const SizedBox(height: EmailCockpitLayout.smallGap),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              key: ValueKey(_type),
              initialValue: _type,
              isExpanded: true,
              decoration: _dense('Type d’apport'),
              items: [
                for (final code in _contributionTypes)
                  DropdownMenuItem(
                    value: code,
                    child: Text(
                      _contributionTypeLabel(code),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _locked ? null : (v) => setState(() => _type = v!),
            ),
          ),
          const SizedBox(width: EmailCockpitLayout.smallGap),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _confidence,
              enabled: !_locked,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: _dense('Confiance (0 à 1)', hint: 'Facultative'),
            ),
          ),
        ],
      ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: () => setState(() => _showDetails = !_showDetails),
          icon: Icon(
            _showDetails ? Icons.expand_less : Icons.expand_more,
            size: 18,
          ),
          label: const Text('Justification et risques (facultatif)'),
        ),
      ),
      if (_showDetails) ...[
        TextField(
          controller: _justification,
          enabled: !_locked,
          maxLength: 2000,
          buildCounter: _nearLimitCounter,
          minLines: 1,
          maxLines: 4,
          decoration: _dense('Justification'),
        ),
        const SizedBox(height: EmailCockpitLayout.smallGap),
        TextField(
          controller: _risks,
          enabled: !_locked,
          minLines: 1,
          maxLines: 4,
          decoration: _dense('Risques (un par ligne, maximum 10)'),
        ),
      ],
      const SizedBox(height: EmailCockpitLayout.mediumGap),
      // Title, each project and its targets flow on one row; a long list
      // wraps onto the next lines in the same order.
      Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: EmailCockpitLayout.smallGap,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Destinations', style: theme.textTheme.titleSmall),
                for (final group in _groupedDestinations) ...[
                  Semantics(
                    header: true,
                    child: Text(group.header, style: muted),
                  ),
                  for (final d in group.items) _destinationChip(d),
                ],
              ],
            ),
          ),
          if (_context?.generatedAt case final generatedAt?) ...[
            const SizedBox(width: EmailCockpitLayout.smallGap),
            Text(_freshnessLabel(generatedAt), style: muted),
          ],
        ],
      ),
      if (_filtering) ...[
        const SizedBox(height: EmailCockpitLayout.smallGap),
        TextField(
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.copy.filterHint,
            prefixIcon: const Icon(Icons.search, size: 18),
          ),
          onChanged: (v) => setState(() => _filter = v),
        ),
      ],
      if (_context?.destinations.isEmpty == true)
        Padding(
          padding: const EdgeInsets.only(top: EmailCockpitLayout.smallGap),
          child: EmailNotice(
            widget.copy.emptyDestinations,
            icon: Icons.folder_off_outlined,
          ),
        ),
    ],
  );

  /// Fixed footer: the selection count and the confirmation stay reachable
  /// while the form scrolls.
  Widget _footer(ThemeData theme, TextStyle? muted) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: EmailCockpitLayout.gap,
        vertical: EmailCockpitLayout.smallGap,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              '${_selected.length} sur 5 au maximum',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
          ),
          const SizedBox(width: EmailCockpitLayout.smallGap),
          Flexible(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              onPressed: _locked || !_ready ? null : _confirm,
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: const Text(
                'Revoir et confirmer le dispatch',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  /// Header and footer stay fixed; only the form scrolls when the host bounds
  /// the panel height. Unbounded (inside a scroll view) it lays out inline.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final header = _header(theme, muted);
    if (widget.collapsed) return header;
    final body = _body(theme, muted);
    const bodyPadding = EdgeInsets.fromLTRB(
      EmailCockpitLayout.gap,
      EmailCockpitLayout.smallGap,
      EmailCockpitLayout.gap,
      EmailCockpitLayout.gap,
    );
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          if (constraints.hasBoundedHeight)
            Flexible(
              child: SingleChildScrollView(padding: bodyPadding, child: body),
            )
          else
            Padding(padding: bodyPadding, child: body),
          _footer(theme, muted),
        ],
      ),
    );
  }
}

/// One project heading in the destination list, with its targets in order.
class _DestinationGroup {
  const _DestinationGroup({required this.header, required this.items});
  final String header;
  final List<DispatchDestination> items;
}

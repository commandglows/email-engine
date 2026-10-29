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
    this.copy = const DispatchPanelCopy(),
  });
  final DispatchRepository repository;
  final String mailboxId, threadId, messageId;
  final DispatchAnalysisCallback? analyze;
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
  bool _busy = true;
  bool _previewing = false;
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
    } catch (_) {
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

  /// Sub-targets are indented under their project so the hierarchy reads at a glance.
  Widget _destinationTile(DispatchDestination d) => CheckboxListTile(
    dense: true,
    contentPadding: EdgeInsetsDirectional.only(
      start: d.kind == 'project' ? EmailCockpitLayout.gap : 40.0,
      end: EmailCockpitLayout.gap,
    ),
    value: _selected.contains(d.id),
    secondary: Icon(_kindIcon(d.kind)),
    title: Text(d.label),
    subtitle: Text(_destinationSubtitle(d)),
    onChanged: _locked || !d.available
        ? null
        : (v) => setState(() {
            if (v == true) {
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
                  '${candidate.contributionType} · ${candidate.confidence}\n${candidate.justification}\n${candidate.risks.join("\n")}',
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final generatedAt = _context?.generatedAt;
    return Card(
      child: Padding(
        padding: EmailCockpitLayout.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: EmailCockpitLayout.smallGap,
              runSpacing: EmailCockpitLayout.smallGap,
              children: [
                Text(
                  widget.copy.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Actualiser les reçus'),
                ),
              ],
            ),
            Text(widget.copy.intro, style: muted),
            if (generatedAt != null)
              Text(_freshnessLabel(generatedAt), style: muted),
            const SizedBox(height: EmailCockpitLayout.gap),
            if (widget.analyze == null)
              const EmailNotice(
                'Analyse IA indisponible. Préparez une proposition manuelle à valider.',
                icon: Icons.auto_awesome_outlined,
              )
            else
              OutlinedButton.icon(
                onPressed: _locked || !_ready ? null : _analyze,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Pré-trier cet email avec l’IA'),
              ),
            if (_analysis case final analysis?) _analysisBlock(analysis),
            if (_busy && !_previewing) ...[
              const SizedBox(height: EmailCockpitLayout.smallGap),
              const LinearProgressIndicator(),
            ],
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
            const SizedBox(height: EmailCockpitLayout.largeGap),
            Text('Proposition', style: theme.textTheme.titleSmall),
            const SizedBox(height: EmailCockpitLayout.smallGap),
            TextField(
              controller: _summary,
              enabled: !_locked,
              maxLength: 4000,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Résumé factuel à transmettre',
              ),
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
                    decoration: const InputDecoration(
                      labelText: 'Type d’apport',
                    ),
                    items: [
                      for (final code in _contributionTypes)
                        DropdownMenuItem(
                          value: code,
                          child: Text(_contributionTypeLabel(code)),
                        ),
                    ],
                    onChanged: _locked
                        ? null
                        : (v) => setState(() => _type = v!),
                  ),
                ),
                const SizedBox(width: EmailCockpitLayout.mediumGap),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _confidence,
                    enabled: !_locked,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Confiance (0 à 1)',
                      hintText: 'Facultative',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: EmailCockpitLayout.smallGap),
            TextField(
              controller: _justification,
              enabled: !_locked,
              maxLength: 2000,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Justification'),
            ),
            const SizedBox(height: EmailCockpitLayout.smallGap),
            TextField(
              controller: _risks,
              enabled: !_locked,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Risques (un par ligne, maximum 10)',
              ),
            ),
            const SizedBox(height: EmailCockpitLayout.largeGap),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Destinations',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text('${_selected.length} sur 5 au maximum', style: muted),
              ],
            ),
            const SizedBox(height: EmailCockpitLayout.smallGap),
            if (_filtering) ...[
              TextField(
                decoration: InputDecoration(
                  isDense: true,
                  hintText: widget.copy.filterHint,
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => _filter = v),
              ),
              const SizedBox(height: EmailCockpitLayout.smallGap),
            ],
            for (final group in _groupedDestinations) ...[
              Semantics(
                header: true,
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: EmailCockpitLayout.smallGap,
                    bottom: 4,
                  ),
                  child: Text(group.header, style: theme.textTheme.labelLarge),
                ),
              ),
              Card.outlined(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (final d in group.items) _destinationTile(d)],
                ),
              ),
            ],
            if (_context?.destinations.isEmpty == true)
              Padding(
                padding: EdgeInsets.only(top: EmailCockpitLayout.smallGap),
                child: EmailNotice(
                  widget.copy.emptyDestinations,
                  icon: Icons.folder_off_outlined,
                ),
              ),
            const SizedBox(height: EmailCockpitLayout.largeGap),
            FilledButton.icon(
              onPressed: _locked || !_ready ? null : _confirm,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Revoir et confirmer le dispatch'),
            ),
          ],
        ),
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

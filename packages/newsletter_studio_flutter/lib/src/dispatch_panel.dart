import 'package:flutter/material.dart';
import 'dispatch_models.dart';
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
  });
  final DispatchRepository repository;
  final String mailboxId, threadId, messageId;
  final DispatchAnalysisCallback? analyze;
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
        content: const Text(
              'Le texte de cet email et le nom ou la description des projets candidats seront transmis au fournisseur IA configuré dans votre compte. '
          'Ses règles de conservation s’appliquent. Les suggestions restent privées et aucun projet ne recevra de contribution avant votre confirmation.',
        ),
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
    if (_locked || _analysis == null) return;
    setState(() {
      _summary.text = _analysis!.summary;
      _type = candidate.contributionType;
      _justification.text = candidate.justification;
      _confidence.text = candidate.confidence.toString();
      _risks.text = {
        ..._analysis!.risks,
        ...candidate.risks,
      }.take(10).join('\n');
      final destination = _context!.destinations.firstWhere(
        (d) => d.id == candidate.destinationId,
      );
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
      setState(
        () => _error =
            'Renseignez un résumé, de un à cinq projets et une confiance entre 0 et 1, ou laissez-la vide.',
      );
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
              const Text(
                'Ce contenu sera conservé dans la file privée de chaque projet sélectionné.',
              ),
              for (final d in _context!.destinations.where(
                (d) => p.destinationIds.contains(d.id),
              ))
                Text('${d.label} · ${d.projectId}'),
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

  String _receiptAdvice(DispatchReceipt receipt) => switch (receipt.errorCode) {
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

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: EmailCockpitLayout.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Dispatch vers les projets',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (widget.analyze == null)
            const Text(
              'Analyse IA indisponible. Préparez une proposition manuelle à valider.',
            )
          else
            OutlinedButton.icon(
              onPressed: _locked || !_ready ? null : _analyze,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Pré-trier cet email avec l’IA'),
            ),
          if (_analysis case final analysis?) ...[
            SelectableText(
              'Suggestion IA · ${analysis.provider} · ${analysis.model}\n${analysis.summary}',
            ),
            for (final risk in analysis.risks) Text('Risque suggéré : $risk'),
            for (final candidate in analysis.candidates)
              ListTile(
                title: Text(
                  _context!.destinations
                      .firstWhere((d) => d.id == candidate.destinationId)
                      .label,
                ),
                subtitle: Text(
                  '${candidate.contributionType} · ${candidate.confidence}\n${candidate.justification}\n${candidate.risks.join("\n")}',
                ),
                trailing: TextButton(
                  onPressed: _locked ? null : () => _applyCandidate(candidate),
                  child: const Text('Utiliser'),
                ),
              ),
          ],
          const Text(
            'Saisissez uniquement les éléments à transmettre et à conserver dans les files privées.',
          ),
          if (_busy && !_previewing) const LinearProgressIndicator(),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          TextButton.icon(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Actualiser les reçus'),
          ),
          if (_pending != null)
            OutlinedButton(
              onPressed: _busy ? null : () => _recover(_pending!),
              child: const Text('Récupérer le résultat incertain'),
            ),
          for (final d in _history) ...[
            SelectableText('Dispatch ${d.id}\n${d.summary}'),
            for (final r in d.receipts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${r.projectId} · ${r.destinationId}'),
                subtitle: SelectableText(
                  '${switch (r.state) {
                    DispatchReceiptState.accepted => "Reçu en revue privée",
                    DispatchReceiptState.failed => "Échec",
                    DispatchReceiptState.unknown => "Résultat inconnu",
                    DispatchReceiptState.intent => "En attente",
                    DispatchReceiptState.inFlight => "En cours",
                  }}${r.intakeId == null ? "" : " · ${r.intakeId}"}\n${_receiptAdvice(r)}',
                ),
              ),
            if (d.unresolved)
              OutlinedButton(
                onPressed: _busy ? null : () => _recover(d.id),
                child: const Text(
                  'Réconcilier et reprendre les destinations restantes',
                ),
              ),
            const Divider(),
          ],
          TextField(
            controller: _summary,
            enabled: !_locked,
            maxLength: 4000,
            minLines: 2,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Résumé factuel à transmettre',
            ),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey(_type),
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type d’apport'),
            items: const [
              DropdownMenuItem(
                value: 'newsletter_inspiration',
                child: Text('Inspiration de newsletter'),
              ),
              DropdownMenuItem(
                value: 'thematic_source',
                child: Text('Source thématique'),
              ),
              DropdownMenuItem(
                value: 'potential_task',
                child: Text('Tâche potentielle'),
              ),
              DropdownMenuItem(value: 'other', child: Text('Autre')),
            ],
            onChanged: _locked ? null : (v) => setState(() => _type = v!),
          ),
          TextField(
            controller: _justification,
            enabled: !_locked,
            maxLength: 2000,
            decoration: const InputDecoration(labelText: 'Justification'),
          ),
          TextField(
            controller: _confidence,
            enabled: !_locked,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Confiance facultative (0 à 1)',
            ),
          ),
          TextField(
            controller: _risks,
            enabled: !_locked,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Risques (un par ligne, maximum 10)',
            ),
          ),
          for (final d in _context?.destinations ?? <DispatchDestination>[])
            CheckboxListTile(
              value: _selected.contains(d.id),
              title: Text(d.label),
              subtitle: Text(
                d.available
                    ? d.projectId
                    : 'Connexion ou autorisation projet indisponible',
              ),
              onChanged: _locked || !d.available
                  ? null
                  : (v) => setState(() {
                      if (v == true) {
                        _selected.add(d.id);
                      } else {
                        _selected.remove(d.id);
                      }
                    }),
            ),
          if (_context?.destinations.isEmpty == true)
            const Text('Aucune destination projet configurée.'),
          FilledButton(
            onPressed: _locked || !_ready ? null : _confirm,
            child: const Text('Revoir et confirmer le dispatch'),
          ),
        ],
      ),
    ),
  );
}

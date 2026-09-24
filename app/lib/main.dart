import 'package:flutter/material.dart';
import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';

import 'campaign_repository.dart';
import 'central_email_api.dart';
import 'session_client.dart';
import 'engine_theme.dart';
import 'source_workspace.dart';

void main() {
  final client = createSessionClient();
  runApp(
    EmailEngineApp(
      api: CentralEmailApi(origin: Uri.parse(Uri.base.origin), client: client),
    ),
  );
}

/// The real operator application has no demo fallbacks or credential inputs.
class EmailEngineApp extends StatefulWidget {
  const EmailEngineApp({super.key, required this.api});
  final CentralEmailApi api;
  @override
  State<EmailEngineApp> createState() => _EmailEngineAppState();
}

class _EmailEngineAppState extends State<EmailEngineApp> {
  bool _dark = false;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ShipGlows · Email Engine',
    debugShowCheckedModeBanner: false,
    theme: EngineTheme.create(Brightness.light),
    darkTheme: EngineTheme.create(Brightness.dark),
    themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
    home: Builder(
      builder: (context) => ReaderSourceWorkspace(
        api: widget.api,
        darkMode: _dark,
        onToggleTheme: () => setState(() => _dark = !_dark),
        onOpenCampaign: (session) => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => _CampaignEditor(session: session)),
        ),
      ),
    ),
  );
}

class _CampaignEditor extends StatefulWidget {
  const _CampaignEditor({required this.session});
  final CampaignEditorSession session;
  @override
  State<_CampaignEditor> createState() => _CampaignEditorState();
}

class _CampaignEditorState extends State<_CampaignEditor> {
  late NewsletterDraft _draft;
  NewsletterAudienceSummary? _audience;
  NewsletterSchedule? _schedule;
  NewsletterTestReceipt? _test;
  bool _busy = false;
  bool _saved = true;
  bool _allowPop = false;
  bool get _canPause => const [
    'scheduled',
    'sending',
    'running',
    'fanout_complete',
  ].contains(widget.session.state);
  bool get _canResume =>
      widget.session.state == 'suspended' &&
      widget.session.record['block_reason'] != 'remaining_plan_reduced';
  bool get _canReduce => const [
    'scheduled',
    'sending',
    'running',
    'fanout_complete',
    'suspended',
    'paused',
  ].contains(widget.session.state);
  bool get _canApproveReducedPlan =>
      widget.session.state == 'suspended' &&
      widget.session.record['block_reason'] == 'remaining_plan_reduced';
  @override
  void initState() {
    super.initState();
    _draft = widget.session.draft;
    final scheduled = widget.session.record['scheduled_at'];
    if (scheduled is String) {
      _schedule = NewsletterSchedule(
        sendAt: DateTime.parse(scheduled),
        timezoneLabel: 'Heure locale',
      );
    }
    _audience = NewsletterAudienceSummary(
      id: widget.session.audienceId,
      label: widget.session.audienceId,
      eligibleCount: 0,
      isResolved: false,
    );
  }

  void _error(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error is EmailApiException
              ? error.message
              : 'L’action n’a pas abouti. Votre brouillon reste ouvert.',
        ),
      ),
    );
  }

  Future<bool> _confirmCampaignAction({
    required String title,
    required String message,
    required String confirmLabel,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Retour'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _pauseCampaign() async {
    if (_busy || !_canPause) return;
    final confirmed = await _confirmCampaignAction(
      title: 'Suspendre la campagne ?',
      message:
          'Les nouveaux départs seront arrêtés. Les messages déjà transmis ne peuvent pas être rappelés.',
      confirmLabel: 'Suspendre',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.session.pause();
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resumeCampaign() async {
    if (_busy || !_canResume) return;
    setState(() => _busy = true);
    try {
      final audience = await widget.session.refreshForResume();
      final blockers = widget.session.preflightIssues();
      if (blockers.isNotEmpty) {
        throw const EmailApiException('preflight_blocked');
      }
      if (!mounted) return;
      setState(() => _audience = audience);
      final confirmed = await _confirmCampaignAction(
        title: 'Reprendre cette campagne ?',
        message:
            'Le préflight frais autorise ${audience.eligibleCount} destinataires. La reprise relancera uniquement le plan déjà approuvé; les messages déjà transmis ne seront pas rappelés.',
        confirmLabel: 'Valider la reprise',
      );
      if (!confirmed || !mounted) return;
      await widget.session.resume();
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approveReducedPlan() async {
    if (_busy || !_canApproveReducedPlan) return;
    setState(() => _busy = true);
    try {
      final audience = await widget.session.refreshForReducedPlan();
      final blockers = widget.session.preflightIssues();
      if (blockers.isNotEmpty) {
        throw const EmailApiException('preflight_blocked');
      }
      if (!mounted) return;
      setState(() => _audience = audience);
      final confirmed = await _confirmCampaignAction(
        title: 'Approuver le plan réduit ? ',
        message:
            'Le nouveau préflight autorise ${audience.eligibleCount} destinataires. Une nouvelle approbation humaine relancera ce plan. Les messages déjà transmis ne seront pas rappelés.',
        confirmLabel: 'Approuver et relancer',
      );
      if (!confirmed || !mounted) return;
      await widget.session.approveReducedPlan();
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reduceCampaign() async {
    if (_busy || !_canReduce) return;
    setState(() => _busy = true);
    try {
      final plan = await widget.session.loadReductionSnapshot();
      if (!mounted) return;
      final initialSelection = plan.reducibleRecipients
          .map((row) => row['recipient_reference'] as String)
          .toSet();
      final selected = await showDialog<Set<String>>(
        context: context,
        builder: (dialogContext) {
          final current = {...initialSelection};
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final removed = initialSelection.length - current.length;
              final removedReferences = plan.reducibleRecipients
                  .where((row) => !current.contains(row['recipient_reference']))
                  .map(
                    (row) => (row['recipient_reference'] as String).substring(
                      (row['recipient_reference'] as String).length > 12
                          ? (row['recipient_reference'] as String).length - 12
                          : 0,
                    ),
                  )
                  .toList();
              return AlertDialog(
                title: const Text('Réduire les prochains départs'),
                content: SizedBox(
                  width: 560,
                  height: 440,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Choisissez les références anonymisées qui restent dans le plan. Aucune adresse email n’est affichée.',
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${current.length} références resteront sélectionnées; $removed seront exclues des prochains départs.',
                      ),
                      if (removedReferences.isNotEmpty)
                        Text('À exclure : ${removedReferences.join(', ')}'),
                      if (plan.protectedCount > 0)
                        Text(
                          '${plan.protectedCount} déjà transmises, livrées ou à résultat incertain resteront protégées.',
                        ),
                      if (plan.lockedCount > plan.protectedCount)
                        Text(
                          '${plan.lockedCount - plan.protectedCount} références sont déjà hors du plan modifiable.',
                        ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: plan.reducibleRecipients.isEmpty
                            ? const Center(
                                child: Text(
                                  'Aucune référence encore modifiable.',
                                ),
                              )
                            : ListView.builder(
                                itemCount: plan.reducibleRecipients.length,
                                itemBuilder: (context, index) {
                                  final row = plan.reducibleRecipients[index];
                                  final id =
                                      row['recipient_reference'] as String;
                                  final included = current.contains(id);
                                  return CheckboxListTile(
                                    value: included,
                                    onChanged: (value) => setDialogState(() {
                                      if (value == true) {
                                        current.add(id);
                                      } else {
                                        current.remove(id);
                                      }
                                    }),
                                    title: Text(
                                      'Référence ${index + 1} · ${_recipientStateLabel(row['state'])}',
                                    ),
                                    subtitle: Text(
                                      '${id.substring(id.length > 12 ? id.length - 12 : 0)}${row['reason'] == null ? '' : ' · ${row['reason']}'}',
                                    ),
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Retour'),
                  ),
                  FilledButton.icon(
                    onPressed: current.isEmpty || removed == 0
                        ? null
                        : () => Navigator.pop(dialogContext, {...current}),
                    icon: const Icon(Icons.filter_alt_outlined),
                    label: const Text('Confirmer la réduction'),
                  ),
                ],
              );
            },
          );
        },
      );
      if (selected == null || !mounted) return;
      await widget.session.reduceRemainingPlan(
        selected.toList(),
        expectedVersion: plan.version,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Plan réduit. Un nouveau préflight et une approbation humaine sont requis avant reprise.',
            ),
          ),
        );
      }
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _recipientStateLabel(Object? state) => switch (state) {
    'queued' => 'En attente',
    'snapshot' => 'À envoyer',
    _ => 'État ${state ?? 'inconnu'}',
  };

  Future<void> _showIncidents() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final incidents = await widget.session.loadIncidents();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Incidents de diffusion'),
          content: SizedBox(
            width: 560,
            child: incidents.isEmpty
                ? const Text(
                    'Aucune fiche durable n’est enregistrée. Le moteur d’évaluation calcule des transitions localement mais aucun traitement serveur ne peuple actuellement ce registre.',
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final incident in incidents)
                        _IncidentCard(incident: incident),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<NewsletterDraft> _save(NewsletterDraft draft) async {
    try {
      final saved = await widget.session.save(draft);
      return saved;
    } on EmailApiException catch (error) {
      _error(error);
      if (const [
        'version_conflict',
        'stale_version',
        'conflict',
      ].contains(error.code)) {
        throw const NewsletterSaveConflict();
      }
      rethrow;
    }
  }

  Future<void> _back() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!_saved && widget.session.state == 'draft') {
        if (_draft.saveState == NewsletterSaveState.conflict) {
          final discard = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Conflit de versions'),
              content: const Text(
                'Copiez vos modifications avant de quitter. La version enregistrée sur le serveur sera conservée.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Rester dans le brouillon'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Quitter sans enregistrer'),
                ),
              ],
            ),
          );
          if (discard != true || !mounted) return;
        } else {
          // The session serializes this latest snapshot behind pending writes.
          // Never infer saved state from equal revisions: keystrokes may share it.
          await _save(_draft);
        }
      }
      if (mounted) {
        setState(() {
          _allowPop = true;
          _busy = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<NewsletterTestReceipt> _sendTest(NewsletterDraft draft) async {
    final recipients = widget.session.business.testRecipients;
    final recipient = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Recevoir un email test'),
        children: [
          for (final address in recipients)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, address),
              child: Text(address),
            ),
        ],
      ),
    );
    if (recipient == null) throw const NewsletterActionCancelled();
    final receipt = await widget.session.test(draft, recipient);
    if (mounted) setState(() => _test = receipt);
    return receipt;
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final business = session.business;
    final editable = session.state == 'draft' && !_busy;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_busy) _back();
      },
      child: Scaffold(
        body: NewsletterStudio(
          key: ValueKey(session.id),
          draft: _draft,
          onDraftChanged: (draft) => setState(() {
            _draft = draft;
            if (draft.saveState == NewsletterSaveState.dirty) _test = null;
            _saved =
                draft.saveState == NewsletterSaveState.saved ||
                draft.saveState == NewsletterSaveState.clean;
          }),
          audience: _audience,
          availableAudiences: business.audiences
              .map(
                (a) => NewsletterAudienceSummary(
                  id: a['id'] as String,
                  label: a['id'] as String,
                  eligibleCount: 0,
                  isResolved: false,
                ),
              )
              .toList(),
          onAudienceChanged: (audience) async {
            if (_busy) return;
            setState(() => _busy = true);
            try {
              await session.selectAudience(audience.id, _draft);
              if (mounted) {
                setState(() {
                  _audience = audience;
                  _test = null;
                });
              }
            } catch (error) {
              _error(error);
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
          sender: NewsletterSenderSummary(
            name: business.brand,
            address: business.from,
            replyTo: business.from,
            isVerified: business.canApprove,
          ),
          design: NewsletterDesignSummary(
            templateName: 'Éditorial',
            brandName: business.brand,
          ),
          schedule: _schedule,
          onScheduleChanged: (value) => setState(() => _schedule = value),
          testReceipt: _test,
          capabilities: NewsletterStudioCapabilities(
            canEdit: editable,
            canPreview: !_busy,
            canTest:
                editable &&
                business.canTest &&
                business.testRecipients.isNotEmpty,
            canSchedule: editable && business.canApprove,
            canSend: editable && business.canApprove,
            canUnschedule: !_busy && session.state == 'scheduled',
            canViewDeliveryStatus: true,
            analyticsUnavailableReason:
                'Résultats analytiques indisponibles : les événements existent, mais aucun read model complet et borné n’est exposé. Aucun taux n’est estimé.',
          ),
          onSaveDraft: _save,
          onResolveAudience: (draft) async {
            final audience = await session.resolve(draft);
            if (mounted) setState(() => _audience = audience);
            return audience;
          },
          // The studio adopts onResolveAudience before checking blockers.
          onValidateDraft: (draft, audience) async =>
              widget.session.preflightIssues(),
          onRenderPreview: session.preview,
          onSendTest: _sendTest,
          onSend: (draft) async {
            final receipt = await session.approve(draft);
            if (mounted) setState(() {});
            return receipt;
          },
          onSchedule: (draft, schedule) async {
            final receipt = await session.approve(draft, schedule);
            if (mounted) setState(() {});
            return receipt;
          },
          onUnschedule: (_) async {
            await session.cancel();
            if (mounted) setState(() {});
          },
          onLoadDeliveryStatus: (_) async {
            final status = await session.delivery();
            if (mounted) setState(() {});
            return status;
          },
          onBack: _back,
          topBarActions: [
            if (_canPause)
              IconButton(
                tooltip: 'Suspendre la campagne',
                onPressed: _busy ? null : _pauseCampaign,
                icon: const Icon(Icons.pause_circle_outline),
              ),
            if (_canResume)
              IconButton(
                tooltip: 'Vérifier et reprendre la campagne',
                onPressed: _busy ? null : _resumeCampaign,
                icon: const Icon(Icons.play_circle_outline),
              ),
            if (_canApproveReducedPlan)
              IconButton(
                tooltip: 'Vérifier et approuver le plan réduit',
                onPressed: _busy ? null : _approveReducedPlan,
                icon: const Icon(Icons.fact_check_outlined),
              ),
            if (_canReduce)
              IconButton(
                tooltip: 'Réduire les prochains départs',
                onPressed: _busy ? null : _reduceCampaign,
                icon: const Icon(Icons.filter_alt_outlined),
              ),
            IconButton(
              tooltip: 'Consulter les incidents (lecture seule)',
              onPressed: _busy ? null : _showIncidents,
              icon: const Icon(Icons.report_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncidentCard extends StatelessWidget {
  const _IncidentCard({required this.incident});

  final Map<String, dynamic> incident;

  @override
  Widget build(BuildContext context) {
    final state = incident['state'] as String? ?? 'unknown';
    final (label, icon) = switch (state) {
      'open' => ('Ouvert', Icons.error_outline),
      'acknowledged' => ('Pris en compte', Icons.visibility_outlined),
      'resolved' => ('Résolu', Icons.check_circle_outline),
      _ => ('État inconnu', Icons.help_outline),
    };
    final transition = incident['last_transition'];
    final reason = transition is Map
        ? transition['reason']?.toString() ?? 'Motif non enregistré'
        : 'Motif non enregistré';
    final updatedAt = incident['record_updated_at'];
    final recordTime = updatedAt is num
        ? DateTime.fromMillisecondsSinceEpoch(
            updatedAt.toInt(),
          ).toLocal().toString()
        : 'inconnue';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon),
              title: Text(
                '$label · ${incident['rule_id'] ?? 'Règle inconnue'}',
              ),
              subtitle: Text('Épisode ${incident['episode'] ?? 'inconnu'}'),
            ),
            Text('Motif enregistré : $reason'),
            Text(
              'Sévérité enregistrée : ${incident['severity'] ?? 'indisponible'}',
            ),
            const Text(
              'Mesure, seuil, échantillon et couverture : indisponibles, non persistés.',
            ),
            const Text(
              'Fraîcheur des données : inconnue; la date de mise à jour du dossier ne prouve pas une nouvelle mesure.',
            ),
            Text('Dossier mis à jour : $recordTime'),
            if (incident['evaluation_unavailable'] == true)
              const Text(
                'Évaluation indisponible : données périmées ou insuffisantes.',
              ),
            const SizedBox(height: 8),
            const Text(
              'Lecture seule. Acquittement et résolution automatiques indisponibles : aucune mutation serveur liée à la session et à la version n’existe.',
            ),
          ],
        ),
      ),
    );
  }
}

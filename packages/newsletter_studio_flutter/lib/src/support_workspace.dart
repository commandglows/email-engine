import 'package:flutter/material.dart';
import 'email_cockpit_parts.dart';
import 'email_cockpit_tokens.dart';
import 'support_models.dart';
import 'support_rich_html.dart';
import 'dispatch_copy.dart';
import 'dispatch_models.dart';
import 'dispatch_panel.dart';

class SupportWorkspace extends StatefulWidget {
  const SupportWorkspace({
    super.key,
    required this.repository,
    this.onConnect,
    this.onOpenLink,
    this.dispatchRepository,
    this.dispatchCopy = const DispatchPanelCopy(),
    this.mailboxReadOnly = false,
    this.userMailboxMode = false,
    this.confirmTrash = true,
    this.oauthReturnOrigin,
    this.onAnalyzeThread,
  });
  final SupportRepository repository;
  final DispatchRepository? dispatchRepository;

  /// Texts of the dispatch panel; the defaults are the project wording.
  final DispatchPanelCopy dispatchCopy;

  /// Embedded session bridges allow reading and human dispatch only.
  final bool mailboxReadOnly;
  final bool userMailboxMode;

  /// When false, deleting a conversation moves it to the Gmail trash at once.
  final bool confirmTrash;
  final String? oauthReturnOrigin;
  final Future<DispatchAnalysis> Function(
    SupportThread thread,
    List<DispatchDestination> destinations,
    String mailboxId,
  )?
  onAnalyzeThread;
  final Future<void> Function(Uri)? onConnect;

  /// Opens a link from an email body after the reader confirms it.
  /// Without it, links in email bodies are shown but not tappable.
  final Future<void> Function(Uri)? onOpenLink;
  @override
  State<SupportWorkspace> createState() => _SupportWorkspaceState();
}

class _SupportWorkspaceState extends State<SupportWorkspace> {
  SupportContext? _context;
  SupportMailbox? _mailbox;
  SupportThread? _thread;
  final List<SupportThreadSummary> _items = [];
  final Map<String, String> _drafts = {};
  final Set<String> _blocked = {};
  final TextEditingController _reply = TextEditingController();
  String? _cursor, _error, _notice;
  String _filter = '';
  String _observabilityWindow = '24h';
  SupportObservability? _observability;
  String? _observabilityError;
  bool _loading = true, _busy = false;
  bool _needsReconnect = false;
  bool _needsMetadataRefresh = false;
  int _generation = 0;
  int _observabilityGeneration = 0;
  String get _key => '${_mailbox?.id}/${_thread?.id}';
  String get _replyKey => '$_key/${_thread?.latestMessageId}';
  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  String _safe(Object error) => error is SupportException
      ? error.message
      : 'Impossible de terminer cette opération. Réessayez.';

  Future<void> _loadContext() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final context = await widget.repository.context();
      if (!mounted || generation != _generation) return;
      setState(() {
        _context = context;
        _loading = false;
      });
      if (context.configured && context.mailboxes.isNotEmpty) {
        await _selectMailbox(context.mailboxes.first);
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = _safe(error);
          _loading = false;
        });
      }
    }
  }

  Future<void> _selectMailbox(SupportMailbox mailbox) async {
    final generation = ++_generation;
    setState(() {
      _mailbox = mailbox;
      _thread = null;
      _needsMetadataRefresh = false;
      _items.clear();
      _cursor = null;
      _notice = null;
      _error = null;
      _observability = null;
      _observabilityError = null;
      _loading = mailbox.connected;
    });
    if (!mailbox.connected) return;
    try {
      final page = await widget.repository.threads(mailbox.id);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _loading = false;
      });
      if (!widget.mailboxReadOnly && !widget.userMailboxMode) {
        await _loadObservability(mailbox.id);
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = _safe(error);
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadObservability(String mailboxId) async {
    final generation = ++_observabilityGeneration;
    final requestedWindow = _observabilityWindow;
    try {
      final value = await widget.repository.observability(
        mailboxId,
        requestedWindow,
      );
      if (mounted &&
          _mailbox?.id == mailboxId &&
          generation == _observabilityGeneration) {
        setState(() {
          _observability = value;
          _observabilityError = null;
        });
      }
    } catch (error) {
      if (mounted &&
          _mailbox?.id == mailboxId &&
          generation == _observabilityGeneration) {
        setState(() {
          _observability = null;
          _observabilityError = _safe(error);
        });
      }
    }
  }

  Future<void> _operation(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _needsReconnect = false;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _safe(error);
          _needsReconnect =
              error is SupportException &&
              error.code == 'modify_scope_required';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reconnectMailbox() async {
    final mailbox = _mailbox;
    if (mailbox == null || widget.onConnect == null) return;
    await _operation(() async {
      final uri = await widget.repository.connect(mailbox.id);
      await widget.onConnect!(uri);
      if (mounted) {
        setState(
          () => _notice =
              'Terminez la reconnexion Google, puis actualisez Gmail.',
        );
      }
    });
  }

  Future<void> _addMailbox() async {
    if (widget.onConnect == null) return;
    await _operation(() async {
      final uri = await widget.repository.addMailbox(
        returnOrigin: widget.oauthReturnOrigin,
      );
      await widget.onConnect!(uri);
      if (mounted) {
        setState(
          () => _notice =
              'Terminez la connexion Google, puis actualisez les boîtes.',
        );
      }
    });
  }

  Future<void> _trashThread(SupportThread thread) async {
    final confirmed = !widget.confirmTrash
        ? true
        : await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Supprimer cette conversation ?'),
              content: const Text(
                'Gmail déplacera cette conversation dans la corbeille. Cette action ne sera jamais déclenchée par le dispatch.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Mettre à la corbeille'),
                ),
              ],
            ),
          );
    if (confirmed != true || _mailbox == null) return;
    await _operation(() async {
      await widget.repository.trashThread(
        _mailbox!.id,
        thread.id,
        expectedMessageId: thread.latestMessageId,
      );
      if (!mounted) return;
      setState(() {
        _items.removeWhere((item) => item.id == thread.id);
        _thread = null;
        _notice = 'Conversation déplacée dans la corbeille Gmail.';
      });
    });
  }

  Widget _observabilityPanel() {
    final data = _observability;
    final error = _observabilityError;
    return ExpansionTile(
      key: const ValueKey('support-observability'),
      title: const Text('Journal et métriques entrants'),
      subtitle: Text(
        data == null
            ? error == null
                  ? 'Données non chargées'
                  : 'Données indisponibles'
            : 'Couverture partielle · observation lors du parcours des boîtes Gmail',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(
        EmailCockpitLayout.gap,
        0,
        EmailCockpitLayout.gap,
        EmailCockpitLayout.gap,
      ),
      children: [
        Row(
          children: [
            const Text('Période'),
            const SizedBox(width: EmailCockpitLayout.gap),
            DropdownButton<String>(
              value: _observabilityWindow,
              items: const [
                DropdownMenuItem(value: '24h', child: Text('24 heures')),
                DropdownMenuItem(value: '7d', child: Text('7 jours')),
                DropdownMenuItem(value: '30d', child: Text('30 jours')),
                DropdownMenuItem(value: '90d', child: Text('90 jours')),
              ],
              onChanged: _busy
                  ? null
                  : (value) {
                      if (value == null || _mailbox == null) return;
                      setState(() => _observabilityWindow = value);
                      _loadObservability(_mailbox!.id);
                    },
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Actualiser le journal entrant',
              onPressed: _busy || _mailbox == null
                  ? null
                  : () => _loadObservability(_mailbox!.id),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (error != null) Text('Journal indisponible : $error'),
        if (data == null && error == null)
          const Text(
            'Aucune mesure disponible. Cela ne signifie pas zéro message reçu.',
          ),
        if (data != null) ...[
          const Text(
            'Les lignes indiquent une observation dans Gmail, pas la réception fournisseur ni la livraison au destinataire.',
          ),
          Text(
            'Couverture : ${data.coverage} · source : ${data.source} · période : ${data.window}',
          ),
          Text(
            data.observedCount == null
                ? 'Messages observés : indisponible'
                : 'Messages observés dans la période : ${data.observedCount}',
          ),
          Text(
            data.sampledCount == null
                ? 'Échantillon : indisponible'
                : 'Lignes échantillonnées : ${data.sampledCount}${data.sampleLimit == null ? '' : ' / limite ${data.sampleLimit}'}',
          ),
          Text(
            data.sampleTruncated == null
                ? 'Complétude de l’échantillon : indisponible'
                : data.sampleTruncated!
                ? 'Échantillon tronqué à la limite configurée.'
                : 'Échantillon complet pour cette période.',
          ),
          if (!data.stateCountsAvailable)
            const Text('Répartition par état : indisponible')
          else if (data.countsByState.isEmpty)
            const Text('Aucun état recensé dans la période.')
          else
            Text(
              'États observés : ${data.countsByState.entries.map((entry) => '${entry.key} ${entry.value?.toString() ?? 'indisponible'}').join(' · ')}',
            ),
          Text(
            'Dernière observation : ${_dateLabel(data.lastObservedAt)} · échantillon le plus ancien : ${_dateLabel(data.oldestSampleAt)}',
          ),
          if (!data.sampleAvailable)
            const Text('Échantillon indisponible.')
          else if (data.sample.isEmpty && data.sampledCount == 0)
            const Text('Aucune observation échantillonnée dans la période.')
          else if (data.sample.isEmpty)
            const Text('Les lignes de l’échantillon ne sont pas disponibles.')
          else ...[
            const Text('Échantillon (identifiants hachés)'),
            for (final item in data.sample.take(30))
              Text(
                '${item.state} · ${item.messageIdHash.isEmpty ? 'identifiant haché indisponible' : item.messageIdHash} · ${_dateLabel(item.observedAt)}',
              ),
          ],
          if (!data.failuresAvailable)
            const Text('Journal des échecs indisponible.')
          else if (data.failures.isEmpty)
            const Text('Aucun échec enregistré dans cette fenêtre.')
          else ...[
            const Text('Échecs opérationnels'),
            for (final failure in data.failures)
              Text(
                '${failure.stage} · ${failure.code} · ${failure.count?.toString() ?? 'nombre indisponible'} occurrence(s) · première ${_dateLabel(failure.firstAt)} · dernière ${_dateLabel(failure.lastAt)} · ${failure.retryable == null
                    ? 'reprise inconnue'
                    : failure.retryable!
                    ? 'réconciliation possible'
                    : 'pas de nouvelle tentative automatique'}',
              ),
          ],
        ],
      ],
    );
  }

  String _dateLabel(DateTime? date) => date == null
      ? 'indisponible'
      : date.toLocal().toString().substring(0, 16);

  /// Compact list date: clock time for today, day and month otherwise.
  String _listDateLabel(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    final local = date.toLocal();
    final now = DateTime.now();
    final today =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    return today
        ? '${two(local.hour)}:${two(local.minute)}'
        : '${two(local.day)}/${two(local.month)}';
  }

  Future<void> _setGmailMetadata({bool? unread, bool? archived}) async {
    final thread = _thread;
    final mailbox = _mailbox;
    if (thread == null ||
        mailbox == null ||
        thread.isUnread == null ||
        thread.isArchived == null) {
      return;
    }
    await _operation(() async {
      late final SupportThread updated;
      try {
        updated = await widget.repository.setGmailMetadata(
          mailbox.id,
          thread.id,
          expectedMessageId: thread.latestMessageId,
          isUnread: unread ?? thread.isUnread!,
          isArchived: archived ?? thread.isArchived!,
        );
      } catch (_) {
        _needsMetadataRefresh = true;
        rethrow;
      }
      if (!mounted) return;
      setState(() {
        _needsMetadataRefresh = false;
        _thread = updated;
        final index = _items.indexWhere((item) => item.id == updated.id);
        if (index >= 0) {
          final old = _items[index];
          _items[index] = SupportThreadSummary(
            id: old.id,
            subject: old.subject,
            from: old.from,
            snippet: old.snippet,
            status: old.status,
            updatedAt: old.updatedAt,
            isUnread: updated.isUnread,
            isArchived: updated.isArchived,
          );
        }
      });
    });
  }

  Future<void> _open(SupportThreadSummary item) async {
    await _operation(() async {
      final thread = await widget.repository.thread(_mailbox!.id, item.id);
      if (!mounted) return;
      setState(() {
        _thread = thread;
        _needsMetadataRefresh = false;
        _reply.text = _drafts[_key] ?? '';
      });
    });
    // Reading a conversation marks it read, as Gmail does. Runs after
    // _operation releases _busy, because the metadata call goes through it.
    final opened = _thread;
    if (mounted &&
        opened?.id == item.id &&
        opened?.isUnread == true &&
        (!widget.mailboxReadOnly || widget.userMailboxMode) &&
        _mailbox?.canModify == true) {
      await _setGmailMetadata(unread: false);
    }
  }

  Future<void> _send() async {
    final thread = _thread!;
    final body = _reply.text.trim();
    if (body.isEmpty || _blocked.contains(_replyKey) || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Envoyer cette réponse ?'),
        content: Text(
          'La réponse sera transmise par Gmail à l’adresse de routage suivante :\n${thread.replyTo ?? "Adresse indisponible"}\n\nLe relais éventuel conserve l’adresse de votre domaine. Vérifiez ce routage avant de confirmer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmer l’envoi'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _operation(() async {
      // An interrupted request may already have reached Gmail. Never create a
      // second reply intent automatically, even after navigating away and back.
      final key = _key;
      final replyKey = _replyKey;
      _blocked.add(replyKey);
      late final SupportReplyResult result;
      try {
        result = await widget.repository.reply(
          _mailbox!.id,
          thread.id,
          body: body,
          expectedMessageId: thread.latestMessageId,
        );
      } on SupportException catch (error) {
        if (!error.outcomeUnknown) _blocked.remove(replyKey);
        rethrow;
      }
      if (!mounted) return;
      setState(() {
        if (result == SupportReplyResult.submitted) {
          _drafts.remove(key);
          _reply.clear();
          _notice =
              'Réponse transmise à Gmail. La réception par le client n’est pas encore confirmée.';
        } else {
          _notice =
              'Résultat incertain. Vérifiez les messages envoyés dans Gmail avant toute nouvelle réponse.';
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final mailbox = _mailbox;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            EmailCockpitLayout.gap,
            EmailCockpitLayout.gap,
            EmailCockpitLayout.gap,
            EmailCockpitLayout.smallGap,
          ),
          child: Wrap(
            spacing: EmailCockpitLayout.gap,
            runSpacing: EmailCockpitLayout.mediumGap,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Service client',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_context?.mailboxes.isNotEmpty == true)
                SizedBox(
                  width: 320,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Boîte Gmail',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: mailbox?.id,
                        hint: const Text('Choisir une boîte'),
                        items: _context!.mailboxes
                            .map(
                              (m) => DropdownMenuItem(
                                value: m.id,
                                child: Text(
                                  m.email,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (id) => _selectMailbox(
                                _context!.mailboxes.firstWhere(
                                  (m) => m.id == id,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              IconButton.filledTonal(
                tooltip: 'Ajouter une boîte Gmail',
                onPressed: _busy || !widget.userMailboxMode
                    ? null
                    : _addMailbox,
                icon: const Icon(Icons.add),
              ),
              IconButton.outlined(
                tooltip: 'Actualiser les boîtes',
                onPressed: _busy || _loading ? null : _loadContext,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (_error != null) _banner(_error!, error: true),
        if (!widget.mailboxReadOnly &&
            !widget.userMailboxMode &&
            (_needsReconnect || mailbox?.reconnectRequired == true))
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: EmailCockpitLayout.gap,
              ),
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _reconnectMailbox,
                icon: const Icon(Icons.link),
                label: const Text(
                  'Reconnecter Gmail avec les droits de modification',
                ),
              ),
            ),
          ),
        if (_notice != null) _banner(_notice!),
        if (!widget.mailboxReadOnly &&
            !widget.userMailboxMode &&
            mailbox?.connected == true &&
            mailbox?.canModify != true)
          _banner(
            'Cette connexion Gmail est en lecture seule. Les changements Gmail sont désactivés jusqu’à la reconnexion avec l’autorisation requise.',
          ),
        if (!widget.mailboxReadOnly &&
            !widget.userMailboxMode &&
            mailbox?.connected == true)
          _observabilityPanel(),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _context == null
              ? EmailEmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Service client indisponible',
                  action: FilledButton(
                    onPressed: _loadContext,
                    child: const Text('Réessayer'),
                  ),
                )
              : !_context!.configured
              ? const EmailEmptyState(
                  icon: Icons.settings_outlined,
                  title: 'Gmail reste à connecter',
                  description:
                      'La connexion sécurisée à vos propres boîtes Gmail doit être configurée sur le serveur.',
                )
              : mailbox == null
              ? EmailEmptyState(
                  icon: Icons.mark_email_unread_outlined,
                  title: widget.userMailboxMode
                      ? 'Aucune boîte connectée'
                      : 'Aucune boîte autorisée',
                  description: widget.userMailboxMode
                      ? 'Connectez une boîte Gmail privée à votre compte.'
                      : 'Ajoutez vos propres boîtes à la configuration du service client.',
                  action: widget.userMailboxMode
                      ? FilledButton.icon(
                          onPressed: _busy || widget.onConnect == null
                              ? null
                              : _addMailbox,
                          icon: const Icon(Icons.add),
                          label: const Text('Ajouter une boîte Gmail'),
                        )
                      : null,
                )
              : !mailbox.connected
              ? EmailEmptyState(
                  icon: Icons.link_off,
                  title: 'Cette boîte Gmail n’est pas connectée.',
                  action: !widget.mailboxReadOnly || widget.userMailboxMode
                      ? FilledButton(
                          onPressed: _busy || widget.onConnect == null
                              ? null
                              : () => _operation(() async {
                                  final uri = await widget.repository.connect(
                                    mailbox.id,
                                  );
                                  await widget.onConnect!(uri);
                                  if (mounted) {
                                    setState(
                                      () => _notice =
                                          'Terminez la connexion Google, puis actualisez les boîtes.',
                                    );
                                  }
                                }),
                          child: const Text('Connecter Gmail'),
                        )
                      : null,
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth <
                        EmailCockpitLayout.supportBreakpoint) {
                      return _thread == null ? _list() : _detail(compact: true);
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: EmailCockpitLayout.conversationWidth,
                          child: _list(),
                        ),
                        const VerticalDivider(width: EmailCockpitLayout.rule),
                        Expanded(
                          child: _thread == null
                              ? const EmailEmptyState(
                                  icon: Icons.forum_outlined,
                                  title: 'Vos conversations clients',
                                  description:
                                      'Sélectionnez une conversation pour la lire et répondre.',
                                )
                              : _detail(compact: false),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _banner(String text, {bool error = false}) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: EmailCockpitLayout.gap,
      vertical: EmailCockpitLayout.smallGap,
    ),
    child: EmailNotice(text, error: error),
  );

  Widget _list() {
    final items = _items
        .where(
          (t) => '${t.subject} ${t.from} ${t.snippet}'.toLowerCase().contains(
            _filter.toLowerCase(),
          ),
        )
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            EmailCockpitLayout.gap,
            0,
            EmailCockpitLayout.gap,
            EmailCockpitLayout.smallGap,
          ),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Filtrer les conversations chargées',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _filter = v),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              if (items.isEmpty)
                const EmailEmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'Aucune conversation à afficher.',
                ),
              for (final item in items) _threadTile(item),
              if (_cursor != null)
                Padding(
                  padding: const EdgeInsets.all(EmailCockpitLayout.gap),
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _operation(() async {
                            final page = await widget.repository.threads(
                              _mailbox!.id,
                              cursor: _cursor,
                            );
                            if (mounted) {
                              setState(() {
                                final ids = _items.map((t) => t.id).toSet();
                                _items.addAll(
                                  page.items.where((t) => ids.add(t.id)),
                                );
                                _cursor = page.nextCursor;
                              });
                            }
                          }),
                    child: const Text('Charger la suite'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// One conversation row: unread dot and weight, sender, snippet, state pills.
  Widget _threadTile(SupportThreadSummary item) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = _thread?.id == item.id;
    final unread = item.isUnread == true;
    final updatedAt = item.updatedAt;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        child: InkWell(
          onTap: _busy ? null : () => _open(item),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              EmailCockpitLayout.gap,
              EmailCockpitLayout.mediumGap,
              EmailCockpitLayout.gap,
              EmailCockpitLayout.mediumGap,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (unread) ...[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox(width: 8, height: 8),
                      ),
                      const SizedBox(width: EmailCockpitLayout.smallGap),
                    ],
                    Expanded(
                      child: Text(
                        item.subject.isEmpty ? '(Sans objet)' : item.subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: unread
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (updatedAt != null) ...[
                      const SizedBox(width: EmailCockpitLayout.smallGap),
                      Text(
                        _listDateLabel(updatedAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  item.from,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (item.snippet.isNotEmpty)
                  Text(
                    item.snippet,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                const SizedBox(height: EmailCockpitLayout.smallGap),
                Wrap(
                  spacing: EmailCockpitLayout.smallGap,
                  runSpacing: 4,
                  children: [
                    EmailStatePill(
                      item.status.label,
                      tone: item.status == SupportStatus.pending
                          ? EmailPillTone.strong
                          : EmailPillTone.neutral,
                    ),
                    if (item.isUnread == null)
                      const EmailStatePill(
                        'Lecture Gmail inconnue',
                        tone: EmailPillTone.muted,
                      ),
                    if (item.isArchived == true)
                      const EmailStatePill('Archivé'),
                    if (item.isArchived == null)
                      const EmailStatePill(
                        'Archivage inconnu',
                        tone: EmailPillTone.muted,
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

  /// Detail pane. The email header stays fixed and only the messages scroll.
  /// Wide layouts keep the dispatch panel in a side column so the message and
  /// the proposal are visible together; narrow ones stack them.
  Widget _detail({required bool compact}) {
    final thread = _thread!;
    final header = _emailHeader(thread, compact: compact);
    final body = _messageColumn(thread);
    final dispatch = widget.dispatchRepository == null
        ? null
        : DispatchPanel(
            key: ValueKey(
              'dispatch/${_mailbox!.id}/${thread.id}/${thread.latestMessageId}',
            ),
            copy: widget.dispatchCopy,
            repository: widget.dispatchRepository!,
            mailboxId: _mailbox!.id,
            threadId: thread.id,
            messageId: thread.latestMessageId,
            analyze: widget.onAnalyzeThread == null
                ? null
                : (destinations) => widget.onAnalyzeThread!(
                    thread,
                    destinations,
                    _mailbox!.id,
                  ),
          );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < EmailCockpitLayout.dispatchBreakpoint;
        final pane = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Expanded(
              child: _detailScroll(
                dispatch != null && stacked ? [...body, dispatch] : body,
              ),
            ),
          ],
        );
        if (dispatch == null || stacked) return pane;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: pane),
            const VerticalDivider(width: EmailCockpitLayout.rule),
            SizedBox(
              width: EmailCockpitLayout.dispatchWidth,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(EmailCockpitLayout.detailGap),
                child: dispatch,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _detailScroll(List<Widget> children) => ListView(
    key: const ValueKey('support-detail-scroll'),
    padding: const EdgeInsets.fromLTRB(
      EmailCockpitLayout.detailGap,
      0,
      EmailCockpitLayout.detailGap,
      EmailCockpitLayout.detailGap,
    ),
    children: children,
  );

  /// Email-level header, fixed above the messages: back, subject, Gmail state,
  /// actions and conversation status.
  Widget _emailHeader(SupportThread thread, {required bool compact}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        EmailCockpitLayout.detailGap,
        EmailCockpitLayout.detailGap,
        EmailCockpitLayout.detailGap,
        EmailCockpitLayout.smallGap,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (compact)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : () => setState(() => _thread = null),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Conversations'),
              ),
            ),
          Text(
            thread.subject.isEmpty ? '(Sans objet)' : thread.subject,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: EmailCockpitLayout.gap),
          Wrap(
            spacing: EmailCockpitLayout.smallGap,
            runSpacing: EmailCockpitLayout.smallGap,
            children: [
              EmailStatePill(
                thread.isUnread == null
                    ? 'Lecture Gmail inconnue'
                    : thread.isUnread!
                    ? 'Non lu dans Gmail'
                    : 'Lu dans Gmail',
                tone: thread.isUnread == null
                    ? EmailPillTone.muted
                    : thread.isUnread!
                    ? EmailPillTone.strong
                    : EmailPillTone.neutral,
              ),
              EmailStatePill(
                thread.isArchived == null
                    ? 'Archivage Gmail inconnu'
                    : thread.isArchived!
                    ? 'Archivé dans Gmail'
                    : 'Dans la boîte de réception Gmail',
                tone: thread.isArchived == null
                    ? EmailPillTone.muted
                    : EmailPillTone.neutral,
              ),
            ],
          ),
          if (!widget.mailboxReadOnly || widget.userMailboxMode) ...[
            const SizedBox(height: EmailCockpitLayout.smallGap),
            Wrap(
              spacing: EmailCockpitLayout.smallGap,
              runSpacing: EmailCockpitLayout.smallGap,
              children: [
                OutlinedButton.icon(
                  onPressed:
                      _busy ||
                          _mailbox?.canModify != true ||
                          thread.isUnread == null
                      ? null
                      : () => _setGmailMetadata(unread: !thread.isUnread!),
                  icon: Icon(
                    thread.isUnread == true
                        ? Icons.mark_email_read_outlined
                        : Icons.mark_email_unread_outlined,
                  ),
                  label: Text(
                    thread.isUnread == true
                        ? 'Marquer comme lu'
                        : 'Marquer comme non lu',
                  ),
                ),
                if (widget.userMailboxMode)
                  OutlinedButton.icon(
                    onPressed: _busy || _mailbox?.canModify != true
                        ? null
                        : () => _trashThread(thread),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Supprimer'),
                  ),
                OutlinedButton.icon(
                  onPressed:
                      _busy ||
                          _mailbox?.canModify != true ||
                          thread.isArchived == null
                      ? null
                      : () => _setGmailMetadata(archived: !thread.isArchived!),
                  icon: Icon(
                    thread.isArchived == true
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                  ),
                  label: Text(
                    thread.isArchived == true
                        ? 'Restaurer dans la boîte'
                        : 'Archiver dans Gmail',
                  ),
                ),
              ],
            ),
          ],
          if (thread.isUnread == null ||
              thread.isArchived == null ||
              _needsMetadataRefresh)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => _operation(() async {
                        final refreshed = await widget.repository.thread(
                          _mailbox!.id,
                          thread.id,
                        );
                        if (mounted) {
                          setState(() {
                            _thread = refreshed;
                            _needsMetadataRefresh = false;
                          });
                        }
                      }),
                icon: const Icon(Icons.refresh),
                label: const Text('Actualiser l’état Gmail'),
              ),
            ),
          if (!widget.userMailboxMode) ...[
            const SizedBox(height: EmailCockpitLayout.gap),
            Text(
              'Statut',
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: EmailCockpitLayout.smallGap),
            Wrap(
              spacing: EmailCockpitLayout.smallGap,
              runSpacing: EmailCockpitLayout.smallGap,
              children: SupportStatus.values
                  .map(
                    (status) => ChoiceChip(
                      label: Text(status.label),
                      selected: thread.status == status,
                      onSelected: _busy || widget.mailboxReadOnly
                          ? null
                          : (_) => _operation(() async {
                              await widget.repository.setStatus(
                                _mailbox!.id,
                                thread.id,
                                status,
                              );
                              final refreshed = await widget.repository.thread(
                                _mailbox!.id,
                                thread.id,
                              );
                              if (mounted) {
                                setState(() {
                                  _thread = refreshed;
                                  final index = _items.indexWhere(
                                    (t) => t.id == thread.id,
                                  );
                                  if (index >= 0) {
                                    final old = _items[index];
                                    _items[index] = SupportThreadSummary(
                                      id: old.id,
                                      subject: old.subject,
                                      from: old.from,
                                      snippet: old.snippet,
                                      status: refreshed.status,
                                      updatedAt: old.updatedAt,
                                      isUnread: old.isUnread,
                                      isArchived: old.isArchived,
                                    );
                                  }
                                });
                              }
                            }),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  /// Messages and reply: the only part of the detail pane that scrolls.
  List<Widget> _messageColumn(SupportThread thread) {
    final blocked = _blocked.contains(_replyKey);
    return [
      for (final message in thread.messages) _messageCard(message),
      if (!widget.mailboxReadOnly && !widget.userMailboxMode)
        _replySection(thread, blocked: blocked),
    ];
  }

  Widget _messageCard(SupportMessage message) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sender = message.from.trim();
    return Card(
      margin: const EdgeInsets.only(top: EmailCockpitLayout.gap),
      child: Padding(
        padding: const EdgeInsets.all(EmailCockpitLayout.gap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: scheme.secondaryContainer,
                  child: Text(
                    sender.isEmpty ? '?' : sender[0].toUpperCase(),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: EmailCockpitLayout.mediumGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.from,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        'À : ${message.to}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (message.date != null) ...[
                  const SizedBox(width: EmailCockpitLayout.smallGap),
                  Text(
                    message.date!.toLocal().toString().substring(0, 16),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
            const Divider(height: EmailCockpitLayout.gap),
            SupportMessageBody(message: message, onOpenLink: widget.onOpenLink),
          ],
        ),
      ),
    );
  }

  Widget _replySection(SupportThread thread, {required bool blocked}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: EmailCockpitLayout.detailGap),
        Text(
          'Réponse via Gmail',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: EmailCockpitLayout.smallGap),
        if (thread.replyTo != null)
          SelectableText('Adresse de routage : ${thread.replyTo}'),
        Text(
          'Pour un email relayé, le routage Mutant Mail doit être conservé. L’adresse Gmail ne doit pas remplacer votre alias de domaine.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (!thread.canReply || !_context!.canReply)
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: EmailCockpitLayout.mediumGap,
            ),
            child: EmailNotice(switch (thread.replyDisabledReason) {
              'reply_delivery_unknown' =>
                'Un envoi précédent a un résultat incertain. Vérifiez les messages envoyés dans Gmail.',
              'reply_already_submitted' =>
                'Une réponse a déjà été transmise pour ce message.',
              'relay_not_verified' =>
                'Le routage du relais doit être vérifié avant de répondre.',
              'synthetic_demo' =>
                'Démonstration : aucun email ne peut être envoyé.',
              _ => 'Les réponses ne sont pas activées pour cette conversation.',
            }),
          ),
        if (blocked)
          const Padding(
            padding: EdgeInsets.symmetric(
              vertical: EmailCockpitLayout.mediumGap,
            ),
            child: EmailNotice(
              'Nouvel envoi bloqué pour éviter un doublon. Vérifiez cette conversation dans Gmail.',
              error: true,
            ),
          ),
        const SizedBox(height: EmailCockpitLayout.mediumGap),
        TextField(
          controller: _reply,
          minLines: 4,
          maxLines: 12,
          maxLength: 20000,
          enabled: !_busy && !blocked,
          decoration: const InputDecoration(
            labelText: 'Votre réponse',
            helperText: 'Brouillon conservé dans cette session.',
          ),
          onChanged: (text) => setState(() => _drafts[_key] = text),
        ),
        const SizedBox(height: EmailCockpitLayout.mediumGap),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed:
                _busy ||
                    blocked ||
                    !thread.canReply ||
                    !_context!.canReply ||
                    _reply.text.trim().isEmpty
                ? null
                : _send,
            icon: const Icon(Icons.send_outlined),
            label: const Text('Relire et envoyer'),
          ),
        ),
      ],
    );
  }
}

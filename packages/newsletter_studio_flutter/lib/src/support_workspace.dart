import 'package:flutter/material.dart';
import 'email_cockpit_tokens.dart';
import 'support_models.dart';

class SupportWorkspace extends StatefulWidget {
  const SupportWorkspace({super.key, required this.repository, this.onConnect});
  final SupportRepository repository;
  final Future<void> Function(Uri)? onConnect;
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
  bool _loading = true, _busy = false;
  int _generation = 0;
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
      _items.clear();
      _cursor = null;
      _notice = null;
      _error = null;
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
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = _safe(error);
          _loading = false;
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
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = _safe(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(SupportThreadSummary item) => _operation(() async {
    final thread = await widget.repository.thread(_mailbox!.id, item.id);
    if (!mounted) return;
    setState(() {
      _thread = thread;
      _reply.text = _drafts[_key] ?? '';
    });
  });

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(EmailCockpitLayout.gap),
          child: Wrap(
            spacing: EmailCockpitLayout.gap,
            runSpacing: EmailCockpitLayout.mediumGap,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Service client',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (_context?.mailboxes.isNotEmpty == true)
                SizedBox(
                  width: (MediaQuery.sizeOf(context).width - 64).clamp(
                    100,
                    300,
                  ),
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
                            _context!.mailboxes.firstWhere((m) => m.id == id),
                          ),
                  ),
                ),
              IconButton(
                tooltip: 'Actualiser les boîtes',
                onPressed: _busy || _loading ? null : _loadContext,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (_error != null) _banner(_error!, error: true),
        if (_notice != null) _banner(_notice!),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _context == null
              ? Center(
                  child: FilledButton(
                    onPressed: _loadContext,
                    child: const Text('Réessayer'),
                  ),
                )
              : !_context!.configured
              ? _empty(
                  'Gmail reste à connecter',
                  'La connexion sécurisée à vos propres boîtes Gmail doit être configurée sur le serveur.',
                )
              : mailbox == null
              ? _empty(
                  'Aucune boîte autorisée',
                  'Ajoutez vos propres boîtes à la configuration du service client.',
                )
              : !mailbox.connected
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Cette boîte Gmail n’est pas connectée.'),
                      const SizedBox(height: EmailCockpitLayout.gap),
                      FilledButton(
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
                      ),
                    ],
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth <
                        EmailCockpitLayout.supportBreakpoint) {
                      return _thread == null ? _list() : _detail(compact: true);
                    }
                    return Row(
                      children: [
                        SizedBox(
                          width: EmailCockpitLayout.conversationWidth,
                          child: _list(),
                        ),
                        const VerticalDivider(width: EmailCockpitLayout.rule),
                        Expanded(
                          child: _thread == null
                              ? _empty(
                                  'Vos conversations clients',
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
    child: Semantics(
      liveRegion: true,
      child: Text(
        text,
        style: TextStyle(
          color: error ? Theme.of(context).colorScheme.error : null,
        ),
      ),
    ),
  );
  Widget _empty(String title, String description) => Center(
    child: Padding(
      padding: const EdgeInsets.all(EmailCockpitLayout.largeGap),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.forum_outlined, size: EmailCockpitLayout.emptyIcon),
          const SizedBox(height: EmailCockpitLayout.gap),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: EmailCockpitLayout.smallGap),
          Text(description, textAlign: TextAlign.center),
        ],
      ),
    ),
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
          padding: const EdgeInsets.all(EmailCockpitLayout.mediumGap),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Filtrer les conversations chargées',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _filter = v),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(EmailCockpitLayout.largeGap),
                  child: Text('Aucune conversation à afficher.'),
                ),
              for (final item in items)
                ListTile(
                  selected: _thread?.id == item.id,
                  enabled: !_busy,
                  title: Text(
                    item.subject.isEmpty ? '(Sans objet)' : item.subject,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${item.from}\n${item.status.label} · ${item.snippet}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: true,
                  onTap: () => _open(item),
                ),
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

  Widget _detail({required bool compact}) {
    final thread = _thread!;
    final blocked = _blocked.contains(_replyKey);
    return ListView(
      key: const ValueKey('support-detail-scroll'),
      padding: const EdgeInsets.all(EmailCockpitLayout.detailGap),
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
        Text(thread.subject, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: EmailCockpitLayout.mediumGap),
        Wrap(
          spacing: EmailCockpitLayout.smallGap,
          runSpacing: EmailCockpitLayout.smallGap,
          children: SupportStatus.values
              .map(
                (status) => ChoiceChip(
                  label: Text(status.label),
                  selected: thread.status == status,
                  onSelected: _busy
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
                                );
                              }
                            });
                          }
                        }),
                ),
              )
              .toList(),
        ),
        for (final message in thread.messages)
          Card(
            margin: const EdgeInsets.only(top: EmailCockpitLayout.gap),
            child: Padding(
              padding: const EdgeInsets.all(EmailCockpitLayout.gap),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.from,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text('À : ${message.to}'),
                  if (message.date != null)
                    Text(message.date!.toLocal().toString().substring(0, 16)),
                  const Divider(),
                  SelectableText(
                    message.text.isEmpty
                        ? 'Aucun contenu texte disponible.'
                        : message.text,
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: EmailCockpitLayout.detailGap),
        Text(
          'Réponse via Gmail',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: EmailCockpitLayout.smallGap),
        if (thread.replyTo != null)
          SelectableText('Adresse de routage : ${thread.replyTo}'),
        const Text(
          'Pour un email relayé, le routage Mutant Mail doit être conservé. L’adresse Gmail ne doit pas remplacer votre alias de domaine.',
        ),
        if (!thread.canReply || !_context!.canReply)
          Padding(
            padding: EdgeInsets.symmetric(
              vertical: EmailCockpitLayout.mediumGap,
            ),
            child: Text(switch (thread.replyDisabledReason) {
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
            child: Text(
              'Nouvel envoi bloqué pour éviter un doublon. Vérifiez cette conversation dans Gmail.',
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

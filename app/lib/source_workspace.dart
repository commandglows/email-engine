import 'package:flutter/material.dart';
import 'package:source_sidebar_flutter/source_sidebar_flutter.dart';
import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'central_email_api.dart';
import 'campaign_repository.dart';
import 'support_repository.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'support_reader.dart';

/// One list and reader. Provider identities stay scoped outside display IDs.
class ReaderSourceWorkspace extends StatefulWidget {
  const ReaderSourceWorkspace({
    super.key,
    required this.api,
    this.darkMode = false,
    this.onToggleTheme,
    this.onOpenCampaign,
  });
  final CentralEmailApi api;
  final bool darkMode;
  final VoidCallback? onToggleTheme;
  final Future<void> Function(CampaignEditorSession)? onOpenCampaign;
  @override
  State<ReaderSourceWorkspace> createState() => _ReaderSourceWorkspaceState();
}

class _ReaderSourceWorkspaceState extends State<ReaderSourceWorkspace> {
  late final _support = CentralSupportRepository(widget.api);
  final _items = <String, SourceSidebarItem>{};
  final _sections = <String, String>{};
  final _sources = <String, String>{};
  final _threads = <String, (String, String)>{};
  final _campaigns = <String, (CentralCampaignRepository, String)>{};
  final _repositories = <String, CentralCampaignRepository>{};
  final _cursors = <String, String>{};
  final _details = <String, SupportThread>{};
  final _sessions = <String, CampaignEditorSession>{};
  final _drafts = <String, TextEditingController>{};
  final _lockedReplies = <String>{};
  final _replyAll = <String, bool>{};
  final _attachments = <String, List<SupportReplyAttachment>>{};
  String _supportQuery = '';
  final _notices = <String, String>{};
  final _sectionKeys = {
    for (final id in ['sources', 'support', 'diffusion']) id: GlobalKey(),
  };
  SupportContext? _supportContext;
  String? _selected, _error;
  bool _loading = false, _busy = false;
  int _generation = 0;
  static const _style = SourceSidebarStyle();
  static const _labels = {
    'sources': 'Sources',
    'support': 'Service client',
    'diffusion': 'Diffusion',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final draft in _drafts.values) {
      draft.dispose();
    }
    super.dispose();
  }

  String _message(Object error) => error is EmailApiException
      ? error.message
      : error is SupportException
      ? error.message
      : 'Chargement indisponible. Réessayez.';
  SourceSidebarItem _row(
    String id,
    String title,
    String author,
    String text, {
    DateTime? date,
    String summary = '',
    String type = '',
    List<String> tags = const [],
    Uri? url,
    SourceSidebarAttention attention = SourceSidebarAttention.none,
  }) => SourceSidebarItem(
    id: id,
    title: title.isEmpty ? '(Sans objet)' : title,
    authorOrPublisher: author,
    summary: summary,
    content: text,
    publishedAt: date ?? DateTime.fromMillisecondsSinceEpoch(0),
    sourceType: type,
    tags: tags,
    attention: attention,
    canonicalExternalUrl: url,
  );

  SourceSidebarAttention _campaignAttention(NewsletterCampaign campaign) {
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
    return SourceSidebarAttention.none;
  }

  void _put(SourceSidebarItem item, String section) {
    _items[item.id] = item;
    _sections[item.id] = section;
  }

  void _source(Map<String, dynamic> data) {
    final original = data['id'] as String, id = 'source:$original';
    _sources[id] = original;
    _put(
      _row(
        id,
        data['title'] as String? ?? '',
        data['author'] as String? ?? '',
        (data['content'] as String?)?.isNotEmpty == true
            ? data['content'] as String
            : 'Sélectionnez cette source pour charger son contenu.',
        summary: data['summary'] as String? ?? '',
        date: DateTime.tryParse(data['published_at'] as String? ?? ''),
        type: 'Source',
        url: Uri.https('read.readwise.io', '/read/$original'),
      ),
      'sources',
    );
  }

  Future<void> _loadSources(bool more) async {
    if (more && !_cursors.containsKey('sources')) return;
    final response = await widget.api.get('sources', {
      if (more) 'cursor': _cursors['sources']!,
    });
    for (final item in response['documents'] as List) {
      _source(item as Map<String, dynamic>);
    }
    _cursor('sources', response['next_cursor'] as String?);
    _notices['sources'] = response['configured'] == true
        ? 'Aucune source disponible.'
        : 'Sources : connexion Reader à configurer.';
  }

  void _cursor(String key, String? value) {
    if (value == null) {
      _cursors.remove(key);
    } else {
      _cursors[key] = value;
    }
  }

  Future<void> _loadSupport(bool more) async {
    if (!more) _supportContext = await _support.context();
    final boxes = _supportContext?.mailboxes ?? [];
    _notices['support'] = _supportContext?.configured == true
        ? 'Aucune conversation disponible.'
        : 'Service client : connexion Gmail à configurer.';
    for (final box in boxes) {
      if (!box.connected) continue;
      final key = 'support:${box.id}';
      if (more && !_cursors.containsKey(key)) continue;
      final page = await _support.threads(
        box.id,
        cursor: more ? _cursors[key] : null,
        query: _supportQuery,
      );
      _cursor(key, page.nextCursor);
      for (final thread in page.items) {
        final id = '$key:${thread.id}';
        _threads[id] = (box.id, thread.id);
        _put(
          _row(
            id,
            thread.subject,
            thread.from,
            thread.snippet,
            summary: thread.snippet,
            date: thread.updatedAt,
            type: 'Service client',
            tags: [thread.status.label],
          ),
          'support',
        );
      }
    }
  }

  Future<void> _loadCampaigns(bool more) async {
    if (!more) {
      final context = await widget.api.get('context');
      _repositories.clear();
      for (final raw in context['businesses'] as List) {
        final business = EmailBusiness(raw as Map<String, dynamic>);
        _repositories[business.id] = CentralCampaignRepository(
          widget.api,
          business,
        );
      }
    }
    _notices['diffusion'] = _repositories.isEmpty
        ? 'Diffusion : aucun espace configuré.'
        : 'Aucune campagne. Créez votre premier brouillon.';
    for (final repository in _repositories.values) {
      final key = 'campaign:${repository.business.id}';
      if (more && !_cursors.containsKey(key)) continue;
      final page = await repository.list(cursor: more ? _cursors[key] : null);
      _cursor(key, page.nextCursor);
      for (final campaign in page.items) {
        final id = '$key:${campaign.id}';
        _campaigns[id] = (repository, campaign.id);
        _put(
          _row(
            id,
            campaign.title,
            repository.business.brand,
            campaign.subject,
            summary: campaign.subject,
            date: campaign.updatedAt,
            type: 'Campagne',
            tags: [campaign.status.label],
            attention: _campaignAttention(campaign),
          ),
          'diffusion',
        );
      }
    }
  }

  Future<void> _load({bool more = false}) async {
    if (_loading || _busy) return;
    _generation++;
    setState(() {
      _loading = true;
      _error = null;
    });
    if (!more) {
      _items.clear();
      _sections.clear();
      _sources.clear();
      _threads.clear();
      _campaigns.clear();
      _cursors.clear();
      _sessions.clear();
      _details.clear();
    }
    await Future.wait([
      for (final entry in <String, Future<void> Function(bool)>{
        'sources': _loadSources,
        'support': _loadSupport,
        'diffusion': _loadCampaigns,
      }.entries)
        () async {
          try {
            await entry.value(more);
          } catch (error) {
            _notices[entry.key] = '${_labels[entry.key]} : ${_message(error)}';
          }
        }(),
    ]);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!_items.containsKey(_selected)) _selected = null;
    });
    final selected = _selected;
    if (selected != null) await _select(selected);
  }

  Future<void> _select(String? id) async {
    if (_busy) return;
    setState(() {
      _selected = id;
      _error = null;
    });
    if (id == null) return;
    final generation = _generation;
    try {
      if (_sources.containsKey(id)) {
        final response = await widget.api.get('sources', {'id': _sources[id]!});
        if (!mounted || generation != _generation || _selected != id) return;
        final docs = response['documents'] as List;
        if (docs.isNotEmpty) _source(docs.first as Map<String, dynamic>);
      } else if (_threads.containsKey(id)) {
        final (mailbox, original) = _threads[id]!;
        final detail = await _support.thread(mailbox, original);
        if (!mounted || generation != _generation || _selected != id) return;
        _details[id] = detail;
        final current = _items[id]!;
        _put(
          _row(
            id,
            detail.subject,
            current.authorOrPublisher,
            detail.messages
                .map(
                  (m) => '${m.from}\n${m.date?.toLocal() ?? ''}\n\n${m.text}',
                )
                .join('\n\n────────\n\n'),
            date: current.publishedAt,
            type: 'Service client',
            tags: [detail.status.label],
          ),
          'support',
        );
      } else if (_campaigns.containsKey(id)) {
        final (repository, original) = _campaigns[id]!;
        final session = await repository.open(original);
        if (!mounted || generation != _generation || _selected != id) return;
        _sessions[id] = session;
        final draft = session.draft;
        _put(
          _row(
            id,
            draft.title,
            repository.business.brand,
            [
              draft.subject,
              draft.preheader,
              ...draft.blocks.map((b) => b.text),
            ].where((s) => s.isNotEmpty).join('\n\n'),
            date: _items[id]!.publishedAt,
            type: 'Campagne',
            tags: _items[id]!.tags,
          ),
          'diffusion',
        );
      }
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted && _selected == id) setState(() => _error = _message(error));
    }
  }

  Future<void> _connect(String id) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final url = await _support.connect(id);
      if (!await launchUrl(url, webOnlyWindowName: '_self')) {
        throw const SupportException('Impossible d’ouvrir Google.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(CampaignEditorSession session) async {
    if (_busy || widget.onOpenCampaign == null) return;
    await widget.onOpenCampaign!(session);
    if (mounted) await _load();
  }

  Future<void> _create() async {
    if (_busy || _repositories.isEmpty) return;
    final controller = TextEditingController();
    String businessId = _repositories.keys.first;
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouvelle campagne'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: businessId,
              items: _repositories.values
                  .map(
                    (r) => DropdownMenuItem(
                      value: r.business.id,
                      child: Text(r.business.brand),
                    ),
                  )
                  .toList(),
              onChanged: (id) {
                if (id != null) businessId = id;
              },
            ),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 160,
              decoration: const InputDecoration(
                labelText: 'Nom de la campagne',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Créer le brouillon'),
          ),
        ],
      ),
    );
    // Dialog route may still animate out while its TextField is mounted.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    if (title == null || !mounted) return;
    setState(() => _busy = true);
    CampaignEditorSession? session;
    try {
      final repo = _repositories[businessId]!;
      final campaign = await repo.create(title: title);
      session = await repo.open(campaign.id);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (session != null && mounted) await _edit(session);
  }

  Future<void> _status(String id, SupportStatus status) async {
    if (_busy) return;
    final (mailbox, original) = _threads[id]!;
    setState(() => _busy = true);
    var saved = false;
    try {
      await _support.setStatus(mailbox, original, status);
      saved = true;
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && saved) await _select(id);
  }

  Future<void> _reply(
    String id,
    SupportThread thread,
    TextEditingController draft,
  ) async {
    final replyAll = _replyAll[id] == true;
    if (_busy ||
        !thread.canReply ||
        (replyAll && !thread.canReplyAll) ||
        draft.text.trim().isEmpty) {
      return;
    }
    final text = draft.text.trim();
    final files = List<SupportReplyAttachment>.of(_attachments[id] ?? []);
    final recipients = replyAll ? thread.replyAllRecipients : [thread.replyTo!];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          replyAll
              ? 'Envoyer cette réponse à tous ?'
              : 'Envoyer cette réponse ?',
        ),
        content: SingleChildScrollView(
          child: Text(
            'Destinataires : ${recipients.join(', ')}\n\n$text'
            '${files.isEmpty ? '' : '\n\nPièces jointes : ${files.map((f) => f.name).join(', ')}'}',
          ),
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
    final (mailbox, original) = _threads[id]!;
    setState(() => _busy = true);
    try {
      final result = await _support.reply(
        mailbox,
        original,
        body: text,
        expectedMessageId: thread.latestMessageId,
        replyAll: replyAll,
        attachments: files,
      );
      _lockedReplies.add('$id:${thread.latestMessageId}');
      if (!mounted) return;
      setState(() {
        _error = result == SupportReplyResult.submitted
            ? 'Réponse acceptée par Gmail.'
            : 'Résultat incertain. Vérifiez Gmail avant tout autre envoi.';
        if (result == SupportReplyResult.submitted) {
          draft.clear();
          _attachments.remove(id);
        }
      });
    } catch (error) {
      if (error is! SupportException || error.outcomeUnknown) {
        _lockedReplies.add('$id:${thread.latestMessageId}');
      }
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAttachments(String id) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.pickFiles(
        dialogTitle: 'Joindre des fichiers',
      );
      final files = List<SupportReplyAttachment>.of(_attachments[id] ?? []);
      if (files.length + picked.length > 10) {
        throw const SupportException(
          'Vous pouvez joindre au maximum 10 fichiers.',
        );
      }
      var total = files.fold<int>(0, (sum, f) => sum + f.size);
      for (final file in picked) {
        final size = file.lengthSync() ?? await file.length();
        if (size == null ||
            size > 3 * 1024 * 1024 ||
            total + size > 3 * 1024 * 1024) {
          throw const SupportException(
            'Les pièces jointes sont limitées à 3 Mio au total.',
          );
        }
        final chunks = <int>[];
        await for (final chunk in file.readAsByteStream()) {
          if (total + chunks.length + chunk.length > 3 * 1024 * 1024) {
            throw const SupportException(
              'Les pièces jointes sont limitées à 3 Mio au total.',
            );
          }
          chunks.addAll(chunk);
        }
        final bytes = chunks;
        total += bytes.length;
        if (total > 3 * 1024 * 1024) {
          throw const SupportException(
            'Les pièces jointes sont limitées à 3 Mio au total.',
          );
        }
        files.add(
          SupportReplyAttachment(
            name: file.name,
            mimeType: 'application/octet-stream',
            dataBase64: base64Encode(bytes),
            size: bytes.length,
          ),
        );
      }
      if (mounted) setState(() => _attachments[id] = files);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download(
    String id,
    SupportMessage message,
    SupportAttachment attachment,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final (mailbox, thread) = _threads[id]!;
      final bytes = await _support.download(
        mailbox,
        thread,
        message.id,
        attachment,
      );
      await FilePicker.saveFile(
        dialogTitle: 'Enregistrer la pièce jointe',
        fileName: safeDownloadName(attachment.name),
        bytes: bytes,
      );
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _searchSupport() async {
    if (_loading || _busy) return;
    final query = TextEditingController(text: _supportQuery);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rechercher dans toutes les boîtes Gmail'),
        content: TextField(
          controller: query,
          autofocus: true,
          maxLength: 512,
          decoration: const InputDecoration(
            labelText: 'Recherche Gmail',
            helperText:
                'Inclut les archives, spams et corbeille. Ex. : has:attachment',
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, query.text.trim()),
            child: const Text('Rechercher'),
          ),
        ],
      ),
    );
    // The dialog route may still use its controller during the closing frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => query.dispose());
    if (value == null || !mounted) return;
    _supportQuery = value;
    await _load();
  }

  Widget? _readerBody() {
    final id = _selected;
    final thread = _details[id];
    if (id == null || thread == null) return null;
    return SupportReader(
      key: ValueKey('reader:$id'),
      thread: thread,
      busy: _busy,
      onDownload: (message, attachment) => _download(id, message, attachment),
      onOpenLink: (uri) async {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
    );
  }

  Widget? _footer() {
    final id = _selected;
    if (id == null) return null;
    final session = _sessions[id];
    if (session != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: _busy ? null : () => _edit(session),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Ouvrir dans le studio'),
        ),
      );
    }
    final thread = _details[id];
    if (thread == null) return null;
    final draft = _drafts.putIfAbsent(id, TextEditingController.new);
    final locked = _lockedReplies.contains('$id:${thread.latestMessageId}');
    final allowed =
        thread.canReply && _supportContext?.canReply == true && !locked;
    final replyAll = _replyAll[id] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: _style.gapSmall,
          children: SupportStatus.values
              .map(
                (s) => ChoiceChip(
                  label: Text(s.label),
                  selected: s == thread.status,
                  onSelected: _busy ? null : (_) => _status(id, s),
                ),
              )
              .toList(),
        ),
        SizedBox(height: _style.gapLarge),
        Wrap(
          spacing: _style.gapSmall,
          children: [
            ChoiceChip(
              label: const Text('Réponse simple'),
              selected: !replyAll,
              onSelected: _busy
                  ? null
                  : (_) => setState(() => _replyAll[id] = false),
            ),
            ChoiceChip(
              label: const Text('Répondre à tous'),
              selected: replyAll,
              onSelected: _busy || !thread.canReplyAll
                  ? null
                  : (_) => setState(() => _replyAll[id] = true),
            ),
          ],
        ),
        if (!thread.canReplyAll)
          const Text(
            'Réponse à tous indisponible : le routage des participants doit être vérifié.',
          ),
        if (replyAll)
          Text('Destinataires : ${thread.replyAllRecipients.join(', ')}'),
        TextField(
          key: ValueKey('reply:$id'),
          controller: draft,
          enabled: !_busy,
          minLines: 3,
          maxLines: 8,
          maxLength: 20000,
          decoration: const InputDecoration(
            labelText: 'Votre réponse',
            hintText: 'Brouillon conservé pendant cette session.',
          ),
        ),
        SizedBox(height: _style.gapSmall),
        for (final file in _attachments[id] ?? <SupportReplyAttachment>[])
          ListTile(
            title: Text(file.name),
            subtitle: Text('${file.size} octets'),
            trailing: IconButton(
              tooltip: 'Retirer ${file.name}',
              icon: const Icon(Icons.close),
              onPressed: _busy
                  ? null
                  : () => setState(() => _attachments[id]!.remove(file)),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy || !allowed ? null : () => _pickAttachments(id),
            icon: const Icon(Icons.attach_file),
            label: const Text('Joindre des fichiers'),
          ),
        ),
        const Text(
          '10 fichiers maximum · 3 Mio au total. Brouillon conservé pendant cette session.',
        ),
        Text(
          allowed
              ? 'La réponse utilise le relais vérifié : ${thread.replyTo}'
              : locked || thread.replyDisabledReason == 'reply_delivery_unknown'
              ? 'Une réponse est en cours de vérification. Consultez Gmail.'
              : 'Réponse désactivée : connexion ou routage à vérifier.',
        ),
        SizedBox(height: _style.gapSmall),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: _busy || !allowed || (replyAll && !thread.canReplyAll)
                ? null
                : () => _reply(id, thread, draft),
            child: const Text('Répondre'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => SourceSidebar(
    title: 'ShipGlows Email Engine',
    items: _items.values.toList(),
    selectedId: _selected,
    onSelected: _select,
    itemSectionIds: _sections,
    sectionLabels: _labels,
    sectionEmptyMessages: _notices,
    sectionKeys: _sectionKeys,
    readerFooter: _footer(),
    readerBody: _readerBody(),
    searchHint: 'Filtrer les éléments déjà chargés',
    navigationHeader: _supportQuery.isEmpty
        ? null
        : Padding(
            padding: _style.searchPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('Recherche Gmail')),
                    IconButton(
                      tooltip: 'Effacer la recherche Gmail',
                      onPressed: _loading || _busy
                          ? null
                          : () async {
                              _supportQuery = '';
                              await _load();
                            },
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Tooltip(
                  message: _supportQuery,
                  child: Text(
                    _supportQuery,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Text('Toutes les boîtes · résultats paginés'),
                SizedBox(height: _style.gapLarge),
              ],
            ),
          ),
    topBarActions: [
      IconButton(
        tooltip: 'Rechercher dans toutes les boîtes Gmail',
        onPressed: _loading || _busy ? null : _searchSupport,
        icon: const Icon(Icons.manage_search),
      ),
      if (_supportContext?.mailboxes.isNotEmpty == true)
        PopupMenuButton<String>(
          tooltip: 'Connecter une boîte Gmail',
          icon: const Icon(Icons.link),
          onSelected: _connect,
          itemBuilder: (_) => _supportContext!.mailboxes
              .map((b) => PopupMenuItem(value: b.id, child: Text(b.email)))
              .toList(),
        ),
      IconButton(
        tooltip: 'Nouvelle campagne',
        onPressed: _loading || _busy || _repositories.isEmpty ? null : _create,
        icon: const Icon(Icons.add),
      ),
      IconButton(
        tooltip: widget.darkMode ? 'Thème clair' : 'Thème sombre',
        onPressed: widget.onToggleTheme,
        icon: Icon(
          widget.darkMode
              ? Icons.light_mode_outlined
              : Icons.dark_mode_outlined,
        ),
      ),
    ],
    onRefresh: _load,
    refreshTooltip: 'Actualiser la boîte',
    isLoading: _loading && _items.isEmpty,
    isLoadingMore: _loading && _items.isNotEmpty,
    hasMore: _cursors.isNotEmpty,
    onLoadMore: () => _load(more: true),
    errorMessage: _error,
    emptyMessage: _notices.values.join('\n'),
    onOpenExternal: _selected != null && _sources.containsKey(_selected)
        ? (item) async {
            if (item.canonicalExternalUrl != null) {
              await launchUrl(
                item.canonicalExternalUrl!,
                mode: LaunchMode.externalApplication,
              );
            }
          }
        : null,
    onActionError: (_) =>
        setState(() => _error = 'Action indisponible. Réessayez.'),
  );
}

import 'package:flutter/material.dart';
import 'newsletter_campaign_models.dart';
import 'newsletter_studio_style.dart';

/// A bounded, accessible campaign list. Opening a campaign belongs to its host.
class CampaignWorkspace extends StatefulWidget {
  const CampaignWorkspace({
    super.key,
    required this.repository,
    required this.onOpenCampaign,
    this.style = const NewsletterStudioStyle(),
    this.canCreate = true,
    this.disabledReason,
    this.businessLabel,
    this.onBack,
  });
  final NewsletterCampaignRepository repository;
  final Future<void> Function(NewsletterCampaign campaign) onOpenCampaign;
  final NewsletterStudioStyle style;
  final bool canCreate;
  final String? disabledReason;
  final String? businessLabel;
  final VoidCallback? onBack;
  @override
  State<CampaignWorkspace> createState() => _CampaignWorkspaceState();
}

class _CampaignWorkspaceState extends State<CampaignWorkspace> {
  final List<NewsletterCampaign> _items = [];
  NewsletterCampaignStatus? _filter;
  String? _cursor;
  String? _error;
  bool _loading = true;
  bool _opening = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CampaignWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) _load();
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.repository.list(
        cursor: more ? _cursor : null,
        status: _filter,
        limit: 25,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        if (!more) _items.clear();
        final ids = _items.map((item) => item.id).toSet();
        _items.addAll(page.items.where((item) => ids.add(item.id)));
        _cursor = page.nextCursor;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error =
            'Impossible de charger les campagnes. Vérifiez votre connexion puis réessayez.';
      });
    }
  }

  Future<void> _open(NewsletterCampaign item) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      await widget.onOpenCampaign(item);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Impossible d’ouvrir ce brouillon. Vos campagnes restent conservées.';
        });
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _create() async {
    if (_opening || !widget.canCreate) return;
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouvelle campagne'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 160,
          decoration: const InputDecoration(
            labelText: 'Nom interne',
            hintText: 'Les nouvelles de septembre',
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
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
    // Route exit animation still reads the field controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (!mounted || title == null) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    NewsletterCampaign? created;
    try {
      created = await widget.repository.create(title: title);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'La création n’a pas pu être confirmée. Actualisez la liste avant de réessayer.';
        });
      }
    }
    if (!mounted) return;
    setState(() => _opening = false);
    await _load();
    if (created != null && mounted) await _open(created);
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final colors =
        style.colors ??
        NewsletterStudioColors.fromColorScheme(Theme.of(context).colorScheme);
    return ColoredBox(
      color: colors.canvas,
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: style.canvasPadding,
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: style.largeGap,
                      runSpacing: style.mediumGap,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (widget.onBack != null)
                          IconButton(
                            onPressed: widget.onBack,
                            tooltip: 'Retour',
                            icon: const Icon(Icons.arrow_back),
                          ),
                        const Icon(Icons.mark_email_unread_outlined),
                        Text(
                          widget.businessLabel == null
                              ? 'Campagnes'
                              : 'Campagnes · ${widget.businessLabel}',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        FilledButton.icon(
                          onPressed: widget.canCreate && !_opening
                              ? _create
                              : null,
                          icon: const Icon(Icons.add),
                          label: const Text('Nouvelle campagne'),
                        ),
                        IconButton(
                          onPressed: _loading ? null : () => _load(),
                          tooltip: 'Actualiser',
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    SizedBox(height: style.smallGap),
                    Text(
                      'Préparez vos nouvelles, choisissez votre audience et suivez chaque envoi.',
                      style: TextStyle(color: colors.mutedForeground),
                    ),
                    if (widget.disabledReason != null)
                      Padding(
                        padding: EdgeInsets.only(top: style.mediumGap),
                        child: Text(
                          widget.disabledReason!,
                          style: TextStyle(color: colors.warning),
                        ),
                      ),
                    SizedBox(height: style.extraLargeGap),
                    Wrap(
                      spacing: style.smallGap,
                      runSpacing: style.smallGap,
                      children: [
                        ChoiceChip(
                          label: const Text('Toutes'),
                          selected: _filter == null,
                          onSelected: _loading
                              ? null
                              : (_) {
                                  _filter = null;
                                  _load();
                                },
                        ),
                        for (final status in [
                          NewsletterCampaignStatus.draft,
                          NewsletterCampaignStatus.scheduled,
                          NewsletterCampaignStatus.sending,
                          NewsletterCampaignStatus.completed,
                          NewsletterCampaignStatus.cancelled,
                        ])
                          ChoiceChip(
                            label: Text(status.label),
                            selected: _filter == status,
                            onSelected: _loading
                                ? null
                                : (_) {
                                    _filter = status;
                                    _load();
                                  },
                          ),
                      ],
                    ),
                    if (_loading)
                      Padding(
                        padding: EdgeInsets.only(top: style.largeGap),
                        child: const LinearProgressIndicator(),
                      ),
                    if (_error != null)
                      Padding(
                        padding: EdgeInsets.only(top: style.largeGap),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                _error!,
                                style: TextStyle(color: colors.danger),
                              ),
                            ),
                            TextButton(
                              onPressed: () => _load(),
                              child: const Text('Réessayer'),
                            ),
                          ],
                        ),
                      ),
                    if (!_loading && _items.isEmpty && _error == null)
                      Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: style.extraLargeGap * 2,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.drafts_outlined,
                              size: style.emptyStateIconSize,
                              color: colors.mutedForeground,
                            ),
                            SizedBox(height: style.largeGap),
                            Text(
                              'Votre prochaine newsletter commence ici.',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const Text(
                              'Créez un brouillon. Aucun message ne part sans votre confirmation.',
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: style.panelPadding,
              sliver: SliverList.builder(
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return Card(
                    color: colors.surface,
                    margin: EdgeInsets.only(bottom: style.mediumGap),
                    child: Semantics(
                      button: true,
                      enabled: !_opening,
                      excludeSemantics: true,
                      label:
                          '${item.title}, ${item.status.label}, ${item.eligibleCount} destinataires, ${item.deliveredCount} livrés, ${item.failedCount} échecs, ${item.unknownCount} résultats incertains',
                      onTap: _opening ? null : () => _open(item),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(style.blockRadius),
                        onTap: _opening ? null : () => _open(item),
                        child: Padding(
                          padding: style.panelPadding,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: style.mediumGap,
                                runSpacing: style.smallGap,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    item.title,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  Chip(
                                    label: Text(item.status.label),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                              if (item.subject.isNotEmpty)
                                Text(
                                  item.subject,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              SizedBox(height: style.smallGap),
                              Wrap(
                                spacing: style.largeGap,
                                runSpacing: style.smallGap,
                                children: [
                                  Text(
                                    item.audienceLabel ?? 'Audience à définir',
                                  ),
                                  Text('${item.eligibleCount} destinataires'),
                                  if (item.submittedCount > 0)
                                    Text('${item.submittedCount} transmis'),
                                  if (item.deliveredCount > 0)
                                    Text('${item.deliveredCount} livrés'),
                                  if (item.failedCount > 0)
                                    Text(
                                      '${item.failedCount} échecs',
                                      style: TextStyle(color: colors.danger),
                                    ),
                                  if (item.unknownCount > 0)
                                    Text(
                                      '${item.unknownCount} résultats incertains',
                                      style: TextStyle(color: colors.warning),
                                    ),
                                  if (item.scheduledAt != null)
                                    Text(
                                      'Prévue le ${_date(item.scheduledAt!)}',
                                    ),
                                  Text(
                                    'Modifiée le ${_date(item.updatedAt)}',
                                    style: TextStyle(
                                      color: colors.mutedForeground,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_cursor != null)
              SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: style.panelPadding,
                    child: OutlinedButton(
                      onPressed: _loading ? null : () => _load(more: true),
                      child: const Text('Charger la suite'),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _date(DateTime date) {
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} à ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

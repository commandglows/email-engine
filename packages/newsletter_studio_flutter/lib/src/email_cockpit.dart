import 'package:flutter/material.dart';
import 'email_cockpit_tokens.dart';

/// Shared navigation; connectors remain owned by the authenticated host.
enum EmailSection { overview, sources, support, diffusion }

extension EmailSectionLabels on EmailSection {
  String get label => switch (this) {
    EmailSection.overview => 'Vue d’ensemble',
    EmailSection.sources => 'Sources',
    EmailSection.support => 'Service client',
    EmailSection.diffusion => 'Diffusion',
  };
  String get provider => switch (this) {
    EmailSection.overview => 'Votre cockpit email',
    EmailSection.sources => 'Readwise Reader',
    EmailSection.support => 'Gmail · Mutant Mail',
    EmailSection.diffusion => 'Postmark',
  };
  IconData get icon => switch (this) {
    EmailSection.overview => Icons.space_dashboard_outlined,
    EmailSection.sources => Icons.auto_stories_outlined,
    EmailSection.support => Icons.forum_outlined,
    EmailSection.diffusion => Icons.send_outlined,
  };
}

class EmailCockpit extends StatefulWidget {
  const EmailCockpit({
    super.key,
    required this.builder,
    this.initialSection = EmailSection.overview,
    this.demonstration = false,
    this.onToggleTheme,
    this.darkMode = false,
  });
  final Widget Function(BuildContext, EmailSection) builder;
  final EmailSection initialSection;
  final bool demonstration;
  final VoidCallback? onToggleTheme;
  final bool darkMode;

  @override
  State<EmailCockpit> createState() => _EmailCockpitState();
}

class _EmailCockpitState extends State<EmailCockpit> {
  final _contentKey = GlobalKey();
  late EmailSection _section = widget.initialSection;
  late final Set<EmailSection> _visited = {_section};

  void _select(EmailSection section) => setState(() {
    _section = section;
    _visited.add(section);
  });

  Widget _navigation({bool drawer = false}) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EmailCockpitLayout.padding,
              child: Row(
                children: [
                  Icon(Icons.mark_email_read_outlined, color: colors.primary),
                  const SizedBox(width: EmailCockpitLayout.mediumGap),
                  Expanded(
                    child: Text(
                      'ShipGlows\nEmail Engine',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: EmailCockpitLayout.mediumGap,
                ),
                children: [
                  for (final section in EmailSection.values) ...[
                    if (section == EmailSection.sources)
                      const Divider(height: EmailCockpitLayout.sectionGap),
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: EmailCockpitLayout.smallGap,
                      ),
                      child: ListTile(
                        selected: _section == section,
                        selectedTileColor: colors.secondaryContainer,
                        selectedColor: colors.onSecondaryContainer,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            EmailCockpitLayout.navigationRadius,
                          ),
                        ),
                        leading: Icon(section.icon),
                        title: Text(section.label),
                        subtitle: section == EmailSection.overview
                            ? null
                            : Text(section.provider),
                        onTap: () {
                          _select(section);
                          if (drawer) Navigator.of(context).pop();
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.demonstration)
              const Padding(
                padding: EmailCockpitLayout.padding,
                child: Text(
                  'Démonstration\nDonnées fictives · aucun envoi réel',
                ),
              ),
            if (widget.onToggleTheme != null)
              ListTile(
                leading: Icon(
                  widget.darkMode
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                ),
                title: Text(widget.darkMode ? 'Thème clair' : 'Thème sombre'),
                onTap: widget.onToggleTheme,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = KeyedSubtree(
      key: _contentKey,
      child: IndexedStack(
        index: _section.index,
        children: [
          for (final section in EmailSection.values)
            if (!_visited.contains(section))
              const SizedBox.shrink()
            else
              TickerMode(
                enabled: _section == section,
                child: section == EmailSection.overview
                    ? _CockpitOverview(
                        onSelect: _select,
                        demonstration: widget.demonstration,
                      )
                    : KeyedSubtree(
                        key: ValueKey(section),
                        child: widget.builder(context, section),
                      ),
              ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= EmailCockpitLayout.wideBreakpoint;
        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                SizedBox(
                  width: EmailCockpitLayout.sidebarWidth,
                  child: _navigation(),
                ),
                const VerticalDivider(width: EmailCockpitLayout.rule),
                Expanded(child: body),
              ],
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(_section.label),
            actions: [
              if (widget.demonstration)
                const Padding(
                  padding: EdgeInsets.only(right: EmailCockpitLayout.gap),
                  child: Chip(label: Text('Démo')),
                ),
            ],
          ),
          drawer: Drawer(child: _navigation(drawer: true)),
          body: SafeArea(top: false, child: body),
        );
      },
    );
  }
}

class _CockpitOverview extends StatelessWidget {
  const _CockpitOverview({required this.onSelect, required this.demonstration});
  final ValueChanged<EmailSection> onSelect;
  final bool demonstration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ColoredBox(
      color: colors.surface,
      child: ListView(
        padding: EmailCockpitLayout.padding,
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: EmailCockpitLayout.contentWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'VOTRE ESPACE EMAIL',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(height: EmailCockpitLayout.mediumGap),
                  Text(
                    'Tout commence par une conversation.',
                    style: theme.textTheme.headlineLarge,
                  ),
                  const SizedBox(height: EmailCockpitLayout.mediumGap),
                  Text(
                    'Vos lectures, vos clients et vos campagnes. Un seul endroit pour garder le fil.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (demonstration) ...[
                    const SizedBox(height: EmailCockpitLayout.mediumGap),
                    Text(
                      'Aperçu interactif avec des exemples. Les connexions réelles se configurent dans l’application authentifiée.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: EmailCockpitLayout.sectionGap),
                  _space(
                    context,
                    EmailSection.sources,
                    'Nourrir vos idées',
                    'Retrouvez les emails et lectures de votre bibliothèque Reader.',
                    'Explorer les sources',
                  ),
                  const SizedBox(height: EmailCockpitLayout.gap),
                  _space(
                    context,
                    EmailSection.support,
                    'Prendre soin de vos clients',
                    'Retrouvez les échanges de vos boîtes Gmail, suivez les demandes et préparez vos réponses.',
                    'Ouvrir le service client',
                  ),
                  const SizedBox(height: EmailCockpitLayout.gap),
                  _space(
                    context,
                    EmailSection.diffusion,
                    'Partager ce qui compte',
                    'Préparez vos newsletters, programmez vos campagnes et suivez les livraisons.',
                    'Accéder aux campagnes',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _space(
    BuildContext context,
    EmailSection section,
    String title,
    String description,
    String action,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: EmailCockpitLayout.radius,
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: EmailCockpitLayout.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: EmailCockpitLayout.mediumGap,
              runSpacing: EmailCockpitLayout.smallGap,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(section.icon, color: colors.primary),
                Text(section.label, style: theme.textTheme.titleMedium),
                Text(
                  section.provider,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: EmailCockpitLayout.gap),
            Text(title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: EmailCockpitLayout.smallGap),
            Text(description, style: theme.textTheme.bodyMedium),
            const SizedBox(height: EmailCockpitLayout.gap),
            OutlinedButton.icon(
              onPressed: () => onSelect(section),
              icon: const Icon(Icons.arrow_forward),
              label: Text(action),
            ),
          ],
        ),
      ),
    );
  }
}

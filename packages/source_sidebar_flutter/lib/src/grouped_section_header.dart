import 'package:flutter/material.dart';

import 'source_sidebar_style.dart';

({Color background, Color foreground, IconData icon}) groupedSectionAppearance(
  ColorScheme scheme,
  String sectionId,
) {
  final violetPrimary = HSLColor.fromColor(
    scheme.primaryContainer,
  ).withHue(265).toColor();
  return switch (sectionId) {
    'support' => (
      background: scheme.secondaryContainer,
      foreground: scheme.onSecondaryContainer,
      icon: Icons.support_agent_outlined,
    ),
    'diffusion' => (
      background: scheme.tertiaryContainer,
      foreground: scheme.onTertiaryContainer,
      icon: Icons.campaign_outlined,
    ),
    _ => (
      background: violetPrimary,
      foreground: scheme.onPrimaryContainer,
      icon: Icons.auto_stories_outlined,
    ),
  };
}

class GroupedSectionHeader extends StatelessWidget {
  const GroupedSectionHeader({
    super.key,
    required this.sectionId,
    required this.label,
    required this.isFirst,
    required this.collapsed,
    required this.unreadCount,
    required this.totalCount,
    required this.style,
    required this.colors,
    required this.onTap,
  });

  final String sectionId;
  final String label;
  final bool isFirst;
  final bool collapsed;
  final int unreadCount;
  final int totalCount;
  final SourceSidebarStyle style;
  final SourceSidebarColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final appearance = groupedSectionAppearance(
      Theme.of(context).colorScheme,
      sectionId,
    );
    final topInset = isFirst ? 0.0 : style.gap4XLarge;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        style.contentPadding.resolve(Directionality.of(context)).left,
        topInset,
        style.contentPadding.resolve(Directionality.of(context)).right,
        style.gapSmall,
      ),
      child: Semantics(
        container: true,
        button: true,
        expanded: !collapsed,
        label:
            '${collapsed ? 'Afficher' : 'Masquer'} $label, $unreadCount non lus sur $totalCount',
        child: ExcludeSemantics(
          child: Material(
            color: appearance.background,
            borderRadius: BorderRadius.circular(style.primaryActionRadius),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(style.primaryActionRadius),
              focusColor: colors.focus.withValues(
                alpha: style.focusOverlayOpacity,
              ),
              child: SizedBox(
                height: style.denseRowHeight,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: style.gapLarge),
                  child: Row(
                    children: [
                      Icon(appearance.icon, color: appearance.foreground),
                      SizedBox(width: style.gapMedium),
                      Expanded(
                        child: Text(
                          label,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: appearance.foreground,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      Icon(
                        Icons.mark_email_unread_outlined,
                        color: appearance.foreground,
                        size: style.actionIconSize,
                      ),
                      SizedBox(width: style.gapSmall),
                      Text(
                        '$unreadCount / $totalCount',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: appearance.foreground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: style.gapMedium),
                      Icon(
                        collapsed ? Icons.expand_more : Icons.expand_less,
                        color: appearance.foreground,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

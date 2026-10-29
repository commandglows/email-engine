import 'package:flutter/material.dart';

import 'email_cockpit_tokens.dart';

/// Visual weight of an [EmailStatePill].
enum EmailPillTone { neutral, strong, muted }

/// Compact status label shared by conversation rows, headers and dispatch.
class EmailStatePill extends StatelessWidget {
  const EmailStatePill(
    this.label, {
    super.key,
    this.tone = EmailPillTone.neutral,
  });

  final String label;
  final EmailPillTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (tone) {
      EmailPillTone.neutral => (
        scheme.surfaceContainerHighest,
        scheme.onSurface,
      ),
      EmailPillTone.strong => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      EmailPillTone.muted => (Colors.transparent, scheme.onSurfaceVariant),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(EmailCockpitLayout.pillRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: foreground),
        ),
      ),
    );
  }
}

/// Inline message. Errors use the error tones; everything else stays neutral.
class EmailNotice extends StatelessWidget {
  const EmailNotice(this.text, {super.key, this.error = false, this.icon});

  final String text;
  final bool error;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = error
        ? scheme.onErrorContainer
        : scheme.onSurfaceVariant;
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: error ? scheme.errorContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(EmailCockpitLayout.tileRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(EmailCockpitLayout.mediumGap),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon ?? (error ? Icons.error_outline : Icons.info_outline),
                size: 18,
                color: foreground,
              ),
              const SizedBox(width: EmailCockpitLayout.smallGap),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The one empty, waiting or blocked state used by every mailbox panel.
class EmailEmptyState extends StatelessWidget {
  const EmailEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(EmailCockpitLayout.largeGap),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: EmailCockpitLayout.emptyWidth,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(EmailCockpitLayout.gap),
                  child: Icon(
                    icon,
                    size: EmailCockpitLayout.emptyIcon,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: EmailCockpitLayout.gap),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              if (description case final text?) ...[
                const SizedBox(height: EmailCockpitLayout.smallGap),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (action case final button?) ...[
                const SizedBox(height: EmailCockpitLayout.gap),
                button,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

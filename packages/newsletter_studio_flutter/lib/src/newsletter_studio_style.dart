import 'package:flutter/material.dart';

@immutable
class NewsletterStudioColors {
  const NewsletterStudioColors({
    required this.canvas,
    required this.surface,
    required this.subtleSurface,
    required this.selectedSurface,
    required this.foreground,
    required this.mutedForeground,
    required this.divider,
    required this.focus,
    required this.primaryActionSurface,
    required this.primaryActionForeground,
    required this.warning,
    required this.danger,
    required this.success,
  });

  factory NewsletterStudioColors.fromColorScheme(ColorScheme colors) {
    return NewsletterStudioColors(
      canvas: colors.surfaceContainerLowest,
      surface: colors.surface,
      subtleSurface: colors.surfaceContainerLow,
      selectedSurface: colors.primaryContainer,
      foreground: colors.onSurface,
      mutedForeground: colors.onSurfaceVariant,
      divider: colors.outlineVariant,
      focus: colors.primary,
      primaryActionSurface: colors.primary,
      primaryActionForeground: colors.onPrimary,
      warning: colors.tertiary,
      danger: colors.error,
      success: colors.secondary,
    );
  }

  final Color canvas;
  final Color surface;
  final Color subtleSurface;
  final Color selectedSurface;
  final Color foreground;
  final Color mutedForeground;
  final Color divider;
  final Color focus;
  final Color primaryActionSurface;
  final Color primaryActionForeground;
  final Color warning;
  final Color danger;
  final Color success;
}

@immutable
class NewsletterStudioStyle {
  const NewsletterStudioStyle({
    this.colors,
    this.compactBreakpoint = 760,
    this.expandedBreakpoint = 1200,
    this.sourcePaneWidth = 304,
    this.inspectorWidth = 328,
    this.emailCanvasWidth = 640,
    this.reviewPanelWidth = 440,
    this.railWidth = 52,
    this.topBarHeight = 64,
    this.compactActionBarHeight = 64,
    this.panelPadding = const EdgeInsets.all(16),
    this.canvasPadding = const EdgeInsets.symmetric(
      horizontal: 28,
      vertical: 24,
    ),
    this.blockPadding = const EdgeInsets.symmetric(
      horizontal: 20,
      vertical: 14,
    ),
    this.smallGap = 8,
    this.mediumGap = 12,
    this.largeGap = 16,
    this.extraLargeGap = 24,
    this.panelRadius = 16,
    this.blockRadius = 12,
    this.chipRadius = 999,
    this.focusWidth = 2,
    this.dividerThickness = 1,
    this.reviewElevation = 12,
    this.compactIconSize = 18,
    this.emptyStateIconSize = 32,
    this.panelSheetHeightFactor = 0.82,
    this.errorSurfaceOpacity = 0.1,
    this.summaryRowVerticalPadding = 6,
    this.minimumZoom = 0.75,
    this.maximumZoom = 1.5,
    this.initialZoom = 1,
    this.zoomStep = 0.1,
    this.autosaveDelay = const Duration(milliseconds: 650),
    this.focusScrollDuration = const Duration(milliseconds: 120),
    this.controlTransitionDuration = const Duration(milliseconds: 120),
    this.reviewTransitionDuration = const Duration(milliseconds: 160),
  }) : assert(compactBreakpoint > 0),
       assert(expandedBreakpoint >= compactBreakpoint),
       assert(minimumZoom > 0),
       assert(maximumZoom >= minimumZoom),
       assert(initialZoom >= minimumZoom && initialZoom <= maximumZoom),
       assert(zoomStep > 0),
       assert(panelSheetHeightFactor > 0 && panelSheetHeightFactor <= 1),
       assert(errorSurfaceOpacity >= 0 && errorSurfaceOpacity <= 1);

  final NewsletterStudioColors? colors;
  final double compactBreakpoint;
  final double expandedBreakpoint;
  final double sourcePaneWidth;
  final double inspectorWidth;
  final double emailCanvasWidth;
  final double reviewPanelWidth;
  final double railWidth;
  final double topBarHeight;
  final double compactActionBarHeight;
  final EdgeInsetsGeometry panelPadding;
  final EdgeInsetsGeometry canvasPadding;
  final EdgeInsetsGeometry blockPadding;
  final double smallGap;
  final double mediumGap;
  final double largeGap;
  final double extraLargeGap;
  final double panelRadius;
  final double blockRadius;
  final double chipRadius;
  final double focusWidth;
  final double dividerThickness;
  final double reviewElevation;
  final double compactIconSize;
  final double emptyStateIconSize;
  final double panelSheetHeightFactor;
  final double errorSurfaceOpacity;
  final double summaryRowVerticalPadding;
  final double minimumZoom;
  final double maximumZoom;
  final double initialZoom;
  final double zoomStep;
  final Duration autosaveDelay;
  final Duration focusScrollDuration;
  final Duration controlTransitionDuration;
  final Duration reviewTransitionDuration;
}

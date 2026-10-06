import 'package:flutter/material.dart';

/// Shared geometry authority. Colors and typography come from the host theme.
abstract final class EmailCockpitLayout {
  static const wideBreakpoint = 1000.0;
  static const supportBreakpoint = 760.0;
  static const sidebarWidth = 244.0;
  static const conversationWidth = 320.0;
  static const contentWidth = 1120.0;
  static const smallGap = 8.0;
  static const mediumGap = 12.0;
  static const gap = 16.0;
  static const detailGap = 20.0;
  static const largeGap = 24.0;
  static const sectionGap = 32.0;
  static const rule = 1.0;
  static const emptyIcon = 40.0;
  static const navigationRadius = 14.0;
  static const padding = EdgeInsets.all(largeGap);
  static const cardPadding = padding;
  static const radius = BorderRadius.all(Radius.circular(detailGap));
}

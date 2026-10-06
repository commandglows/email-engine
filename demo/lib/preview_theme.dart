import 'package:flutter/material.dart';
import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';
import 'package:source_sidebar_flutter/source_sidebar_flutter.dart';

abstract final class PreviewTheme {
  static const Duration simulatedActionDelay = Duration(milliseconds: 450);

  static const SourceSidebarColors lightColors = SourceSidebarColors(
    canvas: Color(0xFFF6F8FC),
    surface: Color(0xFFFFFFFF),
    searchSurface: Color(0xFFEAF1FB),
    selectedSurface: Color(0xFFD3E3FD),
    unreadSurface: Color(0xFFF2F6FC),
    primaryActionSurface: Color(0xFFC2E7FF),
    primaryActionForeground: Color(0xFF001D35),
    foreground: Color(0xFF1F1F1F),
    mutedForeground: Color(0xFF5F6368),
    divider: Color(0xFFE0E3E7),
    focus: Color(0xFF0B57D0),
    danger: Color(0xFFB3261E),
  );

  static const SourceSidebarColors darkColors = SourceSidebarColors(
    canvas: Color(0xFF111318),
    surface: Color(0xFF1B1D21),
    searchSurface: Color(0xFF282A2E),
    selectedSurface: Color(0xFF004A77),
    unreadSurface: Color(0xFF202328),
    primaryActionSurface: Color(0xFF004A77),
    primaryActionForeground: Color(0xFFC2E7FF),
    foreground: Color(0xFFE3E3E3),
    mutedForeground: Color(0xFFC4C7C5),
    divider: Color(0xFF444746),
    focus: Color(0xFFA8C7FA),
    danger: Color(0xFFFFB4AB),
  );

  static const NewsletterStudioColors lightNewsletterColors =
      NewsletterStudioColors(
        canvas: Color(0xFFF6F8FC),
        surface: Color(0xFFFFFFFF),
        subtleSurface: Color(0xFFF2F6FC),
        selectedSurface: Color(0xFFD3E3FD),
        foreground: Color(0xFF1F1F1F),
        mutedForeground: Color(0xFF5F6368),
        divider: Color(0xFFE0E3E7),
        focus: Color(0xFF0B57D0),
        primaryActionSurface: Color(0xFF0B57D0),
        primaryActionForeground: Color(0xFFFFFFFF),
        warning: Color(0xFF8A4F00),
        danger: Color(0xFFB3261E),
        success: Color(0xFF146C2E),
      );

  static const NewsletterStudioColors darkNewsletterColors =
      NewsletterStudioColors(
        canvas: Color(0xFF111318),
        surface: Color(0xFF1B1D21),
        subtleSurface: Color(0xFF202328),
        selectedSurface: Color(0xFF004A77),
        foreground: Color(0xFFE3E3E3),
        mutedForeground: Color(0xFFC4C7C5),
        divider: Color(0xFF444746),
        focus: Color(0xFFA8C7FA),
        primaryActionSurface: Color(0xFFA8C7FA),
        primaryActionForeground: Color(0xFF062E6F),
        warning: Color(0xFFFFB95C),
        danger: Color(0xFFFFB4AB),
        success: Color(0xFF6DD58C),
      );

  static const List<SourceCategory> lightCategories = [
    SourceCategory(
      id: 'shipglows-ready',
      name: 'ShipGlows',
      color: Color(0xFF0B57D0),
      icon: Icons.rocket_launch_outlined,
      kind: SourceCategoryKind.project,
    ),
    SourceCategory(
      id: 'contentglows-ready',
      name: 'ContentGlows',
      color: Color(0xFF7B1FA2),
      icon: Icons.auto_stories_outlined,
      kind: SourceCategoryKind.project,
    ),
    SourceCategory(
      id: 'security',
      name: 'Cybersecurity',
      color: Color(0xFFB3261E),
      icon: Icons.shield_outlined,
    ),
    SourceCategory(
      id: 'flutter',
      name: 'Flutter',
      color: Color(0xFF0277BD),
      icon: Icons.flutter_dash,
    ),
  ];

  static const List<SourceCategory> darkCategories = [
    SourceCategory(
      id: 'shipglows-ready',
      name: 'ShipGlows',
      color: Color(0xFFA8C7FA),
      icon: Icons.rocket_launch_outlined,
      kind: SourceCategoryKind.project,
    ),
    SourceCategory(
      id: 'contentglows-ready',
      name: 'ContentGlows',
      color: Color(0xFFE1BEE7),
      icon: Icons.auto_stories_outlined,
      kind: SourceCategoryKind.project,
    ),
    SourceCategory(
      id: 'security',
      name: 'Cybersecurity',
      color: Color(0xFFFFB4AB),
      icon: Icons.shield_outlined,
    ),
    SourceCategory(
      id: 'flutter',
      name: 'Flutter',
      color: Color(0xFF81D4FA),
      icon: Icons.flutter_dash,
    ),
  ];

  static ThemeData light() => _theme(Brightness.light, lightColors);

  static ThemeData dark() => _theme(Brightness.dark, darkColors);

  static SourceSidebarStyle sidebarStyle(bool darkMode) =>
      SourceSidebarStyle(colors: darkMode ? darkColors : lightColors);

  static NewsletterStudioStyle newsletterStyle(bool darkMode) =>
      NewsletterStudioStyle(
        colors: darkMode ? darkNewsletterColors : lightNewsletterColors,
      );

  static List<SourceCategory> categories(bool darkMode) =>
      darkMode ? darkCategories : lightCategories;

  static ThemeData _theme(
    Brightness brightness,
    SourceSidebarColors sidebarColors,
  ) {
    final colors = ColorScheme.fromSeed(
      seedColor: sidebarColors.focus,
      brightness: brightness,
      surface: sidebarColors.surface,
    );
    return ThemeData(
      colorScheme: colors,
      brightness: brightness,
      useMaterial3: true,
      splashFactory: InkRipple.splashFactory,
      scaffoldBackgroundColor: sidebarColors.canvas,
      fontFamily: 'Arial',
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 14),
        bodySmall: TextStyle(fontSize: 12),
        labelLarge: TextStyle(fontSize: 14),
        labelMedium: TextStyle(fontSize: 12),
        labelSmall: TextStyle(fontSize: 11),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: sidebarColors.mutedForeground,
          minimumSize: const Size.square(40),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.inverseSurface,
        contentTextStyle: TextStyle(color: colors.onInverseSurface),
      ),
    );
  }
}

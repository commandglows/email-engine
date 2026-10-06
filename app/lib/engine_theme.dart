import 'package:flutter/material.dart';

/// Operator host theme; same blue accent as the existing newsletter preview.
abstract final class EngineTheme {
  static const accent = Color(0xFF0B57D0);
  static ThemeData create(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    ),
    useMaterial3: true,
  );
}

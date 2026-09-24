import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:source_sidebar_preview/main.dart';

void main() {
  testWidgets('previews the shared sidebar and simulates project ingestion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const SourceSidebarPreviewApp(showCockpit: false));
    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('Tags'), findsOneWidget);
    expect(find.text('Cybersecurity'), findsOneWidget);

    await tester.tap(find.textContaining('Designing resilient').first);
    await tester.pumpAndSettle();
    expect(find.text('Send to project'), findsNothing);
    expect(find.byTooltip('Send to projects'), findsOneWidget);
  });

  testWidgets('offers a compact list before a source is selected', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const SourceSidebarPreviewApp(showCockpit: false));

    expect(find.text('Sources'), findsOneWidget);
    expect(find.byTooltip('Source filters'), findsOneWidget);
    expect(find.byTooltip('Refresh sources'), findsWidgets);
  });

  testWidgets('demonstrates Later keyboard action', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const SourceSidebarPreviewApp(showCockpit: false));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pumpAndSettle();

    expect(find.text('Moved to Later in this demo.'), findsOneWidget);
  });

  testWidgets('exposes contextual keyboard help and account switching', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const SourceSidebarPreviewApp(showCockpit: false));
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.pumpAndSettle();
    expect(find.textContaining('Switched to Research account'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('Keyboard shortcuts'), findsOneWidget);
    expect(find.textContaining('Summarize'), findsOneWidget);
    expect(find.textContaining('Send to projects'), findsOneWidget);
    expect(find.textContaining('Choose account'), findsOneWidget);
  });

  testWidgets('distributes one source to two projects from the keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const SourceSidebarPreviewApp(showCockpit: false));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'ShipGlows'));
    await tester.tap(find.widgetWithText(CheckboxListTile, 'ContentGlows'));
    await tester.pump();
    expect(
      tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .where((tile) => tile.value == true),
      hasLength(2),
    );
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Designing resilient').first);
    await tester.pumpAndSettle();
    expect(find.text('ShipGlows'), findsWidgets);
    expect(find.text('ContentGlows'), findsWidgets);
  });

  testWidgets('summarizes the active source from the keyboard', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const SourceSidebarPreviewApp(showCockpit: false));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Designing resilient').first);
    await tester.pumpAndSettle();
    expect(find.text('synthetic-summary'), findsOneWidget);
  });

  testWidgets('opens the unified Newsletter Studio with synthetic hooks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const SourceSidebarPreviewApp(showCockpit: false));
    await tester.tap(find.byTooltip('Open Newsletter Studio'));
    await tester.pumpAndSettle();

    expect(find.text('Health Signals · Weekly draft'), findsWidgets);
    expect(find.text('Vérifier et programmer'), findsOneWidget);
    expect(find.text('Sources'), findsOneWidget);

    await tester.tap(find.byTooltip('Aperçu (Ctrl/Commande+P)'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Vérifiez le rendu final'), findsOneWidget);
  });
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shipglows_flutter_zoom/shipglows_flutter_zoom.dart';

void main() {
  testWidgets('zooms globally, keeps the viewport filled, and resets', (
    tester,
  ) async {
    final changes = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: FlutterZoomViewport(
          onZoomChanged: changes.add,
          child: const SizedBox.expand(),
        ),
      ),
    );

    Size viewportSize() => tester.getSize(
      find.byKey(const ValueKey('shipglows-flutter-zoom-viewport')),
    );
    double workspaceScale() {
      final viewport = viewportSize();
      final content = tester.getSize(
        find.byKey(const ValueKey('shipglows-flutter-zoom-content')),
      );
      return viewport.width / content.width;
    }

    final initialSize = viewportSize();
    expect(workspaceScale(), 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(
      const PointerScrollEvent(scrollDelta: Offset(0, -100)),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    // The step is painted at once; the content is laid out again only once
    // the wheel has paused.
    expect(changes, [1.1]);
    expect(workspaceScale(), 1);
    await tester.pump(const Duration(milliseconds: 150));

    expect(workspaceScale(), closeTo(1.1, 0.001));
    expect(viewportSize(), initialSize);
    expect(changes, [1.1]);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(workspaceScale(), 1);
    expect(viewportSize(), initialSize);
    expect(changes, [1.1, 1.0]);
  });

  testWidgets('ignores ordinary scrolling', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: FlutterZoomViewport(child: SizedBox.expand())),
    );

    final content = find.byKey(
      const ValueKey('shipglows-flutter-zoom-content'),
    );
    final initialWidth = tester.getSize(content).width;

    await tester.sendEventToBinding(
      const PointerScrollEvent(scrollDelta: Offset(0, -100)),
    );
    await tester.pump();
    expect(tester.getSize(content).width, initialWidth);
  });
}

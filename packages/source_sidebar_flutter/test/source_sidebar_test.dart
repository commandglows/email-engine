import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:source_sidebar_flutter/source_sidebar_flutter.dart';

void main() {
  const expandedTestWidth = 1200.0;
  final items = [
    SourceSidebarItem(
      id: 'one',
      title: 'A useful source',
      authorOrPublisher: 'Publisher',
      summary: 'Summary',
      publishedAt: DateTime.utc(2026, 8, 26),
      sourceType: 'email',
      content: 'Sanitized plain-text content.',
      tags: const ['project-ready'],
    ),
    SourceSidebarItem(
      id: 'two',
      title: 'Another useful source',
      authorOrPublisher: 'Another publisher',
      summary: 'Another summary',
      publishedAt: DateTime.utc(2026, 8, 25),
      sourceType: 'email',
      content: 'Second sanitized plain-text content.',
    ),
  ];

  testWidgets('shows empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: SourceSidebar(items: const [], onSelected: (_) {}),
      ),
    );
    expect(find.text('No sources to review.'), findsOneWidget);
  });

  testWidgets('presents host-defined categories and accessible fallbacks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const categories = [
      SourceCategory(
        id: 'project-ready',
        name: 'Ready for project',
        color: Color(0xFF006C4C),
        icon: Icons.rocket_launch_outlined,
      ),
    ];
    final categorizedItems = [
      items.first,
      SourceSidebarItem(
        id: 'fallback',
        title: 'Unconfigured category source',
        authorOrPublisher: 'Publisher',
        summary: 'Summary',
        publishedAt: DateTime.utc(2026, 8, 24),
        sourceType: 'email',
        content: 'Content',
        tags: const ['unknown-category'],
      ),
    ];

    await tester.pumpWidget(
      _KeyboardHarness(items: categorizedItems, categories: categories),
    );
    await tester.pump();

    expect(find.text('Tags'), findsOneWidget);
    expect(find.text('Ready for project'), findsOneWidget);
    expect(find.text('unknown-category'), findsOneWidget);
    final configuredIcon = tester.widget<Icon>(
      find.byIcon(Icons.rocket_launch_outlined).first,
    );
    expect(configuredIcon.color, const Color(0xFF006C4C));

    await tester.tap(find.text('A useful source').first);
    await tester.pump();
    expect(find.text('Ready for project'), findsWidgets);
  });

  testWidgets('selects and ingests a source', (tester) async {
    SourceSidebarItem? ingested;
    String? selectedId;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: SizedBox(
          width: expandedTestWidth,
          child: SourceSidebar(
            items: items,
            onSelected: (id) => selectedId = id,
            onIngest: (item) async => ingested = item,
          ),
        ),
      ),
    );

    await tester.tap(find.text('A useful source').first);
    expect(selectedId, 'one');
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: SizedBox(
          width: expandedTestWidth,
          child: SourceSidebar(
            items: items,
            selectedId: selectedId,
            onSelected: (id) => selectedId = id,
            onIngest: (item) async => ingested = item,
          ),
        ),
      ),
    );
    expect(find.text('Send to project'), findsNothing);
    expect(ingested, isNull);
  });

  testWidgets('requires confirmation before delete', (tester) async {
    var deleted = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: SizedBox(
          width: expandedTestWidth,
          child: SourceSidebar(
            items: items,
            selectedId: 'one',
            onSelected: (_) {},
            onDelete: (_) async => deleted = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Delete source'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this source?'), findsOneWidget);
    expect(deleted, isFalse);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
  });

  testWidgets('navigates, opens, and returns with Glows defaults', (
    tester,
  ) async {
    await tester.pumpWidget(_KeyboardHarness(items: items));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    expect(find.byTooltip('Back to list'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byTooltip('Back to list'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
    await tester.pump();
    expect(find.byTooltip('Back to list'), findsNothing);
    expect(find.text('A useful source'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.pump();
    expect(find.byTooltip('Back to list'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byTooltip('Back to list'), findsNothing);
  });

  testWidgets('J and K reclaim primary focus for the active source row', (
    tester,
  ) async {
    await tester.pumpWidget(_KeyboardHarness(items: items));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final toolbarFocus = FocusManager.instance.primaryFocus;
    final toolbarFocusContext = toolbarFocus?.context;
    expect(toolbarFocus, isNotNull);
    expect(toolbarFocusContext?.widget, isNot(isA<EditableText>()));
    expect(
      toolbarFocusContext?.findAncestorWidgetOfExactType<EditableText>(),
      isNull,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    final firstRow = tester.widget<InkWell>(
      find
          .ancestor(
            of: find.text('A useful source').first,
            matching: find.byType(InkWell),
          )
          .first,
    );
    expect(firstRow.focusNode?.hasPrimaryFocus, isTrue);
    expect(FocusManager.instance.primaryFocus, isNot(same(toolbarFocus)));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    final secondRow = tester.widget<InkWell>(
      find
          .ancestor(
            of: find.text('Another useful source').first,
            matching: find.byType(InkWell),
          )
          .first,
    );
    expect(secondRow.focusNode?.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    expect(firstRow.focusNode?.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byTooltip('Back to list'), findsOneWidget);
  });

  testWidgets(
    'Ctrl+wheel and Ctrl+pinch zooms globally and Ctrl+0 resets zoom',
    (tester) async {
      await tester.pumpWidget(_KeyboardHarness(items: items));
      await tester.pump();

      double workspaceScale() {
        final viewport = tester.getSize(
          find.byKey(const ValueKey('shipglows-flutter-zoom-viewport')),
        );
        final content = tester.getSize(
          find.byKey(const ValueKey('shipglows-flutter-zoom-content')),
        );
        return viewport.width / content.width;
      }

      expect(workspaceScale(), 1);
      final initialViewportSize = tester.getSize(
        find.byKey(const ValueKey('shipglows-flutter-zoom-viewport')),
      );
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(600, 400),
          scrollDelta: Offset(0, 100),
        ),
      );
      await tester.pump();
      expect(workspaceScale(), 1);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(600, 400),
          scrollDelta: Offset(0, -100),
        ),
      );
      await tester.sendEventToBinding(
        const PointerScaleEvent(position: Offset(600, 400), scale: 1.1),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(workspaceScale(), greaterThan(1));
      expect(
        tester.getSize(
          find.byKey(const ValueKey('shipglows-flutter-zoom-viewport')),
        ),
        initialViewportSize,
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(workspaceScale(), 1);
    },
  );

  testWidgets('W keeps destructive confirmation in the keyboard path', (
    tester,
  ) async {
    var deleted = false;
    await tester.pumpWidget(
      _KeyboardHarness(items: items, onDelete: (_) async => deleted = true),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.pumpAndSettle();

    expect(find.text('Delete this source?'), findsOneWidget);
    expect(deleted, isFalse);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
  });

  testWidgets('hosts can replace or disable individual bindings', (
    tester,
  ) async {
    await tester.pumpWidget(
      _KeyboardHarness(
        items: items,
        onDelete: (_) async {},
        shortcuts: const SourceSidebarShortcuts(
          delete: [SingleActivator(LogicalKeyboardKey.keyD)],
          archive: [],
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.pump();
    expect(find.text('Delete this source?'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pumpAndSettle();
    expect(find.text('Delete this source?'), findsOneWidget);
  });

  testWidgets('alphabetic shortcuts never intercept editable text', (
    tester,
  ) async {
    var actions = 0;
    await tester.pumpWidget(
      _KeyboardHarness(
        items: items,
        onDelete: (_) async => actions++,
        onArchive: (_) async => actions++,
        onMove: (_, _) async => actions++,
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
    await tester.enterText(find.byType(TextField), 'useful');
    expect(find.text('useful'), findsOneWidget);

    for (final key in [
      LogicalKeyboardKey.keyW,
      LogicalKeyboardKey.keyE,
      LogicalKeyboardKey.keyL,
      LogicalKeyboardKey.keyV,
      LogicalKeyboardKey.keyJ,
      LogicalKeyboardKey.keyK,
      LogicalKeyboardKey.keyO,
      LogicalKeyboardKey.keyU,
    ]) {
      await tester.sendKeyEvent(key);
    }
    await tester.pump();

    expect(actions, 0);
    expect(find.text('Delete this source?'), findsNothing);
    expect(find.text('Move source'), findsNothing);
    expect(editable.focusNode.hasFocus, isTrue);
  });

  testWidgets('Ctrl+F focuses the global source search', (tester) async {
    await tester.pumpWidget(_KeyboardHarness(items: items));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
  });

  testWidgets('L moves to Later and V opens the destination chooser', (
    tester,
  ) async {
    SourceMoveDestination? movedTo;
    await tester.pumpWidget(
      _KeyboardHarness(
        items: items,
        onMove: (_, destination) async => movedTo = destination,
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pump();
    expect(movedTo?.id, 'later');

    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.pumpAndSettle();
    expect(find.text('Move source'), findsOneWidget);
    await tester.tap(find.text('Reference'));
    await tester.pumpAndSettle();
    expect(movedTo?.id, 'reference');
  });

  testWidgets('E invokes the configured archive callback', (tester) async {
    String? archivedId;
    await tester.pumpWidget(
      _KeyboardHarness(
        items: items,
        onArchive: (item) async => archivedId = item.id,
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();
    expect(archivedId, 'one');
  });

  testWidgets('? exposes keyboard help and restores focus after closing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _KeyboardHarness(
        items: items,
        onArchive: (_) async {},
        onDelete: (_) async {},
        onMove: (_, _) async {},
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('Keyboard shortcuts'), findsOneWidget);
    expect(find.textContaining('Delete with confirmation'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Keyboard shortcuts'), findsNothing);
    expect(FocusManager.instance.primaryFocus, isNotNull);
  });

  testWidgets('help omits shortcuts whose host actions are unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(_KeyboardHarness(items: items));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    final help = find.byType(AlertDialog);
    expect(
      find.descendant(of: help, matching: find.textContaining('Archive')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: help,
        matching: find.textContaining('Delete with confirmation'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: help, matching: find.textContaining('Move…')),
      findsNothing,
    );
    expect(
      find.descendant(of: help, matching: find.textContaining('Move to Later')),
      findsNothing,
    );
    expect(
      find.descendant(of: help, matching: find.textContaining('Open source')),
      findsOneWidget,
    );
  });

  testWidgets('Later is recoverable and other locations stay in Inbox', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final locatedItems = [
      items.first,
      _locatedItem('later-item', 'Saved for later', 'later'),
      _locatedItem('reference-item', 'Saved as reference', 'reference'),
    ];

    await tester.pumpWidget(_KeyboardHarness(items: locatedItems));
    await tester.pump();

    final laterNavigation = find.widgetWithText(InkWell, 'Later');
    expect(laterNavigation, findsOneWidget);
    expect(
      find.descendant(of: laterNavigation, matching: find.text('1')),
      findsOneWidget,
    );
    expect(find.text('Saved for later'), findsNothing);
    expect(find.text('Saved as reference'), findsOneWidget);

    await tester.tap(find.text('Later'));
    await tester.pump();
    expect(find.text('Saved for later'), findsOneWidget);
    expect(find.text('Saved as reference'), findsNothing);
  });

  testWidgets('mobile navigation exposes Later when configured', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final locatedItems = [
      items.first,
      _locatedItem('later-item', 'Saved for later', 'later'),
    ];

    await tester.pumpWidget(_KeyboardHarness(items: locatedItems));
    await tester.pump();
    await tester.tap(find.byTooltip('Source filters'));
    await tester.pumpAndSettle();

    expect(find.text('Later'), findsOneWidget);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('Saved for later'), findsOneWidget);
  });

  testWidgets('without Later configuration its location stays in Inbox', (
    tester,
  ) async {
    final locatedItems = [
      items.first,
      _locatedItem('later-item', 'Legacy later location', 'later'),
    ];
    await tester.pumpWidget(
      _KeyboardHarness(items: locatedItems, laterDestinationId: null),
    );
    await tester.pump();

    expect(find.text('Legacy later location'), findsOneWidget);
    await tester.tap(find.byTooltip('Source filters'));
    await tester.pumpAndSettle();
    expect(find.text('Later'), findsNothing);
  });

  testWidgets('Tab and Shift+Tab use native focus traversal', (tester) async {
    await tester.pumpWidget(_KeyboardHarness(items: items));
    await tester.pump();
    final initialFocus = FocusManager.instance.primaryFocus;

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final forwardFocus = FocusManager.instance.primaryFocus;
    expect(forwardFocus, isNotNull);
    expect(forwardFocus, isNot(same(initialFocus)));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, isNotNull);
  });
}

class _KeyboardHarness extends StatefulWidget {
  const _KeyboardHarness({
    required this.items,
    this.shortcuts = const SourceSidebarShortcuts(),
    this.onDelete,
    this.onArchive,
    this.onMove,
    this.laterDestinationId = 'later',
    this.categories = const <SourceCategory>[],
  });

  final List<SourceSidebarItem> items;
  final SourceSidebarShortcuts shortcuts;
  final SourceItemCallback? onDelete;
  final SourceItemCallback? onArchive;
  final SourceMoveCallback? onMove;
  final String? laterDestinationId;
  final List<SourceCategory> categories;

  @override
  State<_KeyboardHarness> createState() => _KeyboardHarnessState();
}

class _KeyboardHarnessState extends State<_KeyboardHarness> {
  String? selectedId;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: SizedBox(
        width: 1200,
        child: SourceSidebar(
          items: widget.items,
          selectedId: selectedId,
          shortcuts: widget.shortcuts,
          onSelected: (id) => setState(() => selectedId = id),
          onDelete: widget.onDelete,
          onArchive: widget.onArchive,
          onMove: widget.onMove,
          moveDestinations: const [
            SourceMoveDestination(id: 'later', label: 'Later'),
            SourceMoveDestination(id: 'reference', label: 'Reference'),
          ],
          laterDestinationId: widget.laterDestinationId,
          categories: widget.categories,
        ),
      ),
    );
  }
}

SourceSidebarItem _locatedItem(String id, String title, String location) {
  return SourceSidebarItem(
    id: id,
    title: title,
    authorOrPublisher: 'Publisher',
    summary: 'Summary',
    publishedAt: DateTime.utc(2026, 8, 24),
    sourceType: 'email',
    content: 'Sanitized plain-text content.',
    location: location,
  );
}

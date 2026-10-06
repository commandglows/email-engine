import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:source_sidebar_flutter/source_sidebar_flutter.dart';

SourceSidebarItem email(String id, {bool seen = false}) => SourceSidebarItem(
  id: id,
  title: 'Email $id',
  authorOrPublisher: 'Expéditeur',
  summary: 'Résumé',
  publishedAt: DateTime(2026, 9, 8),
  sourceType: 'email',
  content: 'Contenu $id',
  seen: seen,
);
const sections = {
  'sources': 'Sources',
  'support': 'Service client',
  'diffusion': 'Diffusion',
};

void main() {
  testWidgets(
    'one grouped inbox retains source rows and eager section anchors',
    (tester) async {
      final sources = List.generate(40, (index) => email('source$index'));
      final supportKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: SourceSidebar(
            items: [...sources, email('support'), email('campaign')],
            onSelected: (_) {},
            sectionLabels: sections,
            itemSectionIds: {'support': 'support', 'campaign': 'diffusion'},
            sectionKeys: {'support': supportKey},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.byType(Viewport), findsOneWidget);
      expect(find.text('Email source0'), findsOneWidget);
      expect(supportKey.currentContext, isNotNull);
      await Scrollable.ensureVisible(supportKey.currentContext!);
      await tester.pumpAndSettle();
      expect(find.text('Email support'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'empty and loading sources retain all sections and host messages',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SourceSidebar(
            items: const [],
            onSelected: (_) {},
            isLoading: true,
            sectionLabels: sections,
            sectionEmptyMessages: const {
              'sources': 'Readwise à connecter',
              'support': 'Gmail à connecter',
              'diffusion': 'Aucune campagne',
            },
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.text('Readwise à connecter'), findsOneWidget);
      expect(find.text('Gmail à connecter'), findsOneWidget);
      expect(find.text('Aucune campagne'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('all providers open the same reader with contextual footer', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, update) => SourceSidebar(
            title: 'ShipGlows Email Engine',
            items: [email('support')],
            selectedId: selected,
            onSelected: (id) => update(() => selected = id),
            sectionLabels: sections,
            itemSectionIds: const {'support': 'support'},
            readerFooter: const Text('Répondre via Gmail'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Email support'));
    await tester.tap(find.text('Email support'));
    await tester.pumpAndSettle();
    expect(find.text('Contenu support'), findsOneWidget);
    expect(find.text('Répondre via Gmail'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'all grouped sections render with their rows on desktop and mobile',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;

      for (final size in [const Size(1440, 1000), const Size(390, 844)]) {
        tester.view.physicalSize = size;
        String? selectedId;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, update) => SourceSidebar(
                title: 'Boîte unifiée',
                items: [email('source'), email('support'), email('campaign')],
                selectedId: selectedId,
                onSelected: (id) => update(() => selectedId = id),
                sectionLabels: sections,
                itemSectionIds: const {
                  'source': 'sources',
                  'support': 'support',
                  'campaign': 'diffusion',
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final sourcesHeader = find.text('Sources');
        final supportHeader = find.text('Service client');
        final diffusionHeader = find.text('Diffusion');
        final sourceRow = find.text('Email source');
        final supportRow = find.text('Email support');
        final campaignRow = find.text('Email campaign');
        expect(sourcesHeader, findsOneWidget);
        expect(supportHeader, findsOneWidget);
        expect(diffusionHeader, findsOneWidget);
        expect(sourceRow, findsOneWidget);
        expect(supportRow, findsOneWidget);
        expect(campaignRow, findsOneWidget);

        final sourcesY = tester.getTopLeft(sourcesHeader).dy;
        final supportY = tester.getTopLeft(supportHeader).dy;
        final diffusionY = tester.getTopLeft(diffusionHeader).dy;
        expect(sourcesY, lessThan(tester.getTopLeft(sourceRow).dy));
        expect(tester.getTopLeft(sourceRow).dy, lessThan(supportY));
        expect(supportY, lessThan(tester.getTopLeft(supportRow).dy));
        expect(tester.getTopLeft(supportRow).dy, lessThan(diffusionY));
        expect(diffusionY, lessThan(tester.getTopLeft(campaignRow).dy));

        await tester.ensureVisible(supportRow);
        await tester.tap(supportRow);
        await tester.pumpAndSettle();
        expect(find.text('Contenu support'), findsOneWidget);
        expect(find.byTooltip('Back to list'), findsOneWidget);
        await tester.tap(find.byTooltip('Back to list'));
        await tester.pumpAndSettle();
        expect(find.text('Sources'), findsOneWidget);
        expect(find.text('Service client'), findsOneWidget);
        expect(find.text('Diffusion'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('navigation header precedes existing desktop filters', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: SourceSidebar(
          items: const [],
          onSelected: (_) {},
          navigationHeader: const Text('Navigation moteur'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Navigation moteur')).dy,
      lessThan(tester.getTopLeft(find.text('Inbox').first).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a colored group header collapses and restores its own rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SourceSidebar(
          items: [email('source', seen: true), email('support')],
          onSelected: (_) {},
          sectionLabels: sections,
          itemSectionIds: const {'support': 'support'},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Email source'), findsOneWidget);
    expect(find.text('0 / 1'), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget);
    await tester.tap(find.text('Sources').last);
    await tester.pumpAndSettle();
    expect(find.text('Email source'), findsNothing);
    expect(find.byIcon(Icons.expand_more), findsWidgets);
    await tester.tap(find.text('Sources').last);
    await tester.pumpAndSettle();
    expect(find.text('Email source'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a host can name unified refresh accurately', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SourceSidebar(
          items: const [],
          onSelected: (_) {},
          sectionLabels: sections,
          refreshTooltip: 'Actualiser la boîte',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Actualiser la boîte'), findsOneWidget);
  });
}

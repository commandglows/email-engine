import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';

class _Repository extends NewsletterCampaignRepository {
  final calls = <String?>[];
  bool fail = false;
  @override
  Future<NewsletterCampaignPage> list({
    String? cursor,
    NewsletterCampaignStatus? status,
    int limit = 25,
  }) async {
    calls.add(cursor);
    if (fail) throw StateError('SECRET must never be displayed');
    return NewsletterCampaignPage(
      items: [
        NewsletterCampaign(
          id: cursor ?? 'first',
          title: cursor == null ? 'Première campagne' : 'Deuxième campagne',
          subject: 'Bonjour',
          revision: 1,
          status: NewsletterCampaignStatus.draft,
          updatedAt: DateTime(2026, 9, 8),
        ),
      ],
      nextCursor: cursor == null ? 'next' : null,
    );
  }

  @override
  Future<NewsletterCampaign> create({required String title}) =>
      throw UnimplementedError();
}

void main() {
  testWidgets('cancelled test request returns idle without error or receipt', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NewsletterStudio(
            draft: const NewsletterDraft(
              id: 'draft',
              revision: 1,
              title: 'Titre',
              subject: 'Objet',
              preheader: '',
              blocks: [],
              sources: [],
            ),
            capabilities: const NewsletterStudioCapabilities(canTest: true),
            onDraftChanged: (_) {},
            onSendTest: (_) async {
              calls++;
              throw const NewsletterActionCancelled();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Opération non confirmée'), findsNothing);
    expect(find.text('Test effectué'), findsNothing);
    await tester.tap(find.text('Test'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('campaign row is a semantic button activated by Enter', (
    tester,
  ) async {
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CampaignWorkspace(
            repository: _Repository(),
            onOpenCampaign: (campaign) async {
              opened = campaign.id;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final row = find.text('Première campagne');
    Focus.of(tester.element(row)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened, 'first');
    final semantics = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where(
          (widget) =>
              widget.properties.label?.startsWith('Première campagne,') == true,
        )
        .single;
    expect(semantics.properties.button, isTrue);
  });

  testWidgets('dashboard loads bounded pages and safely recovers', (
    tester,
  ) async {
    final repository = _Repository()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CampaignWorkspace(
            repository: repository,
            onOpenCampaign: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('SECRET'), findsNothing);
    expect(find.text('Réessayer'), findsOneWidget);
    repository.fail = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('Première campagne'), findsOneWidget);
    await tester.ensureVisible(find.text('Charger la suite'));
    await tester.tap(find.text('Charger la suite'));
    await tester.pumpAndSettle();
    expect(repository.calls, [null, null, 'next']);
    expect(find.text('Deuxième campagne'), findsOneWidget);
  });

  testWidgets('autosave serializes edits and retains the returned revision', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <NewsletterDraft>[];
    final responses = <Completer<NewsletterDraft>>[];
    NewsletterDraft? latest;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NewsletterStudio(
            draft: const NewsletterDraft(
              id: 'draft',
              revision: 1,
              title: 'Titre',
              subject: 'Objet',
              preheader: '',
              blocks: [],
              sources: [],
            ),
            onDraftChanged: (value) => latest = value,
            onSaveDraft: (value) {
              requests.add(value);
              final completion = Completer<NewsletterDraft>();
              responses.add(completion);
              return completion.future;
            },
          ),
        ),
      ),
    );
    final title = find.widgetWithText(TextField, 'Nom de la campagne');
    await tester.enterText(title, 'Premier');
    await tester.pump(const Duration(milliseconds: 700));
    expect(requests.length, 1);
    await tester.enterText(title, 'Dernier');
    await tester.pump(const Duration(milliseconds: 700));
    expect(requests.length, 1);
    responses.first.complete(requests.first.copyWith(revision: 2));
    await tester.pump();
    expect(requests.length, 2);
    expect(requests.last.title, 'Dernier');
    expect(requests.last.revision, 2);
    responses.last.complete(requests.last.copyWith(revision: 3));
    await tester.pump();
    expect(latest?.title, 'Dernier');
    expect(latest?.saveState, NewsletterSaveState.saved);
  });

  testWidgets(
    'conflicting save retains edits and prevents automatic overwrites',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var saves = 0;
      NewsletterDraft? latest;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NewsletterStudio(
              draft: const NewsletterDraft(
                id: 'draft',
                revision: 1,
                title: 'Titre',
                subject: 'Objet',
                preheader: '',
                blocks: [],
                sources: [],
              ),
              onDraftChanged: (value) => latest = value,
              onSaveDraft: (value) async {
                saves++;
                throw const NewsletterSaveConflict();
              },
            ),
          ),
        ),
      );
      final title = find.widgetWithText(TextField, 'Nom de la campagne');
      await tester.enterText(title, 'À conserver');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      expect(latest?.saveState, NewsletterSaveState.conflict);
      await tester.enterText(title, 'Toujours conservé');
      await tester.pump(const Duration(milliseconds: 700));
      expect(saves, 1);
      expect(latest?.title, 'Toujours conservé');
      expect(latest?.saveState, NewsletterSaveState.conflict);
    },
  );

  testWidgets(
    'dashboard supports narrow screens with large text and disabled creation',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: Scaffold(
              body: CampaignWorkspace(
                repository: _Repository(),
                canCreate: false,
                disabledReason: 'Configuration requise',
                onOpenCampaign: (_) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Nouvelle campagne'),
            )
            .onPressed,
        isNull,
      );
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';

class _DispatchFake implements DispatchRepository {
  int confirms = 0, recovers = 0;
  bool loseConfirm = false, rejectRecovery = false;
  bool missingRecovery = false;
  final records = <ProjectDispatch>[];
  @override
  Future<DispatchContext> context(String mailboxId) async =>
      const DispatchContext(
        destinations: [
          DispatchDestination(
            id: 'a',
            label: 'Projet synthétique A',
            projectId: 'a',
            available: true,
          ),
          DispatchDestination(
            id: 'b',
            label: 'Projet synthétique B',
            projectId: 'b',
            available: true,
          ),
        ],
      );
  @override
  Future<List<ProjectDispatch>> history(
    String mailboxId,
    String threadId,
  ) async => List.of(records);
  @override
  Future<ProjectDispatch> confirm(
    String mailboxId,
    String threadId,
    DispatchProposal proposal,
  ) async {
    confirms++;
    expect(proposal.expectedMessageId, 'synthetic-message');
    final d = ProjectDispatch(
      id: proposal.dispatchId,
      summary: proposal.summary,
      receipts: proposal.destinationIds
          .map(
            (id) => DispatchReceipt(
              destinationId: id,
              projectId: id,
              state: id == 'a'
                  ? DispatchReceiptState.accepted
                  : DispatchReceiptState.unknown,
              intakeId: id == 'a' ? 'synthetic-intake-a' : null,
            ),
          )
          .toList(),
    );
    records.add(d);
    if (loseConfirm) throw const DispatchException(unknown: true);
    return d;
  }

  @override
  Future<ProjectDispatch> recover(
    String mailboxId,
    String threadId,
    String dispatchId,
  ) async {
    recovers++;
    expect(dispatchId, records.single.id);
    if (rejectRecovery) throw const DispatchException(code: 'auth_required');
    if (missingRecovery) {
      records.clear();
      throw const DispatchException(code: 'not_found');
    }
    final d = ProjectDispatch(
      id: dispatchId,
      summary: records.single.summary,
      receipts: records.single.receipts
          .map(
            (r) => DispatchReceipt(
              destinationId: r.destinationId,
              projectId: r.projectId,
              state: DispatchReceiptState.accepted,
              intakeId: r.intakeId ?? 'synthetic-intake-b',
            ),
          )
          .toList(),
    );
    records[0] = d;
    return d;
  }
}

void main() {
  testWidgets(
    'AI suggestions require consent and remain inert until human use',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _DispatchFake();
      var analyses = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DispatchPanel(
                repository: repo,
                mailboxId: 'own',
                threadId: 'synthetic-thread',
                messageId: 'synthetic-message',
                analyze: (_) async {
                  analyses++;
                  return const DispatchAnalysis(
                    sourceRevision: 'synthetic-message',
                    summary: 'Synthetic AI summary',
                    provider: 'synthetic',
                    model: 'synthetic',
                    risks: [],
                    candidates: [
                      DispatchAnalysisCandidate(
                        destinationId: 'a',
                        contributionType: 'potential_task',
                        justification: 'Synthetic reason',
                        confidence: 0.8,
                        risks: [],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pré-trier cet email avec l’IA'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(analyses, 0);
      await tester.tap(find.text('Pré-trier cet email avec l’IA'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Analyser cet email'));
      await tester.pumpAndSettle();
      expect(analyses, 1);
      expect(repo.confirms, 0);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
      await tester.tap(find.text('Utiliser'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Synthetic AI summary',
      );
      expect(repo.confirms, 0);
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
            .value,
        isTrue,
      );
    },
  );

  testWidgets('stale AI output never becomes a draft or dispatch', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = _DispatchFake();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DispatchPanel(
              repository: repo,
              mailboxId: 'own',
              threadId: 'synthetic-thread',
              messageId: 'synthetic-message',
              analyze: (_) async => const DispatchAnalysis(
                sourceRevision: 'old-message',
                summary: 'Stale suggestion',
                provider: 'synthetic',
                model: 'synthetic',
                risks: [],
                candidates: [],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pré-trier cet email avec l’IA'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analyser cet email'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Stale suggestion'), findsNothing);
    expect(repo.confirms, 0);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      isEmpty,
    );
  });
  test('dispatch identities are independent version 4 UUIDs', () {
    final a = DispatchProposal.newId(), b = DispatchProposal.newId();
    expect(
      a,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(a, isNot(b));
  });
  testWidgets(
    'preview and cancel have no dispatch; partial receipts recover same operation',
    (tester) async {
      final repo = _DispatchFake();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DispatchPanel(
                repository: repo,
                mailboxId: 'synthetic-box',
                threadId: 'synthetic-thread',
                messageId: 'synthetic-message',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.confirms, 0);
      await tester.enterText(
        find.byType(TextField).first,
        'Résumé synthétique',
      );
      for (final label in ['Projet synthétique A', 'Projet synthétique B']) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
      }
      await tester.ensureVisible(find.text('Revoir et confirmer le dispatch'));
      await tester.tap(find.text('Revoir et confirmer le dispatch'));
      await tester.pumpAndSettle();
      expect(repo.confirms, 0);
      expect(
        find.textContaining('Résumé : Résumé synthétique'),
        findsOneWidget,
      );
      await tester.tap(find.text('Corriger'));
      await tester.pumpAndSettle();
      expect(repo.confirms, 0);
      await tester.tap(find.text('Revoir et confirmer le dispatch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valider les destinations'));
      await tester.pumpAndSettle();
      expect(repo.confirms, 1);
      expect(repo.records.single.receipts.length, 2);
      expect(find.textContaining('Résultat inconnu'), findsOneWidget);
      final summary = tester.widget<TextField>(find.byType(TextField).first);
      expect(summary.enabled, false);
      final recover = find.text(
        'Réconcilier et reprendre les destinations restantes',
      );
      await tester.ensureVisible(recover);
      await tester.tap(recover);
      await tester.pumpAndSettle();
      expect(repo.recovers, 1);
      expect(repo.confirms, 1);
      expect(repo.records.single.receipts.first.intakeId, 'synthetic-intake-a');
    },
  );
  testWidgets(
    'failed authentication during recovery keeps uncertain identity locked',
    (tester) async {
      final repo = _DispatchFake()
        ..loseConfirm = true
        ..rejectRecovery = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DispatchPanel(
                repository: repo,
                mailboxId: 'synthetic-box',
                threadId: 'synthetic-thread',
                messageId: 'synthetic-message',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Synthétique');
      await tester.ensureVisible(find.text('Projet synthétique A'));
      await tester.tap(find.text('Projet synthétique A'));
      await tester.ensureVisible(find.text('Revoir et confirmer le dispatch'));
      await tester.tap(find.text('Revoir et confirmer le dispatch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valider les destinations'));
      await tester.pumpAndSettle();
      final recover = find.text('Récupérer le résultat incertain');
      await tester.ensureVisible(recover);
      await tester.tap(recover);
      await tester.pumpAndSettle();
      expect(repo.recovers, 1);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).enabled,
        false,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(
                FilledButton,
                'Revoir et confirmer le dispatch',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(recover, findsOneWidget);
      await tester.tap(recover);
      await tester.pumpAndSettle();
      expect(repo.recovers, 2);
      expect(repo.confirms, 1);
      repo.rejectRecovery = false;
      repo.missingRecovery = true;
      await tester.tap(recover);
      await tester.pumpAndSettle();
      expect(repo.recovers, 3);
      expect(recover, findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).enabled,
        true,
      );
      expect(repo.confirms, 1);
    },
  );
}

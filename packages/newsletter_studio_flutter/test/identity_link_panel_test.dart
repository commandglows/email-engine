import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';

final _now = DateTime.utc(2026, 10, 13, 12);

final class _Failure implements CodedFailure, Exception {
  const _Failure(this.code, this.raw);
  @override
  final String code;
  final String raw;
  @override
  String toString() => raw;
}

class _FakeGateway implements IdentityLinkGateway {
  _FakeGateway({required this.currentStatus, this.code, this.confirmResult});

  IdentityLinkStatus currentStatus;
  IdentityLinkCode? code;
  IdentityLinkStatus? confirmResult;
  Object? statusError;
  Completer<void>? confirmGate;
  int statusCalls = 0;
  int createCalls = 0;
  final confirmCodes = <String>[];

  @override
  Future<IdentityLinkStatus> status() async {
    statusCalls++;
    final error = statusError;
    if (error != null) {
      statusError = null;
      throw error;
    }
    return currentStatus;
  }

  @override
  Future<IdentityLinkCode> createLinkCode() async {
    createCalls++;
    return code!;
  }

  @override
  Future<IdentityLinkStatus> confirmLinkCode(String code) async {
    confirmCodes.add(code);
    await confirmGate?.future;
    return confirmResult!;
  }
}

const _unlinked = IdentityLinkStatus(linked: false);
const _linked = IdentityLinkStatus(linked: true, fingerprint: 'ABCD-EFGH');

Widget _host(IdentityLinkGateway gateway) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: IdentityLinkPanel(
        gateway: gateway,
        providerLabel: 'ShipGlows',
        otherAppLabel: 'ContentGlows',
        clock: () => _now,
      ),
    ),
  ),
);

Finder _selectable(String text) => find.byWidgetPredicate(
  (widget) => widget is SelectableText && widget.data == text,
);

void main() {
  testWidgets('unlinked state explains the link and offers both actions', (
    tester,
  ) async {
    final gateway = _FakeGateway(currentStatus: _unlinked);
    await tester.pumpWidget(_host(gateway));
    await tester.pump();

    expect(find.textContaining('ne suffit jamais'), findsOneWidget);
    expect(find.text('Générer un code'), findsOneWidget);
    expect(find.text('Saisir un code'), findsOneWidget);
    expect(gateway.statusCalls, 1);
  });

  testWidgets(
    'generated code is selectable, copyable and carries its warning',
    (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final gateway = _FakeGateway(
        currentStatus: _unlinked,
        code: IdentityLinkCode(
          code: 'SYN-CODE-123',
          expiresAt: _now.add(const Duration(minutes: 5)),
        ),
      );
      await tester.pumpWidget(_host(gateway));
      await tester.pump();

      await tester.tap(find.text('Générer un code'));
      await tester.pump();

      expect(gateway.createCalls, 1);
      expect(_selectable('SYN-CODE-123'), findsOneWidget);
      expect(
        find.text(
          'Ne partagez ce code avec personne. Il expire dans 5 minutes.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('encore 5 min'), findsOneWidget);

      await tester.tap(find.text('Copier le code'));
      await tester.pump();
      expect(copied, ['SYN-CODE-123']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('cancelling the confirmation dialog never calls the gateway', (
    tester,
  ) async {
    final gateway = _FakeGateway(currentStatus: _unlinked);
    await tester.pumpWidget(_host(gateway));
    await tester.pump();

    await tester.tap(find.text('Saisir un code'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), ' SYN-CODE-123 ');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Associer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Confirmer l’association'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(gateway.confirmCodes, isEmpty);
    expect(find.text('Confirmer l’association'), findsNothing);
  });

  testWidgets('confirming sends one trimmed code even on a double tap', (
    tester,
  ) async {
    final gate = Completer<void>();
    final gateway = _FakeGateway(
      currentStatus: _unlinked,
      confirmResult: _linked,
    )..confirmGate = gate;
    await tester.pumpWidget(_host(gateway));
    await tester.pump();

    await tester.tap(find.text('Saisir un code'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), ' SYN-CODE-123 ');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Associer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    gateway.currentStatus = _linked;
    final dialogConfirm = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Associer'),
    );
    expect(dialogConfirm, findsOneWidget);
    await tester.tap(dialogConfirm);
    await tester.tap(dialogConfirm, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(gateway.confirmCodes, ['SYN-CODE-123']);
    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(gateway.confirmCodes, hasLength(1));
    expect(gateway.statusCalls, 2);
    expect(find.text('Comptes associés'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('linked state shows the shared fingerprint', (tester) async {
    final gateway = _FakeGateway(currentStatus: _linked);
    await tester.pumpWidget(_host(gateway));
    await tester.pump();

    expect(find.text('Comptes associés'), findsOneWidget);
    expect(
      _selectable(
        'Empreinte : ABCD-EFGH — elle doit être identique dans ContentGlows.',
      ),
      findsOneWidget,
    );
    expect(find.text('Générer un code'), findsNothing);
  });

  testWidgets('error state shows a bounded message and retry without raw text', (
    tester,
  ) async {
    final gateway = _FakeGateway(currentStatus: _unlinked)
      ..statusError = const _Failure(
        'identity_link_unavailable',
        'RAW-SECRET-DETAIL',
      );
    await tester.pumpWidget(_host(gateway));
    await tester.pump();

    expect(find.textContaining('RAW-SECRET-DETAIL'), findsNothing);
    expect(
      find.text(
        'L’association est momentanément indisponible. Réessayez dans un instant.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Réessayer'));
    await tester.pump();

    expect(gateway.statusCalls, 2);
    expect(find.textContaining('ne suffit jamais'), findsOneWidget);
    expect(find.text('Réessayer'), findsNothing);
  });
}

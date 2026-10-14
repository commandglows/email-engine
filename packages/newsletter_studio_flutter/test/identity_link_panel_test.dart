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
  final statusErrors = <Object>[];
  Completer<void>? statusGate;
  Completer<void>? confirmGate;
  int statusCalls = 0;
  int inFlight = 0;
  int maxInFlight = 0;
  int createCalls = 0;
  final confirmCodes = <String>[];

  @override
  Future<IdentityLinkStatus> status() async {
    statusCalls++;
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      await statusGate?.future;
      if (statusErrors.isNotEmpty) throw statusErrors.removeAt(0);
      return currentStatus;
    } finally {
      inFlight--;
    }
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

const _unavailableMessage =
    'L’association est momentanément indisponible. Réessayez dans un instant.';

Widget _host(IdentityLinkGateway gateway, {DateTime Function()? clock}) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: IdentityLinkPanel(
            gateway: gateway,
            providerLabel: 'ShipGlows',
            otherAppLabel: 'ContentGlows',
            clock: clock ?? () => _now,
          ),
        ),
      ),
    );

IdentityLinkCode _freshCode(DateTime expiresAt) =>
    IdentityLinkCode(code: 'SYN-CODE-123', expiresAt: expiresAt);

/// Mounts the panel, then generates a code so polling is running.
Future<void> _generateCode(
  WidgetTester tester,
  _FakeGateway gateway, {
  DateTime Function()? clock,
}) async {
  await tester.pumpWidget(_host(gateway, clock: clock));
  await tester.pump();
  await tester.tap(find.text('Générer un code'));
  await tester.pump();
}

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
    expect(find.text('Générer un code pour un autre compte'), findsOneWidget);
  });

  testWidgets('a linked account can still issue a code for another account', (
    tester,
  ) async {
    final gateway = _FakeGateway(
      currentStatus: _linked,
      code: _freshCode(_now.add(const Duration(minutes: 5))),
    );
    await tester.pumpWidget(_host(gateway));
    await tester.pump();

    await tester.tap(find.text('Générer un code pour un autre compte'));
    await tester.pump();
    expect(gateway.createCalls, 1);
    expect(_selectable('SYN-CODE-123'), findsOneWidget);

    // The code is for another account: polling must neither start nor clear it.
    final callsBefore = gateway.statusCalls;
    await tester.pump(const Duration(seconds: 10));
    expect(gateway.statusCalls, callsBefore);
    expect(_selectable('SYN-CODE-123'), findsOneWidget);
    expect(find.text('Comptes associés'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'error state shows a bounded message and retry without raw text',
    (tester) async {
      final gateway = _FakeGateway(currentStatus: _unlinked)
        ..statusErrors.add(
          const _Failure('identity_link_unavailable', 'RAW-SECRET-DETAIL'),
        );
      await tester.pumpWidget(_host(gateway));
      await tester.pump();

      expect(find.textContaining('RAW-SECRET-DETAIL'), findsNothing);
      expect(find.text(_unavailableMessage), findsOneWidget);

      await tester.tap(find.text('Réessayer'));
      await tester.pump();

      expect(gateway.statusCalls, 2);
      expect(find.textContaining('ne suffit jamais'), findsOneWidget);
      expect(find.text('Réessayer'), findsNothing);
    },
  );

  testWidgets('generated code switches to linked on poll without user action', (
    tester,
  ) async {
    final gateway = _FakeGateway(
      currentStatus: _unlinked,
      code: _freshCode(_now.add(const Duration(minutes: 5))),
    );
    await _generateCode(tester, gateway);
    expect(_selectable('SYN-CODE-123'), findsOneWidget);

    gateway.currentStatus = _linked;
    await tester.pump(const Duration(seconds: 3));

    expect(_selectable('SYN-CODE-123'), findsNothing);
    expect(find.text('Comptes associés'), findsOneWidget);
    expect(
      _selectable(
        'Empreinte : ABCD-EFGH — elle doit être identique dans ContentGlows.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('polling stops once the account is linked', (tester) async {
    final gateway = _FakeGateway(
      currentStatus: _unlinked,
      code: _freshCode(_now.add(const Duration(minutes: 5))),
    );
    await _generateCode(tester, gateway);

    gateway.currentStatus = _linked;
    await tester.pump(const Duration(seconds: 3));
    final callsWhenLinked = gateway.statusCalls;
    await tester.pump(const Duration(seconds: 30));

    expect(gateway.statusCalls, callsWhenLinked);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('polling stops when the displayed code expires', (tester) async {
    var now = _now;
    final gateway = _FakeGateway(
      currentStatus: _unlinked,
      code: _freshCode(_now.add(const Duration(seconds: 10))),
    );
    await _generateCode(tester, gateway, clock: () => now);

    await tester.pump(const Duration(seconds: 3));
    expect(gateway.statusCalls, 2);

    now = _now.add(const Duration(seconds: 11));
    await tester.pump(const Duration(seconds: 3));
    expect(gateway.statusCalls, 2);
    await tester.pump(const Duration(seconds: 30));

    expect(gateway.statusCalls, 2);
    expect(
      find.text('Ce code a expiré. Générez-en un nouveau.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a slow status call is never overlapped by the next poll', (
    tester,
  ) async {
    final gateway = _FakeGateway(
      currentStatus: _unlinked,
      code: _freshCode(_now.add(const Duration(minutes: 5))),
    );
    await _generateCode(tester, gateway);

    gateway.statusGate = Completer<void>();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 9));

    expect(gateway.statusCalls, 2);
    expect(gateway.maxInFlight, 1);

    gateway.statusGate!.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(gateway.statusCalls, 3);
    expect(gateway.maxInFlight, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disposing the panel cancels polling', (tester) async {
    final gateway = _FakeGateway(
      currentStatus: _unlinked,
      code: _freshCode(_now.add(const Duration(minutes: 5))),
    );
    await _generateCode(tester, gateway);

    await tester.pumpWidget(const SizedBox.shrink());
    final callsAfterDispose = gateway.statusCalls;
    await tester.pump(const Duration(seconds: 30));

    expect(gateway.statusCalls, callsAfterDispose);
  });

  testWidgets('transient poll errors stay silent until the third in a row', (
    tester,
  ) async {
    final gateway = _FakeGateway(
      currentStatus: _unlinked,
      code: _freshCode(_now.add(const Duration(minutes: 5))),
    );
    await _generateCode(tester, gateway);

    gateway.statusErrors.addAll([
      const _Failure('identity_link_unavailable', 'RAW-SECRET-DETAIL'),
      const _Failure('identity_link_unavailable', 'RAW-SECRET-DETAIL'),
      const _Failure('identity_link_unavailable', 'RAW-SECRET-DETAIL'),
    ]);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));

    expect(find.text(_unavailableMessage), findsNothing);
    expect(_selectable('SYN-CODE-123'), findsOneWidget);
    expect(gateway.statusCalls, 3);

    await tester.pump(const Duration(seconds: 3));

    expect(find.text(_unavailableMessage), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(find.textContaining('RAW-SECRET-DETAIL'), findsNothing);
    expect(_selectable('SYN-CODE-123'), findsOneWidget);

    final callsAtError = gateway.statusCalls;
    await tester.pump(const Duration(seconds: 30));
    expect(gateway.statusCalls, callsAtError);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('returning to the foreground refreshes status when not linked', (
    tester,
  ) async {
    final gateway = _FakeGateway(currentStatus: _unlinked);
    await tester.pumpWidget(_host(gateway));
    await tester.pump();
    expect(gateway.statusCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(gateway.statusCalls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

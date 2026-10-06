import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shipglows_email_engine_app/main.dart';
import 'package:shipglows_email_engine_app/central_email_api.dart';

void main() {
  testWidgets('dirty editor back saves latest content and exits once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var saves = 0;
    final campaign = <String, dynamic>{
      'id': 'c1',
      'business_id': 'b1',
      'title': 'Initial',
      'subject': 'Objet',
      'preheader': 'Aperçu',
      'version': 1,
      'state': 'draft',
      'audience_id': 'readers',
      'locale': 'fr',
      'blocks': <Object>[],
      'updated_at': '2026-09-08T10:00:00Z',
      'counters': <String, int>{},
    };
    final api = CentralEmailApi(
      origin: Uri.https('example.test'),
      client: MockClient((request) async {
        Object result;
        if (request.url.path.endsWith('/support/context')) {
          result = {'configured': false, 'mailboxes': [], 'can_reply': false};
        } else if (request.url.path.endsWith('/sources')) {
          result = {'configured': false, 'documents': [], 'next_cursor': null};
        } else if (request.url.path.endsWith('/context')) {
          result = {
            'businesses': [
              {
                'id': 'b1',
                'brand': 'Marque',
                'from': 'hello@example.test',
                'audiences': [
                  {'id': 'readers', 'purpose': 'news'},
                ],
                'capabilities': {'can_test': false, 'can_approve': false},
                'test_recipients': <String>[],
              },
            ],
          };
        } else if (request.url.path.endsWith('/save')) {
          saves++;
          campaign['title'] = (jsonDecode(request.body) as Map)['title'];
          campaign['version'] = (campaign['version'] as int) + 1;
          result = {'campaign': campaign};
        } else if (request.url.path.endsWith('/campaigns')) {
          result = {
            'campaigns': [campaign],
            'next_cursor': null,
          };
        } else {
          result = {'campaign': campaign};
        }
        return http.Response(
          jsonEncode(result),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await tester.pumpWidget(EmailEngineApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Initial'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ouvrir dans le studio'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Nom de la campagne'),
      'Dernière version',
    );
    await tester.tap(find.byTooltip('Retour aux campagnes'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(campaign['title'], 'Dernière version');
    expect(find.byTooltip('Nouvelle campagne'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

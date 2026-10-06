import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shipglows_email_engine_app/central_email_api.dart';
import 'package:shipglows_email_engine_app/main.dart';

void main() {
  testWidgets(
    'incident cards are honest and plan reduction waits for explicit confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final campaign = <String, dynamic>{
        'id': 'campaign-1',
        'business_id': 'business-1',
        'title': 'Campaign de test',
        'subject': 'Actualités',
        'preheader': '',
        'version': 5,
        'state': 'sending',
        'audience_id': 'readers',
        'locale': 'fr',
        'blocks': <Object>[
          {'id': 'one', 'type': 'text', 'text': 'Bonjour'},
        ],
        'updated_at': '2026-09-08T10:00:00Z',
        'counters': <String, int>{'queued': 2, 'unknown': 1},
      };
      final reductionRequests = <Map<String, dynamic>>[];
      var recipientReads = 0;
      var incidentReads = 0;
      final api = CentralEmailApi(
        origin: Uri.https('example.test'),
        client: MockClient((request) async {
          final path = request.url.path;
          Object result;
          if (path.endsWith('/support/context')) {
            result = {'configured': false, 'mailboxes': [], 'can_reply': false};
          } else if (path.endsWith('/sources')) {
            result = {
              'configured': false,
              'documents': [],
              'next_cursor': null,
            };
          } else if (path.endsWith('/context')) {
            result = {
              'businesses': [
                {
                  'id': 'business-1',
                  'brand': 'Studio',
                  'from': 'hello@example.test',
                  'audiences': [
                    {'id': 'readers', 'purpose': 'news'},
                  ],
                  'capabilities': {'can_test': false, 'can_approve': true},
                  'test_recipients': <String>[],
                },
              ],
            };
          } else if (path.endsWith('/campaigns')) {
            result = {
              'campaigns': [campaign],
              'next_cursor': null,
            };
          } else if (path.endsWith('/incidents')) {
            incidentReads++;
            result = {
              'incidents': [
                {
                  'id': 'incident-1',
                  'state': 'open',
                  'rule_id': 'bounce-rate',
                  'episode': 1,
                  'severity': 0.2,
                  'evaluation_unavailable': false,
                  'record_updated_at': 1799325600000,
                  'last_transition': {
                    'reason': 'qualified_breach',
                    'kind': 'opened',
                  },
                  'measurement': null,
                  'threshold': null,
                  'sample': null,
                  'coverage': null,
                  'evaluated_at': null,
                },
              ],
              'cursor': null,
              'complete': true,
            };
          } else if (path.endsWith('/recipients')) {
            recipientReads++;
            result = {
              'campaign': campaign,
              'recipients': [
                {
                  'recipient_reference': 'opaque-recipient-0000000001',
                  'state': 'queued',
                  'reason': null,
                  'reducible': true,
                  'protected': false,
                },
                {
                  'recipient_reference': 'opaque-recipient-0000000002',
                  'state': 'snapshot',
                  'reason': null,
                  'reducible': true,
                  'protected': false,
                },
                {
                  'recipient_reference': 'opaque-recipient-protected',
                  'state': 'unknown',
                  'reason': null,
                  'reducible': false,
                  'protected': true,
                },
              ],
              'next_cursor': null,
              'complete': true,
            };
          } else if (path.endsWith('/reduce')) {
            reductionRequests.add(
              jsonDecode(request.body) as Map<String, dynamic>,
            );
            campaign['version'] = 6;
            campaign['state'] = 'suspended';
            campaign['block_reason'] = 'remaining_plan_reduced';
            result = {
              'campaign': campaign,
              'block_reason': 'remaining_plan_reduced',
            };
          } else if (path.endsWith('/campaigns/campaign-1')) {
            result = {
              'campaign': campaign,
              'rendered': {'html': '<p>Bonjour</p>', 'text': 'Bonjour'},
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
      await tester.tap(find.text('Campaign de test'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ouvrir dans le studio'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byTooltip('Consulter les incidents (lecture seule)'),
      );
      await tester.pumpAndSettle();
      expect(incidentReads, 1);
      expect(
        find.textContaining('Motif enregistré : qualified_breach'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Mesure, seuil, échantillon et couverture : indisponibles',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Lecture seule.'), findsOneWidget);
      expect(find.text('Acquitter'), findsNothing);
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Réduire les prochains départs'));
      await tester.pumpAndSettle();
      expect(recipientReads, 1);
      expect(reductionRequests, isEmpty);
      expect(
        find.textContaining('2 références resteront sélectionnées; 0'),
        findsOneWidget,
      );
      expect(
        find.textContaining('déjà transmises, livrées ou à résultat incertain'),
        findsOneWidget,
      );

      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pumpAndSettle();
      expect(reductionRequests, isEmpty);
      expect(find.textContaining('1 référence'), findsOneWidget);
      expect(find.textContaining('À exclure : t-0000000001'), findsOneWidget);
      expect(find.textContaining('@'), findsNothing);

      await tester.tap(find.text('Confirmer la réduction'));
      await tester.pumpAndSettle();
      expect(reductionRequests, hasLength(1));
      expect(reductionRequests.single['expected_version'], 5);
      expect(reductionRequests.single['recipient_ids'], [
        'opaque-recipient-0000000002',
      ]);
      expect(tester.takeException(), isNull);
    },
  );
}

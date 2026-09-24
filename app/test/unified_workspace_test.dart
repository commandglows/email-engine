import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shipglows_email_engine_app/main.dart';
import 'package:shipglows_email_engine_app/central_email_api.dart';
import 'package:source_sidebar_flutter/source_sidebar_flutter.dart';

void main() {
  testWidgets(
    'one list and reader retain support draft across source selection and lock unknown reply',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var replies = 0;
      final api = CentralEmailApi(
        origin: Uri.https('example.test'),
        client: MockClient((request) async {
          final path = request.url.path;
          Object response;
          if (path.endsWith('/support/context')) {
            response = {
              'configured': true,
              'can_reply': true,
              'mailboxes': [
                {'id': 'own', 'email': 'owner@gmail.com', 'connected': true},
              ],
            };
          } else if (path.endsWith('/support/threads')) {
            response = {
              'threads': [
                {
                  'id': 'shared',
                  'subject': 'Question client',
                  'from': 'Client',
                  'snippet': 'Bonjour',
                  'status': 'pending',
                  'updated_at': '2026-09-08T12:00:00Z',
                },
              ],
              'next_cursor': null,
            };
          } else if (path.endsWith('/reply')) {
            replies++;
            expect(jsonDecode(request.body)['expected_message_id'], 'message1');
            expect(jsonDecode(request.body).containsKey('recipient'), false);
            response = {'state': 'unknown', 'message_id': null};
          } else if (path.endsWith('/support/threads/shared')) {
            response = {
              'thread': {
                'id': 'shared',
                'subject': 'Question client',
                'status': 'pending',
                'latest_message_id': 'message1',
                'can_reply': true,
                'reply_to': 'opaque@relay.example.com',
                'messages': [
                  {
                    'id': 'message1',
                    'from': 'Client',
                    'to': 'owner@gmail.com',
                    'text': 'Bonjour client',
                    'date': '2026-09-08T12:00:00Z',
                  },
                ],
              },
            };
          } else if (path.endsWith('/sources')) {
            response = {
              'configured': true,
              'documents': [
                {
                  'id': 'shared',
                  'title': 'Article source',
                  'author': 'Auteur',
                  'summary': 'Lecture',
                  'content': 'Texte source',
                  'published_at': '2026-09-08T12:00:00Z',
                },
              ],
              'next_cursor': null,
            };
          } else {
            response = {'businesses': []};
          }
          return http.Response(
            jsonEncode(response),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await tester.pumpWidget(EmailEngineApp(api: api));
      await tester.pumpAndSettle();
      expect(find.byType(SourceSidebar), findsOneWidget);
      final sidebar = tester.widget<SourceSidebar>(find.byType(SourceSidebar));
      expect(sidebar.sectionLabels.values, [
        'Sources',
        'Service client',
        'Diffusion',
      ]);
      expect(sidebar.items.map((i) => i.id).toSet(), {
        'source:shared',
        'support:own:shared',
      });
      await tester.tap(find.text('Question client').first);
      await tester.pumpAndSettle();
      final replyField = find.widgetWithText(TextField, 'Votre réponse');
      await tester.ensureVisible(replyField);
      await tester.enterText(replyField, 'Réponse conservée');
      await tester.tap(find.byTooltip('Back to list'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Article source').first);
      await tester.pumpAndSettle();
      expect(find.text('Texte source'), findsWidgets);
      await tester.tap(find.byTooltip('Back to list'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Question client').first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(replyField).controller!.text,
        'Réponse conservée',
      );
      await tester.ensureVisible(find.text('Répondre'));
      await tester.tap(find.text('Répondre'));
      await tester.pumpAndSettle();
      expect(replies, 0);
      await tester.tap(find.text('Confirmer l’envoi'));
      await tester.pumpAndSettle();
      expect(replies, 1);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Répondre'))
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<TextField>(replyField).controller!.text,
        'Réponse conservée',
      );
      expect(tester.takeException(), isNull);
    },
  );
}

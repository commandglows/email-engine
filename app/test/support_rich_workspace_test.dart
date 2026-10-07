import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shipglows_email_engine_app/main.dart';
import 'package:shipglows_email_engine_app/central_email_api.dart';
import 'package:source_sidebar_flutter/source_sidebar_flutter.dart';

void main() {
  testWidgets(
    'server search pages all mail; rich reader, files and reply-all require confirmation',
    (tester) async {
      const fontPath = String.fromEnvironment('EMAIL_ENGINE_PROOF_FONTS');
      if (fontPath.isNotEmpty) {
        await tester.runAsync(() async {
          for (final entry in {
            'Roboto': 'roboto-regular.ttf',
            'MaterialIcons': 'materialicons-regular.otf',
          }.entries) {
            final loader = FontLoader(entry.key);
            loader.addFont(
              File(
                '$fontPath/${entry.value}',
              ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
            );
            await loader.load();
          }
        });
      }
      tester.view.physicalSize = const Size(1500, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final picker = _Picker();
      final previous = FilePickerPlatform.instance;
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = previous);
      var searches = 0, replies = 0;
      final api = CentralEmailApi(
        origin: Uri.https('example.test'),
        client: MockClient((request) async {
          final path = request.url.path;
          Object data;
          if (path.endsWith('/support/context')) {
            data = {
              'configured': true,
              'can_reply': true,
              'mailboxes': [
                {'id': 'own', 'email': 'owner@gmail.com', 'connected': true},
              ],
            };
          } else if (path.endsWith('/support/threads')) {
            final query = request.url.queryParameters['query'];
            if (query != null) {
              searches++;
              expect(query, 'has:attachment');
            }
            final more = request.url.queryParameters['cursor'] != null;
            data = {
              'threads': [
                {
                  'id': more ? 'second' : 'thread',
                  'subject': more ? 'Autre archive' : 'Facture archivée',
                  'from': 'Client',
                  'snippet': 'Facture',
                  'status': 'pending',
                },
              ],
              'next_cursor': query != null && !more ? 'next' : null,
            };
          } else if (path.endsWith('/attachments/a')) {
            data = {
              'attachment': {'id': 'a', 'size': 3, 'data_base64': 'AQID'},
            };
          } else if (path.endsWith('/reply')) {
            replies++;
            final body = jsonDecode(request.body);
            expect(body['reply_mode'], 'reply_all');
            expect(body['attachments'].single['data_base64'], 'AQID');
            expect(body.containsKey('recipients'), isFalse);
            data = {'state': 'submitted'};
          } else if (path.contains('/support/threads/')) {
            data = {
              'thread': {
                'id': 'thread',
                'subject': 'Facture archivée',
                'status': 'pending',
                'latest_message_id': 'message',
                'can_reply': true,
                'reply_to': 'one@relay.test',
                'can_reply_all': true,
                'reply_all_recipients': ['one@relay.test', 'two@relay.test'],
                'messages': [
                  {
                    'id': 'message',
                    'from': 'Client',
                    'to': 'Owner',
                    'text': 'Texte alternatif',
                    'html': '<p><strong>Facture enrichie</strong></p>',
                    'attachments': [
                      {
                        'id': 'a',
                        'name': 'receipt.pdf',
                        'mime_type': 'application/pdf',
                        'size': 3,
                      },
                    ],
                  },
                ],
              },
            };
          } else if (path.endsWith('/sources')) {
            data = {'configured': true, 'documents': [], 'next_cursor': null};
          } else {
            data = {'businesses': []};
          }
          return http.Response(
            jsonEncode(data),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('visual-proof'),
          child: EmailEngineApp(api: api),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byTooltip('Rechercher dans toutes les boîtes Gmail'),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Recherche Gmail'),
        'has:attachment',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Rechercher'));
      await tester.pumpAndSettle();
      expect(searches, 1);
      final sidebar = tester.widget<SourceSidebar>(find.byType(SourceSidebar));
      expect(sidebar.hasMore, true);
      await sidebar.onLoadMore!();
      await tester.pumpAndSettle();
      expect(searches, 2);
      expect(
        tester.widget<SourceSidebar>(find.byType(SourceSidebar)).items.length,
        2,
      );
      await tester.tap(find.text('Facture archivée').first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Facture enrichie', findRichText: true),
        findsWidgets,
      );
      const proofPath = String.fromEnvironment('EMAIL_ENGINE_VISUAL_PROOF');
      if (proofPath.isNotEmpty) {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('visual-proof')),
          );
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ImageByteFormat.png);
          await File(proofPath).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Lecture enrichie'), findsOneWidget);
      if (proofPath.isNotEmpty) {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('visual-proof')),
          );
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ImageByteFormat.png);
          await File(
            proofPath.replaceFirst('.png', '-mobile.png'),
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      tester.view.physicalSize = const Size(1500, 1600);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Texte seul'));
      await tester.pumpAndSettle();
      expect(find.text('Texte alternatif'), findsOneWidget);
      await tester.tap(find.text('receipt.pdf · 3 octets'));
      await tester.pumpAndSettle();
      expect(picker.saved, [1, 2, 3]);
      await tester.ensureVisible(find.text('Joindre des fichiers'));
      await tester.tap(find.text('Joindre des fichiers'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Retirer note.txt'), findsOneWidget);
      await tester.tap(find.byTooltip('Retirer note.txt'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Retirer note.txt'), findsNothing);
      await tester.tap(find.text('Joindre des fichiers'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Répondre à tous'));
      await tester.tap(find.text('Répondre à tous'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Votre réponse'),
        'Merci',
      );
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Répondre'));
      await tester.tap(find.widgetWithText(FilledButton, 'Répondre'));
      await tester.pumpAndSettle();
      expect(replies, 0);
      expect(
        find.textContaining('one@relay.test, two@relay.test'),
        findsWidgets,
      );
      expect(find.textContaining('Pièces jointes : note.txt'), findsOneWidget);
      await tester.tap(find.text('Confirmer l’envoi'));
      await tester.pumpAndSettle();
      expect(replies, 1);
      expect(find.byTooltip('Retirer note.txt'), findsNothing);
    },
  );
}

final class _MemoryFile extends PlatformFile {
  @override
  String get name => 'note.txt';
  @override
  Uri get uri => Uri.parse('memory:note.txt');
  @override
  get xFile => throw UnimplementedError();
  @override
  int lengthSync() => 3;
  @override
  Future<int?> length() async => 3;
  @override
  Future<Uint8List> readAsBytes() async => Uint8List.fromList([1, 2, 3]);
  @override
  Stream<Uint8List> readAsByteStream() =>
      Stream.value(Uint8List.fromList([1, 2, 3]));
}

class _Picker extends FilePickerPlatform {
  Uint8List? saved;
  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => [_MemoryFile()];
  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    saved = bytes;
    return Uri.parse('memory:$fileName');
  }
}

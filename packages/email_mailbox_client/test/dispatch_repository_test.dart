import 'dart:convert';

import 'package:email_mailbox_client/email_mailbox_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _bridge = '/api/bridge/email-mailbox/firebase';

CentralDispatchRepository _repositoryReturning(Object body) =>
    CentralDispatchRepository(
      CentralEmailApi(
        origin: Uri.parse('https://synthetic.test'),
        accessTokenProvider: () async => 'synthetic-user-session',
        apiBasePath: _bridge,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    );

Map<String, dynamic> _destinationV1({
  String id = 'synthetic-a',
  String projectId = 'synthetic-a',
}) => {
  'id': id,
  'label': 'Projet synthétique',
  'project_id': projectId,
  'available': true,
  'disabled_reason': null,
};

void main() {
  test('reads kind, project label and generation time when sent', () async {
    final context = await _repositoryReturning({
      'schema_version': 1,
      'analysis_enabled': false,
      'generated_at': '2026-10-14T09:00:00+02:00',
      'destinations': [
        {
          'id': 'synthetic-draft',
          'label': 'Ébauche synthétique',
          'project_id': 'synthetic-project',
          'project_label': 'Projet synthétique',
          'kind': 'content_draft',
          'available': true,
          'disabled_reason': 'Autorisation projet expirée',
        },
      ],
    }).context('own');

    expect(context.generatedAt, DateTime.utc(2026, 10, 14, 7));
    final destination = context.destinations.single;
    expect(destination.kind, 'content_draft');
    expect(destination.projectLabel, 'Projet synthétique');
    expect(destination.projectId, 'synthetic-project');
    expect(destination.disabledReason, 'Autorisation projet expirée');
  });

  test(
    'schema version 1 responses without the new keys keep project defaults',
    () async {
      final context = await _repositoryReturning({
        'schema_version': 1,
        'analysis_enabled': true,
        'destinations': [_destinationV1()],
      }).context('own');

      expect(context.analysisEnabled, isTrue);
      expect(context.generatedAt, isNull);
      final destination = context.destinations.single;
      expect(destination.kind, 'project');
      expect(destination.projectLabel, isNull);
      expect(destination.id, 'synthetic-a');
      expect(destination.available, isTrue);
    },
  );

  test(
    'malformed optional fields fall back instead of failing the list',
    () async {
      final context = await _repositoryReturning({
        'schema_version': 1,
        'generated_at': 'not-a-date',
        'destinations': [
          {
            ..._destinationV1(),
            'kind': 42,
            'project_label': ['not', 'a', 'string'],
          },
        ],
      }).context('own');

      expect(context.generatedAt, isNull);
      final destination = context.destinations.single;
      expect(destination.kind, 'project');
      expect(destination.projectLabel, isNull);
    },
  );
}

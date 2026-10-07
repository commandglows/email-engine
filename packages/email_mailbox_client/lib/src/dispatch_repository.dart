import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';

import 'central_email_api.dart';

class CentralDispatchRepository implements DispatchRepository {
  CentralDispatchRepository(this.api);
  final CentralEmailApi api;
  Future<T> _guard<T>(
    Future<T> Function() action, {
    bool mutation = false,
  }) async {
    try {
      return await action();
    } on EmailApiException catch (e) {
      throw DispatchException(
        code: e.code,
        unknown:
            mutation &&
            !const {
              'auth_required',
              'authentication_required',
              'dispatch_disabled',
              'privacy_not_ready',
              'connection_required',
              'invalid_content_type',
              'body_too_large',
              'source_unavailable',
              'forbidden',
              'invalid_input',
              'invalid_request',
              'stale_thread',
              'thread_changed',
              'dispatch_expired',
              'destination_unavailable',
            }.contains(e.code),
      );
    } catch (_) {
      throw DispatchException(unknown: mutation, code: 'invalid_receipt');
    }
  }

  ProjectDispatch _parse(
    Map<String, dynamic> d, {
    String? expectedId,
    List<String>? expectedDestinations,
  }) {
    final parsed = ProjectDispatch(
      id: d['dispatch_id'] as String,
      summary: d['summary'] as String,
      receipts: (d['receipts'] as List)
          .map(
            (r) => DispatchReceipt(
              destinationId: r['destination_id'] as String,
              projectId: r['project_id'] as String,
              state: DispatchReceiptState.values.firstWhere(
                (s) =>
                    (s == DispatchReceiptState.inFlight
                        ? 'in_flight'
                        : s.name) ==
                    r['state'],
              ),
              intakeId: r['intake_id'] as String?,
              errorCode: r['error_code'] as String?,
            ),
          )
          .toList(),
    );
    final ids = parsed.receipts.map((r) => r.destinationId).toSet();
    if (parsed.id.isEmpty ||
        parsed.receipts.isEmpty ||
        ids.length != parsed.receipts.length ||
        (expectedId != null && parsed.id != expectedId) ||
        (expectedDestinations != null &&
            (ids.length != expectedDestinations.length ||
                !ids.containsAll(expectedDestinations))) ||
        parsed.receipts.any(
          (r) =>
              r.projectId.isEmpty ||
              (r.state == DispatchReceiptState.accepted &&
                  (r.intakeId == null || r.intakeId!.isEmpty)),
        )) {
      throw const FormatException();
    }
    return parsed;
  }

  @override
  Future<DispatchContext> context(String mailboxId) => _guard(() async {
    final d = await api.get('dispatch/context', {'mailbox_id': mailboxId});
    if (d['schema_version'] != 1) throw const FormatException();
    return DispatchContext(
      analysisEnabled: d['analysis_enabled'] == true,
      destinations: (d['destinations'] as List)
          .map(
            (r) => DispatchDestination(
              id: r['id'] as String,
              label: r['label'] as String,
              projectId: r['project_id'] as String,
              available: r['available'] == true,
              disabledReason: r['disabled_reason'] as String?,
            ),
          )
          .toList(),
    );
  });
  @override
  Future<List<ProjectDispatch>> history(String mailboxId, String threadId) =>
      _guard(
        () async =>
            ((await api.get('dispatch/threads/$threadId', {
                      'mailbox_id': mailboxId,
                    }))['dispatches']
                    as List)
                .map((d) => _parse(Map<String, dynamic>.from(d as Map)))
                .toList(),
      );
  @override
  Future<ProjectDispatch> confirm(
    String mailboxId,
    String threadId,
    DispatchProposal proposal,
  ) => _guard(() async {
    final d = await api.post('dispatch/threads/$threadId/confirm', {
      'mailbox_id': mailboxId,
      ...proposal.toJson(),
    });
    return _parse(
      Map<String, dynamic>.from((d['dispatch'] ?? d) as Map),
      expectedId: proposal.dispatchId,
      expectedDestinations: proposal.destinationIds,
    );
  }, mutation: true);
  @override
  Future<ProjectDispatch> recover(
    String mailboxId,
    String threadId,
    String dispatchId,
  ) => _guard(() async {
    final d = await api.post('dispatch/threads/$threadId/recover', {
      'mailbox_id': mailboxId,
      'dispatch_id': dispatchId,
      'confirmed': true,
    });
    return _parse(
      Map<String, dynamic>.from((d['dispatch'] ?? d) as Map),
      expectedId: dispatchId,
    );
  }, mutation: true);
}

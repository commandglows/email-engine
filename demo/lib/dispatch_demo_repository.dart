import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';

/// In-memory synthetic receipts only. No network, Gmail or project API.
class DemoDispatchRepository implements DispatchRepository {
  final _records = <String, List<ProjectDispatch>>{};
  @override
  Future<DispatchContext> context(String mailboxId) async =>
      const DispatchContext(
        destinations: [
          DispatchDestination(
            id: 'synthetic-content',
            label: 'ContentGlows · démonstration',
            projectId: 'synthetic-content',
            available: true,
          ),
          DispatchDestination(
            id: 'synthetic-tasks',
            label: 'ShipGlows · démonstration (résultat partiel)',
            projectId: 'synthetic-tasks',
            available: true,
          ),
        ],
      );
  @override
  Future<List<ProjectDispatch>> history(
    String mailboxId,
    String threadId,
  ) async => List.of(_records['$mailboxId/$threadId'] ?? []);
  @override
  Future<ProjectDispatch> confirm(
    String mailboxId,
    String threadId,
    DispatchProposal proposal,
  ) async {
    final records = _records.putIfAbsent('$mailboxId/$threadId', () => []);
    for (final d in records) {
      if (d.id == proposal.dispatchId) return d;
    }
    final d = ProjectDispatch(
      id: proposal.dispatchId,
      summary: proposal.summary,
      receipts: proposal.destinationIds
          .map(
            (id) => DispatchReceipt(
              destinationId: id,
              projectId: id,
              state: id == 'synthetic-tasks'
                  ? DispatchReceiptState.unknown
                  : DispatchReceiptState.accepted,
              intakeId: id == 'synthetic-tasks'
                  ? null
                  : 'synthetic-${proposal.dispatchId}',
              errorCode: id == 'synthetic-tasks' ? 'synthetic_timeout' : null,
            ),
          )
          .toList(),
    );
    records.add(d);
    return d;
  }

  @override
  Future<ProjectDispatch> recover(
    String mailboxId,
    String threadId,
    String dispatchId,
  ) async {
    final records = _records['$mailboxId/$threadId'] ?? [];
    final index = records.indexWhere((d) => d.id == dispatchId);
    if (index < 0) throw const DispatchException(code: 'not_found');
    final previous = records[index];
    final d = ProjectDispatch(
      id: previous.id,
      summary: previous.summary,
      receipts: previous.receipts
          .map(
            (r) => DispatchReceipt(
              destinationId: r.destinationId,
              projectId: r.projectId,
              state: DispatchReceiptState.accepted,
              intakeId: r.intakeId ?? 'synthetic-$dispatchId',
            ),
          )
          .toList(),
    );
    records[index] = d;
    return d;
  }
}

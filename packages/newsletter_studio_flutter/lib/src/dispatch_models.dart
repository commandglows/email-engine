import 'dart:math';

/// One selectable dispatch target.
///
/// [kind] is `project` for a project inbox, or a sub-target such as
/// `content_draft` or `idea_pool` that belongs to [projectId]. The panel groups
/// sub-targets under their project. Hosts that predate the field omit it, so
/// it defaults to `project`.
class DispatchDestination {
  const DispatchDestination({
    required this.id,
    required this.label,
    required this.projectId,
    required this.available,
    this.disabledReason,
    this.kind = 'project',
    this.projectLabel,
  });
  final String id, label, projectId;
  final bool available;
  final String? disabledReason;

  /// Target kind: `project`, `content_draft` or `idea_pool`.
  final String kind;

  /// Human name of the owning project, used as the group header when present.
  /// Null means the panel falls back to [projectId].
  final String? projectLabel;
}

class DispatchContext {
  const DispatchContext({
    required this.destinations,
    this.analysisEnabled = false,
    this.generatedAt,
  });
  final List<DispatchDestination> destinations;
  final bool analysisEnabled;

  /// When the host generated this destination list, in UTC. Null when the
  /// host did not send it, in which case no freshness hint is shown.
  final DateTime? generatedAt;
}

/// Human-confirmed proposal sent by the panel.
///
/// The payload carries only [destinationIds]. The mapping from each selected
/// destination to an intake v2 `target` (`kind` and `id`) is done server-side
/// by CommandGlows, so the client never sends targets, URLs or tokens.
class DispatchProposal {
  const DispatchProposal({
    required this.dispatchId,
    required this.expectedMessageId,
    required this.summary,
    required this.contributionType,
    required this.justification,
    required this.risks,
    required this.destinationIds,
    this.confidence,
  });
  final String dispatchId,
      expectedMessageId,
      summary,
      contributionType,
      justification;
  final double? confidence;
  final List<String> risks, destinationIds;
  Map<String, dynamic> toJson() => {
    'dispatch_id': dispatchId,
    'expected_message_id': expectedMessageId,
    'revision': 1,
    'summary': summary,
    'contribution_type': contributionType,
    'justification': justification,
    'confidence': confidence,
    'risks': risks,
    'destination_ids': destinationIds,
    'confirmed': true,
  };
  static String newId() {
    final r = Random.secure();
    final b = List.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}

enum DispatchReceiptState { intent, inFlight, accepted, failed, unknown }

class DispatchReceipt {
  const DispatchReceipt({
    required this.destinationId,
    required this.projectId,
    required this.state,
    this.intakeId,
    this.errorCode,
  });
  final String destinationId, projectId;
  final DispatchReceiptState state;
  final String? intakeId, errorCode;
}

class ProjectDispatch {
  const ProjectDispatch({
    required this.id,
    required this.summary,
    required this.receipts,
  });
  final String id, summary;
  final List<DispatchReceipt> receipts;
  bool get unresolved =>
      receipts.any((r) => r.state != DispatchReceiptState.accepted);
}

abstract class DispatchRepository {
  Future<DispatchContext> context(String mailboxId);
  Future<List<ProjectDispatch>> history(String mailboxId, String threadId);
  Future<ProjectDispatch> confirm(
    String mailboxId,
    String threadId,
    DispatchProposal proposal,
  );
  Future<ProjectDispatch> recover(
    String mailboxId,
    String threadId,
    String dispatchId,
  );
}

class DispatchException implements Exception {
  const DispatchException({this.unknown = false, this.code = 'unavailable'});
  final bool unknown;
  final String code;
}

/// Transient, inert provider output. Applying a candidate never confirms dispatch.
class DispatchAnalysisCandidate {
  const DispatchAnalysisCandidate({
    required this.destinationId,
    required this.contributionType,
    required this.justification,
    required this.confidence,
    required this.risks,
  });
  final String destinationId, contributionType, justification;
  final double confidence;
  final List<String> risks;
}

class DispatchAnalysis {
  const DispatchAnalysis({
    required this.sourceRevision,
    required this.summary,
    required this.candidates,
    required this.risks,
    required this.provider,
    required this.model,
  });
  final String sourceRevision, summary, provider, model;
  final List<DispatchAnalysisCandidate> candidates;
  final List<String> risks;
}

typedef DispatchAnalysisCallback =
    Future<DispatchAnalysis> Function(List<DispatchDestination> destinations);

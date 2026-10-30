import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';

/// Email triage contract v2, shared by every host (ShipGlows.app, ContentGlows).
///
/// The request names the destinations the operator may dispatch to and the
/// response picks among them by [DispatchDestination.id]. What a destination is
/// (a project, a content draft, an idea…) and how the host decides stay host
/// concerns: ShipGlows.app routes to projects from their pitches, ContentGlows
/// to contents. Suggestions are inert: applying one never confirms a dispatch.
const emailTriageSchemaVersion = 2;

/// Body of a v2 triage request. [destinations] are sent as untrusted labels;
/// the host re-checks ownership of every [DispatchDestination.projectId].
///
/// [subject] and [sender] help the host tell automatic technical alerts
/// (error trackers, CI, dependencies, monitoring) from everything else.
Map<String, dynamic> emailTriageRequest({
  required String sourceRevision,
  required String text,
  required List<DispatchDestination> destinations,
  String? subject,
  String? sender,
}) => {
  'schema_version': emailTriageSchemaVersion,
  'consent_external_analysis': true,
  'source_revision': sourceRevision,
  'text': text,
  if (subject != null && subject.trim().isNotEmpty)
    'subject': _clip(subject.trim(), 500),
  if (sender != null && sender.trim().isNotEmpty)
    'sender': _clip(sender.trim(), 320),
  'destinations': [
    for (final destination in destinations)
      {
        'id': destination.id,
        'kind': destination.kind,
        'label': destination.label,
        'project_id': destination.projectId,
        'project_label': destination.projectLabel,
      },
  ],
};

/// Validates a v2 triage response against the destinations that were sent.
///
/// Throws `DispatchException(code: 'invalid_analysis')` on any shape error, an
/// unknown or repeated destination, or a revision that no longer matches.
/// Candidates come back most confident first, at most [maxCandidates].
DispatchAnalysis parseEmailTriageResponse(
  Object? result, {
  required String sourceRevision,
  required List<DispatchDestination> destinations,
  int maxCandidates = 5,
}) {
  const invalid = DispatchException(code: 'invalid_analysis');
  if (result is! Map ||
      result['schema_version'] != emailTriageSchemaVersion ||
      result['source_revision'] != sourceRevision ||
      result['requires_human_confirmation'] != true ||
      result['provider'] is! String ||
      result['model'] is! String ||
      result['summary'] is! String ||
      result['candidates'] is! List) {
    throw invalid;
  }
  final known = {for (final destination in destinations) destination.id};
  final seen = <String>{};
  final candidates = <DispatchAnalysisCandidate>[];
  for (final raw in result['candidates'] as List) {
    if (raw is! Map) throw invalid;
    final id = raw['destination_id'];
    final confidence = raw['confidence'];
    final risks = raw['risks'];
    if (id is! String ||
        !known.contains(id) ||
        !seen.add(id) ||
        confidence is! num ||
        !confidence.isFinite ||
        confidence < 0 ||
        confidence > 1 ||
        risks is! List ||
        risks.any((risk) => risk is! String) ||
        raw['contribution_type'] is! String ||
        raw['justification'] is! String) {
      throw invalid;
    }
    candidates.add(
      DispatchAnalysisCandidate(
        destinationId: id,
        contributionType: raw['contribution_type'] as String,
        justification: raw['justification'] as String,
        confidence: confidence.toDouble(),
        risks: risks.cast<String>().toList(),
      ),
    );
  }
  candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
  // Optional: actions the host already took without arbitration (a technical
  // alert filed as a project signal). Malformed entries are ignored.
  final notices = <String>[];
  final automatic = result['automatic_actions'];
  if (automatic is List) {
    for (final action in automatic) {
      if (action is Map &&
          action['kind'] == 'signal' &&
          action['label'] is String) {
        notices.add(
          action['created'] == false
              ? 'Alerte technique déjà transmise à ${action['label']}.'
              : 'Alerte technique transmise à ${action['label']} (signal).',
        );
      }
    }
  }
  return DispatchAnalysis(
    sourceRevision: sourceRevision,
    summary: result['summary'] as String,
    candidates: candidates.take(maxCandidates).toList(),
    risks: const [],
    provider: result['provider'] as String,
    model: result['model'] as String,
    notices: notices,
  );
}

String _clip(String value, int max) =>
    value.length <= max ? value : value.substring(0, max);

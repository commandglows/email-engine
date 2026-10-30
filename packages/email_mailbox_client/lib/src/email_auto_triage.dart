import 'package:flutter/foundation.dart';
import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';

/// The host's analysis of one thread: the same callback as
/// `SupportWorkspace.onAnalyzeThread`.
typedef EmailThreadAnalyzer =
    Future<DispatchAnalysis> Function(
      SupportThread thread,
      List<DispatchDestination> destinations,
      String mailboxId,
    );

/// Outcome of one [EmailAutoTriage.run].
@immutable
final class EmailAutoTriageReport {
  const EmailAutoTriageReport({
    this.analyzed = 0,
    this.skipped = 0,
    this.failed = 0,
    this.automatic = 0,
  });

  /// Threads analysed during this run.
  final int analyzed;

  /// Threads left alone: already analysed at this revision, archived, or
  /// beyond the per-run budget.
  final int skipped;

  /// Threads whose analysis failed; they are retried on the next run.
  final int failed;

  /// Analyses where the host already acted without arbitration (notices).
  final int automatic;
}

/// Automatic pre-triage of the inbox, run by the host on a routine (app start,
/// email page focus, hourly).
///
/// For every connected mailbox it reads the first page of threads, skips the
/// archived ones and those already analysed at their latest message, and asks
/// the host's [EmailThreadAnalyzer] about the rest, within [maxThreadsPerRun].
/// Results are kept in memory by latest message id: the mailbox UI shows them
/// as ready-made suggestions ([analysisFor]) and the operator still confirms
/// every dispatch. What the host does on its own (technical alerts filed as
/// signals) comes back as [DispatchAnalysis.notices]. Never throws: a failing
/// mailbox or thread is counted and retried on the next run. One run at a time.
class EmailAutoTriage extends ChangeNotifier {
  EmailAutoTriage({
    required this.support,
    required this.dispatch,
    required this.analyze,
    this.maxThreadsPerRun = 20,
    this.maxRemembered = 500,
  });

  final SupportRepository support;
  final DispatchRepository dispatch;
  final EmailThreadAnalyzer analyze;
  final int maxThreadsPerRun;
  final int maxRemembered;

  final Map<String, DispatchAnalysis> _byMessage = {};
  // Thread id + last update already examined, so unchanged threads are not
  // fetched again.
  final Map<String, String> _seenRevision = {};
  Future<EmailAutoTriageReport>? _running;
  bool _disposed = false;

  /// The automatic analysis of the thread whose latest message is
  /// [latestMessageId], or null.
  DispatchAnalysis? analysisFor(String latestMessageId) =>
      _byMessage[latestMessageId];

  /// Whether a run is in progress.
  bool get running => _running != null;

  /// The host answered `analysis_setup_required` (no analysis key): runs stop
  /// at the first such answer until an analysis succeeds again.
  bool get setupRequired => _setupRequired;
  bool _setupRequired = false;

  /// Runs once; joins the run in progress instead of starting a second one.
  Future<EmailAutoTriageReport> run() {
    final current = _running;
    if (current != null) return current;
    final next = _run().whenComplete(() => _running = null);
    _running = next;
    return next;
  }

  Future<EmailAutoTriageReport> _run() async {
    var analyzed = 0, skipped = 0, failed = 0, automatic = 0;
    SupportContext context;
    try {
      context = await support.context();
    } catch (_) {
      return const EmailAutoTriageReport(failed: 1);
    }
    for (final mailbox in context.mailboxes) {
      if (_disposed) break;
      if (!mailbox.connected) continue;
      List<DispatchDestination> destinations;
      List<SupportThreadSummary> threads;
      try {
        destinations = (await dispatch.context(mailbox.id)).destinations
            .where((destination) => destination.available)
            .toList();
        threads = (await support.threads(mailbox.id)).items;
      } catch (_) {
        failed++;
        continue;
      }
      if (destinations.isEmpty) continue;
      for (final summary in threads) {
        if (_disposed) break;
        // Without a timestamp the thread is fetched again; its latest message
        // id then tells whether it was already analysed.
        final revision = summary.updatedAt?.toIso8601String();
        final key = '${mailbox.id}/${summary.id}';
        if (summary.isArchived == true ||
            (revision != null && _seenRevision[key] == revision) ||
            analyzed + failed >= maxThreadsPerRun) {
          skipped++;
          continue;
        }
        try {
          final thread = await support.thread(mailbox.id, summary.id);
          if (_byMessage.containsKey(thread.latestMessageId)) {
            if (revision != null) _seenRevision[key] = revision;
            skipped++;
            continue;
          }
          final analysis = await analyze(thread, destinations, mailbox.id);
          _remember(thread.latestMessageId, analysis);
          if (revision != null) _seenRevision[key] = revision;
          analyzed++;
          if (analysis.notices.isNotEmpty) automatic++;
          if (_setupRequired) {
            _setupRequired = false;
            if (!_disposed) notifyListeners();
          }
        } on DispatchException catch (error) {
          failed++;
          if (error.code == 'analysis_setup_required') {
            // Every other thread would fail the same way: stop and tell the host.
            if (!_setupRequired) {
              _setupRequired = true;
              if (!_disposed) notifyListeners();
            }
            return EmailAutoTriageReport(
              analyzed: analyzed,
              skipped: skipped,
              failed: failed,
              automatic: automatic,
            );
          }
        } catch (_) {
          failed++;
        }
      }
    }
    if (!_disposed && analyzed > 0) notifyListeners();
    return EmailAutoTriageReport(
      analyzed: analyzed,
      skipped: skipped,
      failed: failed,
      automatic: automatic,
    );
  }

  void _remember(String messageId, DispatchAnalysis analysis) {
    _byMessage[messageId] = analysis;
    while (_byMessage.length > maxRemembered) {
      _byMessage.remove(_byMessage.keys.first);
    }
    while (_seenRevision.length > maxRemembered * 2) {
      _seenRevision.remove(_seenRevision.keys.first);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

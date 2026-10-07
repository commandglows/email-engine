enum SupportStatus {
  pending,
  waiting,
  resolved;

  String get label => switch (this) {
    pending => 'À traiter',
    waiting => 'En attente',
    resolved => 'Résolu',
  };
}

class SupportMailbox {
  const SupportMailbox({
    required this.id,
    required this.email,
    required this.connected,
    this.canModify,
    this.reconnectRequired = false,
  });
  final String id, email;
  final bool connected;
  final bool? canModify;
  final bool reconnectRequired;
}

class SupportContext {
  const SupportContext({
    required this.configured,
    required this.mailboxes,
    this.canReply = false,
    this.disabledReason,
  });
  final bool configured, canReply;
  final List<SupportMailbox> mailboxes;
  final String? disabledReason;
}

class SupportThreadSummary {
  const SupportThreadSummary({
    required this.id,
    required this.subject,
    required this.from,
    required this.snippet,
    required this.status,
    this.updatedAt,
    this.isUnread,
    this.isArchived,
  });
  final String id, subject, from, snippet;
  final SupportStatus status;
  final DateTime? updatedAt;

  /// Provider-owned Gmail metadata. Null means the provider state is unknown.
  final bool? isUnread, isArchived;
}

class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.from,
    required this.to,
    required this.text,
    this.date,
    this.html,
    this.cc = '',
    this.attachments = const [],
  });
  final String id, from, to, text;
  final DateTime? date;
  final String? html;
  final String cc;
  final List<SupportAttachment> attachments;
}

class SupportAttachment {
  const SupportAttachment({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.size,
  });
  final String id, name, mimeType;
  final int size;
}

class SupportReplyAttachment {
  const SupportReplyAttachment({
    required this.name,
    required this.mimeType,
    required this.dataBase64,
    required this.size,
  });
  final String name, mimeType, dataBase64;
  final int size;
}

class SupportThread {
  const SupportThread({
    required this.id,
    required this.subject,
    required this.status,
    required this.messages,
    required this.latestMessageId,
    required this.canReply,
    this.replyTo,
    this.replyDisabledReason,
    this.canReplyAll = false,
    this.replyAllDisabledReason,
    this.replyAllRecipients = const [],
    this.isUnread,
    this.isArchived,
  });
  final String id, subject, latestMessageId;
  final SupportStatus status;
  final List<SupportMessage> messages;
  final bool canReply;
  final String? replyTo, replyDisabledReason;
  final bool canReplyAll;
  final String? replyAllDisabledReason;
  final List<String> replyAllRecipients;

  /// Provider-owned Gmail metadata. Null means the provider state is unknown.
  final bool? isUnread, isArchived;
}

enum SupportObservabilityState { observed, failure, unknown }

class SupportObservation {
  const SupportObservation({
    required this.messageIdHash,
    required this.observedAt,
    required this.state,
  });
  final String messageIdHash;
  final DateTime? observedAt;
  final String state;
}

class SupportOperationalFailure {
  const SupportOperationalFailure({
    required this.stage,
    required this.code,
    required this.count,
    required this.firstAt,
    required this.lastAt,
    required this.retryable,
  });
  final String stage, code;
  final int? count;
  final DateTime? firstAt, lastAt;
  final bool? retryable;
}

class SupportObservability {
  const SupportObservability({
    required this.coverage,
    required this.source,
    required this.window,
    required this.observedCount,
    required this.sampledCount,
    required this.sampleLimit,
    required this.sampleTruncated,
    required this.countsByState,
    required this.stateCountsAvailable,
    required this.lastObservedAt,
    required this.oldestSampleAt,
    required this.sample,
    required this.sampleAvailable,
    required this.failures,
    required this.failuresAvailable,
  });
  final String coverage, source, window;
  final int? observedCount, sampledCount, sampleLimit;
  final bool? sampleTruncated;
  final Map<String, int?> countsByState;
  final bool stateCountsAvailable, sampleAvailable, failuresAvailable;
  final DateTime? lastObservedAt, oldestSampleAt;
  final List<SupportObservation> sample;
  final List<SupportOperationalFailure> failures;
}

class SupportPage {
  const SupportPage({required this.items, this.nextCursor});
  final List<SupportThreadSummary> items;
  final String? nextCursor;
}

enum SupportReplyResult { submitted, unknown }

/// Host owns authorization, mailbox allowlists and server-side reply routing.
abstract class SupportRepository {
  Future<SupportContext> context();
  Future<Uri> connect(String mailboxId);
  Future<SupportPage> threads(String mailboxId, {String? cursor});
  Future<SupportThread> thread(String mailboxId, String threadId);
  Future<SupportThread> setGmailMetadata(
    String mailboxId,
    String threadId, {
    required String expectedMessageId,
    required bool isUnread,
    required bool isArchived,
  });
  Future<SupportObservability> observability(String mailboxId, String window);
  Future<void> setStatus(
    String mailboxId,
    String threadId,
    SupportStatus status,
  );
  Future<SupportReplyResult> reply(
    String mailboxId,
    String threadId, {
    required String body,
    required String expectedMessageId,
  });
}

class SupportException implements Exception {
  const SupportException(
    this.message, {
    this.outcomeUnknown = false,
    this.code,
  });
  final String message;
  final bool outcomeUnknown;
  final String? code;
}

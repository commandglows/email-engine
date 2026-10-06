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
  });
  final String id, email;
  final bool connected;
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
  });
  final String id, subject, from, snippet;
  final SupportStatus status;
  final DateTime? updatedAt;
}

class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.from,
    required this.to,
    required this.text,
    this.date,
  });
  final String id, from, to, text;
  final DateTime? date;
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
  });
  final String id, subject, latestMessageId;
  final SupportStatus status;
  final List<SupportMessage> messages;
  final bool canReply;
  final String? replyTo, replyDisabledReason;
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
  const SupportException(this.message, {this.outcomeUnknown = false});
  final String message;
  final bool outcomeUnknown;
}

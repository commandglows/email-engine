import 'package:flutter/foundation.dart';

enum SourceProcessingState { idle, processing, processed, failed }

enum SourceSidebarAttention {
  none,
  readyToSend,
  needsReview;

  String get semanticLabel => switch (this) {
    none => '',
    readyToSend => 'prête à envoyer',
    needsReview => 'à vérifier',
  };
}

enum SourceSidebarSignalKind { relevance, urgency }

@immutable
class SourceSidebarItem {
  const SourceSidebarItem({
    required this.id,
    required this.title,
    required this.authorOrPublisher,
    required this.summary,
    required this.publishedAt,
    required this.sourceType,
    required this.content,
    this.tags = const <String>[],
    this.seen = false,
    this.location = 'new',
    this.processingState = SourceProcessingState.idle,
    this.attention = SourceSidebarAttention.none,
    this.signalStrength = 0,
    this.signalKind = SourceSidebarSignalKind.relevance,
    this.canonicalExternalUrl,
  }) : assert(signalStrength >= 0 && signalStrength <= 1);

  final String id;
  final String title;
  final String authorOrPublisher;
  final String summary;
  final DateTime publishedAt;
  final String sourceType;
  final String content;
  final List<String> tags;
  final bool seen;
  final String location;
  final SourceProcessingState processingState;
  final SourceSidebarAttention attention;
  final double signalStrength;
  final SourceSidebarSignalKind signalKind;
  final Uri? canonicalExternalUrl;
}

typedef SourceItemCallback = Future<void> Function(SourceSidebarItem item);
typedef SourceItemsCallback =
    Future<void> Function(List<SourceSidebarItem> items);

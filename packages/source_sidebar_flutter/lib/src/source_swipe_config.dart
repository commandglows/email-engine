import 'package:flutter/foundation.dart';
import 'package:shipglows_swipe_actions/shipglows_swipe_actions.dart';

/// Actions a source row can expose through swipe, long press or modified click.
enum SourceSwipeAction { markSeen, archive, delete }

/// Opt-in gesture setup for source rows, backed by `shipglows_swipe_actions`.
///
/// Only actions whose callback is provided on the sidebar are shown.
/// [startActions] appear when swiping toward the start edge, [endActions]
/// toward the end edge. Labels are host-supplied for localization.
@immutable
class SourceSwipeConfig {
  const SourceSwipeConfig({
    this.startActions = const [SourceSwipeAction.archive],
    this.endActions = const [
      SourceSwipeAction.markSeen,
      SourceSwipeAction.delete,
    ],
    this.labels = const {},
    this.revealLabel = 'Message actions',
    this.closeLabel = 'Close',
    this.direct = false,
    this.threshold = .65,
    this.haptics = true,
    this.longPressSide = SwipeActionSide.end,
    this.clickBindings = const [
      SwipeClickBinding(side: SwipeActionSide.end, alt: true),
      SwipeClickBinding(side: SwipeActionSide.start, alt: true, shift: true),
    ],
  });

  final List<SourceSwipeAction> startActions, endActions;

  /// Overrides keyed by [SourceSwipeAction.name]; English defaults otherwise.
  final Map<String, String> labels;
  final String revealLabel, closeLabel;

  /// Whether a long swipe runs the first action instead of only revealing.
  final bool direct;
  final double threshold;
  final bool haptics;
  final SwipeActionSide? longPressSide;
  final List<SwipeClickBinding> clickBindings;
}

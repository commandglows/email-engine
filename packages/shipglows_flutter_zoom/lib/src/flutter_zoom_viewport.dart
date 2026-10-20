import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keeps a Flutter application surface filled while scaling its complete UI.
class FlutterZoomViewport extends StatefulWidget {
  const FlutterZoomViewport({
    super.key,
    required this.child,
    this.initialZoom = 1,
    this.minimumZoom = 0.75,
    this.maximumZoom = 1.5,
    this.zoomStep = 0.1,
    this.resetShortcuts = const [
      SingleActivator(LogicalKeyboardKey.digit0, control: true),
      SingleActivator(LogicalKeyboardKey.digit0, meta: true),
    ],
    this.onZoomChanged,
  }) : assert(minimumZoom > 0),
       assert(maximumZoom >= minimumZoom),
       assert(initialZoom >= minimumZoom && initialZoom <= maximumZoom),
       assert(zoomStep > 0);

  final Widget child;
  final double initialZoom;
  final double minimumZoom;
  final double maximumZoom;
  final double zoomStep;
  final List<ShortcutActivator> resetShortcuts;
  final ValueChanged<double>? onZoomChanged;

  @override
  State<FlutterZoomViewport> createState() => _FlutterZoomViewportState();
}

class _FlutterZoomViewportState extends State<FlutterZoomViewport> {
  late double _zoom;
  ui.PointerDataPacketCallback? _forwardPointerData;

  @override
  void initState() {
    super.initState();
    _zoom = widget.initialZoom;
    // Scrollables, InteractiveViewers and custom wheel listeners sit deeper
    // in the hit-test path and would claim Ctrl+wheel first: the zoom
    // gesture is taken from the raw pointer data before any widget sees it.
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    _forwardPointerData = dispatcher.onPointerDataPacket;
    dispatcher.onPointerDataPacket = _interceptPointerData;
  }

  @override
  void dispose() {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    if (dispatcher.onPointerDataPacket == _interceptPointerData) {
      dispatcher.onPointerDataPacket = _forwardPointerData;
    }
    super.dispose();
  }

  static bool get _isZoomModifierPressed =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  void _interceptPointerData(ui.PointerDataPacket packet) {
    if (!_isZoomModifierPressed) {
      _forwardPointerData?.call(packet);
      return;
    }
    final kept = <ui.PointerData>[];
    for (final data in packet.data) {
      if (data.signalKind == ui.PointerSignalKind.scroll) {
        if (data.scrollDeltaY != 0) {
          _setZoom(_zoom + (data.scrollDeltaY < 0 ? 1 : -1) * widget.zoomStep);
        }
      } else {
        kept.add(data);
      }
    }
    if (kept.isNotEmpty) {
      _forwardPointerData?.call(ui.PointerDataPacket(data: kept));
    }
  }

  @override
  void didUpdateWidget(FlutterZoomViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    _zoom = _zoom.clamp(widget.minimumZoom, widget.maximumZoom).toDouble();
  }

  void _setZoom(double value) {
    final next = value.clamp(widget.minimumZoom, widget.maximumZoom).toDouble();
    if (next == _zoom) return;
    setState(() => _zoom = next);
    widget.onZoomChanged?.call(next);
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    final isModifiedScroll =
        event is PointerScrollEvent && _isZoomModifierPressed;
    if (!isModifiedScroll && event is! PointerScaleEvent) return;

    GestureBinding.instance.pointerSignalResolver.register(event, (
      resolvedEvent,
    ) {
      final double direction;
      if (resolvedEvent is PointerScaleEvent) {
        if (resolvedEvent.scale == 1) return;
        direction = resolvedEvent.scale > 1 ? 1 : -1;
      } else {
        final scrollEvent = resolvedEvent as PointerScrollEvent;
        if (scrollEvent.scrollDelta.dy == 0) return;
        direction = scrollEvent.scrollDelta.dy < 0 ? 1 : -1;
      }
      _setZoom(_zoom + direction * widget.zoomStep);
    });
  }

  /// Reports the logical size the zoomed content really has, so that
  /// breakpoints read through MediaQuery follow the zoom.
  Widget _zoomedMediaQuery(BuildContext context, Widget child) {
    final media = MediaQuery.maybeOf(context);
    if (media == null || _zoom == 1) return child;
    return MediaQuery(
      data: media.copyWith(
        size: media.size / _zoom,
        // Images keep decoding at the real physical resolution.
        devicePixelRatio: media.devicePixelRatio * _zoom,
        padding: media.padding / _zoom,
        viewPadding: media.viewPadding / _zoom,
        viewInsets: media.viewInsets / _zoom,
        systemGestureInsets: media.systemGestureInsets / _zoom,
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final shortcuts = <ShortcutActivator, Intent>{
      for (final shortcut in widget.resetShortcuts)
        shortcut: const _ResetZoomIntent(),
    };
    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: {
          _ResetZoomIntent: CallbackAction<_ResetZoomIntent>(
            onInvoke: (_) => _setZoom(widget.initialZoom),
          ),
        },
        child: Focus(
          autofocus: true,
          child: Listener(
            onPointerSignal: _handlePointerSignal,
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (!constraints.hasBoundedWidth ||
                    !constraints.hasBoundedHeight) {
                  return widget.child;
                }
                return SizedBox(
                  key: const ValueKey('shipglows-flutter-zoom-viewport'),
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: ClipRect(
                    child: Transform.scale(
                      alignment: Alignment.topLeft,
                      scale: _zoom,
                      child: FractionallySizedBox(
                        alignment: Alignment.topLeft,
                        widthFactor: 1 / _zoom,
                        heightFactor: 1 / _zoom,
                        child: SizedBox.expand(
                          key: const ValueKey('shipglows-flutter-zoom-content'),
                          child: _zoomedMediaQuery(context, widget.child),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ResetZoomIntent extends Intent {
  const _ResetZoomIntent();
}

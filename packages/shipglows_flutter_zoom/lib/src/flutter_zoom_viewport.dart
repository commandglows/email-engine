import 'dart:async';
import 'dart:math' as math;
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
    this.resetZoom,
    this.minimumZoom = 0.75,
    this.maximumZoom = 1.5,
    this.zoomStep = 0.1,
    this.resetShortcuts = const [
      SingleActivator(LogicalKeyboardKey.digit0, control: true),
      SingleActivator(LogicalKeyboardKey.digit0, meta: true),
    ],
    this.reflowDelay = const Duration(milliseconds: 150),
    this.onZoomChanged,
  }) : assert(minimumZoom > 0),
       assert(maximumZoom >= minimumZoom),
       assert(initialZoom >= minimumZoom && initialZoom <= maximumZoom),
       assert(
         resetZoom == null ||
             (resetZoom >= minimumZoom && resetZoom <= maximumZoom),
       ),
       assert(zoomStep > 0);

  final Widget child;
  final double initialZoom;

  /// Zoom restored by the reset shortcuts; defaults to [initialZoom]. Set it
  /// to 1 when [initialZoom] comes from a saved session.
  final double? resetZoom;
  final double minimumZoom;
  final double maximumZoom;
  final double zoomStep;
  final List<ShortcutActivator> resetShortcuts;

  /// How long the zoom must stay still before the content is laid out again
  /// at the new size. Until then each step only rescales what is painted,
  /// so the wheel answers at once even when the app is costly to lay out.
  final Duration reflowDelay;
  final ValueChanged<double>? onZoomChanged;

  @override
  State<FlutterZoomViewport> createState() => _FlutterZoomViewportState();
}

class _FlutterZoomViewportState extends State<FlutterZoomViewport> {
  /// Zoom painted on screen, updated on every step.
  late double _zoom;

  /// Zoom the content is laid out for; catches up with [_zoom] once the
  /// gesture pauses for [FlutterZoomViewport.reflowDelay].
  late double _layoutZoom;
  Timer? _reflowTimer;
  ui.PointerDataPacketCallback? _forwardPointerData;

  @override
  void initState() {
    super.initState();
    _zoom = widget.initialZoom;
    _layoutZoom = _zoom;
    // Scrollables, InteractiveViewers and custom wheel listeners sit deeper
    // in the hit-test path and would claim Ctrl+wheel first: the zoom
    // gesture is taken from the raw pointer data before any widget sees it.
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    _forwardPointerData = dispatcher.onPointerDataPacket;
    dispatcher.onPointerDataPacket = _interceptPointerData;
  }

  @override
  void dispose() {
    _reflowTimer?.cancel();
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    if (dispatcher.onPointerDataPacket == _interceptPointerData) {
      dispatcher.onPointerDataPacket = _forwardPointerData;
    }
    super.dispose();
  }

  static bool get _isZoomModifierPressed =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  /// Scroll delta of one wheel notch as the engine reports it: Windows sends
  /// `lines per notch × 100 / 3` (100 with the default 3 lines), like
  /// Chromium. High-resolution wheels and non-precision touchpads send
  /// fractions of it.
  static const double _wheelNotchDelta = 100;

  /// How far a trackpad pinch must stray from scale 1 before it zooms, so a
  /// two-finger scroll never nudges the zoom.
  static const double _pinchThreshold = 0.02;

  /// Pinches in progress, by pointer device.
  final Map<int, _Pinch> _pinches = {};

  /// Zoom change for a Ctrl+wheel delta: [FlutterZoomViewport.zoomStep] per
  /// full notch, proportionally less for finer deltas, at most one step per
  /// event so that platforms with larger notches still move one step.
  double _wheelZoomDelta(double scrollDeltaY) =>
      (-scrollDeltaY / _wheelNotchDelta).clamp(-1.0, 1.0) * widget.zoomStep;

  /// The web engine turns Ctrl+wheel and trackpad pinches into scale signals
  /// of `exp(-deltaY / 200)`; this gives that delta back.
  static double _scaleSignalDelta(double scale) => -200 * math.log(scale);

  void _interceptPointerData(ui.PointerDataPacket packet) {
    final modifierPressed = _isZoomModifierPressed;
    List<ui.PointerData>? kept;
    for (var i = 0; i < packet.data.length; i++) {
      final data = packet.data[i];
      final replacement = _takeZoomGesture(data, modifierPressed);
      if (identical(replacement, data) && kept == null) continue;
      kept ??= packet.data.sublist(0, i);
      if (replacement != null) kept.add(replacement);
    }
    if (kept == null) {
      _forwardPointerData?.call(packet);
    } else if (kept.isNotEmpty) {
      _forwardPointerData?.call(ui.PointerDataPacket(data: kept));
    }
  }

  /// Zooms for [data] when it is a zoom gesture. Returns what the widgets
  /// below still receive: [data] itself, a copy without the pinch, or null
  /// when the zoom consumed it.
  ui.PointerData? _takeZoomGesture(ui.PointerData data, bool modifierPressed) {
    switch (data.signalKind) {
      case ui.PointerSignalKind.scroll when modifierPressed:
        if (data.scrollDeltaY != 0) {
          _setZoom(_zoom + _wheelZoomDelta(data.scrollDeltaY));
        }
        return null;
      case ui.PointerSignalKind.scale:
        if (data.scale > 0 && data.scale != 1) {
          _setZoom(_zoom + _wheelZoomDelta(_scaleSignalDelta(data.scale)));
        }
        return null;
      default:
        break;
    }
    switch (data.change) {
      case ui.PointerChange.panZoomStart:
        _pinches[data.device] = _Pinch();
        return data;
      case ui.PointerChange.panZoomUpdate:
        return _pinchUpdate(data);
      case ui.PointerChange.panZoomEnd:
        _pinches.remove(data.device);
        return data;
      default:
        return data;
    }
  }

  /// Trackpad pinches (Windows precision touchpads, macOS) arrive as pan/zoom
  /// updates whose scale counts from the start of the gesture. The pinch
  /// zooms the app; the widgets below keep the two-finger pan but never see
  /// the scale, so an InteractiveViewer under the cursor cannot claim it.
  ui.PointerData _pinchUpdate(ui.PointerData data) {
    final pinch = _pinches[data.device];
    if (data.scale == 1 && !(pinch?.zooming ?? false)) return data;
    if (pinch == null || data.scale <= 0) return _withPan(data, scale: 1);
    if (!pinch.zooming && (data.scale - 1).abs() >= _pinchThreshold) {
      pinch
        ..zooming = true
        ..startZoom = _zoom
        ..startScale = data.scale
        ..panX = data.panX
        ..panY = data.panY;
    }
    if (!pinch.zooming) return _withPan(data, scale: 1);
    _setZoom(pinch.startZoom * data.scale / pinch.startScale);
    // The content holds still while it is being pinched.
    return _withPan(data, scale: 1, panX: pinch.panX, panY: pinch.panY);
  }

  static ui.PointerData _withPan(
    ui.PointerData data, {
    required double scale,
    double? panX,
    double? panY,
  }) {
    final frozen = panX != null;
    return ui.PointerData(
      viewId: data.viewId,
      embedderId: data.embedderId,
      timeStamp: data.timeStamp,
      change: data.change,
      kind: data.kind,
      signalKind: data.signalKind,
      device: data.device,
      pointerIdentifier: data.pointerIdentifier,
      physicalX: data.physicalX,
      physicalY: data.physicalY,
      physicalDeltaX: data.physicalDeltaX,
      physicalDeltaY: data.physicalDeltaY,
      buttons: data.buttons,
      obscured: data.obscured,
      synthesized: data.synthesized,
      pressure: data.pressure,
      pressureMin: data.pressureMin,
      pressureMax: data.pressureMax,
      distance: data.distance,
      distanceMax: data.distanceMax,
      size: data.size,
      radiusMajor: data.radiusMajor,
      radiusMinor: data.radiusMinor,
      radiusMin: data.radiusMin,
      radiusMax: data.radiusMax,
      orientation: data.orientation,
      tilt: data.tilt,
      platformData: data.platformData,
      scrollDeltaX: data.scrollDeltaX,
      scrollDeltaY: data.scrollDeltaY,
      panX: panX ?? data.panX,
      panY: panY ?? data.panY,
      panDeltaX: frozen ? 0 : data.panDeltaX,
      panDeltaY: frozen ? 0 : data.panDeltaY,
      scale: scale,
      rotation: data.rotation,
    );
  }

  @override
  void didUpdateWidget(FlutterZoomViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    _zoom = _zoom.clamp(widget.minimumZoom, widget.maximumZoom).toDouble();
    _reflowTimer?.cancel();
    _layoutZoom = _zoom;
  }

  void _setZoom(double value, {bool reflowNow = false}) {
    // Rounded so that fractional wheel deltas do not pile up float noise.
    final next =
        (value.clamp(widget.minimumZoom, widget.maximumZoom) * 1e6)
            .roundToDouble() /
        1e6;
    if (next == _zoom) return;
    _reflowTimer?.cancel();
    final reflow = reflowNow || widget.reflowDelay == Duration.zero;
    setState(() {
      _zoom = next;
      if (reflow) _layoutZoom = next;
    });
    if (!reflow && _layoutZoom != next) {
      _reflowTimer = Timer(widget.reflowDelay, _reflow);
    }
    widget.onZoomChanged?.call(next);
  }

  void _reflow() {
    if (!mounted || _layoutZoom == _zoom) return;
    setState(() => _layoutZoom = _zoom);
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    final isModifiedScroll =
        event is PointerScrollEvent && _isZoomModifierPressed;
    if (!isModifiedScroll && event is! PointerScaleEvent) return;

    GestureBinding.instance.pointerSignalResolver.register(event, (
      resolvedEvent,
    ) {
      final double scrollDeltaY;
      if (resolvedEvent is PointerScaleEvent) {
        if (resolvedEvent.scale <= 0 || resolvedEvent.scale == 1) return;
        scrollDeltaY = _scaleSignalDelta(resolvedEvent.scale);
      } else {
        scrollDeltaY = (resolvedEvent as PointerScrollEvent).scrollDelta.dy;
        if (scrollDeltaY == 0) return;
      }
      _setZoom(_zoom + _wheelZoomDelta(scrollDeltaY));
    });
  }

  /// Reports the logical size the zoomed content really has, so that
  /// breakpoints read through MediaQuery follow the zoom.
  Widget _zoomedMediaQuery(BuildContext context, Widget child) {
    final media = MediaQuery.maybeOf(context);
    final zoom = _layoutZoom;
    if (media == null || zoom == 1) return child;
    return MediaQuery(
      data: media.copyWith(
        size: media.size / zoom,
        // Images keep decoding at the real physical resolution.
        devicePixelRatio: media.devicePixelRatio * zoom,
        padding: media.padding / zoom,
        viewPadding: media.viewPadding / zoom,
        viewInsets: media.viewInsets / zoom,
        systemGestureInsets: media.systemGestureInsets / zoom,
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
            onInvoke: (_) => _setZoom(
              widget.resetZoom ?? widget.initialZoom,
              reflowNow: true,
            ),
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
                    // The content size is set above the transform: a box
                    // under it would keep the viewport size and, zoomed out,
                    // reject hits on the right and bottom bands of the screen.
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: constraints.maxWidth / _layoutZoom,
                      maxWidth: constraints.maxWidth / _layoutZoom,
                      minHeight: constraints.maxHeight / _layoutZoom,
                      maxHeight: constraints.maxHeight / _layoutZoom,
                      // While the wheel turns only this transform changes:
                      // the content keeps its layout and its own layer, and
                      // is laid out again once at the final size (see
                      // reflowDelay).
                      child: Transform.scale(
                        alignment: Alignment.topLeft,
                        scale: _zoom,
                        child: RepaintBoundary(
                          child: SizedBox.expand(
                            key: const ValueKey(
                              'shipglows-flutter-zoom-content',
                            ),
                            child: _zoomedMediaQuery(context, widget.child),
                          ),
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

class _Pinch {
  bool zooming = false;
  double startZoom = 1;
  double startScale = 1;
  double panX = 0;
  double panY = 0;
}

class _ResetZoomIntent extends Intent {
  const _ResetZoomIntent();
}

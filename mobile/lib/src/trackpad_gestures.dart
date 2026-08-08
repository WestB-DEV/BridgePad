import 'dart:async';

import 'package:flutter/gestures.dart';

typedef BridgepadGuard = Future<void> Function(Future<void> Function() action);
typedef BridgepadPointerMove = Future<void> Function(int dx, int dy);
typedef BridgepadScroll = Future<void> Function(int amount);
typedef BridgepadPointerButton = Future<void> Function(int mask, bool down);

class BridgepadTrackpadGestures {
  BridgepadTrackpadGestures(
    this._enabled,
    this._guard,
    this._onMove,
    this._onScroll,
    this._onButton,
  );

  static const _pointerGain = 2.4;
  static const _scrollPixelsPerStep = 6.0;
  static const _flushInterval = Duration(milliseconds: 33);
  static const _longPressDelay = Duration(milliseconds: 450);
  static const _tapSlop = 12.0;

  final _positions = <int, Offset>{};
  late bool _enabled;
  late BridgepadGuard _guard;
  late BridgepadPointerMove _onMove;
  late BridgepadScroll _onScroll;
  late BridgepadPointerButton _onButton;
  Timer? _flushTimer;
  Timer? _longPressTimer;
  int? _primaryPointer;
  Offset? _primaryDownPosition;
  Offset _pendingPointer = Offset.zero;
  double _pendingScrollPixels = 0;
  bool _moved = false;
  bool _hadMultiplePointers = false;
  bool _dragging = false;
  bool _disposed = false;

  Offset get _centroid {
    if (_positions.isEmpty) return Offset.zero;
    var total = Offset.zero;
    for (final position in _positions.values) {
      total += position;
    }
    return total / _positions.length.toDouble();
  }

  void update({
    required bool enabled,
    required BridgepadGuard guard,
    required BridgepadPointerMove onMove,
    required BridgepadScroll onScroll,
    required BridgepadPointerButton onButton,
  }) {
    final wasEnabled = _enabled;
    _enabled = enabled;
    _guard = guard;
    _onMove = onMove;
    _onScroll = onScroll;
    _onButton = onButton;
    if (wasEnabled && !enabled) _cancelActiveGesture();
  }

  void pointerDown(PointerDownEvent event) {
    _positions[event.pointer] = event.localPosition;
    if (_positions.length == 1) {
      _primaryPointer = event.pointer;
      _primaryDownPosition = event.localPosition;
      _moved = false;
      _hadMultiplePointers = false;
      _longPressTimer = Timer(_longPressDelay, () {
        if (_disposed || !_enabled || _positions.length != 1 || _moved) return;
        _dragging = true;
        _guard(() => _onButton(1, true));
      });
      return;
    }

    _hadMultiplePointers = true;
    _pendingPointer = Offset.zero;
    _longPressTimer?.cancel();
    _longPressTimer = null;
    if (_dragging) {
      _dragging = false;
      _guard(() => _onButton(1, false));
    }
  }

  void pointerMove(PointerMoveEvent event) {
    if (!_positions.containsKey(event.pointer)) return;
    final previousCentroid = _centroid;
    _positions[event.pointer] = event.localPosition;
    final centroidDelta = _centroid - previousCentroid;

    final downPosition = _primaryDownPosition;
    if (downPosition != null &&
        (event.localPosition - downPosition).distance > _tapSlop) {
      _moved = true;
      _longPressTimer?.cancel();
      _longPressTimer = null;
    }

    if (_positions.length >= 2) {
      _hadMultiplePointers = true;
      _pendingPointer = Offset.zero;
      _pendingScrollPixels += -centroidDelta.dy;
      _scheduleFlush();
    } else if (!_hadMultiplePointers) {
      _pendingPointer += centroidDelta * _pointerGain;
      _scheduleFlush();
    }
  }

  void pointerUp(PointerUpEvent event) {
    final primaryReleased = event.pointer == _primaryPointer;
    _positions.remove(event.pointer);
    _longPressTimer?.cancel();
    _longPressTimer = null;

    if (primaryReleased && _dragging) {
      _dragging = false;
      _guard(() => _onButton(1, false));
    } else if (primaryReleased &&
        !_moved &&
        !_hadMultiplePointers &&
        _positions.isEmpty) {
      _guard(() async {
        await _onButton(1, true);
        await _onButton(1, false);
      });
    }

    if (_positions.isEmpty) _resetGesture();
  }

  void pointerCancel(PointerCancelEvent event) {
    _positions.remove(event.pointer);
    if (_dragging) {
      _dragging = false;
      _guard(() => _onButton(1, false));
    }
    if (_positions.isEmpty) _resetGesture();
  }

  void _scheduleFlush() {
    _flushTimer ??= Timer(_flushInterval, _flush);
  }

  void _flush() {
    _flushTimer = null;
    if (_disposed || !_enabled) return;
    final dx = _pendingPointer.dx.truncate().clamp(-127, 127).toInt();
    final dy = _pendingPointer.dy.truncate().clamp(-127, 127).toInt();
    if (dx != 0 || dy != 0) {
      _pendingPointer -= Offset(dx.toDouble(), dy.toDouble());
      _guard(() => _onMove(dx, dy));
    }

    final scroll = (_pendingScrollPixels / _scrollPixelsPerStep)
        .truncate()
        .clamp(-127, 127)
        .toInt();
    if (scroll != 0) {
      _pendingScrollPixels -= scroll * _scrollPixelsPerStep;
      _guard(() => _onScroll(scroll));
    }

    if (_pendingPointer.dx.abs() >= 1 ||
        _pendingPointer.dy.abs() >= 1 ||
        _pendingScrollPixels.abs() >= _scrollPixelsPerStep) {
      _scheduleFlush();
    }
  }

  void _cancelActiveGesture() {
    if (_dragging) _guard(() => _onButton(1, false));
    _positions.clear();
    _pendingPointer = Offset.zero;
    _pendingScrollPixels = 0;
    _resetGesture();
  }

  void _resetGesture() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _primaryPointer = null;
    _primaryDownPosition = null;
    _moved = false;
    _hadMultiplePointers = false;
    _dragging = false;
  }

  void dispose() {
    _disposed = true;
    _flushTimer?.cancel();
    _longPressTimer?.cancel();
    if (_dragging) unawaited(_onButton(1, false));
  }
}

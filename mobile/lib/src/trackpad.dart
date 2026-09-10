import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import 'session_controller.dart';

/// Keeps sub-pixel movement between HID reports rather than rounding each event.
class TrackpadMotion {
  double _x = 0;
  double _y = 0;
  double get pendingDistance => _x.abs() + _y.abs();

  void add(double x, double y) {
    _x += x;
    _y += y;
  }

  void clear() {
    _x = 0;
    _y = 0;
  }

  List<(int, int)> take() {
    // Compensate for floating point sums such as ten 0.3-pixel samples.
    int whole(double v) => (v + (v.isNegative ? -1e-9 : 1e-9)).truncate();
    var x = whole(_x);
    var y = whole(_y);
    _x -= x;
    _y -= y;
    final result = <(int, int)>[];
    while (x != 0 || y != 0) {
      final dx = x.clamp(-127, 127);
      final dy = y.clamp(-127, 127);
      result.add((dx, dy));
      x -= dx;
      y -= dy;
    }
    return result;
  }
}

class _PadCommand {
  _PadCommand(this.run, this.created);
  final Future<void> Function() run;
  final Duration created;
}

/// Raw-pointer recognizer and bounded, ordered output queue. No gesture arena
/// competes with the trackpad, and movement is coalesced, never throttled away.
class TrackpadController extends ChangeNotifier {
  TrackpadController({
    required this.movePointer,
    required this.button,
    required this.scroll,
    required this.onFailure,
    this.now,
  });

  final Future<void> Function(int, int) movePointer;
  final Future<void> Function(int, bool) button;
  final Future<void> Function(int) scroll;
  final void Function(Object) onFailure;
  final Duration Function()? now;
  final _motion = TrackpadMotion();
  final _wheel = TrackpadMotion();
  final _points = <int, Offset>{};
  final _queue = Queue<_PadCommand>();
  final _clock = Stopwatch()..start();
  Timer? _cadence;
  Timer? _hold;
  bool _busy = false;
  bool _disposed = false;
  bool _multi = false;
  bool _moved = false;
  bool _secondTap = false;
  bool _gestureDrag = false;
  bool _latchedDrag = false;
  bool _failed = false;
  Offset _origin = Offset.zero;
  Offset? _lastTapPosition;
  Duration? _lastTap;
  Duration? _downAt;
  int _generation = 0;
  double sensitivity = 1;
  bool precision = false;
  bool naturalScroll = false;
  bool get dragging => _latchedDrag || _gestureDrag;
  Duration get _now => now?.call() ?? _clock.elapsed;

  void down(int pointer, Offset position) {
    if (_disposed || _failed) return;
    _points[pointer] = position;
    if (_points.length == 1) {
      _origin = position;
      _downAt = _now;
      _moved = false;
      _multi = false;
      _secondTap =
          _lastTap != null &&
          _now - _lastTap! < const Duration(milliseconds: 300) &&
          (position - _lastTapPosition!).distance < 24;
      if (_secondTap && !dragging) {
        _hold = Timer(const Duration(milliseconds: 180), _beginGestureDrag);
      }
    } else {
      _multi = true;
      _hold?.cancel();
      _lastTap = null;
      _flush();
      if (_gestureDrag) {
        _gestureDrag = false;
        _enqueue(() => button(1, false));
        notifyListeners();
      }
    }
  }

  void move(int pointer, Offset position) {
    final previous = _points[pointer];
    if (_disposed || _failed || previous == null) return;
    _points[pointer] = position;
    final delta = position - previous;
    if (_multi) {
      if (_points.length >= 2) {
        // Each finger contributes its fraction of centroid movement.
        _wheel.add(
          0,
          delta.dy / _points.length / 18 * (naturalScroll ? 1 : -1),
        );
      }
    } else {
      if ((position - _origin).distance > 4) {
        _moved = true;
        if (_secondTap && !dragging) _beginGestureDrag();
      }
      final scale = sensitivity * (precision ? .35 : 1);
      _motion.add(delta.dx * scale, delta.dy * scale);
    }
    if (_motion.pendingDistance + _wheel.pendingDistance > 4096) {
      _fail(
        StateError(
          'Pointer backlog exceeded its safe limit; input was released.',
        ),
      );
      return;
    }
    _cadence ??= Timer.periodic(
      const Duration(milliseconds: 33),
      (_) => _flush(),
    );
  }

  void up(int pointer) {
    if (!_points.containsKey(pointer)) return;
    _points.remove(pointer);
    _hold?.cancel();
    if (_points.isNotEmpty) return;
    _flush();
    if (_gestureDrag) {
      _gestureDrag = false;
      _enqueue(() => button(1, false));
      _lastTap = null;
      notifyListeners();
    } else if (!_multi &&
        !_moved &&
        !_latchedDrag &&
        _downAt != null &&
        _now - _downAt! < const Duration(milliseconds: 300)) {
      click(1);
      _lastTap = _now;
      _lastTapPosition = _origin;
    } else {
      _lastTap = null;
    }
    _cadence?.cancel();
    _cadence = null;
  }

  void _beginGestureDrag() {
    _hold?.cancel();
    if (_disposed || _failed || _multi || _points.length != 1 || dragging) {
      return;
    }
    _gestureDrag = true;
    _enqueue(() => button(1, true));
    notifyListeners();
  }

  void click(int mask) {
    if (_disposed || _failed || (mask == 1 && dragging)) return;
    _flush();
    _enqueue(() async {
      await button(mask, true);
      await button(mask, false);
    });
  }

  void toggleDrag() {
    if (_disposed || _failed) return;
    _flush();
    _latchedDrag = !dragging;
    _gestureDrag = false;
    final pressed = _latchedDrag;
    _enqueue(() => button(1, pressed));
    notifyListeners();
  }

  void _flush() {
    if (_disposed || _failed) return;
    for (final delta in _motion.take()) {
      _enqueue(() => movePointer(delta.$1, delta.$2));
    }
    for (final delta in _wheel.take()) {
      if (delta.$2 != 0) _enqueue(() => scroll(delta.$2));
    }
  }

  void _enqueue(Future<void> Function() operation) {
    if (_disposed || _failed) return;
    if (_queue.length >= 64) {
      _fail(StateError('Pointer delivery is too slow; input was released.'));
      return;
    }
    _queue.add(_PadCommand(operation, _now));
    unawaited(_pump());
  }

  Future<void> _pump() async {
    if (_busy) return;
    _busy = true;
    final generation = _generation;
    try {
      while (!_disposed &&
          !_failed &&
          _queue.isNotEmpty &&
          generation == _generation) {
        final command = _queue.removeFirst();
        if (_now - command.created > const Duration(milliseconds: 500)) {
          throw StateError('Pointer delivery fell behind; input was released.');
        }
        await command.run();
      }
    } catch (error) {
      if (!_disposed && generation == _generation) _fail(error);
    } finally {
      _busy = false;
      if (!_disposed && !_failed && _queue.isNotEmpty) unawaited(_pump());
    }
  }

  void _fail(Object error) {
    reset();
    _failed = true;
    onFailure(error);
  }

  /// Cancellation discards untransmitted movement before releasing any drag.
  void cancel() {
    final release = dragging;
    reset();
    if (release) _enqueue(() => button(1, false));
  }

  /// Used when the session becomes unarmed; session safety owns host release.
  void reset() {
    _generation++;
    _queue.clear();
    _motion.clear();
    _wheel.clear();
    _points.clear();
    _cadence?.cancel();
    _cadence = null;
    _hold?.cancel();
    _gestureDrag = _latchedDrag = _multi = _secondTap = _failed = false;
    _lastTap = null;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    reset();
    _clock.stop();
    super.dispose();
  }
}

class BridgepadTrackpad extends StatefulWidget {
  const BridgepadTrackpad({
    super.key,
    required this.session,
    required this.guard,
    this.enabled = true,
    this.onBeforeInput,
  });
  final BridgepadSessionController session;
  final Future<void> Function(Future<void> Function()) guard;
  final bool enabled;
  final VoidCallback? onBeforeInput;

  @override
  State<BridgepadTrackpad> createState() => _BridgepadTrackpadState();
}

class _BridgepadTrackpadState extends State<BridgepadTrackpad>
    with WidgetsBindingObserver {
  late TrackpadController _pad;

  @override
  void initState() {
    super.initState();
    _createPad();
    widget.session.addListener(_sessionChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  void _createPad() {
    _pad = TrackpadController(
      movePointer: (x, y) => widget.session.pointerMove(x, y),
      button: (mask, pressed) => widget.session.pointerButton(mask, pressed),
      scroll: (amount) => widget.session.scroll(amount),
      onFailure: (error) {
        // Safety release bypasses the pointer queue; never replay failed input.
        unawaited(
          widget.guard(() async {
            await widget.session.emergencyRelease();
            throw error;
          }),
        );
      },
    )..addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _sessionChanged() {
    if (!widget.session.canSend) _pad.reset();
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant BridgepadTrackpad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_sessionChanged);
      _pad.removeListener(_changed);
      _pad.dispose();
      _createPad();
      widget.session.addListener(_sessionChanged);
    }
    if (oldWidget.enabled && !widget.enabled) _pad.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _pad.cancel();
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_sessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    _pad.removeListener(_changed);
    // Host lifecycle safety remains owned by the session/home controller.
    _pad.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.session.canSend && widget.enabled;
    final colors = Theme.of(context).colorScheme;
    return TextFieldTapRegion(
      child: Column(
        children: [
          Expanded(
            child: Semantics(
              label:
                  'Trackpad. One finger moves, tap clicks, two fingers scroll. Use the buttons below for dragging and right click.',
              child: Listener(
                key: const Key('trackpad-surface'),
                behavior: HitTestBehavior.opaque,
                onPointerDown: enabled
                    ? (e) {
                        widget.onBeforeInput?.call();
                        _pad.down(e.pointer, e.localPosition);
                      }
                    : null,
                onPointerMove: enabled
                    ? (e) => _pad.move(e.pointer, e.localPosition)
                    : null,
                onPointerUp: enabled ? (e) => _pad.up(e.pointer) : null,
                onPointerCancel: (_) => _pad.cancel(),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _pad.dragging
                          ? colors.primary
                          : colors.outlineVariant,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      enabled
                          ? (_pad.precision
                                ? 'TRACKPAD · PRECISION'
                                : 'TRACKPAD')
                          : (widget.session.canSend
                                ? 'TRACKPAD · SENDING'
                                : 'TRACKPAD · DISARMED'),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: enabled
                        ? () {
                            widget.onBeforeInput?.call();
                            _pad.click(1);
                          }
                        : null,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    child: const Text('Left'),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: enabled
                        ? () {
                            widget.onBeforeInput?.call();
                            _pad.click(2);
                          }
                        : null,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    child: const Text('Right'),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: enabled
                        ? () {
                            widget.onBeforeInput?.call();
                            _pad.toggleDrag();
                          }
                        : null,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      backgroundColor: _pad.dragging
                          ? colors.primaryContainer
                          : null,
                    ),
                    child: Text(_pad.dragging ? 'Drag ON' : 'Drag'),
                  ),
                ),
                PopupMenuButton<void>(
                  tooltip: 'Pointer settings',
                  requestFocus: false,
                  icon: const Icon(Icons.tune),
                  itemBuilder: (context) => [
                    PopupMenuItem<void>(
                      enabled: false,
                      child: StatefulBuilder(
                        builder: (context, update) => SizedBox(
                          width: 260,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Sensitivity ${_pad.sensitivity.toStringAsFixed(2)}×',
                              ),
                              Slider(
                                value: _pad.sensitivity,
                                min: .25,
                                max: 2.5,
                                label: _pad.sensitivity.toStringAsFixed(2),
                                onChanged: (v) =>
                                    update(() => _pad.sensitivity = v),
                              ),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Precision'),
                                value: _pad.precision,
                                onChanged: (v) {
                                  update(() => _pad.precision = v);
                                  _changed();
                                },
                              ),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Natural scroll'),
                                value: _pad.naturalScroll,
                                onChanged: (v) =>
                                    update(() => _pad.naturalScroll = v),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

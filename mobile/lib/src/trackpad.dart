import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'trackpad_gestures.dart';

class BridgepadTrackpad extends StatefulWidget {
  const BridgepadTrackpad({
    super.key,
    required this.enabled,
    required this.guard,
    required this.onMove,
    required this.onScroll,
    required this.onButton,
  });

  final bool enabled;
  final BridgepadGuard guard;
  final BridgepadPointerMove onMove;
  final BridgepadScroll onScroll;
  final BridgepadPointerButton onButton;

  @override
  State<BridgepadTrackpad> createState() => _BridgepadTrackpadState();
}

class _BridgepadTrackpadState extends State<BridgepadTrackpad> {
  late final BridgepadTrackpadGestures _gestures;

  @override
  void initState() {
    super.initState();
    _gestures = BridgepadTrackpadGestures(
      widget.enabled,
      widget.guard,
      widget.onMove,
      widget.onScroll,
      widget.onButton,
    );
  }

  @override
  void didUpdateWidget(covariant BridgepadTrackpad oldWidget) {
    super.didUpdateWidget(oldWidget);
    _gestures.update(
      enabled: widget.enabled,
      guard: widget.guard,
      onMove: widget.onMove,
      onScroll: widget.onScroll,
      onButton: widget.onButton,
    );
  }

  @override
  void dispose() {
    _gestures.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gestures = <Type, GestureRecognizerFactory>{};
    if (widget.enabled) {
      gestures[EagerGestureRecognizer] =
          GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
            EagerGestureRecognizer.new,
            (_) {},
          );
    }

    return Semantics(
      container: true,
      enabled: widget.enabled,
      label:
          'Mouse trackpad. Tap for left click, hold and move to drag, two fingers to scroll.',
      child: Container(
        height: 220,
        decoration: BoxDecoration(
          color: const Color(0xff20262b),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Expanded(
              child: RawGestureDetector(
                gestures: gestures,
                behavior: HitTestBehavior.opaque,
                child: Listener(
                  key: const Key('bridgepad-trackpad-surface'),
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: widget.enabled ? _gestures.pointerDown : null,
                  onPointerMove: widget.enabled ? _gestures.pointerMove : null,
                  onPointerUp: widget.enabled ? _gestures.pointerUp : null,
                  onPointerCancel: widget.enabled
                      ? _gestures.pointerCancel
                      : null,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.touch_app_outlined, size: 36),
                        SizedBox(height: 8),
                        Text('TRACKPAD', style: TextStyle(letterSpacing: 2)),
                        Text(
                          'fast cursor • two-finger scroll',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            SizedBox(
              height: 48,
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: widget.enabled
                      ? () => widget.guard(() async {
                          await widget.onButton(2, true);
                          await widget.onButton(2, false);
                        })
                      : null,
                  child: const Text('RIGHT CLICK'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

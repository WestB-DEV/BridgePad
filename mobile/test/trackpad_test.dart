import 'package:bridgepad/src/trackpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('trackpad owns vertical drags and applies useful pointer gain', (
    tester,
  ) async {
    final pageScroll = ScrollController();
    final movements = <Offset>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: pageScroll,
            children: [
              BridgepadTrackpad(
                enabled: true,
                guard: (action) => action(),
                onMove: (dx, dy) async =>
                    movements.add(Offset(dx.toDouble(), dy.toDouble())),
                onScroll: (_) async {},
                onButton: (_, _) async {},
              ),
              const SizedBox(height: 1200),
            ],
          ),
        ),
      ),
    );

    await tester.drag(
      find.byKey(const Key('bridgepad-trackpad-surface')),
      const Offset(0, -40),
    );
    await tester.pump(const Duration(milliseconds: 40));

    expect(pageScroll.offset, 0);
    expect(movements, isNotEmpty);
    expect(
      movements.map((movement) => movement.dy.abs()).reduce((a, b) => a + b),
      greaterThan(40),
    );
  });

  testWidgets('two fingers produce scroll without moving the pointer', (
    tester,
  ) async {
    final movements = <Offset>[];
    final scrolls = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BridgepadTrackpad(
            enabled: true,
            guard: (action) => action(),
            onMove: (dx, dy) async =>
                movements.add(Offset(dx.toDouble(), dy.toDouble())),
            onScroll: (amount) async => scrolls.add(amount),
            onButton: (_, _) async {},
          ),
        ),
      ),
    );

    final center = tester.getCenter(
      find.byKey(const Key('bridgepad-trackpad-surface')),
    );
    final first = await tester.createGesture(pointer: 1);
    final second = await tester.createGesture(pointer: 2);
    await first.down(center + const Offset(-24, 0));
    await second.down(center + const Offset(24, 0));
    await first.moveBy(const Offset(0, -30));
    await second.moveBy(const Offset(0, -30));
    await tester.pump(const Duration(milliseconds: 40));
    await first.up();
    await second.up();

    expect(scrolls, isNotEmpty);
    expect(scrolls.reduce((a, b) => a + b), greaterThan(0));
    expect(movements, isEmpty);
  });

  testWidgets('tap still sends a complete left click', (tester) async {
    final buttons = <(int, bool)>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BridgepadTrackpad(
            enabled: true,
            guard: (action) => action(),
            onMove: (_, _) async {},
            onScroll: (_) async {},
            onButton: (mask, down) async => buttons.add((mask, down)),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('bridgepad-trackpad-surface')));
    await tester.pump();

    expect(buttons, [(1, true), (1, false)]);
  });
}

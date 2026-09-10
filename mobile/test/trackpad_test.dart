import 'dart:async';

import 'package:bridgepad/src/trackpad.dart';
import 'package:bridgepad/src/demo_transport.dart';
import 'package:bridgepad/src/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'touch clicks retain editor focus while buttons remain keyboard reachable',
    (tester) async {
      final session = PadSession();
      final editorFocus = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: editorFocus),
                SizedBox(
                  height: 100,
                  child: BridgepadTrackpad(
                    session: session,
                    guard: (action) => action(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.tap(find.text('Left'));
      await tester.pump();
      expect(editorFocus.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(editorFocus.hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(session.buttons, [true, false, true, false]);
      await tester.pumpWidget(const SizedBox());
      editorFocus.dispose();
      session.dispose();
    },
  );
  testWidgets(
    'compact trackpad exposes buttons without overflow or scrolling',
    (tester) async {
      final session = PadSession();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 100,
              width: 320,
              child: BridgepadTrackpad(
                session: session,
                guard: (action) => action(),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Left'), findsOneWidget);
      expect(find.text('Right'), findsOneWidget);
      expect(find.text('Drag'), findsOneWidget);
      expect(find.byType(Scrollable), findsNothing);
      await tester.tap(find.text('Drag'));
      await tester.pump();
      expect(find.text('Drag ON'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 100,
              width: 320,
              child: BridgepadTrackpad(
                session: session,
                enabled: false,
                guard: (action) => action(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('TRACKPAD · SENDING'), findsOneWidget);
      expect(session.buttons, [true, false]);
      session.disable();
      await tester.pump();
      expect(find.text('Drag ON'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  test('fractional movement survives coalescing and splits without loss', () {
    final motion = TrackpadMotion();
    for (var i = 0; i < 10; i++) {
      motion.add(.3, -.3);
    }
    var chunks = motion.take();
    expect(chunks.fold<int>(0, (sum, p) => sum + p.$1), 3);
    expect(chunks.fold<int>(0, (sum, p) => sum + p.$2), -3);
    motion.add(300.5, -260.5);
    chunks = motion.take();
    expect(chunks.every((p) => p.$1.abs() <= 127 && p.$2.abs() <= 127), isTrue);
    expect(chunks.fold<int>(0, (sum, p) => sum + p.$1), 300);
    motion.add(.5, -.5);
    expect(motion.take(), [(1, -1)]);
  });

  testWidgets('two fingers scroll without clicking on either lift', (
    tester,
  ) async {
    final events = <String>[];
    final pad = makePad(events);
    pad.down(1, const Offset(10, 10));
    pad.down(2, const Offset(30, 10));
    pad.move(1, const Offset(10, 50));
    pad.move(2, const Offset(30, 50));
    pad.up(1);
    pad.up(2);
    await tester.pump(const Duration(milliseconds: 40));
    expect(events.where((e) => e.startsWith('button')), isEmpty);
    expect(events.any((e) => e.startsWith('scroll')), isTrue);
    pad.dispose();
  });

  testWidgets('tap and double tap hold have ordered button releases', (
    tester,
  ) async {
    final events = <String>[];
    final pad = makePad(events);
    pad.down(1, Offset.zero);
    pad.up(1);
    await tester.pump(const Duration(milliseconds: 50));
    pad.down(1, Offset.zero);
    await tester.pump(const Duration(milliseconds: 200));
    pad.move(1, const Offset(20, 0));
    pad.up(1);
    await tester.pump();
    expect(events, [
      'button:1:true',
      'button:1:false',
      'button:1:true',
      'move:20:0',
      'button:1:false',
    ]);
    expect(pad.dragging, isFalse);
    pad.dispose();
  });

  testWidgets('cancellation clears pending movement and releases drag', (
    tester,
  ) async {
    final events = <String>[];
    final pad = makePad(events);
    pad.toggleDrag();
    await tester.pump();
    pad.down(1, Offset.zero);
    pad.move(1, const Offset(25, 0));
    pad.cancel();
    await tester.pump(const Duration(milliseconds: 40));
    expect(events, ['button:1:true', 'button:1:false']);
    expect(pad.dragging, isFalse);
    pad.dispose();
  });

  testWidgets('slow acknowledgments retain ordinary accumulated movement', (
    tester,
  ) async {
    final events = <String>[];
    final gate = Completer<void>();
    final pad = makePad(events, firstMove: gate.future);
    pad.down(1, Offset.zero);
    pad.move(1, const Offset(10, 0));
    await tester.pump(const Duration(milliseconds: 34));
    pad.move(1, const Offset(20, 0));
    await tester.pump(const Duration(milliseconds: 34));
    gate.complete();
    await tester.pump();
    expect(events, ['move:10:0', 'move:10:0']);
    pad.dispose();
  });

  testWidgets('excessive backlog fails safely without stale replay', (
    tester,
  ) async {
    final events = <String>[];
    var failures = 0;
    final pad = makePad(events, onFailure: (_) => failures++);
    pad.down(1, Offset.zero);
    pad.move(1, const Offset(5000, 0));
    await tester.pump(const Duration(milliseconds: 40));
    expect(failures, 1);
    expect(events, isEmpty);
    pad.dispose();
  });

  testWidgets('expired queued movement is never replayed after a delayed ACK', (
    tester,
  ) async {
    final events = <String>[];
    final gate = Completer<void>();
    var time = Duration.zero;
    var failures = 0;
    final pad = TrackpadController(
      now: () => time,
      movePointer: (x, y) async {
        events.add('move:$x:$y');
        await gate.future;
      },
      button: (_, pressed) async {},
      scroll: (_) async {},
      onFailure: (_) => failures++,
    );
    pad.down(1, Offset.zero);
    pad.move(1, const Offset(10, 0));
    await tester.pump(const Duration(milliseconds: 34));
    pad.move(1, const Offset(20, 0));
    await tester.pump(const Duration(milliseconds: 34));
    time = const Duration(seconds: 1);
    gate.complete();
    await tester.pump();
    expect(events, ['move:10:0']);
    expect(failures, 1);
    pad.dispose();
  });

  testWidgets('precision scales motion and moving never becomes a tap', (
    tester,
  ) async {
    final events = <String>[];
    final pad = makePad(events)..precision = true;
    pad.down(1, Offset.zero);
    pad.move(1, const Offset(20, 0));
    pad.up(1);
    await tester.pump();
    expect(events, ['move:7:0']);
    pad.dispose();
  });

  testWidgets('double taps click twice without latching drag', (tester) async {
    final events = <String>[];
    final pad = makePad(events);
    for (var i = 0; i < 2; i++) {
      pad.down(1, Offset.zero);
      pad.up(1);
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(events, [
      'button:1:true',
      'button:1:false',
      'button:1:true',
      'button:1:false',
    ]);
    expect(pad.dragging, isFalse);
    pad.dispose();
  });
}

class PadSession extends BridgepadSessionController {
  PadSession() : super(DemoBridgepadTransport());
  bool enabled = true;
  final buttons = <bool>[];
  @override
  bool get canSend => enabled;
  void disable() {
    enabled = false;
    notifyListeners();
  }

  @override
  Future<void> pointerButton(int mask, bool pressed) async {
    buttons.add(pressed);
  }
}

TrackpadController makePad(
  List<String> events, {
  Future<void>? firstMove,
  void Function(Object)? onFailure,
}) {
  var moves = 0;
  return TrackpadController(
    now: () => Duration.zero,
    movePointer: (x, y) async {
      events.add('move:$x:$y');
      if (moves++ == 0 && firstMove != null) await firstMove;
    },
    button: (mask, pressed) async => events.add('button:$mask:$pressed'),
    scroll: (amount) async => events.add('scroll:$amount'),
    onFailure: onFailure ?? (error) => fail('$error'),
  );
}

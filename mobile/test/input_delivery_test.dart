import 'package:bridgepad/src/protocol.dart';
import 'package:bridgepad/src/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_controller_test.dart' show FakeTransport;

void main() {
  late FakeTransport transport;
  late BridgepadSessionController session;
  setUp(() async {
    transport = FakeTransport();
    session = BridgepadSessionController(
      transport,
      heartbeatInterval: const Duration(days: 1),
    );
    await session.connect('test');
    transport.writes.clear();
  });
  tearDown(() async {
    session.dispose();
    await transport.close();
  });

  testWidgets(
    'one-way ACK loss stops heartbeat and disconnects after failed release',
    (tester) async {
      final lost = FakeTransport();
      final guarded = BridgepadSessionController(
        lost,
        heartbeatInterval: const Duration(seconds: 2),
        commandTimeout: const Duration(seconds: 3),
      );
      await guarded.connect('test');
      await guarded.pointerButton(1, true);
      lost.autoAck = false;
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 3));
      expect(guarded.canSend, isFalse);
      final pingCount = lost.writes
          .where((f) => f.opcode == BridgepadOpcode.ping)
          .length;
      await tester.pump(const Duration(seconds: 3));
      expect(
        lost.writes.where((f) => f.opcode == BridgepadOpcode.ping).length,
        pingCount,
      );
      expect(lost.disconnectCalls, 1);
      guarded.dispose();
      await lost.close();
    },
  );

  testWidgets('heartbeat fault closes link even when safety release succeeds', (
    tester,
  ) async {
    final lost = FakeTransport();
    final guarded = BridgepadSessionController(
      lost,
      heartbeatInterval: const Duration(seconds: 2),
      commandTimeout: const Duration(seconds: 3),
    );
    await guarded.connect('test');
    lost.autoAck = false;
    await tester.pump(const Duration(seconds: 2));
    lost.autoAck = true;
    await tester.pump(const Duration(seconds: 3));
    expect(guarded.canSend, isFalse);
    expect(guarded.connectionState, BridgepadConnectionState.disconnected);
    expect(lost.disconnectCalls, 1);
    expect(lost.writes.last.opcode, BridgepadOpcode.releaseAll);
    guarded.dispose();
    await lost.close();
  });

  test('multiline uses Enter events without an extra trailing Enter', () async {
    await session.sendText('one\r\ntwo');
    expect(transport.writes.map((f) => f.opcode), [
      BridgepadOpcode.textAscii,
      BridgepadOpcode.keyDown,
      BridgepadOpcode.keyUp,
      BridgepadOpcode.textAscii,
    ]);
    expect(transport.writes[1].payload, [0x28, 0]);
    expect(String.fromCharCodes(transport.writes.last.payload), 'two');
  });

  test('validates every line before sending any part of a draft', () async {
    await expectLater(
      session.sendText('safe\nunsupported ☃'),
      throwsA(isA<UnsupportedTextException>()),
    );
    expect(transport.writes, isEmpty);
  });

  test(
    'packed chords release the same modifier bits and Compose stays plain',
    () async {
      await session.sendKey(0x06, modifiers: {0xe3});
      await session.sendText('c');
      expect(transport.writes[0].payload, [0x06, 0x08]);
      expect(transport.writes[1].payload, [0x06, 0x08]);
      expect(transport.writes[2].opcode, BridgepadOpcode.textAscii);
      expect(transport.writes[2].payload, [99]);
    },
  );

  test('live replacements and newline produce exact key order', () async {
    await session.sendLiveEdit(1, 'A\n');
    expect(transport.writes.map((f) => f.payload.toList()), [
      [0x2a, 0],
      [0x2a, 0],
      [0x04, 2],
      [0x04, 2],
      [0x28, 0],
      [0x28, 0],
    ]);
  });

  test('live invalid text does not delete host content first', () async {
    await expectLater(
      session.sendLiveEdit(3, '☃'),
      throwsA(isA<UnsupportedTextException>()),
    );
    expect(transport.writes, isEmpty);
  });

  test('4096 character limit includes newlines and rejects bare CR', () async {
    await expectLater(
      session.sendText('a' * 4096 + '\n'),
      throwsA(isA<UnsupportedTextException>()),
    );
    await expectLater(
      session.sendText('a\rb'),
      throwsA(isA<UnsupportedTextException>()),
    );
    expect(transport.writes, isEmpty);
  });

  test('concurrent key presses stay discrete ordered transactions', () async {
    await Future.wait([session.sendKey(0x04), session.sendKey(0x05)]);
    expect(transport.writes.map((f) => [f.opcode, f.payload.first]), [
      [BridgepadOpcode.keyDown, 0x04],
      [BridgepadOpcode.keyUp, 0x04],
      [BridgepadOpcode.keyDown, 0x05],
      [BridgepadOpcode.keyUp, 0x05],
    ]);
  });

  test(
    'disarm interrupts an unacknowledged draft and blocks queued keys',
    () async {
      transport.autoAck = false;
      final text = session.sendText('x' * 441);
      final key = session.sendKey(0x04);
      final textResult = expectLater(text, throwsA(isA<Exception>()));
      final keyResult = expectLater(key, throwsA(isA<Exception>()));
      await Future<void>.delayed(Duration.zero);
      final first = transport.writes.first;
      transport.autoAck = true;
      await session.emergencyRelease();
      transport.emitResult(
        BridgepadOpcode.ack,
        first.sequence,
        BridgepadStatus.ok,
      );
      await Future.wait([textResult, keyResult]);
      expect(session.canSend, isFalse);
      expect(transport.writes.map((f) => f.opcode), [
        BridgepadOpcode.textAscii,
        BridgepadOpcode.releaseAll,
      ]);
    },
  );
}

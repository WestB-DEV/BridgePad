import 'package:bridgepad/src/remote_workspace.dart';
import 'package:bridgepad/src/session_controller.dart';
import 'package:bridgepad/src/protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_controller_test.dart' show FakeTransport;

class SessionOwner extends StatefulWidget {
  const SessionOwner({super.key, required this.session});
  final BridgepadSessionController session;
  @override
  State<SessionOwner> createState() => _SessionOwnerState();
}

class _SessionOwnerState extends State<SessionOwner> {
  @override
  Widget build(BuildContext context) =>
      RemoteWorkspace(session: widget.session);
  @override
  void dispose() {
    widget.session.dispose();
    super.dispose();
  }
}

void main() {
  late FakeTransport transport;
  late BridgepadSessionController session;
  tearDown(() async {
    await transport.close();
  });

  Future<void> open(
    WidgetTester tester,
    Size size, {
    double inset = 0,
    double scale = 1,
  }) async {
    // Create async session state inside the widget test's fake-async zone.
    transport = FakeTransport();
    session = BridgepadSessionController(
      transport,
      heartbeatInterval: const Duration(days: 1),
    );
    await session.connect('test');
    transport.writes.clear();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.viewInsets = FakeViewPadding(bottom: inset);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SafeArea(child: SessionOwner(session: session)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('remote has no scrolling page and disarm stays reachable', (
    tester,
  ) async {
    await open(tester, const Size(360, 640), inset: 280);
    expect(find.byType(ListView), findsNothing);
    expect(
      find.byTooltip('Release All + Disarm').hitTestable(),
      findsOneWidget,
    );
    await tester.drag(
      find.byKey(const Key('trackpad-surface')),
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();
    expect(
      find.byTooltip('Release All + Disarm').hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Compose Send remains reachable and retains keyboard focus', (
    tester,
  ) async {
    await open(tester, const Size(360, 640), inset: 280);
    await tester.tap(find.byTooltip('Compose and review'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('compose-input')), 'one\ntwo');
    await tester.tap(find.byKey(const Key('send-compose')));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const Key('compose-input')),
    );
    expect(field.focusNode!.hasFocus, isTrue);
    expect(
      field.controller!.text,
      isEmpty,
      reason:
          'canSend=${session.canSend}, error=${session.lastError}, frames=${transport.writes.map((f) => f.opcode).toList()}',
    );
    expect(
      transport.writes.where((f) => f.opcode == BridgepadOpcode.keyDown),
      hasLength(1),
      reason:
          'canSend=${session.canSend}, error=${session.lastError}, frames=${transport.writes.map((f) => f.opcode).toList()}',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Live keyboard Enter emits one host Enter without unfocus', (
    tester,
  ) async {
    await open(tester, const Size(360, 640));
    await tester.tap(find.byKey(const Key('live-input')));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '\u2060\n',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.testTextInput.receiveAction(TextInputAction.newline);
    await tester.pumpAndSettle();
    expect(
      transport.writes.where((f) => f.opcode == BridgepadOpcode.keyDown),
      hasLength(1),
    );
    final field = tester.widget<TextField>(find.byKey(const Key('live-input')));
    expect(field.focusNode!.hasFocus, isTrue);
  });

  for (final size in [const Size(320, 568), const Size(740, 360)]) {
    testWidgets('layout fits $size at enlarged text with keyboard', (
      tester,
    ) async {
      await open(
        tester,
        size,
        inset: size.width > size.height ? 120 : 240,
        scale: 1.5,
      );
      await tester.tap(find.byTooltip('Extra keys'));
      await tester.pumpAndSettle();
      expect(find.text('Super'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        find.byTooltip('Release All + Disarm').hitTestable(),
        findsOneWidget,
      );
    });
  }

  testWidgets('app Enter flushes composing word before the host Enter', (
    tester,
  ) async {
    await open(tester, const Size(360, 640));
    await tester.tap(find.byKey(const Key('live-input')));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '\u2060hello',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange(start: 1, end: 6),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Enter'));
    await tester.pumpAndSettle();
    expect(
      transport.writes
          .where((f) => f.opcode == BridgepadOpcode.keyDown)
          .map((f) => f.payload.first),
      [0x0b, 0x08, 0x0f, 0x0f, 0x12, 0x28],
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('live-input')))
          .focusNode!
          .hasFocus,
      isTrue,
    );
  });

  testWidgets(
    'Compose cannot cross disarm/rearm while release ACK is delayed',
    (tester) async {
      await open(tester, const Size(360, 640));
      await tester.tap(find.byTooltip('Compose and review'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('compose-input')),
        'never replay',
      );
      transport.autoAck = false;
      await tester.tap(find.byKey(const Key('send-compose')));
      await tester.pump();
      final release = transport.writes.last;
      expect(release.opcode, BridgepadOpcode.pointerButton);
      transport.autoAck = true;
      await session.emergencyRelease();
      transport.emitStatus(ble: true, usb: true, armed: true);
      transport.emitResult(
        BridgepadOpcode.ack,
        release.sequence,
        BridgepadStatus.ok,
      );
      await tester.pumpAndSettle();
      expect(
        transport.writes.where((f) => f.opcode == BridgepadOpcode.textAscii),
        isEmpty,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('compose-input')))
            .controller!
            .text,
        'never replay',
      );
    },
  );
}

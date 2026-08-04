import 'package:bridgepad/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hardware-free demo opens the armed remote controls', (tester) async {
    await tester.pumpWidget(const BridgepadApp());

    expect(find.text('Find BridgePad'), findsOneWidget);
    expect(find.textContaining('no accounts'), findsOneWidget);

    await tester.tap(find.text('Open hardware-free demo'));
    await tester.pumpAndSettle();

    expect(find.text('TRACKPAD'), findsOneWidget);
    expect(find.text('Send reviewed text'), findsOneWidget);
    expect(find.byIcon(Icons.link_off), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('RELEASE ALL + DISARM'), findsOneWidget);
  });
}

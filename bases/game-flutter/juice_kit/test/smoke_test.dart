import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_kit/juice_kit.dart';

void main() {
  testWidgets('BounceButton taps + scales', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: BounceButton(onPressed: () => tapped++, child: const Text('go')),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(tapped, 1);
  });

  testWidgets('CelebrationOverlay fires without crash', (tester) async {
    final c = CelebrationController();
    await tester.pumpWidget(MaterialApp(
      home: Stack(children: [const SizedBox.expand(), CelebrationOverlay(controller: c)]),
    ));
    c.fire();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('EmptyState renders action', (tester) async {
    var acted = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EmptyState(
          illustration: const Icon(Icons.pets),
          message: '还没有画作',
          actionLabel: '画一张',
          onAction: () => acted = true,
        ),
      ),
    ));
    await tester.tap(find.text('画一张'));
    await tester.pumpAndSettle();
    expect(acted, isTrue);
  });

  testWidgets('JuicyTimerRing urgent state renders', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: JuicyTimerRing(
          remaining: Duration(seconds: 5),
          total: Duration(seconds: 60),
        ),
      ),
    ));
    expect(find.text('5'), findsOneWidget);
  });
}

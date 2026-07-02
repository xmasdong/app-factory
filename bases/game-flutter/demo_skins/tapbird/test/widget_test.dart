import 'package:flutter_test/flutter_test.dart';
import 'package:tapbird/main.dart';

void main() {
  testWidgets('home renders + start navigates to game', (tester) async {
    await tester.pumpWidget(const TapbirdApp());
    expect(find.text('Tapbird'), findsOneWidget);
    await tester.tap(find.text('开始'));
    await tester.pump(const Duration(milliseconds: 400));
    // 游戏屏出现分数 0
    expect(find.text('0'), findsOneWidget);
  });
}

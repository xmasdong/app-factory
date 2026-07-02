import 'package:flutter_test/flutter_test.dart';
import 'package:tapbird/main.dart';

void main() {
  testWidgets('home renders + start navigates to game', (tester) async {
    await tester.pumpWidget(const TapbirdApp());
    expect(find.text('Tapbird'), findsOneWidget);
    await tester.tap(find.text('开始'));
    await tester.pump();                                   // 提交路由
    await tester.pump(const Duration(milliseconds: 320));  // 过渡完成
    // 游戏屏出现分数 0(注意游戏 Ticker 常驻,禁 pumpAndSettle)
    expect(find.text('0'), findsOneWidget);
  });
}

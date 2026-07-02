import 'package:flutter/services.dart';

/// 触感分级(信/质感工序:关键动作带 haptic,轻重分级)。
/// 全局开关给设置页用;测试环境自动静音。
class Haptics {
  Haptics._();
  static bool enabled = true;

  /// 轻:落笔/选中/普通按钮
  static void light() { if (enabled) HapticFeedback.lightImpact(); }
  /// 中:提交/翻页/关键确认
  static void medium() { if (enabled) HapticFeedback.mediumImpact(); }
  /// 重:猜对/过关/大事件(常与 Celebration 同发)
  static void heavy() { if (enabled) HapticFeedback.heavyImpact(); }
  /// 失败/错误(系统震动模式)
  static void error() { if (enabled) HapticFeedback.vibrate(); }
  /// 选择器滚动
  static void tick() { if (enabled) HapticFeedback.selectionClick(); }
}

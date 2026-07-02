// design_feed.dart 模板 —— shape Step 1.65 从 DESIGN-FEED 生成本文件(项目内 lib/theme/)。
// 原则:UI 实现只准引用这里,禁散落硬编码 —— import 即正确,裸奔反而多写代码。
import 'package:flutter/material.dart';

/// 从 DESIGN-FEED 机器提取段(extracted)落成的 token。
abstract final class Feed {
  // ── 色板(mockup 提取)──
  static const Color primary = Color(0xFFFF5D73);   // {EXTRACTED}
  static const Color secondary = Color(0xFFFFD24A); // {EXTRACTED}
  static const Color surface = Color(0xFFFFF6E3);   // 纸底 {EXTRACTED}
  static const Color ink = Color(0xFF3B2F2F);       // 线条/文字 {EXTRACTED}

  // ── 形状(mockup 提取)──
  static const double radius = 18;                  // {EXTRACTED}
  static const double buttonRadius = 20;

  // ── 风格基因(inferred,供资产工位/字体选型参考,非程序值)──
  // styleGene: "{INFERRED: e.g. children's crayon, wobbly outlines, warm paper}"

  // ── 字体槽(授权圆体/手写体装好后填;禁系统默认黑体见质感工序)──
  static const String? fontFamily = null; // {TODO: 装字体后填}

  static ThemeData theme() => ThemeData(
        useMaterial3: true,
        fontFamily: fontFamily,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          surface: surface,
        ),
        scaffoldBackgroundColor: surface,
      );
}

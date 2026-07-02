// 换皮验证 demo 的投料主题:纸剪贴拼贴风(与首款蜡笔风刻意不同,验基座风格无关性)。
import 'package:flutter/material.dart';

abstract final class Feed {
  static const Color primary = Color(0xFF2E9E6B);   // 叶绿
  static const Color secondary = Color(0xFFF2B441); // 纸黄
  static const Color surface = Color(0xFFF3EAD8);   // 牛皮纸底
  static const Color ink = Color(0xFF35322B);
  static const double radius = 16;
  static const double buttonRadius = 20;
  // styleGene: "paper cutout collage, torn paper edges, layered construction paper, soft shadows"
  static const String? fontFamily = null;

  static ThemeData theme() => ThemeData(
        useMaterial3: true,
        fontFamily: fontFamily,
        colorScheme: ColorScheme.fromSeed(seedColor: primary, surface: surface),
        scaffoldBackgroundColor: surface,
      );
}

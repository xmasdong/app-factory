import 'package:flutter/services.dart';

/// SFX 槽位(价值函数:BGM 不做;短音效可选,默认走系统点击音,可整体关闭)。
/// 项目要真音效时:注册自己的 player 回调即可(如 audioplayers),基座零音频依赖。
enum SfxEvent { tap, correct, wrong, roundEnd, draw }

class Sfx {
  Sfx._();
  static bool enabled = true;

  /// 项目可注入真实现:Sfx.player = (e) => audioPlayer.play(...);
  static void Function(SfxEvent event)? player;

  static void play(SfxEvent event) {
    if (!enabled) return;
    final p = player;
    if (p != null) {
      p(event);
      return;
    }
    // 默认极简:仅 tap 用系统点击音,其余静音(触感由 Haptics 补位)
    if (event == SfxEvent.tap) SystemSound.play(SystemSoundType.click);
  }
}

import 'package:flutter/material.dart';
import 'haptic_service.dart';
import 'sfx_service.dart';

/// 按压回弹按钮(质感工序:按钮必须有按压反馈,禁硬邦邦)。
/// 用法:BounceButton(onPressed: ..., child: 你的按钮视觉)。
/// 只管手感不管长相——视觉由基座贴纸件/项目主题给。
class BounceButton extends StatefulWidget {
  const BounceButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.pressedScale = 0.94,
    this.duration = const Duration(milliseconds: 90),
    this.haptic = true,
    this.sfx = true,
    this.enabled = true,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final double pressedScale;
  final Duration duration;
  final bool haptic;
  final bool sfx;
  final bool enabled;

  @override
  State<BounceButton> createState() => _BounceButtonState();
}

class _BounceButtonState extends State<BounceButton> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && widget.onPressed != null;
    return GestureDetector(
      onTapDown: active ? (_) { _set(true); if (widget.haptic) Haptics.light(); } : null,
      onTapCancel: active ? () => _set(false) : null,
      onTapUp: active
          ? (_) {
              _set(false);
              if (widget.sfx) Sfx.play(SfxEvent.tap);
              widget.onPressed!();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1.0,
        duration: widget.duration,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

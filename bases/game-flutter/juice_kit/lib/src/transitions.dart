import 'package:flutter/material.dart';

/// 页面过渡包(质感工序:页面进出场,禁硬切)。
class JuicyRoute<T> extends PageRouteBuilder<T> {
  /// 滑入+微缩放(游戏屏切换默认)
  JuicyRoute.slideUp(Widget page)
      : super(
          transitionDuration: const Duration(milliseconds: 280),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (_, anim, __, child) {
            final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(curved),
                child: child,
              ),
            );
          },
        );

  /// 纯淡入(对话框式)
  JuicyRoute.fade(Widget page)
      : super(
          transitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
        );
}

/// 进场小弹(卡片/元素首次出现)
class PopIn extends StatelessWidget {
  const PopIn({super.key, required this.child, this.delay = Duration.zero});
  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.9 + 0.1 * v, child: child),
      ),
      child: child,
    );
  }
}

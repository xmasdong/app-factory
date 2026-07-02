import 'package:flutter/material.dart';

/// 环形倒计时(游戏常用件):最后 N 秒自动变色+脉冲,不用项目自己写紧张感。
class JuicyTimerRing extends StatelessWidget {
  const JuicyTimerRing({
    super.key,
    required this.remaining,
    required this.total,
    this.size = 56,
    this.color = const Color(0xFF4ADFFF),
    this.urgentColor = const Color(0xFFFF5D73),
    this.urgentThreshold = 10,
    this.textStyle,
  });

  final Duration remaining;
  final Duration total;
  final double size;
  final Color color;
  final Color urgentColor;
  final int urgentThreshold;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final secs = remaining.inSeconds;
    final urgent = secs <= urgentThreshold;
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (remaining.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final ring = SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: progress,
            strokeWidth: size * 0.1,
            color: urgent ? urgentColor : color,
            backgroundColor: (urgent ? urgentColor : color).withValues(alpha: 0.2),
          ),
          Text('$secs', style: textStyle ?? Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
    if (!urgent) return ring;
    // 紧张脉冲
    return TweenAnimationBuilder<double>(
      key: ValueKey(secs),
      tween: Tween(begin: 1.08, end: 1.0),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: ring,
    );
  }
}

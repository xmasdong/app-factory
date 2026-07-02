import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'haptic_service.dart';
import 'sfx_service.dart';

/// 庆祝系统(质感工序:猜对/过关必须有可感知高光,不是弹对话框)。
/// 零依赖自绘 confetti + 分数弹跳 + mascot 钩子。
///
/// 用法:
///   final celebration = CelebrationController();
///   Stack(children:[ 游戏内容, CelebrationOverlay(controller: celebration) ])
///   猜对时: celebration.fire();   // 彩带+触感+SFX 一次全发
class CelebrationController extends ChangeNotifier {
  int _burstSeed = 0;
  int get burstSeed => _burstSeed;

  /// 发一次庆祝(彩带爆发 + 重触感 + correct 音)。mascot 反应经 onFire 钩子接。
  void fire() {
    _burstSeed = DateTime.now().microsecondsSinceEpoch;
    Haptics.heavy();
    Sfx.play(SfxEvent.correct);
    onFire?.call();
    notifyListeners();
  }

  /// mascot/其他联动钩子(如切换吉祥物到"庆祝"表情)
  VoidCallback? onFire;
}

class CelebrationOverlay extends StatefulWidget {
  const CelebrationOverlay({
    super.key,
    required this.controller,
    this.particleCount = 90,
    this.duration = const Duration(milliseconds: 1400),
    this.colors = const [
      Color(0xFFFF5D73), Color(0xFF4ADFFF), Color(0xFFFFD24A),
      Color(0xFF6BD968), Color(0xFFB388FF),
    ],
  });

  final CelebrationController controller;
  final int particleCount;
  final Duration duration;
  final List<Color> colors;

  @override
  State<CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<CelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac =
      AnimationController(vsync: this, duration: widget.duration);
  List<_Particle> _particles = const [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onFire);
  }

  void _onFire() {
    final rnd = math.Random(widget.controller.burstSeed);
    _particles = List.generate(widget.particleCount, (_) => _Particle.random(rnd, widget.colors));
    _ac.forward(from: 0);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onFire);
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // SizedBox.expand:作为 Stack 非定位子级时防尺寸塌陷(qa 实证门抓到的真 bug)
      child: SizedBox.expand(
        child: AnimatedBuilder(
          animation: _ac,
          builder: (context, _) => CustomPaint(
            painter: _ac.isAnimating ? _ConfettiPainter(_particles, _ac.value) : null,
          ),
        ),
      ),
    );
  }
}

class _Particle {
  _Particle(this.origin, this.velocity, this.color, this.size, this.spin, this.shape);

  /// 从屏幕上沿中部爆出
  factory _Particle.random(math.Random rnd, List<Color> colors) {
    final angle = (rnd.nextDouble() * math.pi) + math.pi; // 向下扇面
    final speed = 0.5 + rnd.nextDouble() * 0.9;
    return _Particle(
      Offset(0.2 + rnd.nextDouble() * 0.6, -0.05),
      Offset(math.cos(angle) * speed * 0.4, -math.sin(angle) * speed),
      colors[rnd.nextInt(colors.length)],
      4 + rnd.nextDouble() * 6,
      (rnd.nextDouble() - 0.5) * 12,
      rnd.nextInt(3),
    );
  }

  final Offset origin;   // 相对坐标 0..1
  final Offset velocity; // 相对速度
  final Color color;
  final double size;
  final double spin;
  final int shape;       // 0 方块 1 圆 2 条
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.particles, this.t);
  final List<_Particle> particles;
  final double t; // 0..1

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in particles) {
      final gravity = 1.6 * t * t; // 相对重力下落
      final dx = (p.origin.dx + p.velocity.dx * t) * size.width;
      final dy = (p.origin.dy + p.velocity.dy * t + gravity) * size.height;
      if (dy > size.height + 20) continue;
      paint.color = p.color.withValues(alpha: (1.0 - t).clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(p.spin * t);
      switch (p.shape) {
        case 0:
          canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size), paint);
        case 1:
          canvas.drawCircle(Offset.zero, p.size / 2, paint);
        default:
          canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size * 1.6, height: p.size * 0.5), paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t || old.particles != particles;
}

/// 分数弹跳(得分数字 pop 一下,庆祝的常用搭子)
class ScorePop extends StatelessWidget {
  const ScorePop({super.key, required this.score, this.style});
  final int score;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(score),
      tween: Tween(begin: 1.35, end: 1.0),
      duration: const Duration(milliseconds: 320),
      curve: Curves.elasticOut,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: Text('$score', style: style),
    );
  }
}

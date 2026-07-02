// tapbird — 基座换皮验证 demo(实时类,widget-tree 族)。
// 目的:证明基座(juice_kit/状态屏/资产工位/主题投料)对【非回合制】玩法同样成立。
// 玩法:点按让小鸟上飞,穿过纸卷间隙得分;撞上=结束。全程站在基座件上,不重写质感。
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:juice_kit/juice_kit.dart';
import 'theme/design_feed.dart';

void main() => runApp(const TapbirdApp());

class TapbirdApp extends StatelessWidget {
  const TapbirdApp({super.key});
  @override
  Widget build(BuildContext context) =>
      MaterialApp(title: 'Tapbird', theme: Feed.theme(), home: const HomeScreen());
}

// ───────────────────────── Home(用基座状态屏/按钮) ─────────────────────────
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PopIn(
                child: Image.asset('assets/art/mascot-idle.png', height: 160,
                    errorBuilder: (c, e, s) => const Icon(Icons.flutter_dash, size: 120)),
              ),
              const SizedBox(height: 12),
              Text('Tapbird', style: Theme.of(context).textTheme.displaySmall
                  ?.copyWith(fontWeight: FontWeight.w800, color: Feed.ink)),
              const SizedBox(height: 6),
              Text('点一下,飞一下', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 28),
              BounceButton(
                onPressed: () => Navigator.of(context).push(JuicyRoute.slideUp(const GameScreen())),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                  decoration: BoxDecoration(
                    color: Feed.primary,
                    borderRadius: BorderRadius.circular(Feed.buttonRadius),
                    boxShadow: const [BoxShadow(blurRadius: 6, offset: Offset(0, 3), color: Colors.black26)],
                  ),
                  child: const Text('开始',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(height: 12),
              BounceButton(
                onPressed: () => Navigator.of(context).push(JuicyRoute.fade(HowToScaffold(
                  steps: [
                    (visual: const Icon(Icons.touch_app, size: 96), caption: '点屏幕,小鸟往上飞'),
                    (visual: const Icon(Icons.filter_alt_outlined, size: 96), caption: '穿过纸卷缝隙 +1 分'),
                    (visual: const Icon(Icons.sentiment_very_dissatisfied, size: 96), caption: '撞到就结束,再来一把!'),
                  ],
                  onDone: () => Navigator.of(context).pop(),
                ))),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('怎么玩', style: TextStyle(color: Feed.ink.withValues(alpha: 0.7))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Game(实时循环:Ticker) ─────────────────────────
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _Pipe {
  _Pipe(this.x, this.gapY);
  double x;      // 0..1+
  double gapY;   // 缝中心 0..1
  bool scored = false;
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  static const gravity = 2.6;   // 相对/s²
  static const flap = -0.9;     // 相对/s
  static const pipeSpeed = 0.32; // 相对/s
  static const gapSize = 0.30;
  static const birdX = 0.28;
  static const birdR = 0.035;

  late final Ticker _ticker = createTicker(_tick);
  final celebration = CelebrationController();

  double birdY = 0.45, vy = 0;
  List<_Pipe> pipes = [];
  double sinceSpawn = 0;
  int score = 0;
  bool over = false;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 0.0 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    if (over || dt == 0) return;
    setState(() {
      vy += gravity * dt;
      birdY += vy * dt;
      sinceSpawn += dt;
      if (sinceSpawn > 1.6) {
        sinceSpawn = 0;
        pipes.add(_Pipe(1.15, 0.25 + math.Random().nextDouble() * 0.5));
      }
      for (final p in pipes) {
        p.x -= pipeSpeed * dt;
        if (!p.scored && p.x + 0.06 < birdX) {
          p.scored = true;
          score++;
          Haptics.light();
          Sfx.play(SfxEvent.correct);
        }
        // 碰撞:在柱子横向范围内且不在缝里
        if ((p.x - birdX).abs() < 0.06 + birdR &&
            (birdY < p.gapY - gapSize / 2 + birdR || birdY > p.gapY + gapSize / 2 - birdR)) {
          _gameOver();
        }
      }
      pipes.removeWhere((p) => p.x < -0.2);
      if (birdY > 1.0 - birdR || birdY < birdR) _gameOver();
    });
  }

  void _gameOver() {
    if (over) return;
    over = true;
    Haptics.error();
    Sfx.play(SfxEvent.wrong);
    _ticker.stop();
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) Navigator.of(context).pushReplacement(JuicyRoute.fade(ResultScreen(score: score)));
    });
  }

  void _flap() {
    if (over) return;
    vy = flap;
    Haptics.light();
    Sfx.play(SfxEvent.tap);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _flap(),
      child: Scaffold(
        body: Stack(
          children: [
            // 背景纹理(资产工位产)
            Positioned.fill(
              child: Image.asset('assets/art/bg-texture.png', fit: BoxFit.cover,
                  errorBuilder: (c, e, s) => Container(color: Feed.surface)),
            ),
            // 游戏画布
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, c) => CustomPaint(
                  painter: _GamePainter(
                    birdY: birdY, pipes: pipes,
                    size: Size(c.maxWidth, c.maxHeight),
                  ),
                ),
              ),
            ),
            // 小鸟(mascot 资产)
            LayoutBuilder(
              builder: (context, c) => AnimatedPositioned(
                duration: const Duration(milliseconds: 16),
                left: c.maxWidth * birdX - 28,
                top: c.maxHeight * birdY - 28,
                child: Transform.rotate(
                  angle: (vy * 0.6).clamp(-0.5, 0.8),
                  child: Image.asset('assets/art/mascot-idle.png', width: 56, height: 56,
                      errorBuilder: (c, e, s) => const Icon(Icons.flutter_dash, size: 48)),
                ),
              ),
            ),
            // 分数
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ScorePop(score: score,
                      style: Theme.of(context).textTheme.displayMedium
                          ?.copyWith(fontWeight: FontWeight.w900, color: Feed.ink)),
                ),
              ),
            ),
            CelebrationOverlay(controller: celebration),
          ],
        ),
      ),
    );
  }
}

class _GamePainter extends CustomPainter {
  _GamePainter({required this.birdY, required this.pipes, required this.size});
  final double birdY;
  final List<_Pipe> pipes;
  final Size size;

  @override
  void paint(Canvas canvas, Size s) {
    final paint = Paint()..color = Feed.primary.withValues(alpha: 0.85);
    for (final p in pipes) {
      final x = p.x * s.width;
      const w = 0.12;
      final gapTop = (p.gapY - _GameScreenState.gapSize / 2) * s.height;
      final gapBot = (p.gapY + _GameScreenState.gapSize / 2) * s.height;
      final r = Radius.circular(Feed.radius);
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTRB(x - w * s.width / 2, -10, x + w * s.width / 2, gapTop), r), paint);
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTRB(x - w * s.width / 2, gapBot, x + w * s.width / 2, s.height + 10), r), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GamePainter old) => true;
}

// ───────────────────────── Result(基座 ResultScaffold + 庆祝) ─────────────────────────
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.score});
  final int score;
  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  static int best = 0; // demo 级(真项目走持久化)
  final celebration = CelebrationController();
  late final bool newBest = widget.score > best;

  @override
  void initState() {
    super.initState();
    if (newBest) {
      best = widget.score;
      WidgetsBinding.instance.addPostFrameCallback((_) => celebration.fire());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          ResultScaffold(
            title: newBest ? '新纪录!' : '这一局',
            mascot: Image.asset(
                newBest ? 'assets/art/mascot-celebrate.png' : 'assets/art/mascot-sad.png',
                errorBuilder: (c, e, s) => Icon(
                    newBest ? Icons.emoji_events : Icons.sentiment_dissatisfied, size: 96)),
            scoreArea: Column(children: [
              ScorePop(score: widget.score,
                  style: Theme.of(context).textTheme.displayLarge
                      ?.copyWith(fontWeight: FontWeight.w900, color: Feed.ink)),
              Text('最佳 $best', style: Theme.of(context).textTheme.titleMedium),
            ]),
            primaryLabel: '再来一把',
            onPrimary: () => Navigator.of(context)
                .pushReplacement(JuicyRoute.slideUp(const GameScreen())),
            secondaryLabel: '回主页',
            onSecondary: () => Navigator.of(context)
                .pushReplacement(JuicyRoute.fade(const HomeScreen())),
          ),
          CelebrationOverlay(controller: celebration),
        ],
      ),
    );
  }
}

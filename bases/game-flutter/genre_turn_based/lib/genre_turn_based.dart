// genre_turn_based — 回合制回合机(基座 genre 插件层)。
// 泛化自首款回合制游戏的 FSM:home → playing → (可异步判定) → result → next/end。
// 覆盖:出题池、计分/连击、回合上限、异步判定的迟到响应丢弃(序号守卫)。
library;

import 'package:flutter/foundation.dart';

enum RoundPhase { idle, playing, resolving, result, ended }

/// 出题池接口:词/关卡/题目都行。
abstract class PromptPool<P> {
  /// 取下一题(会话内不重复由实现方保证);null = 池尽。
  P? next();
  void resetSession();
}

/// 单轮判定结果。
class RoundOutcome {
  const RoundOutcome({required this.correct, this.detail});
  final bool correct;
  final Object? detail; // 如 AI 的猜测列表
}

/// 回合机。判定可同步(本地比对)或异步(云端 AI):
/// 异步用 [resolveWith] 提交 Future,内置序号守卫——过期响应静默丢弃。
class RoundMachine<P> extends ChangeNotifier {
  RoundMachine({required this.pool, this.maxRounds, this.onCorrect, this.onWrong});

  final PromptPool<P> pool;
  final int? maxRounds; // null = 无限(直到池尽/退出)
  final VoidCallback? onCorrect; // 接 CelebrationController.fire
  final VoidCallback? onWrong;

  RoundPhase _phase = RoundPhase.idle;
  P? _prompt;
  int _score = 0;
  int _round = 0;
  int _streak = 0;
  int _bestStreak = 0;
  RoundOutcome? _outcome;
  int _seq = 0; // 异步判定序号守卫

  RoundPhase get phase => _phase;
  P? get prompt => _prompt;
  int get score => _score;
  int get round => _round;
  int get streak => _streak;
  int get bestStreak => _bestStreak;
  RoundOutcome? get outcome => _outcome;
  bool get isResolving => _phase == RoundPhase.resolving;

  void startSession() {
    pool.resetSession();
    _score = 0;
    _round = 0;
    _streak = 0;
    _bestStreak = 0;
    _outcome = null;
    _nextPrompt();
  }

  void _nextPrompt() {
    _seq++; // 使在途判定过期
    final p = pool.next();
    if (p == null || (maxRounds != null && _round >= maxRounds!)) {
      _phase = RoundPhase.ended;
      notifyListeners();
      return;
    }
    _prompt = p;
    _round++;
    _outcome = null;
    _phase = RoundPhase.playing;
    notifyListeners();
  }

  /// 同步判定(本地规则,如 4 选 1 比对)。
  void resolve(RoundOutcome o) => _apply(o);

  /// 异步判定(如云端 AI 看画):迟到/被取消的响应自动丢弃。
  Future<void> resolveWith(Future<RoundOutcome> future) async {
    final my = ++_seq;
    _phase = RoundPhase.resolving;
    notifyListeners();
    try {
      final o = await future;
      if (my != _seq) return; // 过期:玩家已跳过/重画/下一轮
      _apply(o);
    } catch (_) {
      if (my != _seq) return;
      _phase = RoundPhase.playing; // 回到可重试
      notifyListeners();
    }
  }

  /// 取消在途判定(玩家继续画/离开)。
  void cancelResolve() {
    if (_phase != RoundPhase.resolving) return;
    _seq++;
    _phase = RoundPhase.playing;
    notifyListeners();
  }

  void _apply(RoundOutcome o) {
    _outcome = o;
    if (o.correct) {
      _score++;
      _streak++;
      if (_streak > _bestStreak) _bestStreak = _streak;
      onCorrect?.call();
    } else {
      _streak = 0;
      onWrong?.call();
    }
    _phase = RoundPhase.result;
    notifyListeners();
  }

  void nextRound() => _nextPrompt();

  void endSession() {
    _seq++;
    _phase = RoundPhase.ended;
    notifyListeners();
  }

  void backToIdle() {
    _seq++;
    _phase = RoundPhase.idle;
    _prompt = null;
    notifyListeners();
  }
}

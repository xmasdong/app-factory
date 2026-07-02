import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:genre_turn_based/genre_turn_based.dart';

class _ListPool implements PromptPool<String> {
  _ListPool(this.items);
  final List<String> items;
  int _i = 0;
  @override
  String? next() => _i < items.length ? items[_i++] : null;
  @override
  void resetSession() => _i = 0;
}

void main() {
  test('回合流转 + 计分/连击', () {
    var cheers = 0;
    final m = RoundMachine<String>(
        pool: _ListPool(['a', 'b', 'c']), onCorrect: () => cheers++);
    m.startSession();
    expect(m.phase, RoundPhase.playing);
    expect(m.prompt, 'a');
    m.resolve(const RoundOutcome(correct: true));
    expect(m.phase, RoundPhase.result);
    expect(m.score, 1);
    m.nextRound();
    m.resolve(const RoundOutcome(correct: false));
    expect(m.streak, 0);
    expect(m.bestStreak, 1);
    m.nextRound();
    m.resolve(const RoundOutcome(correct: true));
    m.nextRound(); // 池尽
    expect(m.phase, RoundPhase.ended);
    expect(cheers, 2);
  });

  test('异步判定:迟到响应丢弃(序号守卫)', () async {
    final m = RoundMachine<String>(pool: _ListPool(['a', 'b']));
    m.startSession();
    final late1 = Completer<RoundOutcome>();
    final f = m.resolveWith(late1.future);
    expect(m.isResolving, isTrue);
    m.cancelResolve(); // 玩家继续画
    late1.complete(const RoundOutcome(correct: true)); // 迟到
    await f;
    expect(m.score, 0); // 被丢弃
    expect(m.phase, RoundPhase.playing);
  });

  test('maxRounds 封顶', () {
    final m = RoundMachine<String>(pool: _ListPool(['a', 'b', 'c']), maxRounds: 2);
    m.startSession();
    m.resolve(const RoundOutcome(correct: true));
    m.nextRound();
    m.resolve(const RoundOutcome(correct: true));
    m.nextRound();
    expect(m.phase, RoundPhase.ended);
  });
}

import 'dart:math';

import '../models/base_runners.dart';
import '../models/enums.dart';
import '../models/player.dart';
import 'team_fielding_state.dart';

// ============================================================
// 代打 (Pinch Hit)
// ============================================================

/// 代打判断に必要なコンテキスト
class PinchHitContext {
  final TeamFieldingState fieldingState;
  final int inning;
  final bool isTop;
  final int outs;
  final int myTeamScore;
  final int opponentScore;
  final BaseRunners runners;
  final int battingOrder;
  final Player currentBatter;
  final Player opposingPitcher;
  final Random random;

  const PinchHitContext({
    required this.fieldingState,
    required this.inning,
    required this.isTop,
    required this.outs,
    required this.myTeamScore,
    required this.opponentScore,
    required this.runners,
    required this.battingOrder,
    required this.currentBatter,
    required this.opposingPitcher,
    required this.random,
  });

  int get scoreDiff => myTeamScore - opponentScore;
}

/// 代打の決定（攻撃面のみ）
/// 守備配置は別途、次の守備ハーフ開始時に決定される
class PinchHitDecision {
  final Player hitter;
  final Player outgoing;
  final int battingOrder;
  final String reason;

  const PinchHitDecision({
    required this.hitter,
    required this.outgoing,
    required this.battingOrder,
    required this.reason,
  });
}

// ============================================================
// 代走 (Pinch Run)
// ============================================================

/// 代走判断に必要なコンテキスト
class PinchRunContext {
  final TeamFieldingState fieldingState;
  final int inning;
  final bool isTop;
  final int outs;
  final int myTeamScore;
  final int opponentScore;
  final Base base;
  final Player runner;
  final int battingOrder;
  final Random random;

  const PinchRunContext({
    required this.fieldingState,
    required this.inning,
    required this.isTop,
    required this.outs,
    required this.myTeamScore,
    required this.opponentScore,
    required this.base,
    required this.runner,
    required this.battingOrder,
    required this.random,
  });

  int get scoreDiff => myTeamScore - opponentScore;
}

/// 代走の決定（攻撃面のみ）
class PinchRunDecision {
  final Player runner;
  final Player outgoing;
  final Base base;
  final int battingOrder;
  final String reason;

  const PinchRunDecision({
    required this.runner,
    required this.outgoing,
    required this.base,
    required this.battingOrder,
    required this.reason,
  });
}

// ============================================================
// 戦略
// ============================================================

/// 野手交代の戦略
///
/// 「誰を入れるか」だけを決める。守備配置は TeamFieldingState.reconcileAlignment が
/// 守備ハーフ開始時に自動計算する。
abstract class FielderChangeStrategy {
  PinchHitDecision? decidePinchHit(PinchHitContext context);
  PinchRunDecision? decidePinchRun(PinchRunContext context) => null;
}

/// 簡易な野手交代戦略
class SimpleFielderChangeStrategy implements FielderChangeStrategy {
  final int minInningForPinchHit;
  final int weakBatterThreshold;
  final int minInningForPinchRun;
  final int maxScoreDiffForPinchRun;
  final int slowRunnerThreshold;
  final int pinchRunSpeedAdvantage;

  const SimpleFielderChangeStrategy({
    this.minInningForPinchHit = 7,
    this.weakBatterThreshold = 11,
    this.minInningForPinchRun = 7,
    this.maxScoreDiffForPinchRun = 2,
    this.slowRunnerThreshold = 5,
    this.pinchRunSpeedAdvantage = 3,
  });

  @override
  PinchHitDecision? decidePinchHit(PinchHitContext ctx) {
    final state = ctx.fieldingState;
    if (state.bench.isEmpty) return null;
    if (ctx.inning < minInningForPinchHit) return null;
    if (ctx.scoreDiff > 0) return null;
    if (ctx.battingOrder == 0) return null;

    final current = ctx.currentBatter;
    final currentScore = (current.meet ?? 5) + (current.power ?? 5);
    if (currentScore > weakBatterThreshold) return null;

    Player? best;
    int bestScore = currentScore;
    for (final b in state.bench) {
      if (b.isPitcher) continue;
      final score = (b.meet ?? 5) + (b.power ?? 5);
      if (score > bestScore) {
        bestScore = score;
        best = b;
      }
    }
    if (best == null) return null;

    return PinchHitDecision(
      hitter: best,
      outgoing: current,
      battingOrder: ctx.battingOrder,
      reason: '代打',
    );
  }

  @override
  PinchRunDecision? decidePinchRun(PinchRunContext ctx) {
    final state = ctx.fieldingState;
    if (state.bench.isEmpty) return null;
    if (ctx.inning < minInningForPinchRun) return null;
    if (ctx.scoreDiff.abs() > maxScoreDiffForPinchRun) return null;
    if (ctx.battingOrder == 0) return null;

    final runnerSpeed = ctx.runner.speed ?? 5;
    if (runnerSpeed > slowRunnerThreshold) return null;

    Player? best;
    int bestSpeed = runnerSpeed;
    for (final b in state.bench) {
      if (b.isPitcher) continue;
      final s = b.speed ?? 5;
      if (s >= bestSpeed + pinchRunSpeedAdvantage && s > bestSpeed) {
        bestSpeed = s;
        best = b;
      }
    }
    if (best == null) return null;

    return PinchRunDecision(
      runner: best,
      outgoing: ctx.runner,
      base: ctx.base,
      battingOrder: ctx.battingOrder,
      reason: '代走',
    );
  }
}

// 後方互換
typedef SimplePinchHitStrategy = SimpleFielderChangeStrategy;

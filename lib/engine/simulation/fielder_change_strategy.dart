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
///
/// 代打の判定は **打者の打撃能力（meet+power）と打順** の組み合わせで決める。
/// 投手かどうかで特別扱いはしない:
///   - 典型的な投手は打撃能力が低い → 閾値を下回り、自然に代打される
///   - 大谷型の打撃能力の高い投手 → 閾値を超えるため代打されず打席続行
/// クリーンアップ（3,4,5番）への代打はハード制約でブロック。
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

    final current = ctx.currentBatter;
    final order = ctx.battingOrder;

    // 打順による起用方針:
    //   - クリーンアップ（3,4,5番 = order 2-4）: 起用しない。
    //     当日の調子で動的に判断するロジックがまだ無いので、
    //     基本能力での判定だけで主軸に代打を送るのは違和感が大きい。
    //   - 1番（リードオフ）: 通常は固定起用。よほど弱い打者でない限り温存。
    //   - その他（2, 6, 7, 8, 9番）: 能力ベース判定。
    //
    // 投手も「打者の打撃能力」で扱う。典型的な投手は meet/power が低いので
    // 自然に閾値を下回って代打が送られる。大谷型のように打撃能力が高ければ
    // 閾値を超えるので代打されず、そのまま打席に立つ。
    if (order >= 2 && order <= 4) return null;

    // 特別判定: リリーフ投手（中継ぎ・セットアッパー等）に打席が回った場合は
    // リード中でも代打を送る。次の守備イニングで投手交代するのが定石なので
    // 「凡退ほぼ確定」の投手に打席を消費させるメリットが薄い。
    //
    // 例外: 抑え（クローザー）は試合を締めくくる起用なので代打を送らない。
    //       8 回途中に登板したクローザーをそのまま 9 回も投げさせるのが基本。
    //
    // 先発投手は対象外（スコアによっては続投の選択肢が残る。スコア差リードを
    // 守る場面では既存の `scoreDiff > 0` 判定が代打を抑止する）。
    if (current.isPitcher &&
        current.reliefRole != null &&
        current.reliefRole != ReliefRole.closer) {
      final reliefPh = _findReliefPinchHitter(ctx, current);
      if (reliefPh != null) return reliefPh;
    }

    // 以降は通常判定: リードしている時は代打を送らない（点差守備に入る）
    if (ctx.scoreDiff > 0) return null;

    // 通常の能力ベース判定。
    // 1番は固定起用が基本なので閾値を厳しく（-2）して相当弱くないと代打しない。
    final threshold =
        order == 0 ? weakBatterThreshold - 2 : weakBatterThreshold;

    final currentScore = (current.meet ?? 5) + (current.power ?? 5);
    if (currentScore > threshold) return null;

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

  /// リリーフ投手（非クローザー）への代打候補を探す。
  /// 「ベンチに打撃が明確に上の野手がいれば送る」という単純判定。
  /// 典型的なリリーフ投手の meet+power は 2-4、控え野手は 8-12 程度。
  /// 大谷型の高打撃リリーフ（meet+power ≥ 10）の場合は自然と候補が見つからない。
  PinchHitDecision? _findReliefPinchHitter(
      PinchHitContext ctx, Player current) {
    final state = ctx.fieldingState;
    final currentScore = (current.meet ?? 5) + (current.power ?? 5);
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
    // 控え野手が投手と同等以下なら送らない（差が出てから送る）
    if (bestScore - currentScore < 3) return null;
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
    // 投手が走者の場合はここではスキップ（投手交代ロジック側で対応）
    if (ctx.runner.isPitcher) return null;

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

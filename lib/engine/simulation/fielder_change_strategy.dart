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

  /// 攻撃側チームのブルペンに次に投げられる投手が残っているか。
  /// 投手代打（リリーフ投手 → 代打野手）は代打成立で投手が退場するため、
  /// 残り投手が居ない場合は代打を送らない。
  final bool hasReservePitcher;

  /// 現打者が投手で、次の守備イニング頭で交代する予定かどうか（先読み結果）。
  /// `game_simulator` が `PitcherChangeStrategy.preview` を仮想 context で
  /// 呼んで判定し、戻り値が非 null ならここに true をセットする。
  /// 「次回どうせ交代するなら、打席を消費する前に代打を送る」判定の入力。
  /// 先発・クローザー含めて統一的に使う（投手ロール別の特別扱いは不要）。
  final bool pitcherWillBePulledNextInning;

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
    this.hasReservePitcher = true,
    this.pitcherWillBePulledNextInning = false,
  });

  int get scoreDiff => myTeamScore - opponentScore;

  /// 試合終了が確定する局面（延長12回裏）かどうか。
  /// この局面では代打後に守備に就く必要が無いため、守備カバー要件を緩める。
  bool get isFinalHalfInning => inning >= 12 && !isTop;
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

  /// 試合終了が確定する局面（延長12回裏）かどうか。
  /// この局面では代走後に守備に就く必要が無いため、守備カバー要件を緩める。
  bool get isFinalHalfInning => inning >= 12 && !isTop;
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

    // 特別判定: 投手が打席に立ち、かつ「次の守備イニング頭でどうせ交代する」と
    // 先読みで判定されている場合、リード中でも代打を送る。
    // 「凡退ほぼ確定」の投手に打席を消費させるメリットが薄いため。
    //
    // 先読みは `game_simulator` が `PitcherChangeStrategy.preview` を仮想 context
    // で呼んで判定する。先発・リリーフ・クローザーで分け隔てない:
    //   - 先発: 球数 100 や QS 崩壊で次回交代予定 → 代打
    //   - リリーフ（非クローザー）: 25 球到達やイニング終了で次回交代予定 → 代打
    //   - クローザー: 通常は続投予定なので preview が null を返す → 代打しない
    //     （8 回途中から登板して 9 回まで投げきる運用が維持される）
    if (current.isPitcher && ctx.pitcherWillBePulledNextInning) {
      // 投手代打は投手交代を強制する。残り投手が居ない場合は送らない
      // （ただし延長12回裏は試合終了確定なので投手枯渇を気にしない）。
      if (ctx.hasReservePitcher || ctx.isFinalHalfInning) {
        final reliefPh = _findReliefPinchHitter(ctx, current);
        if (reliefPh != null) {
          return _filterByDefenseCoverage(ctx, reliefPh);
        }
      }
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

    final decision = PinchHitDecision(
      hitter: best,
      outgoing: current,
      battingOrder: ctx.battingOrder,
      reason: '代打',
    );
    return _filterByDefenseCoverage(ctx, decision);
  }

  /// 代打を送った場合に、outgoing の守備位置を誰かが守れるかチェック。
  /// 守れる選手がどこにも居なければ代打を送らない。
  /// 投手への代打は投手交代を強制するため、残り投手が居なければ送らない。
  ///
  /// 「守れる」の判定対象:
  ///   - incoming (代打で入った選手) が直接守れる
  ///   - 既存野手 (outgoing 以外) の誰かが守れる → スワップで埋められる
  ///   - ベンチに守れる選手が居る → 守備固めで投入できる
  ///
  /// 主に「捕手の代打」で控え捕手がベンチに居ない場合に代打を抑止する。
  /// 一塁・外野等は誰でも守りやすいので影響は小さい。
  ///
  /// 例外: 延長12回裏は試合終了確定なので守備カバーも投手枯渇も気にしない。
  PinchHitDecision? _filterByDefenseCoverage(
    PinchHitContext ctx,
    PinchHitDecision decision,
  ) {
    if (ctx.isFinalHalfInning) return decision;

    // 投手代打 → 投手交代を強制するため、残り投手が居なければ送らない
    if (decision.outgoing.isPitcher && !ctx.hasReservePitcher) {
      return null;
    }

    final state = ctx.fieldingState;
    final outgoingPos = state.positionOf(decision.outgoing);
    if (outgoingPos == null) return decision;
    if (outgoingPos == FieldPosition.pitcher) return decision;
    final defPos = outgoingPos.defensePosition;
    if (defPos == null) return decision;

    if (decision.hitter.canPlay(defPos)) return decision;

    for (final entry in state.currentAlignment.entries) {
      if (entry.key == outgoingPos) continue;
      if (entry.key == FieldPosition.pitcher) continue;
      if (entry.value.id == decision.outgoing.id) continue;
      if (entry.value.canPlay(defPos)) return decision;
    }

    for (final b in state.bench) {
      if (b.id == decision.hitter.id) continue;
      if (b.isPitcher) continue;
      if (b.canPlay(defPos)) return decision;
    }

    return null;
  }

  /// 投手への代打候補を探す（先読みで「次回交代予定」と判定された投手向け）。
  /// 「ベンチに打撃が明確に上の野手がいれば送る」という単純判定。
  /// 典型的な投手の meet+power は 2-4、控え野手は 8-12 程度。
  /// 大谷型の高打撃投手（meet+power ≥ 10）の場合は自然と候補が見つからない。
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

    final decision = PinchRunDecision(
      runner: best,
      outgoing: ctx.runner,
      base: ctx.base,
      battingOrder: ctx.battingOrder,
      reason: '代走',
    );
    return _filterPinchRunByDefenseCoverage(ctx, decision);
  }

  /// 代走を送った場合に、outgoing の守備位置を誰かが守れるかチェック。
  /// 代打と同じく、捕手など専門ポジションの選手に代走を出した結果、
  /// 守備が破綻するケースを防ぐ。
  ///
  /// 例外: 延長12回裏は試合終了確定なので守備カバー不要。
  PinchRunDecision? _filterPinchRunByDefenseCoverage(
    PinchRunContext ctx,
    PinchRunDecision decision,
  ) {
    if (ctx.isFinalHalfInning) return decision;

    final state = ctx.fieldingState;
    final outgoingPos = state.positionOf(decision.outgoing);
    if (outgoingPos == null) return decision;
    if (outgoingPos == FieldPosition.pitcher) return decision;
    final defPos = outgoingPos.defensePosition;
    if (defPos == null) return decision;

    if (decision.runner.canPlay(defPos)) return decision;

    for (final entry in state.currentAlignment.entries) {
      if (entry.key == outgoingPos) continue;
      if (entry.key == FieldPosition.pitcher) continue;
      if (entry.value.id == decision.outgoing.id) continue;
      if (entry.value.canPlay(defPos)) return decision;
    }

    for (final b in state.bench) {
      if (b.id == decision.runner.id) continue;
      if (b.isPitcher) continue;
      if (b.canPlay(defPos)) return decision;
    }

    return null;
  }
}

// 後方互換
typedef SimplePinchHitStrategy = SimpleFielderChangeStrategy;

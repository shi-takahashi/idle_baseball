import 'dart:math';

import '../models/base_runners.dart';
import '../models/enums.dart';
import '../models/fielder_change.dart';
import '../models/player.dart';
import 'team_fielding_state.dart';

/// 代打判断に必要なコンテキスト
class PinchHitContext {
  /// 攻撃側チームの運用状態
  final TeamFieldingState fieldingState;

  final int inning;
  final bool isTop;
  final int outs;

  /// 攻撃側チームの現在得点
  final int myTeamScore;

  /// 守備側チームの現在得点
  final int opponentScore;

  final BaseRunners runners;

  /// これから打席に立つ打者の打順（0-8）
  final int battingOrder;

  /// 現在の打者（代打適用前）
  final Player currentBatter;

  /// 対戦している投手（左右マッチアップ判断用）
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

/// 代打の決定
/// 代打選手と、その後の守備配置再編を含む
class PinchHitDecision {
  final Player hitter; // ベンチから入る代打選手
  final Player outgoing; // 退く選手
  final int battingOrder; // 打順
  final FieldPosition? incomingPosition; // 代打選手が次の守備で入るポジション
  final List<FielderPositionChange> otherMoves; // 既存野手のポジション移動
  final String reason;

  const PinchHitDecision({
    required this.hitter,
    required this.outgoing,
    required this.battingOrder,
    required this.incomingPosition,
    required this.otherMoves,
    required this.reason,
  });
}

/// 野手交代の戦略
///
/// 現在は代打（pinchHit）のみ対応。将来的には代走・守備固めも追加する。
/// - 代走: 打席後、盗塁や進塁狙いで走者を交代
/// - 守備固め: リードしている終盤で守備のうまい選手に交代
///
/// 拡張時は decidePinchRun / decideDefensiveReplacement を追加する想定
abstract class FielderChangeStrategy {
  /// 代打を送るかどうかを判定する
  /// 代打しない場合は null
  PinchHitDecision? decidePinchHit(PinchHitContext context);
}

/// 簡易な代打戦略
///
/// 以下の条件で代打を検討:
/// - 終盤（7回以降）
/// - 同点 or 負けている
/// - 現在の打者が弱い（ミート+長打 < 閾値）
/// - ベンチにより強い代打候補がいる
///
/// 投手の打席（打順0）は代打しない（投手交代の連鎖を避けるため）
class SimplePinchHitStrategy implements FielderChangeStrategy {
  /// 代打を検討する最小のイニング
  final int minInning;

  /// 代打を検討する現打者の能力上限（ミート+長打）
  final int weakBatterThreshold;

  const SimplePinchHitStrategy({
    this.minInning = 7,
    this.weakBatterThreshold = 11,
  });

  @override
  PinchHitDecision? decidePinchHit(PinchHitContext ctx) {
    final state = ctx.fieldingState;

    // ベンチが空なら代打不可
    if (state.bench.isEmpty) return null;

    // 終盤（7回以降）のみ
    if (ctx.inning < minInning) return null;

    // リードしていたら温存
    if (ctx.scoreDiff > 0) return null;

    // 投手の打席（打順0）は代打しない（投手交代が必要になるため未対応）
    if (ctx.battingOrder == 0) return null;

    final current = ctx.currentBatter;
    final currentScore = (current.meet ?? 5) + (current.power ?? 5);

    // 現打者が十分に強ければ代打不要
    if (currentScore > weakBatterThreshold) return null;

    // ベンチから最も打力の高い（投手でない）野手を選ぶ
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

    // 守備再編を計算
    final reshuffle = _computeReshuffle(state, current, best);
    if (reshuffle == null) return null;

    return PinchHitDecision(
      hitter: best,
      outgoing: current,
      battingOrder: ctx.battingOrder,
      incomingPosition: reshuffle.incomingPosition,
      otherMoves: reshuffle.otherMoves,
      reason: '代打',
    );
  }

  /// 守備再編の計算
  ///
  /// 代打選手が元の選手のポジションを守れるなら直接交代。
  /// 守れないなら、他の守備選手とポジションを入れ替えて全員が守れる配置を探す。
  /// どうしても成立しない場合は、代打選手を元のポジションに強引に入れる（守備は妥協）。
  _ReshuffleResult? _computeReshuffle(
    TeamFieldingState state,
    Player outgoing,
    Player incoming,
  ) {
    // outgoing の現在の守備位置を取得
    final outgoingPos = state.positionOf(outgoing);
    if (outgoingPos == null) {
      // 想定外: outgoingが守備についていない
      return _ReshuffleResult(
          incomingPosition: null, otherMoves: const []);
    }

    // 投手位置の代打は想定外（投手交代の連鎖になるため戦略側で除外している）
    if (outgoingPos == FieldPosition.pitcher) return null;

    final outgoingDefPos = outgoingPos.defensePosition;
    if (outgoingDefPos == null) return null;

    // ケース1: 代打選手が元のポジションをそのまま守れる
    if (incoming.canPlay(outgoingDefPos)) {
      return _ReshuffleResult(
        incomingPosition: outgoingPos,
        otherMoves: const [],
      );
    }

    // ケース2: スワップ可能な野手を探す
    // - 既存野手 F が outgoingPos を守れる
    // - かつ incoming が F の現在のポジションを守れる
    for (final entry in state.currentAlignment.entries) {
      final pos = entry.key;
      final fielder = entry.value;
      if (fielder.id == outgoing.id) continue; // outgoingは除外
      if (pos == FieldPosition.pitcher) continue; // 投手は対象外

      if (!fielder.canPlay(outgoingDefPos)) continue;

      final incomingDefPos = pos.defensePosition;
      if (incomingDefPos == null) continue;
      if (!incoming.canPlay(incomingDefPos)) continue;

      // スワップ成立
      return _ReshuffleResult(
        incomingPosition: pos,
        otherMoves: [
          FielderPositionChange(
            player: fielder,
            from: pos,
            to: outgoingPos,
          ),
        ],
      );
    }

    // ケース3: どうしても無理なので強引に配置（守備は諦める）
    return _ReshuffleResult(
      incomingPosition: outgoingPos,
      otherMoves: const [],
    );
  }
}

/// 守備再編の結果
class _ReshuffleResult {
  final FieldPosition? incomingPosition;
  final List<FielderPositionChange> otherMoves;

  const _ReshuffleResult({
    required this.incomingPosition,
    required this.otherMoves,
  });
}

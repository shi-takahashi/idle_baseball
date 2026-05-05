import 'dart:math';

import '../models/base_runners.dart';
import '../models/player.dart';

/// 送りバントの試行判定に必要なコンテキスト
class BuntContext {
  final Player batter;

  /// 次打者（バント後にこの打者が打つ）。null の場合は中立補正。
  /// 次打者が強打者ほど「ここはバントで進めて彼に打たせたい」となる。
  final Player? nextBatter;

  final BaseRunners runners;
  final int outs;
  final int inning;

  /// 攻撃側チームの現在得点
  final int myTeamScore;

  /// 守備側チームの現在得点
  final int opponentScore;

  /// 同じ打順内で乱数選択に使う
  final Random random;

  const BuntContext({
    required this.batter,
    this.nextBatter,
    required this.runners,
    required this.outs,
    required this.inning,
    required this.myTeamScore,
    required this.opponentScore,
    required this.random,
  });

  /// スコア差（攻撃側基準: 正なら攻撃側リード）
  int get scoreDiff => myTeamScore - opponentScore;
}

/// バント判定の戦略インターフェース
abstract class BuntDecisionStrategy {
  /// 当該打席で送りバントを試みるかどうか
  bool shouldBunt(BuntContext ctx);
}

/// シンプルなバント判定ロジック
///
/// 試行条件（ハード制約）:
///   - 2アウトではない
///   - ランナーが1塁または2塁に居る（3塁単独や満塁、走者なしは対象外）
///   - 攻撃側が大量リードしているときは行わない
///
/// 確率（ソフト基準）:
///   - 投手枠（power ≤ 3）: 状況揃えばほぼ確実
///   - 弱打者（power ≤ 4）: そこそこ高確率
///   - 中堅（power 5-6）: 低確率（0アウト・接戦・終盤に限る）
///   - 主軸（power ≥ 7）: しない
class SimpleBuntDecisionStrategy implements BuntDecisionStrategy {
  /// 大量リード時はバントしない（接戦に効果が無いため）
  static const int maxLeadForBunt = 3;

  const SimpleBuntDecisionStrategy();

  @override
  bool shouldBunt(BuntContext ctx) {
    // ハード制約
    if (ctx.outs >= 2) return false;
    if (!_hasBuntableRunner(ctx.runners)) return false;
    if (ctx.scoreDiff > maxLeadForBunt) return false;

    final probability = _computeBuntProbability(ctx);
    if (probability <= 0) return false;
    return ctx.random.nextDouble() < probability;
  }

  /// バント可能なランナー配置か（1塁か2塁のいずれかに走者）
  bool _hasBuntableRunner(BaseRunners runners) {
    return runners.first != null || runners.second != null;
  }

  double _computeBuntProbability(BuntContext ctx) {
    final power = ctx.batter.power ?? 5;

    // 基本確率（長打力ベース）
    double base;
    if (power <= 2) {
      base = 0.85; // 投手レベル: ほぼ確実
    } else if (power <= 3) {
      base = 0.55;
    } else if (power == 4) {
      base = 0.30;
    } else if (power == 5) {
      base = 0.10;
    } else if (power == 6) {
      base = 0.04;
    } else {
      return 0; // 主軸はバントしない
    }

    // アウトカウント補正
    double mod = 1.0;
    if (ctx.outs == 0) {
      mod *= 1.3;
    } else {
      // 1アウトはやや控えめ（実際には1アウト2塁でバントは少ない）
      mod *= 0.7;
    }

    // 走者位置補正
    // 2塁単独: 0アウトなら3塁送りで犠飛圏に入れる効果大、1アウトでは少なめ
    if (ctx.runners.second != null && ctx.runners.first == null) {
      if (ctx.outs == 0) {
        mod *= 1.2;
      } else {
        mod *= 0.5;
      }
    }
    // 1,2塁: 一気に進塁できるチャンス
    if (ctx.runners.first != null && ctx.runners.second != null) {
      mod *= 1.1;
    }

    // イニング補正: 後半になるほどバント率↑（1点の重みが増す）
    // 1〜5回 ×1.0 / 6回 ×1.15 / 7回 ×1.30 / 8回 ×1.45 / 9回以降 ×1.60
    if (ctx.inning == 6) {
      mod *= 1.15;
    } else if (ctx.inning == 7) {
      mod *= 1.30;
    } else if (ctx.inning == 8) {
      mod *= 1.45;
    } else if (ctx.inning >= 9) {
      mod *= 1.60;
    }

    // 得点差補正: 接戦になるほどバント率↑、点差が大きいほどバント率↓
    // 同点 ×1.30 / 1点差 ×1.20 / 2点差 ×1.10 / 3点差 ×1.0 / それ以上 ×0.6
    final absDiff = ctx.scoreDiff.abs();
    if (absDiff == 0) {
      mod *= 1.30;
    } else if (absDiff == 1) {
      mod *= 1.20;
    } else if (absDiff == 2) {
      mod *= 1.10;
    } else if (absDiff >= 4) {
      mod *= 0.6;
    }

    // 大量ビハインド時はバントしない（一発狙い）。上の補正と複合で減衰。
    if (ctx.scoreDiff <= -4) {
      mod *= 0.3;
    }

    // 次打者補正: 次打者が強打者なら「彼に打たせたい」のでバント率↑、
    //              次打者が弱打者なら「打たせても期待薄」のでバント率↓
    final nextPower = ctx.nextBatter?.power ?? 5;
    if (nextPower >= 8) {
      mod *= 1.30;
    } else if (nextPower >= 6) {
      mod *= 1.10;
    } else if (nextPower <= 3) {
      mod *= 0.5;
    } else if (nextPower == 4) {
      mod *= 0.8;
    }

    return (base * mod).clamp(0.0, 0.95);
  }
}

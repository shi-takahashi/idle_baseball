import 'dart:math';

import '../models/base_runners.dart';
import '../models/player.dart';

/// 送りバントの試行判定に必要なコンテキスト
class BuntContext {
  final Player batter;
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

    // 終盤の接戦は積極的に犠打を選択
    if (ctx.inning >= 7 && ctx.scoreDiff.abs() <= 2) {
      mod *= 1.4;
    }

    // 大量ビハインド時はバントしない（一発狙い）
    if (ctx.scoreDiff <= -4) {
      mod *= 0.3;
    }

    return (base * mod).clamp(0.0, 0.95);
  }
}

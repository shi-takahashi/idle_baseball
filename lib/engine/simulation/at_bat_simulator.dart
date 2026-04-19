import 'dart:math';
import '../models/models.dart';

/// 1打席のシミュレーター
class AtBatSimulator {
  final Random _random;

  // Phase 1a: 全員同じ確率（プロ野球平均）
  // 1球の結果確率
  static const double _probBall = 0.35;
  static const double _probStrikeLooking = 0.15;
  static const double _probStrikeSwinging = 0.10;
  static const double _probFoul = 0.20;
  static const double _probInPlay = 0.20;

  // インプレー時の結果確率
  static const double _probOut = 0.70;
  static const double _probSingle = 0.20;
  static const double _probDouble = 0.05;
  static const double _probTriple = 0.01;
  static const double _probHomeRun = 0.04;

  AtBatSimulator({Random? random}) : _random = random ?? Random();

  /// 1球をシミュレート
  PitchResult simulatePitch(int balls, int strikes) {
    final roll = _random.nextDouble();

    double cumulative = 0;

    // ボール
    cumulative += _probBall;
    if (roll < cumulative) {
      return const PitchResult(type: PitchResultType.ball);
    }

    // 見逃しストライク
    cumulative += _probStrikeLooking;
    if (roll < cumulative) {
      return const PitchResult(type: PitchResultType.strikeLooking);
    }

    // 空振りストライク
    cumulative += _probStrikeSwinging;
    if (roll < cumulative) {
      return const PitchResult(type: PitchResultType.strikeSwinging);
    }

    // ファウル
    cumulative += _probFoul;
    if (roll < cumulative) {
      return const PitchResult(type: PitchResultType.foul);
    }

    // インプレー
    return PitchResult(
      type: PitchResultType.inPlay,
      battedBallType: _randomBattedBallType(),
    );
  }

  /// 打球の種類をランダムに決定
  BattedBallType _randomBattedBallType() {
    final roll = _random.nextDouble();
    if (roll < 0.45) return BattedBallType.groundBall;
    if (roll < 0.85) return BattedBallType.flyBall;
    return BattedBallType.lineDrive;
  }

  /// インプレー時の打席結果を決定
  AtBatResultType simulateInPlayResult(BattedBallType battedBallType) {
    final roll = _random.nextDouble();

    double cumulative = 0;

    // アウト
    cumulative += _probOut;
    if (roll < cumulative) {
      switch (battedBallType) {
        case BattedBallType.groundBall:
          return AtBatResultType.groundOut;
        case BattedBallType.flyBall:
          return AtBatResultType.flyOut;
        case BattedBallType.lineDrive:
          return AtBatResultType.lineOut;
      }
    }

    // 単打
    cumulative += _probSingle;
    if (roll < cumulative) {
      return AtBatResultType.single;
    }

    // 二塁打
    cumulative += _probDouble;
    if (roll < cumulative) {
      return AtBatResultType.double_;
    }

    // 三塁打
    cumulative += _probTriple;
    if (roll < cumulative) {
      return AtBatResultType.triple;
    }

    // 本塁打
    return AtBatResultType.homeRun;
  }

  /// 1打席をシミュレート
  /// 戻り値: (打席結果タイプ, 投球リスト)
  (AtBatResultType, List<PitchResult>) simulateAtBat() {
    int balls = 0;
    int strikes = 0;
    final pitches = <PitchResult>[];

    while (true) {
      final pitch = simulatePitch(balls, strikes);
      pitches.add(pitch);

      switch (pitch.type) {
        case PitchResultType.ball:
          balls++;
          if (balls >= 4) {
            return (AtBatResultType.walk, pitches);
          }
          break;

        case PitchResultType.strikeLooking:
        case PitchResultType.strikeSwinging:
          strikes++;
          if (strikes >= 3) {
            return (AtBatResultType.strikeout, pitches);
          }
          break;

        case PitchResultType.foul:
          if (strikes < 2) {
            strikes++;
          }
          // 2ストライク以降のファウルはカウント変わらず
          break;

        case PitchResultType.inPlay:
          final result = simulateInPlayResult(pitch.battedBallType!);
          return (result, pitches);
      }
    }
  }
}

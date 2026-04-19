import 'dart:math';
import '../models/models.dart';

/// 1打席のシミュレーター
class AtBatSimulator {
  final Random _random;

  // 基準球速（この球速で基本確率になる）
  static const int _baseSpeed = 145;

  // 球速1kmあたりの補正率
  static const double _speedModifierPerKm = 0.005;

  // 基本確率（球速145km基準）
  static const double _baseProbBall = 0.35;
  static const double _baseProbStrikeLooking = 0.15;
  static const double _baseProbStrikeSwinging = 0.10;
  static const double _baseProbFoul = 0.20;
  // インプレー確率は残り

  // インプレー時の結果確率（球速145km基準）
  static const double _baseProbOut = 0.70;
  static const double _baseProbSingle = 0.20;
  static const double _baseProbDouble = 0.05;
  static const double _baseProbTriple = 0.01;
  // 本塁打確率は残り

  AtBatSimulator({Random? random}) : _random = random ?? Random();

  /// 球速を生成（正規分布的、中央付近が出やすい）
  int generateSpeed(int averageSpeed) {
    // 2つの一様乱数の平均を使って中央寄りの分布を作る
    // これで±5の範囲で中央付近が出やすくなる
    final r1 = _random.nextDouble() * 10 - 5; // -5 to +5
    final r2 = _random.nextDouble() * 10 - 5; // -5 to +5
    final offset = ((r1 + r2) / 2).round(); // 平均を取ると中央寄りに
    return averageSpeed + offset;
  }

  /// 1球をシミュレート
  PitchResult simulatePitch(int balls, int strikes, int speed) {
    // 球速による補正（速いほど空振り増、ヒット減）
    final speedDiff = speed - _baseSpeed;
    final modifier = speedDiff * _speedModifierPerKm;

    // 確率を調整
    final probBall = _baseProbBall; // ボールは球速に影響されない
    final probStrikeLooking = _baseProbStrikeLooking;
    final probStrikeSwinging = (_baseProbStrikeSwinging + modifier).clamp(0.05, 0.25);
    final probFoul = _baseProbFoul;
    // インプレー確率は残り（球速が速いほど減る）
    final probInPlay = (1.0 - probBall - probStrikeLooking - probStrikeSwinging - probFoul).clamp(0.10, 0.30);

    final roll = _random.nextDouble();
    double cumulative = 0;

    // ボール
    cumulative += probBall;
    if (roll < cumulative) {
      return PitchResult(type: PitchResultType.ball, speed: speed);
    }

    // 見逃しストライク
    cumulative += probStrikeLooking;
    if (roll < cumulative) {
      return PitchResult(type: PitchResultType.strikeLooking, speed: speed);
    }

    // 空振りストライク
    cumulative += probStrikeSwinging;
    if (roll < cumulative) {
      return PitchResult(type: PitchResultType.strikeSwinging, speed: speed);
    }

    // ファウル
    cumulative += probFoul;
    if (roll < cumulative) {
      return PitchResult(type: PitchResultType.foul, speed: speed);
    }

    // インプレー
    return PitchResult(
      type: PitchResultType.inPlay,
      battedBallType: _randomBattedBallType(),
      speed: speed,
    );
  }

  /// 打球の種類をランダムに決定
  BattedBallType _randomBattedBallType() {
    final roll = _random.nextDouble();
    if (roll < 0.45) return BattedBallType.groundBall;
    if (roll < 0.85) return BattedBallType.flyBall;
    return BattedBallType.lineDrive;
  }

  /// インプレー時の打席結果を決定（球速考慮）
  AtBatResultType simulateInPlayResult(BattedBallType battedBallType, int speed) {
    // 球速による補正（速いほどヒットが減る）
    final speedDiff = speed - _baseSpeed;
    final modifier = speedDiff * _speedModifierPerKm;

    // 確率を調整（速いほどアウト増、ヒット減）
    final probOut = (_baseProbOut + modifier).clamp(0.60, 0.85);
    final probSingle = (_baseProbSingle - modifier * 0.5).clamp(0.10, 0.25);
    final probDouble = (_baseProbDouble - modifier * 0.3).clamp(0.02, 0.08);
    final probTriple = _baseProbTriple;
    // 本塁打は残り

    final roll = _random.nextDouble();
    double cumulative = 0;

    // アウト
    cumulative += probOut;
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
    cumulative += probSingle;
    if (roll < cumulative) {
      return AtBatResultType.single;
    }

    // 二塁打
    cumulative += probDouble;
    if (roll < cumulative) {
      return AtBatResultType.double_;
    }

    // 三塁打
    cumulative += probTriple;
    if (roll < cumulative) {
      return AtBatResultType.triple;
    }

    // 本塁打
    return AtBatResultType.homeRun;
  }

  /// 1打席をシミュレート
  /// 戻り値: (打席結果タイプ, 投球リスト)
  (AtBatResultType, List<PitchResult>) simulateAtBat(Player pitcher) {
    // 投手の平均球速（設定されていなければ145km）
    final avgSpeed = pitcher.averageSpeed ?? 145;

    int balls = 0;
    int strikes = 0;
    final pitches = <PitchResult>[];

    while (true) {
      // 毎球、球速を生成
      final speed = generateSpeed(avgSpeed);
      final pitch = simulatePitch(balls, strikes, speed);
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
          final result = simulateInPlayResult(pitch.battedBallType!, speed);
          return (result, pitches);
      }
    }
  }
}

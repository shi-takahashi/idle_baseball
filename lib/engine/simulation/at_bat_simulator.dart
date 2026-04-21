import 'dart:math';
import '../models/models.dart';

/// 1打席のシミュレーター
class AtBatSimulator {
  final Random _random;

  // 基準球速（この球速で基本確率になる）
  static const int _baseSpeed = 145;

  // 球速1kmあたりの補正率
  static const double _speedModifierPerKm = 0.005;

  // 基準制球力（この制球力で基本確率になる）
  static const int _baseControl = 5;

  // 制球力1あたりの補正率
  static const double _controlBallModifier = 0.015; // ボール確率補正
  static const double _controlHitModifier = 0.01; // 被打率補正（アウト率への影響）

  // 基準ミート力（このミート力で基本確率になる）
  static const int _baseMeet = 5;

  // ミート力1あたりの補正率（インプレーになる確率に影響）
  static const double _meetSwingModifier = 0.015; // 空振り確率補正（高いほど空振り減→インプレー増）

  // 基準長打力（この長打力で基本確率になる）
  static const int _basePower = 5;

  // 長打力1あたりの補正率
  static const double _powerHomeRunModifier = 0.015; // ホームラン確率補正（大きく影響）
  static const double _powerDoubleModifier = 0.005; // 二塁打確率補正
  static const double _powerTripleModifier = 0.002; // 三塁打確率補正
  static const double _powerSingleModifier = 0.003; // 単打確率補正（打球速度で少し増）

  // 基本確率（球速145km、制球力5、ミート力5、長打力5基準）
  static const double _baseProbBall = 0.35;
  static const double _baseProbStrikeLooking = 0.15;
  static const double _baseProbStrikeSwinging = 0.10;
  static const double _baseProbFoul = 0.20;
  // インプレー確率は残り

  // インプレー時の結果確率（球速145km、制球力5基準）
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
  PitchResult simulatePitch(int balls, int strikes, int speed, int control, int meet) {
    // 球速による補正（速いほど空振り増、ヒット減）
    final speedDiff = speed - _baseSpeed;
    final speedModifier = speedDiff * _speedModifierPerKm;

    // 制球力による補正（高いほどボール減）
    final controlDiff = control - _baseControl;
    final ballModifier = controlDiff * _controlBallModifier;

    // ミート力による補正（高いほど空振り減）
    final meetDiff = meet - _baseMeet;
    final swingModifier = meetDiff * _meetSwingModifier;

    // 確率を調整
    // 制球力が高いほどボール確率が下がる（ただし最低25%、最高45%）
    final probBall = (_baseProbBall - ballModifier).clamp(0.25, 0.45);
    final probStrikeLooking = _baseProbStrikeLooking;
    // 球速が速いほど空振り増、ミート力が高いほど空振り減
    final probStrikeSwinging = (_baseProbStrikeSwinging + speedModifier - swingModifier).clamp(0.03, 0.25);
    final probFoul = _baseProbFoul;
    // インプレー確率は残り
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
    final battedBallType = _randomBattedBallType();
    final fieldPosition = _randomFieldPosition(battedBallType);
    return PitchResult(
      type: PitchResultType.inPlay,
      battedBallType: battedBallType,
      fieldPosition: fieldPosition,
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

  /// 打球方向をランダムに決定（打球の種類によって確率が変わる）
  FieldPosition _randomFieldPosition(BattedBallType battedBallType) {
    final roll = _random.nextDouble();

    switch (battedBallType) {
      case BattedBallType.groundBall:
        // ゴロは内野に飛ぶ（投手5%, 一塁25%, 二塁25%, 三塁20%, 遊撃25%）
        if (roll < 0.05) return FieldPosition.pitcher;
        if (roll < 0.30) return FieldPosition.first;
        if (roll < 0.55) return FieldPosition.second;
        if (roll < 0.75) return FieldPosition.third;
        return FieldPosition.shortstop;

      case BattedBallType.flyBall:
        // フライは外野メイン、内野フライもある
        // 捕手5%, 一塁5%, 二塁5%, 三塁5%, 遊撃5%, 左翼25%, 中堅30%, 右翼20%
        if (roll < 0.05) return FieldPosition.catcher;
        if (roll < 0.10) return FieldPosition.first;
        if (roll < 0.15) return FieldPosition.second;
        if (roll < 0.20) return FieldPosition.third;
        if (roll < 0.25) return FieldPosition.shortstop;
        if (roll < 0.50) return FieldPosition.left;
        if (roll < 0.80) return FieldPosition.center;
        return FieldPosition.right;

      case BattedBallType.lineDrive:
        // ライナーは全方向に分散
        // 投手10%, 一塁10%, 二塁15%, 三塁10%, 遊撃15%, 左翼15%, 中堅15%, 右翼10%
        if (roll < 0.10) return FieldPosition.pitcher;
        if (roll < 0.20) return FieldPosition.first;
        if (roll < 0.35) return FieldPosition.second;
        if (roll < 0.45) return FieldPosition.third;
        if (roll < 0.60) return FieldPosition.shortstop;
        if (roll < 0.75) return FieldPosition.left;
        if (roll < 0.90) return FieldPosition.center;
        return FieldPosition.right;
    }
  }

  /// インプレー時の打席結果を決定（球速・制球力・長打力考慮）
  /// ミート力はインプレーになる確率に影響し、インプレー後の結果には影響しない
  AtBatResultType simulateInPlayResult(BattedBallType battedBallType, int speed, int control, int power) {
    // 球速による補正（速いほどヒットが減る）
    final speedDiff = speed - _baseSpeed;
    final speedModifier = speedDiff * _speedModifierPerKm;

    // 制球力による補正（高いほど甘い球が減り、アウトが増える）
    final controlDiff = control - _baseControl;
    final controlModifier = controlDiff * _controlHitModifier;

    // 長打力による補正（高いほど長打が増える）
    final powerDiff = power - _basePower;
    final homeRunModifier = powerDiff * _powerHomeRunModifier;
    final doubleModifier = powerDiff * _powerDoubleModifier;
    final tripleModifier = powerDiff * _powerTripleModifier;
    final singleModifier = powerDiff * _powerSingleModifier;

    // アウト率（球速が速いほど、制球力が高いほど増える）
    final outModifier = speedModifier + controlModifier;
    final probOut = (_baseProbOut + outModifier).clamp(0.50, 0.85);

    // 長打確率（長打力で大きく変動）
    // ホームラン: 長打力1で約1%、長打力10で約11%
    final probHomeRun = (0.04 + homeRunModifier).clamp(0.005, 0.15);
    // 三塁打: 長打力でわずかに増加
    final probTriple = (_baseProbTriple + tripleModifier).clamp(0.005, 0.03);
    // 二塁打: 長打力で増加
    final probDouble = (_baseProbDouble + doubleModifier).clamp(0.02, 0.12);
    // 単打: 長打力で少し増加
    final probSingle = (_baseProbSingle - outModifier * 0.5 + singleModifier).clamp(0.10, 0.35);

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

    // 本塁打（残り）
    // ただし長打力で確率を直接使う
    if (_random.nextDouble() < probHomeRun / (probHomeRun + 0.01)) {
      return AtBatResultType.homeRun;
    }
    // 本塁打にならなかった場合は二塁打
    return AtBatResultType.double_;
  }

  /// 1打席をシミュレート
  /// 戻り値: (打席結果タイプ, 投球リスト)
  (AtBatResultType, List<PitchResult>) simulateAtBat(Player pitcher, Player batter) {
    // 投手の平均球速（設定されていなければ145km）
    final avgSpeed = pitcher.averageSpeed ?? 145;
    // 投手の制球力（設定されていなければ5）
    final control = pitcher.control ?? 5;
    // 打者のミート力（設定されていなければ5）
    final meet = batter.meet ?? 5;
    // 打者の長打力（設定されていなければ5）
    final power = batter.power ?? 5;

    int balls = 0;
    int strikes = 0;
    final pitches = <PitchResult>[];

    while (true) {
      // 毎球、球速を生成
      final speed = generateSpeed(avgSpeed);
      final pitch = simulatePitch(balls, strikes, speed, control, meet);
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
          final result = simulateInPlayResult(pitch.battedBallType!, speed, control, power);
          return (result, pitches);
      }
    }
  }
}

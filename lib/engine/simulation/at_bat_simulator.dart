import 'dart:math';

import '../models/models.dart';
import 'error_simulator.dart';
import 'steal_simulator.dart';

/// インプレー結果（エラー情報を含む）
class InPlayResult {
  final AtBatResultType result;
  final FieldingError? fieldingError;

  const InPlayResult({
    required this.result,
    this.fieldingError,
  });
}

/// 打席終了チェックの結果
class AtBatEndCheckResult {
  final AtBatResultType? result;
  final FieldingError? fieldingError;

  const AtBatEndCheckResult({
    this.result,
    this.fieldingError,
  });

  /// 打席が終了したかどうか
  bool get isEnded => result != null;
}

/// 打席シミュレーションの結果
class AtBatSimulationResult {
  final AtBatResultType result;
  final List<PitchResult> pitches;
  final List<StealAttempt> stealAttempts; // 打席中の盗塁（記録されるもののみ）
  final BaseRunners updatedRunners; // 盗塁後のランナー状況
  final int additionalOuts; // 盗塁失敗によるアウト数
  final FieldingError? fieldingError; // フィールディングエラー
  final int batteryErrorRuns; // バッテリーエラーによる得点

  const AtBatSimulationResult({
    required this.result,
    required this.pitches,
    this.stealAttempts = const [],
    required this.updatedRunners,
    this.additionalOuts = 0,
    this.fieldingError,
    this.batteryErrorRuns = 0,
  });
}

/// インプレー結果の確率データ
class InPlayProbabilities {
  final double probOut;
  final double probSingle;
  final double probDouble;
  final double probTriple;
  final double probHomeRun;

  const InPlayProbabilities({
    required this.probOut,
    required this.probSingle,
    required this.probDouble,
    required this.probTriple,
    required this.probHomeRun,
  });
}

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

  // 基準選球眼（この選球眼で基本確率になる）
  static const int _baseEye = 5;

  // 選球眼1あたりの補正率
  static const double _eyeBallModifier = 0.015; // ボール確率補正（高いほどボール見逃し増→四球増）

  // 長打力による四球率補正（ホームラン警戒で勝負を避けられる）
  static const double _powerWalkModifier = 0.008; // 長打力1あたりの四球率補正

  // 基準長打力（この長打力で基本確率になる）
  static const int _basePower = 5;

  // 長打力1あたりの補正率
  static const double _powerHomeRunModifier = 0.015; // ホームラン確率補正（大きく影響）
  static const double _powerDoubleModifier = 0.005; // 二塁打確率補正
  static const double _powerTripleModifier = 0.002; // 三塁打確率補正
  static const double _powerSingleModifier = 0.003; // 単打確率補正（打球速度で少し増）

  // 基準守備力（この守備力で基本確率になる）
  static const int _baseFielding = 5;

  // 守備力1あたりの補正率（高いほどアウト率が上がる）
  static const double _fieldingModifier = 0.015;

  // 捕手リード1あたりの補正率（高いほどアウト率が上がる、おまけ程度）
  static const double _leadModifier = 0.005;

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

  // 基準球種パラメータ（この値で基本効果）
  static const int _basePitchParam = 5;

  // パラメータ1あたりの補正率（球種の効果をスケール）
  static const double _pitchParamModifier = 0.01;

  // 球種ごとの特性定義
  // 球速低下量（km/h）
  static const Map<PitchType, int> _speedReductions = {
    PitchType.fastball: 0,
    PitchType.slider: 15,    // -10〜-20の中央
    PitchType.curveball: 25, // -20〜-30の中央
    PitchType.splitter: 10,  // -5〜-15の中央
    PitchType.changeup: 15,  // -10〜-20の中央
  };

  // ボール率補正（正=ボール増）
  // ストレート: 低、スライダー: 中、カーブ: やや高、スプリット: 高、チェンジアップ: 中
  static const Map<PitchType, double> _ballModifiers = {
    PitchType.fastball: -0.02,  // 低（制球しやすい）
    PitchType.slider: 0.0,      // 中
    PitchType.curveball: 0.02,  // やや高
    PitchType.splitter: 0.05,   // 高（抜けやすい）
    PitchType.changeup: 0.0,    // 中
  };

  // 三振率補正（正=空振り増）
  // ストレート: 中、スライダー: 高、カーブ: 中、スプリット: 最高、チェンジアップ: 中〜高
  static const Map<PitchType, double> _swingModifiers = {
    PitchType.fastball: 0.0,    // 中（質パラメータで変動）
    PitchType.slider: 0.03,     // 高
    PitchType.curveball: 0.01,  // 中
    PitchType.splitter: 0.05,   // 最高（決め球）
    PitchType.changeup: 0.02,   // 中〜高
  };

  // アウト率補正（正=アウト増=被打率低）
  // ストレート: やや高（被打率やや高=アウト率低）、スライダー: 低、カーブ: 中、スプリット: 低、チェンジアップ: 低
  static const Map<PitchType, double> _outModifiers = {
    PitchType.fastball: -0.02,  // 被打率やや高
    PitchType.slider: 0.03,     // 被打率低
    PitchType.curveball: 0.0,   // 被打率中
    PitchType.splitter: 0.03,   // 被打率低
    PitchType.changeup: 0.02,   // 被打率低
  };

  // 被長打率補正（正=長打増=打者有利）
  // ストレート: 高、スライダー: 低〜中、カーブ: やや高、スプリット: 低、チェンジアップ: 低
  static const Map<PitchType, double> _xbhModifiers = {
    PitchType.fastball: 0.02,   // 被長打率高（力負けしやすい）
    PitchType.slider: -0.01,    // 被長打率低〜中
    PitchType.curveball: 0.01,  // 被長打率やや高
    PitchType.splitter: -0.02,  // 被長打率低
    PitchType.changeup: -0.02,  // 被長打率低（タイミング崩れる）
  };

  // === 疲労システム ===

  // 基準スタミナ（この値で標準的な疲労カーブ）
  static const int _baseStamina = 5;

  // 疲労開始球数（スタミナ5で70球から疲労開始）
  static const int _baseFatigueStartPitches = 70;

  // 完全疲労球数（スタミナ5で100球で完全疲労）
  static const int _baseFullFatiguePitches = 100;

  // スタミナ1あたりの疲労開始球数補正
  static const int _staminaPitchModifier = 5;

  // 球種ごとの疲労影響度（0.0〜1.0、高いほど疲労の影響を受けやすい）
  // スプリット: 最大、スライダー: 高、カーブ: 中、チェンジアップ: 低、ストレート: 低
  static const Map<PitchType, double> _fatigueSensitivity = {
    PitchType.fastball: 0.4,    // ★★☆☆☆ 球速低下
    PitchType.slider: 0.8,      // ★★★★☆ 曲がらない
    PitchType.curveball: 0.6,   // ★★★☆☆ 浮く
    PitchType.splitter: 1.0,    // ★★★★★ 落ちない＆被弾
    PitchType.changeup: 0.4,    // ★★☆☆☆ 少しズレる
  };

  // 疲労時の球速低下量（ストレート用、最大値）
  static const int _fatigueSpeedReduction = 5;

  // 疲労時のボール率増加（最大値）
  static const double _fatigueBallModifier = 0.08;

  // 疲労時の空振り率低下（最大値）
  static const double _fatigueSwingModifier = 0.05;

  // 疲労時のアウト率低下（最大値、被打率増加）
  static const double _fatigueOutModifier = 0.08;

  // 疲労時の被長打率増加（最大値）
  static const double _fatigueXbhModifier = 0.03;

  late final ErrorSimulator _errorSimulator;

  AtBatSimulator({Random? random}) : _random = random ?? Random() {
    _errorSimulator = ErrorSimulator(random: _random);
  }

  /// 疲労度を計算（0.0〜1.0）
  /// pitchCount: 現在の投球数
  /// stamina: スタミナパラメータ（1-10、nullは5）
  double _calculateFatigue(int pitchCount, int? stamina) {
    final staminaValue = stamina ?? _baseStamina;

    // スタミナに応じた疲労開始/完全疲労の球数を計算
    // スタミナ1: 50球から開始、80球で完全疲労
    // スタミナ5: 70球から開始、100球で完全疲労
    // スタミナ10: 95球から開始、125球で完全疲労
    final fatigueStart =
        _baseFatigueStartPitches + (staminaValue - _baseStamina) * _staminaPitchModifier;
    final fullFatigue =
        _baseFullFatiguePitches + (staminaValue - _baseStamina) * _staminaPitchModifier;

    if (pitchCount < fatigueStart) {
      return 0.0; // 疲労なし
    }
    if (pitchCount >= fullFatigue) {
      return 1.0; // 完全疲労
    }

    // 疲労開始〜完全疲労の間で線形補間
    return (pitchCount - fatigueStart) / (fullFatigue - fatigueStart);
  }

  /// 球種に応じた疲労効果を計算
  /// fatigue: 基本疲労度（0.0〜1.0）
  /// pitchType: 球種
  /// 戻り値: 球種ごとの実効疲労度（0.0〜1.0）
  double _getEffectiveFatigue(double fatigue, PitchType pitchType) {
    final sensitivity = _fatigueSensitivity[pitchType] ?? 0.5;
    return fatigue * sensitivity;
  }

  /// 投げる球種を選択
  /// 速球派: ストレート60%程度、変化球各20%程度
  /// 技巧派: ストレート40%程度、変化球各20%程度
  /// 球種選択の確率は調子に影響されない（習慣的なもの）
  PitchType _selectPitchType(Player pitcher, PitcherCondition condition) {
    // 調子は選択確率には影響しない（効果のみに影響）
    // ignore: unused_local_variable
    final _ = condition;
    final avgSpeed = pitcher.averageSpeed ?? 145;
    final fastballQuality = pitcher.fastball ?? 5;

    // 各球種の重み
    // nullの球種は重み0（投げない）
    final weights = <PitchType, double>{};

    // ストレートは基本重み1.8 + 球速と質で補正
    final speedBonus = ((avgSpeed - 140) / 30.0).clamp(-0.3, 0.5);  // -0.3〜+0.5
    final qualityBonus = (fastballQuality - 5) * 0.1;               // -0.4〜+0.5
    weights[PitchType.fastball] = (1.8 + speedBonus + qualityBonus).clamp(1.2, 2.5);

    // 変化球はパラメータ値を重みに使用（0.5〜1.2）
    if (pitcher.slider != null) {
      weights[PitchType.slider] = (pitcher.slider! / 10.0 + 0.2).clamp(0.5, 1.2);
    }
    if (pitcher.curve != null) {
      weights[PitchType.curveball] = (pitcher.curve! / 10.0 + 0.2).clamp(0.5, 1.2);
    }
    if (pitcher.splitter != null) {
      weights[PitchType.splitter] = (pitcher.splitter! / 10.0 + 0.2).clamp(0.5, 1.2);
    }
    if (pitcher.changeup != null) {
      weights[PitchType.changeup] = (pitcher.changeup! / 10.0 + 0.2).clamp(0.5, 1.2);
    }

    // 全球種が投げられない場合はストレートのみ
    if (weights.isEmpty) {
      return PitchType.fastball;
    }

    // 合計重みを計算
    final totalWeight = weights.values.fold(0.0, (sum, w) => sum + w);
    final roll = _random.nextDouble() * totalWeight;

    // 重み付き選択
    double cumulative = 0;
    for (final entry in weights.entries) {
      cumulative += entry.value;
      if (roll < cumulative) {
        return entry.key;
      }
    }

    // フォールバック
    return PitchType.fastball;
  }

  /// 球種に応じた球速を生成
  int _generatePitchSpeed(int avgSpeed, PitchType pitchType) {
    final speedReduction = _speedReductions[pitchType] ?? 0;
    final baseSpeed = avgSpeed - speedReduction;
    return generateSpeed(baseSpeed);
  }

  /// 球速を生成（正規分布的、中央付近が出やすい）
  int generateSpeed(int averageSpeed) {
    // 2つの一様乱数の平均を使って中央寄りの分布を作る
    // ±3の範囲で中央付近が出やすい（調子±2と合わせて±5の変動）
    final r1 = _random.nextDouble() * 6 - 3; // -3 to +3
    final r2 = _random.nextDouble() * 6 - 3; // -3 to +3
    final offset = ((r1 + r2) / 2).round(); // 平均を取ると中央寄りに
    return averageSpeed + offset;
  }

  /// 1球をシミュレート
  /// pitchType: 球種
  /// pitchParam: その球種のパラメータ値（1-10、nullは基準値5）
  /// eye: 打者の選球眼（1-10、デフォルト5）
  /// power: 打者の長打力（1-10、デフォルト5）- 警戒されて四球増
  /// fatigue: 基本疲労度（0.0〜1.0、デフォルト0）
  PitchResult simulatePitch(int balls, int strikes, int speed, int control, int meet, PitchType pitchType, int? pitchParam, {int eye = 5, int power = 5, double fatigue = 0.0}) {
    // 球種に応じた実効疲労度を計算
    final effectiveFatigue = _getEffectiveFatigue(fatigue, pitchType);

    // 球速による補正（ストレートのみ、速いほど空振り増）
    // 疲労時はストレートの球速が低下
    double speedModifier = 0.0;
    int effectiveSpeed = speed;
    if (pitchType == PitchType.fastball) {
      // 疲労による球速低下（最大5km/h）
      final fatigueSpeedDrop = (effectiveFatigue * _fatigueSpeedReduction).round();
      effectiveSpeed = speed - fatigueSpeedDrop;
      final speedDiff = effectiveSpeed - _baseSpeed;
      speedModifier = speedDiff * _speedModifierPerKm;
    }

    // 制球力による補正（高いほどボール減）
    final controlDiff = control - _baseControl;
    final controlBallModifier = controlDiff * _controlBallModifier;

    // ミート力による補正（高いほど空振り減）
    final meetDiff = meet - _baseMeet;
    final swingModifier = meetDiff * _meetSwingModifier;

    // 選球眼による補正（高いほどボール見逃し増→四球増）
    final eyeDiff = eye - _baseEye;
    final eyeBallBonus = eyeDiff * _eyeBallModifier;     // ボール率増加

    // 長打力による補正（高いほど警戒されて四球増）
    final powerDiff = power - _basePower;
    final powerWalkBonus = powerDiff * _powerWalkModifier;  // ボール率増加

    // 球種固有のベース補正
    final pitchBallModifier = _ballModifiers[pitchType] ?? 0.0;
    final pitchSwingModifier = _swingModifiers[pitchType] ?? 0.0;

    // パラメータによるスケーリング（パラメータ5で基準、1-10で±4%）
    // ストレートの場合はfastballパラメータ、変化球はそれぞれのパラメータ
    final paramValue = pitchParam ?? _basePitchParam;
    final paramScaling = (paramValue - _basePitchParam) * _pitchParamModifier;

    // 疲労による補正
    // ボール率増加、空振り率低下
    final fatigueBallIncrease = effectiveFatigue * _fatigueBallModifier;
    final fatigueSwingDecrease = effectiveFatigue * _fatigueSwingModifier;

    // 確率を調整
    // ボール率: 球種固有 + 制球力 + パラメータ補正 + 疲労 + 選球眼 + 長打力警戒
    final probBall = (_baseProbBall + pitchBallModifier - controlBallModifier - paramScaling * 0.5 + fatigueBallIncrease + eyeBallBonus + powerWalkBonus).clamp(0.20, 0.55);
    final probStrikeLooking = _baseProbStrikeLooking;
    // 空振り率: 球種固有 + 球速（ストレートのみ）+ パラメータ補正 - ミート力 - 疲労
    final probStrikeSwinging = (_baseProbStrikeSwinging + pitchSwingModifier + speedModifier + paramScaling - swingModifier - fatigueSwingDecrease).clamp(0.03, 0.30);
    final probFoul = _baseProbFoul;
    // インプレー確率は残り（他の結果にならなかった場合）

    final roll = _random.nextDouble();
    double cumulative = 0;

    // ボール
    cumulative += probBall;
    if (roll < cumulative) {
      return PitchResult(type: PitchResultType.ball, pitchType: pitchType, speed: speed);
    }

    // 見逃しストライク
    cumulative += probStrikeLooking;
    if (roll < cumulative) {
      return PitchResult(type: PitchResultType.strikeLooking, pitchType: pitchType, speed: speed);
    }

    // 空振りストライク
    cumulative += probStrikeSwinging;
    if (roll < cumulative) {
      return PitchResult(type: PitchResultType.strikeSwinging, pitchType: pitchType, speed: speed);
    }

    // ファウル
    cumulative += probFoul;
    if (roll < cumulative) {
      return PitchResult(type: PitchResultType.foul, pitchType: pitchType, speed: speed);
    }

    // インプレー
    final battedBallType = _randomBattedBallType();
    final fieldPosition = _randomFieldPosition(battedBallType);
    return PitchResult(type: PitchResultType.inPlay, pitchType: pitchType, battedBallType: battedBallType, fieldPosition: fieldPosition, speed: speed);
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

  // 内野安打の基本確率（走力1あたり）
  static const double _infieldHitBaseRate = 0.012;

  /// 内野安打の確率を計算
  /// batterSpeed: 打者の走力（1〜10）
  /// fieldPosition: 打球方向
  /// fielding: 守備力（1〜10）
  double _calcInfieldHitProbability(int batterSpeed, FieldPosition fieldPosition, int fielding, int arm) {
    // 基本確率: 走力 × 1.2%（走力10で12%）
    final baseProbability = batterSpeed * _infieldHitBaseRate;

    // 打球方向による補正
    double directionModifier;
    switch (fieldPosition) {
      case FieldPosition.third:
      case FieldPosition.shortstop:
        // 三遊間: 一塁からの距離が遠いので内野安打になりやすい
        directionModifier = 1.5;
        break;
      case FieldPosition.second:
        // 二塁: 普通
        directionModifier = 1.0;
        break;
      case FieldPosition.first:
        // 一塁: 一塁に近いので内野安打になりにくい
        directionModifier = 0.3;
        break;
      case FieldPosition.pitcher:
      case FieldPosition.catcher:
        // 投手、捕手: 特殊なケース
        directionModifier = 0.5;
        break;
      default:
        // 外野（通常ゴロは来ない）
        directionModifier = 0.0;
    }

    // 守備力による補正（守備力が高いほど内野安打減少）
    // 守備力5で1.0、守備力10で0.75、守備力1で1.2
    final fieldingModifier = 1.0 - (fielding - 5) * 0.05;

    // 肩の強さによる補正（肩が強いほど内野安打減少）
    // 肩5で1.0、肩10で0.85、肩1で1.12
    final armModifier = 1.0 - (arm - 5) * 0.03;

    return (baseProbability * directionModifier * fieldingModifier * armModifier).clamp(0.0, 0.25);
  }

  /// インプレー結果の確率データ
  /// 確率計算ロジックをsimulateInPlayResultから分離
  InPlayProbabilities _calculateInPlayProbabilities({
    required int speed,
    required int control,
    required int power,
    required int fielding,
    required int catcherLead,
    required PitchType pitchType,
    required int pitchParam,
    required double fatigue,
  }) {
    // 球種に応じた実効疲労度を計算
    final effectiveFatigue = _getEffectiveFatigue(fatigue, pitchType);

    // 球速による補正（ストレートのみ、速いほどヒットが減る）
    double speedModifier = 0.0;
    if (pitchType == PitchType.fastball) {
      // 疲労による球速低下を考慮
      final fatigueSpeedDrop = (effectiveFatigue * _fatigueSpeedReduction).round();
      final effectiveSpeed = speed - fatigueSpeedDrop;
      final speedDiff = effectiveSpeed - _baseSpeed;
      speedModifier = speedDiff * _speedModifierPerKm;
    }

    // 制球力による補正（高いほど甘い球が減り、アウトが増える）
    final controlDiff = control - _baseControl;
    final controlModifier = controlDiff * _controlHitModifier;

    // 守備力による補正（高いほどアウトが増える）
    final fieldingDiff = fielding - _baseFielding;
    final fieldingModifierValue = fieldingDiff * _fieldingModifier;

    // 捕手リードによる補正（高いほどアウトが増える、おまけ程度）
    final leadDiff = catcherLead - 5;
    final leadModifierValue = leadDiff * _leadModifier;

    // 球種固有のベース補正
    final pitchOutModifier = _outModifiers[pitchType] ?? 0.0;
    final pitchXbhModifier = _xbhModifiers[pitchType] ?? 0.0;

    // パラメータによるスケーリング（パラメータ5で基準、1-10で±4%）
    final paramScaling = (pitchParam - _basePitchParam) * _pitchParamModifier;

    // 疲労による補正（アウト率低下、被長打率増加）
    final fatigueOutDecrease = effectiveFatigue * _fatigueOutModifier;
    final fatigueXbhIncrease = effectiveFatigue * _fatigueXbhModifier;

    // 長打力による補正（高いほど長打が増える）
    final powerDiff = power - _basePower;
    final homeRunModifier = powerDiff * _powerHomeRunModifier;
    final doubleModifier = powerDiff * _powerDoubleModifier;
    final tripleModifier = powerDiff * _powerTripleModifier;
    final singleModifier = powerDiff * _powerSingleModifier;

    // アウト率: 球種固有 + 球速（ストレートのみ）+ パラメータ + 制球力 + 守備力 + リード - 疲労
    final outModifier = pitchOutModifier +
        speedModifier +
        paramScaling +
        controlModifier +
        fieldingModifierValue +
        leadModifierValue -
        fatigueOutDecrease;
    final probOut = (_baseProbOut + outModifier).clamp(0.45, 0.85);

    // 長打確率（長打力 + 球種効果 + 疲労で変動）
    final probHomeRun =
        (0.04 + homeRunModifier + pitchXbhModifier + fatigueXbhIncrease).clamp(0.005, 0.18);
    final probTriple =
        (_baseProbTriple + tripleModifier + pitchXbhModifier * 0.3 + fatigueXbhIncrease * 0.3)
            .clamp(0.005, 0.04);
    final probDouble =
        (_baseProbDouble + doubleModifier + pitchXbhModifier * 0.5 + fatigueXbhIncrease * 0.5)
            .clamp(0.02, 0.15);
    final probSingle =
        (_baseProbSingle - outModifier * 0.5 + singleModifier).clamp(0.10, 0.35);

    return InPlayProbabilities(
      probOut: probOut,
      probSingle: probSingle,
      probDouble: probDouble,
      probTriple: probTriple,
      probHomeRun: probHomeRun,
    );
  }

  /// ゴロアウト判定（エラーチェック・内野安打チェック含む）
  InPlayResult _determineGroundOutResult({
    required FieldPosition? fieldPosition,
    required int fielding,
    required int? batterSpeed,
    required int? fielderArm,
  }) {
    // ゴロの場合、まずエラーチェック（内野のみ）
    if (fieldPosition != null && !fieldPosition.isOutfield) {
      if (_errorSimulator.checkGroundBallError(fielding, fieldPosition)) {
        // エラー発生 → 打者出塁
        return InPlayResult(
          result: AtBatResultType.reachedOnError,
          fieldingError: FieldingError(
            type: FieldingErrorType.fielding,
            position: fieldPosition,
            runsScored: 0, // 得点はGameSimulatorで計算
          ),
        );
      }
    }
    // エラーなし → 内野安打の可能性をチェック
    if (batterSpeed != null && fieldPosition != null) {
      final armValue = fielderArm ?? 5;
      final infieldHitProb = _calcInfieldHitProbability(batterSpeed, fieldPosition, fielding, armValue);
      if (_random.nextDouble() < infieldHitProb) {
        return const InPlayResult(result: AtBatResultType.infieldHit);
      }
    }
    return const InPlayResult(result: AtBatResultType.groundOut);
  }

  /// インプレー時の打席結果を決定（球速・制球力・長打力・守備力・走力・球種・疲労考慮）
  /// ミート力はインプレーになる確率に影響し、インプレー後の結果には影響しない
  /// fielding: 打球方向を守る野手の守備力（0〜10、nullの場合はデフォルト5）
  /// batterSpeed: 打者の走力（1〜10、内野安打判定に使用）
  /// fieldPosition: 打球方向（内野安打判定に使用）
  /// pitchType: 球種
  /// pitchParam: その球種のパラメータ値（1-10、nullは基準値5）
  /// fatigue: 基本疲労度（0.0〜1.0、デフォルト0）
  InPlayResult simulateInPlayResult(
    BattedBallType battedBallType,
    int speed,
    int control,
    int power,
    int? fielding, {
    int? batterSpeed,
    FieldPosition? fieldPosition,
    int? fielderArm,
    int? catcherLead,
    PitchType pitchType = PitchType.fastball,
    int? pitchParam,
    double fatigue = 0.0,
  }) {
    final fieldingValue = fielding ?? _baseFielding;
    final leadValue = catcherLead ?? 5;
    final paramValue = pitchParam ?? _basePitchParam;

    // 確率を計算
    final probs = _calculateInPlayProbabilities(
      speed: speed,
      control: control,
      power: power,
      fielding: fieldingValue,
      catcherLead: leadValue,
      pitchType: pitchType,
      pitchParam: paramValue,
      fatigue: fatigue,
    );

    final roll = _random.nextDouble();
    double cumulative = 0;

    // アウト判定
    cumulative += probs.probOut;
    if (roll < cumulative) {
      switch (battedBallType) {
        case BattedBallType.groundBall:
          return _determineGroundOutResult(
            fieldPosition: fieldPosition,
            fielding: fieldingValue,
            batterSpeed: batterSpeed,
            fielderArm: fielderArm,
          );
        case BattedBallType.flyBall:
          return const InPlayResult(result: AtBatResultType.flyOut);
        case BattedBallType.lineDrive:
          return const InPlayResult(result: AtBatResultType.lineOut);
      }
    }

    // 単打
    cumulative += probs.probSingle;
    if (roll < cumulative) {
      return const InPlayResult(result: AtBatResultType.single);
    }

    // 二塁打
    cumulative += probs.probDouble;
    if (roll < cumulative) {
      return const InPlayResult(result: AtBatResultType.double_);
    }

    // 三塁打
    cumulative += probs.probTriple;
    if (roll < cumulative) {
      return const InPlayResult(result: AtBatResultType.triple);
    }

    // 本塁打（残り）
    if (_random.nextDouble() < probs.probHomeRun / (probs.probHomeRun + 0.01)) {
      return const InPlayResult(result: AtBatResultType.homeRun);
    }
    // 本塁打にならなかった場合は二塁打
    return const InPlayResult(result: AtBatResultType.double_);
  }

  /// 1打席をシミュレート（盗塁判定を含む）
  /// pitchingTeam: 守備側チーム（打球方向の守備力を取得するため）
  /// runners: 現在のランナー状況
  /// outs: 現在のアウト数
  /// stealSimulator: 盗塁シミュレーター
  /// 投手から球種に対応するパラメータ値を取得（調子補正を適用）
  int? _getPitchParam(Player pitcher, PitchType pitchType, PitcherCondition condition) {
    int? baseParam;
    int modifier;

    switch (pitchType) {
      case PitchType.fastball:
        baseParam = pitcher.fastball;
        modifier = condition.fastballModifier;
        break;
      case PitchType.slider:
        baseParam = pitcher.slider;
        modifier = condition.sliderModifier;
        break;
      case PitchType.curveball:
        baseParam = pitcher.curve;
        modifier = condition.curveModifier;
        break;
      case PitchType.splitter:
        baseParam = pitcher.splitter;
        modifier = condition.splitterModifier;
        break;
      case PitchType.changeup:
        baseParam = pitcher.changeup;
        modifier = condition.changeupModifier;
        break;
    }

    if (baseParam == null) return null;
    // 調子補正を適用（1〜10の範囲内）
    return (baseParam + modifier).clamp(1, 10);
  }

  AtBatSimulationResult simulateAtBat(
    Player pitcher,
    Player batter,
    Team pitchingTeam, {
    required BaseRunners runners,
    required int outs,
    required StealSimulator stealSimulator,
    int pitchCount = 0, // この打席前までの投球数
    PitcherCondition condition = const PitcherCondition(), // 投手の調子
  }) {
    // 投手の平均球速（設定されていなければ145km）+ 調子補正
    final avgSpeed = (pitcher.averageSpeed ?? 145) + condition.speedModifier;
    // 投手の制球力（設定されていなければ5）+ 調子補正（1〜10の範囲内）
    final control = ((pitcher.control ?? 5) + condition.controlModifier).clamp(1, 10);
    // 投手のスタミナ（設定されていなければ5）
    final stamina = pitcher.stamina;
    // 打者のミート力（設定されていなければ5）
    final meet = batter.meet ?? 5;
    // 打者の長打力（設定されていなければ5）
    final power = batter.power ?? 5;
    // 打者の走力（設定されていなければ5）
    final batterSpeed = batter.speed ?? 5;
    // 打者の選球眼（設定されていなければ5）
    final eye = batter.eye ?? 5;
    // 捕手の肩の強さ（盗塁阻止に使用）
    final catcher = pitchingTeam.getFielder(FieldPosition.catcher);
    final catcherArm = catcher?.arm ?? 5;

    int balls = 0;
    int strikes = 0;
    final pitches = <PitchResult>[];
    final recordedSteals = <StealAttempt>[]; // 記録される盗塁
    var currentRunners = runners;
    int additionalOuts = 0;
    int currentPitchCount = pitchCount; // 打席中の投球数を追跡
    int batteryErrorRuns = 0; // バッテリーエラーによる得点
    // 捕手の守備力（パスボール判定に使用）
    final catcherFielding = catcher?.getFielding(DefensePosition.catcher) ?? 5;

    while (true) {
      // 盗塁失敗で3アウトになったら打席終了
      if (outs + additionalOuts >= 3) {
        return AtBatSimulationResult(
          result: AtBatResultType.strikeout, // ダミー（使われない）
          pitches: pitches,
          stealAttempts: recordedSteals,
          updatedRunners: currentRunners,
          additionalOuts: additionalOuts,
          batteryErrorRuns: batteryErrorRuns,
        );
      }

      // 1. 盗塁判定（投球前）
      final stealAttempts = stealSimulator.simulateSteal(currentRunners, outs + additionalOuts, catcherArm: catcherArm);

      // 2. 球種選択と投球
      // 疲労度を計算（投球数とスタミナに基づく）
      final fatigue = _calculateFatigue(currentPitchCount, stamina);
      final pitchType = _selectPitchType(pitcher, condition);
      final speed = _generatePitchSpeed(avgSpeed, pitchType);
      final pitchParam = _getPitchParam(pitcher, pitchType, condition);
      var pitch = simulatePitch(balls, strikes, speed, control, meet, pitchType, pitchParam, eye: eye, power: power, fatigue: fatigue);
      currentPitchCount++; // 投球数を増加

      // 2.5 ワイルドピッチ/パスボールチェック（ボール時のみ、ランナーがいる場合）
      BatteryError? currentBatteryError;
      if (pitch.type == PitchResultType.ball && currentRunners.hasRunners) {
        // ワイルドピッチチェック（投手の制球力と球種に依存）
        if (_errorSimulator.checkWildPitch(control, pitchType)) {
          final errorResult = _errorSimulator.applyBatteryError(
            ErrorType.wildPitch,
            currentRunners,
          );
          currentRunners = _errorSimulator.applyBatteryErrorToRunners(currentRunners);
          batteryErrorRuns += errorResult.runsScored;
          currentBatteryError = BatteryError(
            type: BatteryErrorType.wildPitch,
            runsScored: errorResult.runsScored,
          );
        }
        // ワイルドピッチでなければパスボールチェック（捕手の守備力と球種に依存）
        else if (_errorSimulator.checkPassedBall(catcherFielding, pitchType)) {
          final errorResult = _errorSimulator.applyBatteryError(
            ErrorType.passedBall,
            currentRunners,
          );
          currentRunners = _errorSimulator.applyBatteryErrorToRunners(currentRunners);
          batteryErrorRuns += errorResult.runsScored;
          currentBatteryError = BatteryError(
            type: BatteryErrorType.passedBall,
            runsScored: errorResult.runsScored,
          );
        }

        // バッテリーエラーがあればPitchResultを更新
        if (currentBatteryError != null) {
          pitch = PitchResult(
            type: pitch.type,
            pitchType: pitch.pitchType,
            battedBallType: pitch.battedBallType,
            fieldPosition: pitch.fieldPosition,
            speed: pitch.speed,
            steals: pitch.steals,
            batteryError: currentBatteryError,
          );
        }
      }

      // 3. 盗塁がある場合の処理
      if (stealAttempts.isNotEmpty) {
        final result = _resolveStealAndPitch(
          stealAttempts: stealAttempts,
          pitch: pitch,
          balls: balls,
          strikes: strikes,
          currentRunners: currentRunners,
          stealSimulator: stealSimulator,
          outs: outs + additionalOuts,
        );

        // 盗塁結果を反映
        currentRunners = result.newRunners;
        additionalOuts += result.additionalOuts;
        recordedSteals.addAll(result.recordedSteals);

        // 盗塁結果を投球に付加して記録（バッテリーエラーも保持）
        pitches.add(
          PitchResult(
            type: pitch.type,
            pitchType: pitch.pitchType,
            battedBallType: pitch.battedBallType,
            fieldPosition: pitch.fieldPosition,
            speed: pitch.speed,
            steals: stealAttempts,
            batteryError: pitch.batteryError,
          ),
        );

        // 盗塁失敗で3アウトになったら打席終了
        if (outs + additionalOuts >= 3) {
          return AtBatSimulationResult(
            result: AtBatResultType.strikeout, // ダミー（使われない）
            pitches: pitches,
            stealAttempts: recordedSteals,
            updatedRunners: currentRunners,
            additionalOuts: additionalOuts,
            batteryErrorRuns: batteryErrorRuns,
          );
        }
      } else {
        // 盗塁なしの場合
        pitches.add(pitch);
      }

      // 4. 打席終了条件をチェック（共通処理）
      final atBatEndCheck = _checkAtBatEnd(
        pitch: pitch,
        balls: balls,
        strikes: strikes,
        power: power,
        control: control,
        speed: speed,
        batterSpeed: batterSpeed,
        pitchingTeam: pitchingTeam,
        pitchParam: pitchParam,
        fatigue: fatigue,
      );

      if (atBatEndCheck.isEnded) {
        return AtBatSimulationResult(
          result: atBatEndCheck.result!,
          pitches: pitches,
          stealAttempts: recordedSteals,
          updatedRunners: currentRunners,
          additionalOuts: additionalOuts,
          fieldingError: atBatEndCheck.fieldingError,
          batteryErrorRuns: batteryErrorRuns,
        );
      }

      // 5. カウント更新（共通処理）
      _updateCount(pitch, balls, strikes, (b, s) {
        balls = b;
        strikes = s;
      });
    }
  }

  /// 盗塁と投球の組み合わせを解決
  _StealPitchResult _resolveStealAndPitch({
    required List<StealAttempt> stealAttempts,
    required PitchResult pitch,
    required int balls,
    required int strikes,
    required BaseRunners currentRunners,
    required StealSimulator stealSimulator,
    required int outs,
  }) {
    var newRunners = currentRunners;
    int additionalOuts = 0;
    final recordedSteals = <StealAttempt>[];

    // 投球結果による打席終了判定（四球時の盗塁記録判定に使用）
    final isBall4 = pitch.type == PitchResultType.ball && balls >= 3;

    // 盗塁結果を適用
    final (runnersAfterSteal, outsAfterSteal) = stealSimulator.applyStealResult(currentRunners, outs, stealAttempts);
    newRunners = runnersAfterSteal;
    additionalOuts = outsAfterSteal - outs;

    // 成功した盗塁を記録するかどうか判定
    for (final attempt in stealAttempts) {
      if (attempt.success) {
        // 四球時、押し出し対象のランナーは盗塁記録なし
        if (isBall4 && _isForceAdvance(attempt.fromBase, currentRunners)) {
          // 押し出し対象なので盗塁記録なし
          continue;
        }
        // それ以外は盗塁成功として記録
        recordedSteals.add(attempt);
      }
      // 失敗した盗塁は記録しない（caught stealingは別途カウント）
    }

    return _StealPitchResult(newRunners: newRunners, additionalOuts: additionalOuts, recordedSteals: recordedSteals);
  }

  /// ランナーが押し出し対象かどうか
  bool _isForceAdvance(Base fromBase, BaseRunners runners) {
    switch (fromBase) {
      case Base.first:
        return true; // 1塁ランナーは常に押し出し対象
      case Base.second:
        return runners.first != null; // 1塁にランナーがいれば押し出し
      case Base.third:
        return runners.first != null && runners.second != null; // 満塁なら押し出し
      case Base.home:
        return false;
    }
  }

  /// 打席終了条件をチェック
  AtBatEndCheckResult _checkAtBatEnd({
    required PitchResult pitch,
    required int balls,
    required int strikes,
    required int power,
    required int control,
    required int speed,
    required int batterSpeed,
    required Team pitchingTeam,
    required int? pitchParam,
    double fatigue = 0.0,
  }) {
    switch (pitch.type) {
      case PitchResultType.ball:
        if (balls >= 3) {
          return const AtBatEndCheckResult(result: AtBatResultType.walk);
        }
        return const AtBatEndCheckResult();

      case PitchResultType.strikeLooking:
      case PitchResultType.strikeSwinging:
        if (strikes >= 2) {
          return const AtBatEndCheckResult(result: AtBatResultType.strikeout);
        }
        return const AtBatEndCheckResult();

      case PitchResultType.foul:
        return const AtBatEndCheckResult();

      case PitchResultType.inPlay:
        final fielding = pitchingTeam.getFieldingAt(pitch.fieldPosition!);
        final fielder = pitchingTeam.getFielder(pitch.fieldPosition!);
        final catcher = pitchingTeam.getFielder(FieldPosition.catcher);
        final inPlayResult = simulateInPlayResult(
          pitch.battedBallType!,
          speed,
          control,
          power,
          fielding,
          batterSpeed: batterSpeed,
          fieldPosition: pitch.fieldPosition,
          fielderArm: fielder?.arm,
          catcherLead: catcher?.lead,
          pitchType: pitch.pitchType,
          pitchParam: pitchParam,
          fatigue: fatigue,
        );
        return AtBatEndCheckResult(
          result: inPlayResult.result,
          fieldingError: inPlayResult.fieldingError,
        );
    }
  }

  /// カウント更新
  void _updateCount(PitchResult pitch, int balls, int strikes, void Function(int, int) callback) {
    switch (pitch.type) {
      case PitchResultType.ball:
        callback(balls + 1, strikes);
        break;
      case PitchResultType.strikeLooking:
      case PitchResultType.strikeSwinging:
        callback(balls, strikes + 1);
        break;
      case PitchResultType.foul:
        if (strikes < 2) {
          callback(balls, strikes + 1);
        } else {
          callback(balls, strikes);
        }
        break;
      case PitchResultType.inPlay:
        callback(balls, strikes);
        break;
    }
  }
}

/// 盗塁と投球の組み合わせ結果
class _StealPitchResult {
  final BaseRunners newRunners;
  final int additionalOuts;
  final List<StealAttempt> recordedSteals;

  const _StealPitchResult({required this.newRunners, required this.additionalOuts, required this.recordedSteals});
}

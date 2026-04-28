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

  /// バッテリーエラー（WP/PB）で生還した走者
  /// 失点の責任投手を特定するために必要（インヘリット走者の場合は前任投手の責任）
  /// type は自責点判定に使用（WP=自責、PB=不自責）
  final List<({Player runner, BatteryErrorType type})> batteryErrorScorers;

  const AtBatSimulationResult({
    required this.result,
    required this.pitches,
    this.stealAttempts = const [],
    required this.updatedRunners,
    this.additionalOuts = 0,
    this.fieldingError,
    this.batteryErrorRuns = 0,
    this.batteryErrorScorers = const [],
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

  // ミート力1あたりのインプレー時の打球の質補正
  // 高ミートでアウト率↓（=ヒット率↑）、低ミートでアウト率↑（=ヒット率↓）
  // ※ コンタクトの「質」のモデル化。低ミート打者（投手など）は当てても弱い当たりに。
  static const double _meetOutModifier = 0.020;

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

  // === プラトーン（左vs左=打者不利）補正 ===
  // 左投手 vs 左打者 のみ打者に不利な補正を適用
  // 右vs右は実際の野球でも専門家交代がほぼないため補正なし
  static const double _platoonSwingModifier = 0.02; // 空振り率 +2%
  static const double _platoonOutModifier = 0.02; // インプレー時のアウト率 +2%
  static const double _platoonBallModifier = -0.015; // ボール率 -1.5%（制球しやすい）

  // === 左打者の一塁ベース近さによる補正 ===
  // 左打者は一塁に近い位置から走れるため、内野安打が増える
  // （併殺率の補正は GameSimulator 側で適用）
  static const double _leftBatterInfieldHitMultiplier = 1.15; // 内野安打率 ×1.15

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
  /// isPlatoonDisadvantage: 利き手同士マッチアップで打者不利なら true
  /// batterSide: 打者の実効打席（打球方向バイアス用）
  PitchResult simulatePitch(int balls, int strikes, int speed, int control, int meet, PitchType pitchType, int? pitchParam, {int eye = 5, int power = 5, double fatigue = 0.0, bool isPlatoonDisadvantage = false, Handedness batterSide = Handedness.right}) {
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

    // プラトーン補正（同じ手=投手有利）
    final platoonBall = isPlatoonDisadvantage ? _platoonBallModifier : 0.0;
    final platoonSwing = isPlatoonDisadvantage ? _platoonSwingModifier : 0.0;

    // 確率を調整
    // ボール率: 球種固有 + 制球力 + パラメータ補正 + 疲労 + 選球眼 + 長打力警戒 + プラトーン
    final probBall = (_baseProbBall + pitchBallModifier - controlBallModifier - paramScaling * 0.5 + fatigueBallIncrease + eyeBallBonus + powerWalkBonus + platoonBall).clamp(0.20, 0.55);
    final probStrikeLooking = _baseProbStrikeLooking;
    // 空振り率: 球種固有 + 球速（ストレートのみ）+ パラメータ補正 - ミート力 - 疲労 + プラトーン
    final probStrikeSwinging = (_baseProbStrikeSwinging + pitchSwingModifier + speedModifier + paramScaling - swingModifier - fatigueSwingDecrease + platoonSwing).clamp(0.03, 0.30);
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
    final fieldPosition = _randomFieldPosition(battedBallType, batterSide);
    return PitchResult(type: PitchResultType.inPlay, pitchType: pitchType, battedBallType: battedBallType, fieldPosition: fieldPosition, speed: speed);
  }

  /// 打球の種類をランダムに決定
  BattedBallType _randomBattedBallType() {
    final roll = _random.nextDouble();
    if (roll < 0.45) return BattedBallType.groundBall;
    if (roll < 0.85) return BattedBallType.flyBall;
    return BattedBallType.lineDrive;
  }

  /// 打球方向をランダムに決定
  /// 打球の種類と打者の打席（利き手）によって確率が変わる
  /// 右打者はレフト方向・三遊間に引っ張りやすい
  /// 左打者はライト方向・一二塁間に引っ張りやすい
  FieldPosition _randomFieldPosition(
      BattedBallType battedBallType, Handedness batterSide) {
    final weights = _directionWeights(battedBallType, batterSide);
    return _pickWeighted(weights);
  }

  /// 重み付きで FieldPosition を選択
  FieldPosition _pickWeighted(Map<FieldPosition, double> weights) {
    final total = weights.values.fold(0.0, (a, b) => a + b);
    final roll = _random.nextDouble() * total;
    double cumulative = 0;
    for (final entry in weights.entries) {
      cumulative += entry.value;
      if (roll < cumulative) return entry.key;
    }
    return weights.keys.last;
  }

  /// 打球の種類と打者の打席から、各守備位置への打球確率（重み）を返す
  /// 基本分布はbothの値で、右/左に応じて pull/opposite のシフトを適用
  Map<FieldPosition, double> _directionWeights(
      BattedBallType battedBallType, Handedness batterSide) {
    switch (battedBallType) {
      case BattedBallType.groundBall:
        // 基本: 投手5, 一塁25, 二塁25, 三塁20, 遊撃25
        // 右打者はサード/ショートに引っ張る、左打者はファースト/セカンドに引っ張る
        double first = 25, second = 25, third = 20, shortstop = 25;
        if (batterSide == Handedness.right) {
          // 右打者: +左寄り
          third += 5;
          shortstop += 3;
          first -= 5;
          second -= 3;
        } else if (batterSide == Handedness.left) {
          // 左打者: +右寄り
          first += 5;
          second += 3;
          third -= 5;
          shortstop -= 3;
        }
        return {
          FieldPosition.pitcher: 5,
          FieldPosition.first: first,
          FieldPosition.second: second,
          FieldPosition.third: third,
          FieldPosition.shortstop: shortstop,
        };

      case BattedBallType.flyBall:
        // 基本: 捕手5, 一塁5, 二塁5, 三塁5, 遊撃5, 左翼25, 中堅30, 右翼20
        // 右打者はレフト方向、左打者はライト方向
        double left = 25, center = 30, right = 20;
        if (batterSide == Handedness.right) {
          left += 8;
          right -= 8;
        } else if (batterSide == Handedness.left) {
          right += 8;
          left -= 8;
        }
        return {
          FieldPosition.catcher: 5,
          FieldPosition.first: 5,
          FieldPosition.second: 5,
          FieldPosition.third: 5,
          FieldPosition.shortstop: 5,
          FieldPosition.left: left,
          FieldPosition.center: center,
          FieldPosition.right: right,
        };

      case BattedBallType.lineDrive:
        // 基本: 投手10, 一塁10, 二塁15, 三塁10, 遊撃15, 左翼15, 中堅15, 右翼10
        double first = 10, second = 15, third = 10, shortstop = 15;
        double leftOf = 15, rightOf = 10;
        if (batterSide == Handedness.right) {
          third += 3;
          shortstop += 2;
          leftOf += 4;
          first -= 3;
          second -= 2;
          rightOf -= 4;
        } else if (batterSide == Handedness.left) {
          first += 3;
          second += 2;
          rightOf += 4;
          third -= 3;
          shortstop -= 2;
          leftOf -= 4;
        }
        return {
          FieldPosition.pitcher: 10,
          FieldPosition.first: first,
          FieldPosition.second: second,
          FieldPosition.third: third,
          FieldPosition.shortstop: shortstop,
          FieldPosition.left: leftOf,
          FieldPosition.center: 15,
          FieldPosition.right: rightOf,
        };
    }
  }

  // 内野安打の基本確率（走力1あたり）
  static const double _infieldHitBaseRate = 0.012;

  /// 内野安打の確率を計算
  /// batterSpeed: 打者の走力（1〜10）
  /// fieldPosition: 打球方向
  /// fielding: 守備力（1〜10）
  /// isLeftBatter: 左打者なら一塁に近い分だけ有利
  double _calcInfieldHitProbability(int batterSpeed, FieldPosition fieldPosition, int fielding, int arm, {bool isLeftBatter = false}) {
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

    // 左打者は一塁に近いため内野安打になりやすい
    final leftBatterBonus = isLeftBatter ? _leftBatterInfieldHitMultiplier : 1.0;

    return (baseProbability *
            directionModifier *
            fieldingModifier *
            armModifier *
            leftBatterBonus)
        .clamp(0.0, 0.30);
  }

  /// インプレー結果の確率データ
  /// 確率計算ロジックをsimulateInPlayResultから分離
  InPlayProbabilities _calculateInPlayProbabilities({
    required int speed,
    required int control,
    required int meet,
    required int power,
    required int fielding,
    required int catcherLead,
    required PitchType pitchType,
    required int pitchParam,
    required double fatigue,
    bool isPlatoonDisadvantage = false,
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

    // ミート力によるアウト率補正
    // 高ミート → アウト率↓（ヒットが増える）、低ミート → アウト率↑（弱い当たり=アウト）
    // 投手のような低ミート打者は、当てても弱い当たりになりアウトになりやすい
    final meetDiff = meet - _baseMeet;
    final meetOutAdjustment = -meetDiff * _meetOutModifier;

    // プラトーン補正（同じ手=投手有利）
    final platoonOut = isPlatoonDisadvantage ? _platoonOutModifier : 0.0;

    // アウト率: 球種固有 + 球速（ストレートのみ）+ パラメータ + 制球力 + 守備力 + リード - 疲労 + ミート + プラトーン
    final outModifier = pitchOutModifier +
        speedModifier +
        paramScaling +
        controlModifier +
        fieldingModifierValue +
        leadModifierValue -
        fatigueOutDecrease +
        meetOutAdjustment +
        platoonOut;
    final probOut = (_baseProbOut + outModifier).clamp(0.45, 0.85);

    // 長打確率（長打力 + 球種効果 + 疲労で変動）
    // floor を 0.002 に下げて、低長打力打者（投手など）の HR をより抑える
    // 基本値 0.025 はインプレー結果の正規化後の HR 率がリーグ平均で約2.5%になるよう調整
    final probHomeRun =
        (0.025 + homeRunModifier + pitchXbhModifier + fatigueXbhIncrease)
            .clamp(0.002, 0.18);
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
    bool isLeftBatter = false,
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
      final infieldHitProb = _calcInfieldHitProbability(
        batterSpeed,
        fieldPosition,
        fielding,
        armValue,
        isLeftBatter: isLeftBatter,
      );
      if (_random.nextDouble() < infieldHitProb) {
        return const InPlayResult(result: AtBatResultType.infieldHit);
      }
    }
    return const InPlayResult(result: AtBatResultType.groundOut);
  }

  /// インプレー時の打席結果を決定（球速・制球力・ミート・長打力・守備力・走力・球種・疲労考慮）
  /// ミート力は (1) インプレーになる確率 (2) インプレー時のアウト率 の両方に影響
  /// fielding: 打球方向を守る野手の守備力（0〜10、nullの場合はデフォルト5）
  /// batterSpeed: 打者の走力（1〜10、内野安打判定に使用）
  /// fieldPosition: 打球方向（内野安打判定に使用）
  /// pitchType: 球種
  /// pitchParam: その球種のパラメータ値（1-10、nullは基準値5）
  /// fatigue: 基本疲労度（0.0〜1.0、デフォルト0）
  /// isPlatoonDisadvantage: 利き手同士マッチアップで打者不利なら true
  /// isLeftBatter: 左打者なら一塁に近い分だけ内野安打確率UP
  InPlayResult simulateInPlayResult(
    BattedBallType battedBallType,
    int speed,
    int control,
    int meet,
    int power,
    int? fielding, {
    int? batterSpeed,
    FieldPosition? fieldPosition,
    int? fielderArm,
    int? catcherLead,
    PitchType pitchType = PitchType.fastball,
    int? pitchParam,
    double fatigue = 0.0,
    bool isPlatoonDisadvantage = false,
    bool isLeftBatter = false,
  }) {
    final fieldingValue = fielding ?? _baseFielding;
    final leadValue = catcherLead ?? 5;
    final paramValue = pitchParam ?? _basePitchParam;

    // 確率を計算
    final probs = _calculateInPlayProbabilities(
      speed: speed,
      control: control,
      meet: meet,
      power: power,
      fielding: fieldingValue,
      catcherLead: leadValue,
      pitchType: pitchType,
      pitchParam: paramValue,
      fatigue: fatigue,
      isPlatoonDisadvantage: isPlatoonDisadvantage,
    );

    // 5つの確率を合算して正規化したうえでロール判定する。
    // 旧実装は「残り確率 → HR/Double 二択」を `probHomeRun / (probHomeRun + 0.01)` で
    // 行っていたが、probHomeRun が小さい（=低長打力）場合でも 30% 前後 HR に振られる
    // 不具合があったため、正規化して probHomeRun の比率がそのまま反映されるよう修正。
    final total = probs.probOut +
        probs.probSingle +
        probs.probDouble +
        probs.probTriple +
        probs.probHomeRun;
    final roll = _random.nextDouble() * total;
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
            isLeftBatter: isLeftBatter,
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

    // 残りは本塁打（probHomeRun 分）
    return const InPlayResult(result: AtBatResultType.homeRun);
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

    // 打者の実効打席（両打ちは対投手で決まる）と利き手マッチアップ
    final batterSide = batter.effectiveBatsAgainst(pitcher);
    final isLeftBatter = batterSide == Handedness.left;
    // プラトーン不利は左vs左のみ（右vs右は補正なし）
    final isPlatoonDisadvantage =
        pitcher.effectiveThrows == Handedness.left && isLeftBatter;

    int balls = 0;
    int strikes = 0;
    final pitches = <PitchResult>[];
    final recordedSteals = <StealAttempt>[]; // 記録される盗塁
    var currentRunners = runners;
    int additionalOuts = 0;
    int currentPitchCount = pitchCount; // 打席中の投球数を追跡
    int batteryErrorRuns = 0; // バッテリーエラーによる得点
    final batteryErrorScorers = <({Player runner, BatteryErrorType type})>[];
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
          batteryErrorScorers: batteryErrorScorers,
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
      var pitch = simulatePitch(
        balls,
        strikes,
        speed,
        control,
        meet,
        pitchType,
        pitchParam,
        eye: eye,
        power: power,
        fatigue: fatigue,
        isPlatoonDisadvantage: isPlatoonDisadvantage,
        batterSide: batterSide,
      );
      currentPitchCount++; // 投球数を増加

      // 2.5 ワイルドピッチ/パスボールチェック（ボール時のみ、ランナーがいる場合）
      BatteryError? currentBatteryError;
      if (pitch.type == PitchResultType.ball && currentRunners.hasRunners) {
        // ワイルドピッチチェック（投手の制球力と球種に依存）
        if (_errorSimulator.checkWildPitch(control, pitchType)) {
          final scorer = currentRunners.third; // 3塁ランナーが生還
          final errorResult = _errorSimulator.applyBatteryError(
            ErrorType.wildPitch,
            currentRunners,
          );
          currentRunners = _errorSimulator.applyBatteryErrorToRunners(currentRunners);
          batteryErrorRuns += errorResult.runsScored;
          if (errorResult.runsScored > 0 && scorer != null) {
            batteryErrorScorers.add(
              (runner: scorer, type: BatteryErrorType.wildPitch),
            );
          }
          currentBatteryError = BatteryError(
            type: BatteryErrorType.wildPitch,
            runsScored: errorResult.runsScored,
          );
        }
        // ワイルドピッチでなければパスボールチェック（捕手の守備力と球種に依存）
        else if (_errorSimulator.checkPassedBall(catcherFielding, pitchType)) {
          final scorer = currentRunners.third;
          final errorResult = _errorSimulator.applyBatteryError(
            ErrorType.passedBall,
            currentRunners,
          );
          currentRunners = _errorSimulator.applyBatteryErrorToRunners(currentRunners);
          batteryErrorRuns += errorResult.runsScored;
          if (errorResult.runsScored > 0 && scorer != null) {
            batteryErrorScorers.add(
              (runner: scorer, type: BatteryErrorType.passedBall),
            );
          }
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

        // フォアボール（ball 4）時は盗塁ではなく四球による進塁が優先される。
        // 走者位置は applyStealResult で既に進めた状態のままにするが、
        // pitch.steals に残る成功盗塁は SB として記録されないよう success=false に書き換える
        // （UI 上もフォアボール時の盗塁チップを表示しない）。
        // 盗塁失敗（CS）は実際にアウトが発生しているので、そのまま残す。
        final isBall4 =
            pitch.type == PitchResultType.ball && balls >= 3;
        final pitchSteals = isBall4
            ? stealAttempts
                .map((a) => a.success
                    ? StealAttempt(
                        runner: a.runner,
                        fromBase: a.fromBase,
                        toBase: a.toBase,
                        success: false,
                        isOut: false,
                      )
                    : a)
                .toList()
            : stealAttempts;

        // 盗塁結果を投球に付加して記録（バッテリーエラーも保持）
        pitches.add(
          PitchResult(
            type: pitch.type,
            pitchType: pitch.pitchType,
            battedBallType: pitch.battedBallType,
            fieldPosition: pitch.fieldPosition,
            speed: pitch.speed,
            steals: pitchSteals,
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
            batteryErrorScorers: batteryErrorScorers,
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
        meet: meet,
        power: power,
        control: control,
        speed: speed,
        batterSpeed: batterSpeed,
        pitchingTeam: pitchingTeam,
        pitchParam: pitchParam,
        fatigue: fatigue,
        isPlatoonDisadvantage: isPlatoonDisadvantage,
        isLeftBatter: isLeftBatter,
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
          batteryErrorScorers: batteryErrorScorers,
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
        // フォアボール（ball 4）時は盗塁としてカウントしない
        // 押し出されない走者の進塁も「フォアボール優先」で SB クレジットを付けない
        if (isBall4) continue;
        recordedSteals.add(attempt);
      }
      // 失敗した盗塁は記録しない（caught stealingは別途カウント）
    }

    return _StealPitchResult(newRunners: newRunners, additionalOuts: additionalOuts, recordedSteals: recordedSteals);
  }

  /// 打席終了条件をチェック
  AtBatEndCheckResult _checkAtBatEnd({
    required PitchResult pitch,
    required int balls,
    required int strikes,
    required int meet,
    required int power,
    required int control,
    required int speed,
    required int batterSpeed,
    required Team pitchingTeam,
    required int? pitchParam,
    double fatigue = 0.0,
    bool isPlatoonDisadvantage = false,
    bool isLeftBatter = false,
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
          meet,
          power,
          fielding,
          batterSpeed: batterSpeed,
          fieldPosition: pitch.fieldPosition,
          fielderArm: fielder?.arm,
          catcherLead: catcher?.lead,
          pitchType: pitch.pitchType,
          pitchParam: pitchParam,
          fatigue: fatigue,
          isPlatoonDisadvantage: isPlatoonDisadvantage,
          isLeftBatter: isLeftBatter,
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

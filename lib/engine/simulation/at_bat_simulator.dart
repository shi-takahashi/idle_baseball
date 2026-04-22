import 'dart:math';

import '../models/models.dart';
import 'steal_simulator.dart';

/// 打席シミュレーションの結果
class AtBatSimulationResult {
  final AtBatResultType result;
  final List<PitchResult> pitches;
  final List<StealAttempt> stealAttempts; // 打席中の盗塁（記録されるもののみ）
  final BaseRunners updatedRunners; // 盗塁後のランナー状況
  final int additionalOuts; // 盗塁失敗によるアウト数

  const AtBatSimulationResult({
    required this.result,
    required this.pitches,
    this.stealAttempts = const [],
    required this.updatedRunners,
    this.additionalOuts = 0,
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

  // カーブの球速低下量
  static const int _curveSpeedReduction = 25;

  // 基準カーブ（このカーブで基本確率になる）
  static const int _baseCurve = 5;

  // カーブ1あたりの補正率
  static const double _curveSwingModifier = 0.01; // 空振り確率補正
  static const double _curveOutModifier = 0.01; // アウト率補正

  // 基準ストレートの質（この値で基本確率になる）
  static const int _baseFastball = 5;

  // ストレートの質1あたりの補正率（キレ、ノビ等）
  static const double _fastballSwingModifier = 0.01; // 空振り確率補正
  static const double _fastballOutModifier = 0.01; // アウト率補正

  AtBatSimulator({Random? random}) : _random = random ?? Random();

  /// 投げる球種を選択
  /// avgSpeed: 平均球速（高いほどストレートを投げやすい）
  /// curve: カーブパラメータ（nullの場合はストレートのみ、高いほどカーブを投げやすい）
  PitchType _selectPitchType(int avgSpeed, int? curve) {
    // カーブが投げられない場合はストレート
    if (curve == null) return PitchType.fastball;

    // 球種選択の確率計算
    // 基準: 球速145km、カーブ5の場合は50:50
    // 球速が高いほどストレートを投げやすい、カーブが高いほどカーブを投げやすい
    final speedWeight = ((avgSpeed - 130) / 25.0).clamp(0.2, 1.0); // 130-155kmで0.2-1.0
    final curveWeight = (curve / 10.0).clamp(0.1, 1.0); // 1-10で0.1-1.0

    final totalWeight = speedWeight + curveWeight;
    final fastballProb = speedWeight / totalWeight;

    return _random.nextDouble() < fastballProb ? PitchType.fastball : PitchType.curveball;
  }

  /// 球種に応じた球速を生成
  int _generatePitchSpeed(int avgSpeed, PitchType pitchType) {
    final baseSpeed = pitchType == PitchType.curveball
        ? avgSpeed -
              _curveSpeedReduction // カーブは30km/h遅い
        : avgSpeed;
    return generateSpeed(baseSpeed);
  }

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
  /// pitchType: 球種
  /// fastball: ストレートの質パラメータ（ストレートの場合に使用）
  /// curve: カーブパラメータ（カーブの場合に使用）
  PitchResult simulatePitch(int balls, int strikes, int speed, int control, int meet, PitchType pitchType, int? fastball, int? curve) {
    // 球速による補正（速いほど空振り増、ヒット減）
    // ただしカーブの場合は球速ペナルティを受けない（curveパラメータで効果を決定）
    double speedModifier = 0.0;
    if (pitchType == PitchType.fastball) {
      final speedDiff = speed - _baseSpeed;
      speedModifier = speedDiff * _speedModifierPerKm;
    }

    // 制球力による補正（高いほどボール減）
    final controlDiff = control - _baseControl;
    final ballModifier = controlDiff * _controlBallModifier;

    // ミート力による補正（高いほど空振り減）
    final meetDiff = meet - _baseMeet;
    final swingModifier = meetDiff * _meetSwingModifier;

    // ストレートの質による空振り補正（キレ、ノビ等）
    // fastball 1: -4%, fastball 5: 0%, fastball 10: +5%
    double fastballSwingModifier = 0.0;
    if (pitchType == PitchType.fastball) {
      final fastballValue = fastball ?? _baseFastball;
      fastballSwingModifier = (fastballValue - _baseFastball) * _fastballSwingModifier;
    }

    // カーブによる空振り補正
    // カーブ1: -4%, カーブ5: 0%, カーブ10: +5%
    double curveSwingModifier = 0.0;
    if (pitchType == PitchType.curveball && curve != null) {
      curveSwingModifier = (curve - _baseCurve) * _curveSwingModifier;
    }

    // 確率を調整
    // 制球力が高いほどボール確率が下がる（ただし最低25%、最高45%）
    final probBall = (_baseProbBall - ballModifier).clamp(0.25, 0.45);
    final probStrikeLooking = _baseProbStrikeLooking;
    // ストレートは球速+質で空振り増、カーブはcurveパラメータで空振り増、ミート力が高いほど空振り減
    final probStrikeSwinging = (_baseProbStrikeSwinging + speedModifier + fastballSwingModifier - swingModifier + curveSwingModifier).clamp(0.03, 0.25);
    final probFoul = _baseProbFoul;
    // インプレー確率は残り
    final probInPlay = (1.0 - probBall - probStrikeLooking - probStrikeSwinging - probFoul).clamp(0.10, 0.30);

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
  double _calcInfieldHitProbability(int batterSpeed, FieldPosition fieldPosition, int fielding) {
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

    return (baseProbability * directionModifier * fieldingModifier).clamp(0.0, 0.25);
  }

  /// インプレー時の打席結果を決定（球速・制球力・長打力・守備力・走力・球種考慮）
  /// ミート力はインプレーになる確率に影響し、インプレー後の結果には影響しない
  /// fielding: 打球方向を守る野手の守備力（0〜10、nullの場合はデフォルト5）
  /// batterSpeed: 打者の走力（1〜10、内野安打判定に使用）
  /// fieldPosition: 打球方向（内野安打判定に使用）
  /// pitchType: 球種（カーブの場合はアウト率に影響）
  /// fastball: ストレートの質パラメータ（ストレートの場合に使用）
  /// curve: カーブパラメータ（カーブの場合に使用）
  AtBatResultType simulateInPlayResult(
    BattedBallType battedBallType,
    int speed,
    int control,
    int power,
    int? fielding, {
    int? batterSpeed,
    FieldPosition? fieldPosition,
    PitchType pitchType = PitchType.fastball,
    int? fastball,
    int? curve,
  }) {
    // 球速による補正（速いほどヒットが減る）
    // ただしカーブの場合は球速ペナルティを受けない（curveパラメータで効果を決定）
    double speedModifier = 0.0;
    if (pitchType == PitchType.fastball) {
      final speedDiff = speed - _baseSpeed;
      speedModifier = speedDiff * _speedModifierPerKm;
    }

    // 制球力による補正（高いほど甘い球が減り、アウトが増える）
    final controlDiff = control - _baseControl;
    final controlModifier = controlDiff * _controlHitModifier;

    // 守備力による補正（高いほどアウトが増える）
    final fieldingValue = fielding ?? _baseFielding;
    final fieldingDiff = fieldingValue - _baseFielding;
    final fieldingModifierValue = fieldingDiff * _fieldingModifier;

    // ストレートの質によるアウト率補正（キレ、ノビ等）
    // fastball 1: -4%, fastball 5: 0%, fastball 10: +5%
    double fastballOutModifier = 0.0;
    if (pitchType == PitchType.fastball) {
      final fastballValue = fastball ?? _baseFastball;
      fastballOutModifier = (fastballValue - _baseFastball) * _fastballOutModifier;
    }

    // カーブによるアウト率補正
    // カーブ1: -4%, カーブ5: 0%, カーブ10: +5%
    double curveOutModifier = 0.0;
    if (pitchType == PitchType.curveball && curve != null) {
      curveOutModifier = (curve - _baseCurve) * _curveOutModifier;
    }

    // 長打力による補正（高いほど長打が増える）
    final powerDiff = power - _basePower;
    final homeRunModifier = powerDiff * _powerHomeRunModifier;
    final doubleModifier = powerDiff * _powerDoubleModifier;
    final tripleModifier = powerDiff * _powerTripleModifier;
    final singleModifier = powerDiff * _powerSingleModifier;

    // アウト率（ストレートは球速+質で、カーブはcurveパラメータで、制球力・守備力も影響）
    final outModifier = speedModifier + fastballOutModifier + controlModifier + fieldingModifierValue + curveOutModifier;
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
          // ゴロの場合、内野安打の可能性をチェック
          if (batterSpeed != null && fieldPosition != null) {
            final infieldHitProb = _calcInfieldHitProbability(batterSpeed, fieldPosition, fieldingValue);
            if (_random.nextDouble() < infieldHitProb) {
              return AtBatResultType.infieldHit; // 内野安打
            }
          }
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

  /// 1打席をシミュレート（盗塁判定を含む）
  /// pitchingTeam: 守備側チーム（打球方向の守備力を取得するため）
  /// runners: 現在のランナー状況
  /// outs: 現在のアウト数
  /// stealSimulator: 盗塁シミュレーター
  AtBatSimulationResult simulateAtBat(
    Player pitcher,
    Player batter,
    Team pitchingTeam, {
    required BaseRunners runners,
    required int outs,
    required StealSimulator stealSimulator,
  }) {
    // 投手の平均球速（設定されていなければ145km）
    final avgSpeed = pitcher.averageSpeed ?? 145;
    // 投手の制球力（設定されていなければ5）
    final control = pitcher.control ?? 5;
    // 投手のカーブ（nullの場合は投げられない）
    final curve = pitcher.curve;
    // 投手のストレートの質（設定されていなければnull=基準値5）
    final fastball = pitcher.fastball;
    // 打者のミート力（設定されていなければ5）
    final meet = batter.meet ?? 5;
    // 打者の長打力（設定されていなければ5）
    final power = batter.power ?? 5;
    // 打者の走力（設定されていなければ5）
    final batterSpeed = batter.speed ?? 5;

    int balls = 0;
    int strikes = 0;
    final pitches = <PitchResult>[];
    final recordedSteals = <StealAttempt>[]; // 記録される盗塁
    var currentRunners = runners;
    int additionalOuts = 0;

    while (true) {
      // 盗塁失敗で3アウトになったら打席終了
      if (outs + additionalOuts >= 3) {
        return AtBatSimulationResult(
          result: AtBatResultType.strikeout, // ダミー（使われない）
          pitches: pitches,
          stealAttempts: recordedSteals,
          updatedRunners: currentRunners,
          additionalOuts: additionalOuts,
        );
      }

      // 1. 盗塁判定（投球前）
      final stealAttempts = stealSimulator.simulateSteal(currentRunners, outs + additionalOuts);

      // 2. 球種選択と投球
      final pitchType = _selectPitchType(avgSpeed, curve);
      final speed = _generatePitchSpeed(avgSpeed, pitchType);
      final pitch = simulatePitch(balls, strikes, speed, control, meet, pitchType, fastball, curve);

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

        // 盗塁結果を投球に付加して記録
        pitches.add(
          PitchResult(
            type: pitch.type,
            pitchType: pitch.pitchType,
            battedBallType: pitch.battedBallType,
            fieldPosition: pitch.fieldPosition,
            speed: pitch.speed,
            steals: stealAttempts,
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
          );
        }
      } else {
        // 盗塁なしの場合
        pitches.add(pitch);
      }

      // 4. 打席終了条件をチェック（共通処理）
      final atBatResult = _checkAtBatEnd(
        pitch: pitch,
        balls: balls,
        strikes: strikes,
        power: power,
        control: control,
        speed: speed,
        batterSpeed: batterSpeed,
        pitchingTeam: pitchingTeam,
        fastball: fastball,
        curve: curve,
      );

      if (atBatResult != null) {
        return AtBatSimulationResult(
          result: atBatResult,
          pitches: pitches,
          stealAttempts: recordedSteals,
          updatedRunners: currentRunners,
          additionalOuts: additionalOuts,
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
  AtBatResultType? _checkAtBatEnd({
    required PitchResult pitch,
    required int balls,
    required int strikes,
    required int power,
    required int control,
    required int speed,
    required int batterSpeed,
    required Team pitchingTeam,
    required int? fastball,
    required int? curve,
  }) {
    switch (pitch.type) {
      case PitchResultType.ball:
        if (balls >= 3) {
          return AtBatResultType.walk;
        }
        return null;

      case PitchResultType.strikeLooking:
      case PitchResultType.strikeSwinging:
        if (strikes >= 2) {
          return AtBatResultType.strikeout;
        }
        return null;

      case PitchResultType.foul:
        return null;

      case PitchResultType.inPlay:
        final fielding = pitchingTeam.getFieldingAt(pitch.fieldPosition!);
        return simulateInPlayResult(
          pitch.battedBallType!,
          speed,
          control,
          power,
          fielding,
          batterSpeed: batterSpeed,
          fieldPosition: pitch.fieldPosition,
          pitchType: pitch.pitchType,
          fastball: fastball,
          curve: curve,
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

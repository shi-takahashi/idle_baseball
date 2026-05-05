import 'dart:math';
import '../models/models.dart';

/// エラーの種類
enum ErrorType {
  wildPitch,      // ワイルドピッチ（投手の暴投）
  passedBall,     // パスボール（捕手の捕逸）
  fieldingError,  // フィールディングエラー（捕球ミス）
  throwingError,  // スローイングエラー（送球ミス）
  cushionError,   // クッションボール処理ミス（外野手）
}

extension ErrorTypeExtension on ErrorType {
  String get displayName {
    switch (this) {
      case ErrorType.wildPitch:
        return '暴投';
      case ErrorType.passedBall:
        return '捕逸';
      case ErrorType.fieldingError:
        return '捕球エラー';
      case ErrorType.throwingError:
        return '送球エラー';
      case ErrorType.cushionError:
        return '処理エラー';
    }
  }
}

/// エラー結果
class ErrorResult {
  final ErrorType type;
  final Player? responsible; // エラーした選手（null = 投手/捕手のバッテリーエラー）
  final FieldPosition? position; // エラーしたポジション

  const ErrorResult({
    required this.type,
    this.responsible,
    this.position,
  });

  @override
  String toString() {
    final posName = position?.shortName ?? '';
    return '$posName${type.displayName}';
  }
}

/// ワイルドピッチ/パスボールの結果
class BatteryErrorResult {
  final ErrorType type; // wildPitch or passedBall
  final List<(Player runner, Base from, Base to)> advances; // 進塁したランナー
  final int runsScored; // 得点

  const BatteryErrorResult({
    required this.type,
    required this.advances,
    required this.runsScored,
  });
}

/// フィールディングエラーの結果
class FieldingErrorResult {
  final ErrorType type;
  final FieldPosition position;
  final Player fielder;
  final List<(Player runner, Base from, Base to)> advances; // 進塁したランナー
  final int runsScored; // 得点
  final bool batterReachedBase; // 打者が塁に出たか

  const FieldingErrorResult({
    required this.type,
    required this.position,
    required this.fielder,
    required this.advances,
    required this.runsScored,
    required this.batterReachedBase,
  });
}

/// エラーシミュレーター
class ErrorSimulator {
  final Random _random;

  // === ワイルドピッチ/パスボール関連 ===
  // ワイルドピッチ基本確率（1投球あたり）
  static const double _baseWildPitchRate = 0.003; // 0.3%
  // 制球力による補正（1ポイントあたり）
  static const double _controlWildPitchModifier = 0.0006; // 制球力1で+0.24%、10で-0.18%
  // 変化球によるワイルドピッチ増加率
  static final Map<PitchType, double> _pitchTypeWildPitchModifier = {
    PitchType.fastball: 0.0,
    PitchType.slider: 0.001,    // +0.1%
    PitchType.curveball: 0.0015,    // +0.15%
    PitchType.splitter: 0.002,  // +0.2%（落ちる球は暴投しやすい）
    PitchType.changeup: 0.001,  // +0.1%
  };

  // パスボール基本確率（1投球あたり）
  static const double _basePassedBallRate = 0.001; // 0.1%
  // 捕手守備力による補正（1ポイントあたり）
  static const double _catcherFieldingPassedBallModifier = 0.0002;

  // === 内野エラー関連 ===
  // ゴロエラー基本確率（捕球 + 送球の合算）。
  // 検知時に [pickGroundBallErrorType] で 捕球エラー / 送球エラー に振り分ける。
  // NPB 水準（1チーム143試合で60〜80失策、リーグ全体で約 0.45 失策/試合）に
  // 外野フライエラー・クッションエラーを足して合致するよう設定。
  static const double _baseGroundBallErrorRate = 0.04; // 4%
  // 内野ゴロエラー検知時の「捕球 vs 送球」内訳（NPB の実績に近い 6:4）
  static const double _groundBallFieldingErrorShare = 0.6;
  // 守備力による補正（1ポイントあたり）
  static const double _fieldingErrorModifier = 0.006; // 守備力1で+2.4%、10で-3.0%
  // ポジション別の難易度補正
  static const Map<FieldPosition, double> _positionErrorModifier = {
    FieldPosition.pitcher: 0.010,   // 投手は守備機会少なく難しい
    FieldPosition.catcher: 0.006,   // 捕手も難しい
    FieldPosition.first: -0.010,    // 一塁は比較的簡単
    FieldPosition.second: 0.0,      // 二塁は標準
    FieldPosition.third: 0.010,     // 三塁は強い打球が多い
    FieldPosition.shortstop: 0.006, // 遊撃は守備範囲広く難しい
  };

  // === 外野エラー関連 ===
  // 外野手のエラーは「ヒット + 追加進塁」の形で発生する。
  // 単独で「アウトをセーフに」するエラー（外野フライ落球）はプロレベルで
  // ほぼあり得ないので未実装。
  //
  // 二塁打エラー（クッション処理ミス + 中継返球ミス）基本確率
  static const double _baseDoubleErrorRate = 0.015; // 1.5%
  // 単打エラー（中継返球ミス）基本確率
  // クッション処理を伴わず、長距離返球の機会も少ないため低め
  static const double _baseSingleErrorRate = 0.005; // 0.5%
  // 守備力による補正（共通）
  static const double _outfieldFieldingErrorModifier = 0.003;

  // 二塁打エラー検知時の内訳: クッション処理ミス vs 中継返球ミス
  static const double _doubleCushionShare = 0.70;

  ErrorSimulator({Random? random}) : _random = random ?? Random();

  /// ワイルドピッチ判定
  /// control: 投手の制球力
  /// pitchType: 球種
  /// 戻り値: ワイルドピッチが発生したらtrue
  bool checkWildPitch(int control, PitchType pitchType) {
    final controlDiff = control - 5;
    final controlModifier = controlDiff * _controlWildPitchModifier;
    final pitchModifier = _pitchTypeWildPitchModifier[pitchType] ?? 0.0;

    final probability = (_baseWildPitchRate - controlModifier + pitchModifier).clamp(0.001, 0.015);
    return _random.nextDouble() < probability;
  }

  /// パスボール判定
  /// catcherFielding: 捕手の守備力
  /// pitchType: 球種（変化球はパスボールしやすい）
  bool checkPassedBall(int catcherFielding, PitchType pitchType) {
    final fieldingDiff = catcherFielding - 5;
    final fieldingModifier = fieldingDiff * _catcherFieldingPassedBallModifier;
    final pitchModifier = (_pitchTypeWildPitchModifier[pitchType] ?? 0.0) * 0.5; // ワイルドピッチより影響小

    final probability = (_basePassedBallRate - fieldingModifier + pitchModifier).clamp(0.0002, 0.005);
    return _random.nextDouble() < probability;
  }

  /// ワイルドピッチ/パスボール時のランナー進塁を計算
  BatteryErrorResult applyBatteryError(
    ErrorType type,
    BaseRunners runners,
  ) {
    final advances = <(Player, Base, Base)>[];
    var runsScored = 0;

    // ランナーは1つずつ進塁（3塁ランナーはホームイン）
    if (runners.third != null) {
      advances.add((runners.third!, Base.third, Base.home));
      runsScored++;
    }
    if (runners.second != null) {
      advances.add((runners.second!, Base.second, Base.third));
    }
    if (runners.first != null) {
      advances.add((runners.first!, Base.first, Base.second));
    }

    return BatteryErrorResult(
      type: type,
      advances: advances,
      runsScored: runsScored,
    );
  }

  /// ワイルドピッチ/パスボール後のランナー状況を更新
  BaseRunners applyBatteryErrorToRunners(BaseRunners runners) {
    return BaseRunners(
      first: null, // 1塁ランナーは2塁へ
      second: runners.first, // 元1塁ランナーが2塁へ
      third: runners.second, // 元2塁ランナーが3塁へ（3塁ランナーはホームイン）
    );
  }

  /// 内野ゴロエラー判定
  /// fielding: 守る野手の守備力
  /// position: 守備位置
  /// 戻り値: エラーが発生したらtrue
  bool checkGroundBallError(int fielding, FieldPosition position) {
    final fieldingDiff = fielding - 5;
    final fieldingModifier = fieldingDiff * _fieldingErrorModifier;
    final posModifier = _positionErrorModifier[position] ?? 0.0;

    final probability = (_baseGroundBallErrorRate - fieldingModifier + posModifier).clamp(0.010, 0.12);
    return _random.nextDouble() < probability;
  }

  /// 内野ゴロエラー検知時の内訳を抽選する。
  /// - [FieldingErrorType.fielding]（捕球失策、ゴロが股を抜けた等）: 60%
  /// - [FieldingErrorType.throwing]（送球失策、悪送球で打者出塁）: 40%
  /// 進塁ロジックはどちらも同じ（打者出塁・各走者 1 つずつ進塁）。
  /// 表示と統計の内訳のみが異なる。
  FieldingErrorType pickGroundBallErrorType() {
    return _random.nextDouble() < _groundBallFieldingErrorShare
        ? FieldingErrorType.fielding
        : FieldingErrorType.throwing;
  }


  /// 内野エラー時のランナー進塁を計算
  /// batterSpeed: 打者の走力（エラー時の進塁に影響）
  FieldingErrorResult applyFieldingError(
    FieldPosition position,
    Player fielder,
    BaseRunners runners,
    Player batter,
    int batterSpeed,
  ) {
    final advances = <(Player, Base, Base)>[];
    var runsScored = 0;

    // エラー時、各ランナーは基本的に1つ進塁
    // 走力が高いランナーは追加進塁の可能性あり
    if (runners.third != null) {
      // 3塁ランナーはホームイン
      advances.add((runners.third!, Base.third, Base.home));
      runsScored++;
    }
    if (runners.second != null) {
      // 2塁ランナーは3塁へ（走力が高ければホームも）
      final runnerSpeed = runners.second!.speed ?? 5;
      if (runnerSpeed >= 7 && _random.nextDouble() < 0.3 + (runnerSpeed - 7) * 0.1) {
        advances.add((runners.second!, Base.second, Base.home));
        runsScored++;
      } else {
        advances.add((runners.second!, Base.second, Base.third));
      }
    }
    if (runners.first != null) {
      // 1塁ランナーは2塁へ（走力が高ければ3塁も）
      final runnerSpeed = runners.first!.speed ?? 5;
      if (runnerSpeed >= 8 && runners.second == null && _random.nextDouble() < 0.2 + (runnerSpeed - 8) * 0.1) {
        advances.add((runners.first!, Base.first, Base.third));
      } else {
        advances.add((runners.first!, Base.first, Base.second));
      }
    }

    // 打者は1塁へ（エラーなので打者は必ず出塁）
    return FieldingErrorResult(
      type: ErrorType.fieldingError,
      position: position,
      fielder: fielder,
      advances: advances,
      runsScored: runsScored,
      batterReachedBase: true,
    );
  }

  /// エラー後のランナー状況を更新（内野エラー用）
  BaseRunners applyFieldingErrorToRunners(
    BaseRunners runners,
    Player batter,
    FieldingErrorResult error,
  ) {
    Player? newFirst;
    Player? newSecond;
    Player? newThird;

    // 各進塁を適用
    for (final (runner, _, to) in error.advances) {
      switch (to) {
        case Base.second:
          newSecond = runner;
          break;
        case Base.third:
          newThird = runner;
          break;
        case Base.home:
          // ホームインは何もしない（得点として処理済み）
          break;
        case Base.first:
          newFirst = runner;
          break;
      }
    }

    // 打者は1塁へ
    if (error.batterReachedBase) {
      newFirst = batter;
    }

    return BaseRunners(
      first: newFirst,
      second: newSecond,
      third: newThird,
    );
  }

  /// 二塁打エラー判定（クッション処理ミス + 中継本塁返球ミス）。
  /// 二塁打が出た外野方向で、外野手のミスにより打者が三塁まで進むケース。
  /// fielding: 外野手の守備力
  bool checkDoubleError(int fielding, FieldPosition position) {
    if (!position.isOutfield) return false;
    final fieldingDiff = fielding - 5;
    final fieldingModifier = fieldingDiff * _outfieldFieldingErrorModifier;
    final probability =
        (_baseDoubleErrorRate - fieldingModifier).clamp(0.003, 0.04);
    return _random.nextDouble() < probability;
  }

  /// 単打エラー判定（中継・返球ミス）。
  /// 単打が出た外野方向で、外野手の返球ミスにより打者が二塁まで進むケース。
  /// 二塁打エラーより低確率（クッション処理がなく長距離返球の機会も少ない）。
  bool checkSingleError(int fielding, FieldPosition position) {
    if (!position.isOutfield) return false;
    final fieldingDiff = fielding - 5;
    final fieldingModifier = fieldingDiff * _outfieldFieldingErrorModifier;
    final probability =
        (_baseSingleErrorRate - fieldingModifier).clamp(0.001, 0.02);
    return _random.nextDouble() < probability;
  }

  /// 二塁打エラー検知時の内訳を抽選。
  /// - [FieldingErrorType.cushion]（クッション処理ミス）: 70%
  /// - [FieldingErrorType.throwing]（中継・本塁返球ミス）: 30%
  /// 進塁ロジックはどちらも同じ（打者が三塁まで進む）。
  FieldingErrorType pickDoubleErrorType() {
    return _random.nextDouble() < _doubleCushionShare
        ? FieldingErrorType.cushion
        : FieldingErrorType.throwing;
  }
}

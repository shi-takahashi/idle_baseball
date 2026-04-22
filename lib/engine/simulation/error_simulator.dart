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

/// 外野エラーの結果（長打時のクッションボール/返球ミス）
class OutfieldErrorResult {
  final ErrorType type;
  final FieldPosition position;
  final Player fielder;
  final List<(Player runner, Base from, Base to)> extraAdvances; // 追加進塁
  final int extraRuns; // 追加得点

  const OutfieldErrorResult({
    required this.type,
    required this.position,
    required this.fielder,
    required this.extraAdvances,
    required this.extraRuns,
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
  // ゴロエラー基本確率
  static const double _baseGroundBallErrorRate = 0.02; // 2%
  // 守備力による補正（1ポイントあたり）
  static const double _fieldingErrorModifier = 0.003; // 守備力1で+1.2%、10で-1.5%
  // ポジション別の難易度補正
  static const Map<FieldPosition, double> _positionErrorModifier = {
    FieldPosition.pitcher: 0.005,   // 投手は守備機会少なく難しい
    FieldPosition.catcher: 0.003,   // 捕手も難しい
    FieldPosition.first: -0.005,    // 一塁は比較的簡単
    FieldPosition.second: 0.0,      // 二塁は標準
    FieldPosition.third: 0.005,     // 三塁は強い打球が多い
    FieldPosition.shortstop: 0.003, // 遊撃は守備範囲広く難しい
  };

  // === 外野エラー関連 ===
  // クッションボール/返球エラー基本確率（長打時）
  static const double _baseOutfieldErrorRate = 0.015; // 1.5%
  // 守備力による補正
  static const double _outfieldFieldingErrorModifier = 0.003;

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

    final probability = (_baseGroundBallErrorRate - fieldingModifier + posModifier).clamp(0.005, 0.06);
    return _random.nextDouble() < probability;
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

  /// 外野エラー判定（長打時のクッションボール/返球ミス）
  /// fielding: 外野手の守備力
  /// position: 守備位置
  bool checkOutfieldError(int fielding, FieldPosition position) {
    final fieldingDiff = fielding - 5;
    final fieldingModifier = fieldingDiff * _outfieldFieldingErrorModifier;

    final probability = (_baseOutfieldErrorRate - fieldingModifier).clamp(0.003, 0.04);
    return _random.nextDouble() < probability;
  }

  /// 外野エラー時の追加進塁を計算
  /// hitType: 打球の種類（double_/triple）
  /// runners: 現在のランナー状況（進塁適用後）
  /// batter: 打者
  OutfieldErrorResult applyOutfieldError(
    FieldPosition position,
    Player fielder,
    AtBatResultType hitType,
    BaseRunners runnersAfterHit,
    Player batter,
  ) {
    final extraAdvances = <(Player, Base, Base)>[];
    var extraRuns = 0;

    // 二塁打→三塁打相当になる（打者が3塁へ）
    if (hitType == AtBatResultType.double_) {
      // 打者は2塁にいるはずなので3塁へ
      extraAdvances.add((batter, Base.second, Base.third));

      // 3塁にいたランナーがいればホームへ
      if (runnersAfterHit.third != null) {
        extraAdvances.add((runnersAfterHit.third!, Base.third, Base.home));
        extraRuns++;
      }
    }

    return OutfieldErrorResult(
      type: ErrorType.cushionError,
      position: position,
      fielder: fielder,
      extraAdvances: extraAdvances,
      extraRuns: extraRuns,
    );
  }
}

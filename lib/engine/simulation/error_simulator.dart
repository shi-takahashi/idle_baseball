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
  // ワイルドピッチ基本確率（1投球あたり、ボール球＋走者ありの投球で判定）。
  // 2026-05-17: 旧 0.003 では 143試合換算 WP 約11本と NPB（40〜60）比で
  // 少なすぎ「試合でほぼ見ない」状態だったため引き上げ。
  // 2026-05-18: 球種差を強めた（下記）ぶん、リーグ全体の WP 水準を保つため
  // ベースを 0.017→0.015 に再センタ（球種補正の平均増加と相殺）。
  static const double _baseWildPitchRate = 0.015; // 1.5%
  // 制球力による補正（1ポイントあたり）
  static const double _controlWildPitchModifier = 0.0010; // 制球力1で+0.4%、10で-0.5%
  // 球種によるワイルドピッチ増加率。
  // 2026-05-18: 旧実装は球種差が ±0.2% と小さく、ベース＋制球力の変動に
  // 埋もれて「スプリットは暴投しやすい」が成績に出ていなかった。落差の大きい
  // 球（スプリット・カーブ）ほど捕手の前でワンバウンドしやすい、という個性が
  // イニング詳細・成績で観測できるよう球種差を約4.5倍に拡大した。
  static final Map<PitchType, double> _pitchTypeWildPitchModifier = {
    PitchType.fastball: 0.0,      // 基準（最も逸らしにくい）
    PitchType.shoot: 0.001,       // +0.1%（ツーシーム系。ほぼ逸らさない）
    PitchType.cutter: 0.001,      // +0.1%
    PitchType.slider: 0.002,      // +0.2%
    PitchType.changeup: 0.003,    // +0.3%
    PitchType.sinker: 0.006,      // +0.6%（沈む球）
    PitchType.curveball: 0.006,   // +0.6%（大きく曲がり落ちる）
    PitchType.splitter: 0.009,    // +0.9%（鋭く落ちる＝最も暴投・捕逸しやすい）
  };

  // パスボール基本確率（1投球あたり、ボール球＋走者ありの投球で判定）。
  // 2026-05-17: WP と同様、旧 0.001 では少なすぎたため引き上げ（NPB 5〜15）。
  // 2026-05-18: 球種差拡大に伴い、リーグ PB 水準を保つためベースを再センタ。
  static const double _basePassedBallRate = 0.002; // 0.2%
  // 捕手守備力による補正（1ポイントあたり）
  static const double _catcherFieldingPassedBallModifier = 0.0004;

  // === 内野エラー関連 ===
  // ゴロエラー判定。検知時に [pickGroundBallErrorType] で 捕球 / 送球 に振り分ける。
  //
  // 2026-05-23: 旧設計（base 0.048 + 線形 modifier 0.006/pt + clamp 下限 0.010）
  // では NPB 比でエラー数が約2倍多く、守備力差もランダム性に埋もれて推測ゲーム
  // として機能していなかった。具体的には 150 試合換算で
  //   遊撃 守備力5: 26.9 個（NPB 目安 10〜15）
  //   遊撃 守備力8: 15.2 個（守備力9のサンプルゼロ＝ほぼ生成されない）
  // という状態。clamp 下限 0.010 が守備力9 以上の値を切り捨てており、能力9 の
  // 名手でも普通の守備力に均されていた。
  //
  // 新設計: 「ポジション別 base（守備力5のエラー確率）× 守備力スケール」の積で
  // 表現。守備力スケールは 1pt あたり 0.7 倍の指数減衰で、守備力9 で base の
  // 0.24 倍まで落ちる（線形 modifier より上下を引き離す、[feedback_parameter_influence]）。
  //
  // NPB 目安（150試合、スタメン平均 = 守備力5 相当）:
  //   遊撃 10〜15 / 三塁 7〜12 / 二塁 5〜9 / 捕手 3〜5 / 一塁 ~5
  // base は計測値から逆算（ポジション別ゴロ機会数を所与として、目標エラー数を
  // 達成する確率を選定）。
  static const Map<FieldPosition, double> _positionErrorBase = {
    FieldPosition.pitcher: 0.020,   // 投手（機会少、難しい）
    FieldPosition.catcher: 0.030,   // 捕手（ゴロ機会少、難しい）
    FieldPosition.first: 0.014,     // 一塁（楽）
    FieldPosition.second: 0.018,    // 二塁
    FieldPosition.third: 0.027,     // 三塁（強い打球が多い）
    FieldPosition.shortstop: 0.024, // 遊撃（守備範囲広い）
  };
  // 守備力スケール（守備力5 = 1.0、1pt あたり 0.7 倍の指数減衰）。
  // 上下を引き離す非線形。守備力1 は 4.17 倍、守備力9 は 0.24 倍。
  static const Map<int, double> _fieldingErrorScale = {
    1: 4.17,
    2: 2.92,
    3: 2.04,
    4: 1.43,
    5: 1.00,
    6: 0.70,
    7: 0.49,
    8: 0.34,
    9: 0.24,
    10: 0.17,
  };
  // 内野ゴロエラー検知時の「捕球 vs 送球」内訳（NPB の実績に近い 6:4）
  static const double _groundBallFieldingErrorShare = 0.6;

  // === 外野エラー関連 ===
  // 外野手のエラーは「ヒット + 追加進塁」の形で発生する。
  // 単独で「アウトをセーフに」するエラー（外野フライ落球）はプロレベルで
  // ほぼあり得ないので未実装。
  //
  // 2026-05-23: 守備力ごとの非線形テーブルに変更。旧設計（base + 線形 modifier
  // 0.003/pt）では能力差がランダム性に埋もれており、150試合で守備力9=0個 /
  // 守備力5=1個 / 守備力1=5個と全体的に低すぎ、かつ上下差も小さかった。
  // 目標: 守備力 X の外野手は約 (10-X) 個 / 150試合（守備力1で9個、守備力5で
  // 5個、守備力9で1個）。上下を引き離すため線形でなく非線形テーブルで定義。
  //
  // 二塁打エラー（クッション処理ミス + 中継返球ミス）と単打エラー（中継返球
  // ミスのみ）の per-event 確率を守備力ごとに定義。二塁打側は長距離処理を
  // 伴うため確率高め（おおむね単打側の 3 倍）。
  static const Map<int, double> _outfieldDoubleErrorByFielding = {
    1: 0.120,
    2: 0.105,
    3: 0.092,
    4: 0.078,
    5: 0.068,
    6: 0.056,
    7: 0.045,
    8: 0.030,
    9: 0.016,
    10: 0.008,
  };
  static const Map<int, double> _outfieldSingleErrorByFielding = {
    1: 0.040,
    2: 0.035,
    3: 0.031,
    4: 0.026,
    5: 0.023,
    6: 0.019,
    7: 0.015,
    8: 0.010,
    9: 0.005,
    10: 0.0025,
  };

  // 二塁打エラー検知時の内訳: クッション処理ミス vs 中継返球ミス
  static const double _doubleCushionShare = 0.70;

  // === 捕手送球エラー関連 ===
  // 走者あり投球で独立試行する捕手の送球エラー（盗塁阻止失敗・牽制送球ミス等）。
  // NPB の捕手は PB を除く失策が 150試合あたり 3〜5 個。本ゲームでは捕手にゴロが
  // 飛ぶ機会自体が極小（_baseGroundBallErrorRate 経路では実質発生しない）ため、
  // 別経路として実装する。
  // per-runner-pitch（走者ありの投球）で独立試行。守備力5 で 0.06% (年 ~4個)、
  // 守備力9 で 0.014% (年 ~1個)。
  static const Map<int, double> _catcherThrowingErrorByFielding = {
    1: 0.0025,
    2: 0.0018,
    3: 0.0012,
    4: 0.00085,
    5: 0.00060,
    6: 0.00042,
    7: 0.00029,
    8: 0.00020,
    9: 0.00014,
    10: 0.00010,
  };

  /// 守れない（canPlay=false）ポジションに強引配置された選手のエラー倍率。
  /// NPB の「捕手不在で内野手が捕手」のような状況の表現で、守備力 1 の選手
  /// よりも明らかにミスが多発する想定。
  static const double _forcedPlacementErrorMultiplier = 3.0;

  ErrorSimulator({Random? random}) : _random = random ?? Random();

  /// ワイルドピッチ判定
  /// control: 投手の制球力
  /// pitchType: 球種
  /// 戻り値: ワイルドピッチが発生したらtrue
  bool checkWildPitch(int control, PitchType pitchType) {
    final controlDiff = control - 5;
    final controlModifier = controlDiff * _controlWildPitchModifier;
    final pitchModifier = _pitchTypeWildPitchModifier[pitchType] ?? 0.0;

    final probability = (_baseWildPitchRate - controlModifier + pitchModifier).clamp(0.001, 0.025);
    return _random.nextDouble() < probability;
  }

  /// パスボール判定
  /// catcherFielding: 捕手の守備力
  /// pitchType: 球種（変化球はパスボールしやすい）
  /// isForcedPlacement: 捕手不在で内野手等を強引配置している場合 true（エラー率3倍）
  bool checkPassedBall(int catcherFielding, PitchType pitchType,
      {bool isForcedPlacement = false}) {
    final fieldingDiff = catcherFielding - 5;
    final fieldingModifier = fieldingDiff * _catcherFieldingPassedBallModifier;
    final pitchModifier = (_pitchTypeWildPitchModifier[pitchType] ?? 0.0) * 0.5; // ワイルドピッチより影響小

    var probability = (_basePassedBallRate - fieldingModifier + pitchModifier).clamp(0.0002, 0.010);
    if (isForcedPlacement) probability *= _forcedPlacementErrorMultiplier;
    return _random.nextDouble() < probability;
  }

  /// 捕手の送球エラー判定（盗塁阻止失敗・牽制送球ミス等）。
  /// 走者あり投球で独立試行。発生時はランナー1つ進塁（WP/PB と同じ）。
  /// catcherFielding: 捕手の守備力
  /// isForcedPlacement: 捕手不在で内野手等を強引配置している場合 true（エラー率3倍）
  bool checkCatcherThrowingError(int catcherFielding,
      {bool isForcedPlacement = false}) {
    final f = catcherFielding.clamp(1, 10);
    var probability = _catcherThrowingErrorByFielding[f] ?? 0.0006;
    if (isForcedPlacement) probability *= _forcedPlacementErrorMultiplier;
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
  /// isForcedPlacement: 当該選手がその位置を「守れない」（canPlay=false）まま
  ///                    強引配置されている場合 true。エラー率3倍。
  /// 戻り値: エラーが発生したらtrue
  bool checkGroundBallError(int fielding, FieldPosition position,
      {bool isForcedPlacement = false}) {
    final base = _positionErrorBase[position] ?? 0.020;
    final f = fielding.clamp(1, 10);
    final scale = _fieldingErrorScale[f] ?? 1.0;
    var probability = base * scale;
    if (isForcedPlacement) probability *= _forcedPlacementErrorMultiplier;
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
  /// isForcedPlacement: 外野を「守れない」選手が強引配置されている場合 true（エラー率3倍）
  bool checkDoubleError(int fielding, FieldPosition position,
      {bool isForcedPlacement = false}) {
    if (!position.isOutfield) return false;
    final f = fielding.clamp(1, 10);
    var probability = _outfieldDoubleErrorByFielding[f] ?? 0.06;
    if (isForcedPlacement) probability *= _forcedPlacementErrorMultiplier;
    return _random.nextDouble() < probability;
  }

  /// 単打エラー判定（中継・返球ミス）。
  /// 単打が出た外野方向で、外野手の返球ミスにより打者が二塁まで進むケース。
  /// 二塁打エラーより低確率（クッション処理がなく長距離返球の機会も少ない）。
  /// isForcedPlacement: 外野を「守れない」選手が強引配置されている場合 true（エラー率3倍）
  bool checkSingleError(int fielding, FieldPosition position,
      {bool isForcedPlacement = false}) {
    if (!position.isOutfield) return false;
    final f = fielding.clamp(1, 10);
    var probability = _outfieldSingleErrorByFielding[f] ?? 0.02;
    if (isForcedPlacement) probability *= _forcedPlacementErrorMultiplier;
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

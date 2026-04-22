import 'dart:math';

import 'enums.dart';
import 'player.dart';

/// 投手の調子（試合ごとに変動）
/// 各パラメータに±2の補正を適用
class PitcherCondition {
  final int speedModifier;     // 球速補正（-2〜+2 km/h）
  final int fastballModifier;  // ストレートの質補正（-2〜+2）
  final int controlModifier;   // 制球力補正（-2〜+2）
  final int sliderModifier;    // スライダー補正（-2〜+2）
  final int curveModifier;     // カーブ補正（-2〜+2）
  final int splitterModifier;  // スプリット補正（-2〜+2）
  final int changeupModifier;  // チェンジアップ補正（-2〜+2）

  const PitcherCondition({
    this.speedModifier = 0,
    this.fastballModifier = 0,
    this.controlModifier = 0,
    this.sliderModifier = 0,
    this.curveModifier = 0,
    this.splitterModifier = 0,
    this.changeupModifier = 0,
  });

  /// ランダムに調子を生成（各パラメータ独立に-2〜+2）
  factory PitcherCondition.random(Random random) {
    return PitcherCondition(
      speedModifier: random.nextInt(5) - 2,     // -2, -1, 0, +1, +2
      fastballModifier: random.nextInt(5) - 2,
      controlModifier: random.nextInt(5) - 2,
      sliderModifier: random.nextInt(5) - 2,
      curveModifier: random.nextInt(5) - 2,
      splitterModifier: random.nextInt(5) - 2,
      changeupModifier: random.nextInt(5) - 2,
    );
  }

  /// 絶好調（全パラメータ+2）
  static const excellent = PitcherCondition(
    speedModifier: 2,
    fastballModifier: 2,
    controlModifier: 2,
    sliderModifier: 2,
    curveModifier: 2,
    splitterModifier: 2,
    changeupModifier: 2,
  );

  /// 絶不調（全パラメータ-2）
  static const terrible = PitcherCondition(
    speedModifier: -2,
    fastballModifier: -2,
    controlModifier: -2,
    sliderModifier: -2,
    curveModifier: -2,
    splitterModifier: -2,
    changeupModifier: -2,
  );

  /// 普通（全パラメータ±0）
  static const normal = PitcherCondition();

  @override
  String toString() {
    return 'PitcherCondition(速$speedModifier, 直$fastballModifier, 制$controlModifier, '
        'ス$sliderModifier, カ$curveModifier, フ$splitterModifier, チ$changeupModifier)';
  }
}

/// 盗塁の試み
class StealAttempt {
  final Player runner;
  final Base fromBase; // 元の塁
  final Base toBase; // 目標の塁
  final bool success; // 盗塁成功として記録
  final bool isOut; // アウトかどうか（ダブルスチール失敗時、1塁ランナーはアウトにならず進塁）

  const StealAttempt({
    required this.runner,
    required this.fromBase,
    required this.toBase,
    required this.success,
    this.isOut = false,
  });

  @override
  String toString() {
    final result = success ? '成功' : '失敗';
    return '${runner.name} ${fromBase.name}→${toBase.name} $result';
  }
}

/// 1球の結果
class PitchResult {
  final PitchResultType type;
  final PitchType pitchType; // 球種
  final BattedBallType? battedBallType; // インプレー時のみ
  final FieldPosition? fieldPosition; // インプレー時の打球方向
  final int speed; // 球速（km/h）
  final List<StealAttempt>? steals; // 盗塁の試み（ダブルスチール対応）

  const PitchResult({
    required this.type,
    required this.pitchType,
    this.battedBallType,
    this.fieldPosition,
    required this.speed,
    this.steals,
  });

  /// 盗塁があったかどうか
  bool get hasSteal => steals != null && steals!.isNotEmpty;

  /// 盗塁失敗があったかどうか
  bool get hasFailedSteal => steals?.any((s) => !s.success) ?? false;
}

/// 1打席の結果
class AtBatResult {
  final Player batter;
  final Player pitcher;
  final int inning;
  final bool isTop; // 表かどうか
  final List<PitchResult> pitches; // 全投球
  final AtBatResultType result;
  final FieldPosition? fieldPosition; // 打球方向（インプレー時のみ）
  final int rbiCount; // 打点
  final int outsBefore; // 打席前のアウトカウント
  final BaseRunners runnersBefore; // 打席前のランナー状況

  const AtBatResult({
    required this.batter,
    required this.pitcher,
    required this.inning,
    required this.isTop,
    required this.pitches,
    required this.result,
    this.fieldPosition,
    required this.rbiCount,
    required this.outsBefore,
    required this.runnersBefore,
  });

  /// 球数
  int get pitchCount => pitches.length;
}

/// 走者の状態
class BaseRunners {
  final Player? first;
  final Player? second;
  final Player? third;

  const BaseRunners({
    this.first,
    this.second,
    this.third,
  });

  /// 空の状態
  static const empty = BaseRunners();

  /// 走者がいるかどうか
  bool get hasRunners => first != null || second != null || third != null;

  /// 満塁かどうか
  bool get isLoaded => first != null && second != null && third != null;

  /// 走者の数
  int get count {
    int c = 0;
    if (first != null) c++;
    if (second != null) c++;
    if (third != null) c++;
    return c;
  }

  @override
  String toString() {
    final runners = <String>[];
    if (first != null) runners.add('1塁:${first!.name}');
    if (second != null) runners.add('2塁:${second!.name}');
    if (third != null) runners.add('3塁:${third!.name}');
    return runners.isEmpty ? '走者なし' : runners.join(', ');
  }

  /// 盗塁可能かどうか（少なくとも1人が盗塁可能な状態か）
  bool get canSteal {
    // 1塁ランナーが2塁へ盗塁可能: 2塁が空いている
    if (first != null && second == null) return true;
    // 2塁ランナーが3塁へ盗塁可能: 3塁が空いている
    if (second != null && third == null) return true;
    // ダブルスチール: 1,2塁で3塁が空いている
    if (first != null && second != null && third == null) return true;
    // その他は盗塁不可
    return false;
  }

  /// 盗塁可能なランナーのリストを取得
  /// 戻り値: [(ランナー, 元の塁, 目標の塁)]
  List<(Player, Base, Base)> getStealCandidates() {
    final candidates = <(Player, Base, Base)>[];

    // 2塁ランナーが3塁へ盗塁可能（先に判定、ダブルスチール時は2塁が先に走る）
    if (second != null && third == null) {
      candidates.add((second!, Base.second, Base.third));
    }

    // 1塁ランナーが2塁へ盗塁可能
    // 条件: 2塁が空いている、または2塁ランナーも同時に盗塁（ダブルスチール）
    if (first != null && (second == null || (second != null && third == null))) {
      candidates.add((first!, Base.first, Base.second));
    }

    return candidates;
  }

  /// 盗塁成功後のランナー状況を取得
  BaseRunners afterSuccessfulSteal(List<(Player, Base, Base)> steals) {
    Player? newFirst = first;
    Player? newSecond = second;
    Player? newThird = third;

    for (final (runner, from, to) in steals) {
      // 元の塁を空ける
      switch (from) {
        case Base.first:
          newFirst = null;
          break;
        case Base.second:
          newSecond = null;
          break;
        case Base.third:
          newThird = null;
          break;
        case Base.home:
          break;
      }
      // 目標の塁に移動
      switch (to) {
        case Base.first:
          newFirst = runner;
          break;
        case Base.second:
          newSecond = runner;
          break;
        case Base.third:
          newThird = runner;
          break;
        case Base.home:
          // ホームスチールは実装しない
          break;
      }
    }

    return BaseRunners(first: newFirst, second: newSecond, third: newThird);
  }

  /// 盗塁失敗後のランナー状況を取得（失敗したランナーを除去）
  BaseRunners afterFailedSteal(Player failedRunner, Base fromBase) {
    Player? newFirst = first;
    Player? newSecond = second;
    Player? newThird = third;

    // 失敗したランナーを除去
    switch (fromBase) {
      case Base.first:
        if (first == failedRunner) newFirst = null;
        break;
      case Base.second:
        if (second == failedRunner) newSecond = null;
        break;
      case Base.third:
        if (third == failedRunner) newThird = null;
        break;
      case Base.home:
        break;
    }

    return BaseRunners(first: newFirst, second: newSecond, third: newThird);
  }
}

/// 盗塁イベント（イニング内で発生した盗塁）
class StealEvent {
  final List<StealAttempt> attempts;
  final int beforeAtBatIndex; // この打席の前に発生

  const StealEvent({
    required this.attempts,
    required this.beforeAtBatIndex,
  });
}

/// 1イニングの結果（表または裏）
class HalfInningResult {
  final int inning;
  final bool isTop;
  final List<AtBatResult> atBats;
  final int runs; // この回の得点
  final List<StealEvent> stealEvents; // 盗塁イベント
  final int stolenBases; // 盗塁成功数
  final int caughtStealing; // 盗塁失敗（刺殺）数

  const HalfInningResult({
    required this.inning,
    required this.isTop,
    required this.atBats,
    required this.runs,
    this.stealEvents = const [],
    this.stolenBases = 0,
    this.caughtStealing = 0,
  });
}

/// イニングごとのスコア
class InningScore {
  final int? top; // 表の得点（null = まだ）
  final int? bottom; // 裏の得点（null = まだ、またはサヨナラ等でなし）

  const InningScore({
    this.top,
    this.bottom,
  });
}

/// 試合結果
class GameResult {
  final String homeTeamName;
  final String awayTeamName;
  final List<InningScore> inningScores;
  final List<HalfInningResult> halfInnings;
  final int homeScore;
  final int awayScore;

  const GameResult({
    required this.homeTeamName,
    required this.awayTeamName,
    required this.inningScores,
    required this.halfInnings,
    required this.homeScore,
    required this.awayScore,
  });

  /// 勝者のチーム名（同点ならnull）
  String? get winner {
    if (homeScore > awayScore) return homeTeamName;
    if (awayScore > homeScore) return awayTeamName;
    return null;
  }

  /// スコアボードの文字列表現
  String toScoreBoard() {
    final buffer = StringBuffer();

    // ヘッダー
    buffer.write('      |');
    for (int i = 1; i <= inningScores.length; i++) {
      buffer.write(' $i |');
    }
    buffer.writeln(' 計 |');

    // 区切り線
    buffer.write('------+');
    for (int i = 0; i < inningScores.length; i++) {
      buffer.write('---+');
    }
    buffer.writeln('----+');

    // アウェイチーム（先攻）
    buffer.write('${awayTeamName.padRight(6).substring(0, 6)}|');
    for (final score in inningScores) {
      final s = score.top?.toString() ?? '-';
      buffer.write(' $s |');
    }
    buffer.writeln(' ${awayScore.toString().padLeft(2)} |');

    // 区切り線
    buffer.write('------+');
    for (int i = 0; i < inningScores.length; i++) {
      buffer.write('---+');
    }
    buffer.writeln('----+');

    // ホームチーム（後攻）
    buffer.write('${homeTeamName.padRight(6).substring(0, 6)}|');
    for (final score in inningScores) {
      final s = score.bottom?.toString() ?? 'X';
      buffer.write(' $s |');
    }
    buffer.writeln(' ${homeScore.toString().padLeft(2)} |');

    return buffer.toString();
  }
}

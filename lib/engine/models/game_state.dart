import 'enums.dart';
import 'player.dart';

/// 1球の結果
class PitchResult {
  final PitchResultType type;
  final BattedBallType? battedBallType; // インプレー時のみ
  final int speed; // 球速（km/h）

  const PitchResult({
    required this.type,
    this.battedBallType,
    required this.speed,
  });
}

/// 1打席の結果
class AtBatResult {
  final Player batter;
  final Player pitcher;
  final int inning;
  final bool isTop; // 表かどうか
  final List<PitchResult> pitches; // 全投球
  final AtBatResultType result;
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
}

/// 1イニングの結果（表または裏）
class HalfInningResult {
  final int inning;
  final bool isTop;
  final List<AtBatResult> atBats;
  final int runs; // この回の得点

  const HalfInningResult({
    required this.inning,
    required this.isTop,
    required this.atBats,
    required this.runs,
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

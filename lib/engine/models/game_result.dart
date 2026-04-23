import 'at_bat_result.dart';
import 'base_runners.dart';
import 'pitcher_change.dart';

/// 1イニングの結果（表または裏）
class HalfInningResult {
  final int inning;
  final bool isTop;
  final List<AtBatResult> atBats;
  final int runs; // この回の得点
  final List<StealEvent> stealEvents; // 盗塁イベント
  final int stolenBases; // 盗塁成功数
  final int caughtStealing; // 盗塁失敗（刺殺）数
  final List<PitcherChangeEvent> pitcherChanges; // このイニング内で発生した投手交代

  const HalfInningResult({
    required this.inning,
    required this.isTop,
    required this.atBats,
    required this.runs,
    this.stealEvents = const [],
    this.stolenBases = 0,
    this.caughtStealing = 0,
    this.pitcherChanges = const [],
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

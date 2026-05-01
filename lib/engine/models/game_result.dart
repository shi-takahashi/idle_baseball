import 'at_bat_result.dart';
import 'base_runners.dart';
import 'fielder_change.dart';
import 'pitcher_change.dart';
import 'player.dart';
import 'team.dart';

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
  final List<FielderChangeEvent> fielderChanges; // このイニング内で発生した野手交代（代打・代走・守備固め）

  /// このハーフイニング開始時に確定した守備配置の変更
  /// （前の攻撃ハーフでの代打・代走の結果、このハーフから有効になる守備配置）
  /// 攻撃側の半イニングでは常に空
  final List<DefensiveChange> defensiveChangesAtStart;

  const HalfInningResult({
    required this.inning,
    required this.isTop,
    required this.atBats,
    required this.runs,
    this.stealEvents = const [],
    this.stolenBases = 0,
    this.caughtStealing = 0,
    this.pitcherChanges = const [],
    this.fielderChanges = const [],
    this.defensiveChangesAtStart = const [],
  });

  Map<String, dynamic> toJson() => {
        'inning': inning,
        'isTop': isTop,
        'atBats': [for (final ab in atBats) ab.toJson()],
        'runs': runs,
        'stealEvents': [for (final s in stealEvents) s.toJson()],
        'stolenBases': stolenBases,
        'caughtStealing': caughtStealing,
        'pitcherChanges': [for (final c in pitcherChanges) c.toJson()],
        'fielderChanges': [for (final c in fielderChanges) c.toJson()],
        'defensiveChangesAtStart':
            [for (final d in defensiveChangesAtStart) d.toJson()],
      };

  factory HalfInningResult.fromJson(
    Map<String, dynamic> json,
    Map<String, Player> playerById,
  ) =>
      HalfInningResult(
        inning: json['inning'] as int,
        isTop: json['isTop'] as bool,
        atBats: [
          for (final ab in (json['atBats'] as List))
            AtBatResult.fromJson(ab as Map<String, dynamic>, playerById),
        ],
        runs: json['runs'] as int,
        stealEvents: [
          for (final s in (json['stealEvents'] as List? ?? []))
            StealEvent.fromJson(s as Map<String, dynamic>, playerById),
        ],
        stolenBases: (json['stolenBases'] as int?) ?? 0,
        caughtStealing: (json['caughtStealing'] as int?) ?? 0,
        pitcherChanges: [
          for (final c in (json['pitcherChanges'] as List? ?? []))
            PitcherChangeEvent.fromJson(
                c as Map<String, dynamic>, playerById),
        ],
        fielderChanges: [
          for (final c in (json['fielderChanges'] as List? ?? []))
            FielderChangeEvent.fromJson(
                c as Map<String, dynamic>, playerById),
        ],
        defensiveChangesAtStart: [
          for (final d in (json['defensiveChangesAtStart'] as List? ?? []))
            DefensiveChange.fromJson(
                d as Map<String, dynamic>, playerById),
        ],
      );
}

/// イニングごとのスコア
class InningScore {
  final int? top; // 表の得点（null = まだ）
  final int? bottom; // 裏の得点（null = まだ、またはサヨナラ等でなし）

  const InningScore({
    this.top,
    this.bottom,
  });

  Map<String, dynamic> toJson() => {
        if (top != null) 'top': top,
        if (bottom != null) 'bottom': bottom,
      };

  factory InningScore.fromJson(Map<String, dynamic> json) => InningScore(
        top: json['top'] as int?,
        bottom: json['bottom'] as int?,
      );
}

/// 試合結果
class GameResult {
  final Team homeTeam;
  final Team awayTeam;
  final List<InningScore> inningScores;
  final List<HalfInningResult> halfInnings;
  final int homeScore;
  final int awayScore;

  const GameResult({
    required this.homeTeam,
    required this.awayTeam,
    required this.inningScores,
    required this.halfInnings,
    required this.homeScore,
    required this.awayScore,
  });

  String get homeTeamName => homeTeam.name;
  String get awayTeamName => awayTeam.name;

  /// 勝者のチーム名（同点ならnull）
  String? get winner {
    if (homeScore > awayScore) return homeTeamName;
    if (awayScore > homeScore) return awayTeamName;
    return null;
  }

  /// 永続化: home/away Team はその試合時点でのスナップショットなので Team を直接シリアライズする
  /// （Schedule の Team とは copyWith で異なるリストを持つため、共有 Team registry に
  /// 押し込むと打順情報が失われる）。Player は id 参照で共有 registry から resolve。
  Map<String, dynamic> toJson() => {
        'homeTeam': homeTeam.toJson(),
        'awayTeam': awayTeam.toJson(),
        'inningScores': [for (final s in inningScores) s.toJson()],
        'halfInnings': [for (final h in halfInnings) h.toJson()],
        'homeScore': homeScore,
        'awayScore': awayScore,
      };

  factory GameResult.fromJson(
    Map<String, dynamic> json,
    Map<String, Player> playerById,
  ) =>
      GameResult(
        homeTeam: Team.fromJson(
            json['homeTeam'] as Map<String, dynamic>, playerById),
        awayTeam: Team.fromJson(
            json['awayTeam'] as Map<String, dynamic>, playerById),
        inningScores: [
          for (final s in (json['inningScores'] as List))
            InningScore.fromJson(s as Map<String, dynamic>),
        ],
        halfInnings: [
          for (final h in (json['halfInnings'] as List))
            HalfInningResult.fromJson(
                h as Map<String, dynamic>, playerById),
        ],
        homeScore: json['homeScore'] as int,
        awayScore: json['awayScore'] as int,
      );

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

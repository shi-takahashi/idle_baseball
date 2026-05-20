import '../models/player.dart';
import '../models/team.dart';
import 'player_season_stats.dart';
import 'standings.dart';

/// 1 シーズンが終わった時点の集計結果のスナップショット。
///
/// 年度別履歴 (`SeasonController._seasonHistory`) として積み上げ、
/// 「2 年目以降のスタメン編成で前年成績を見たい」「年度別成績画面で
/// キャリアの推移を追いたい」といった用途に使う。
///
/// 含むデータ:
///   - [year]: シーズン年度（1, 2, 3, ...）
///   - [batterStats]: playerId → 当該シーズン野手成績
///   - [pitcherStats]: playerId → 当該シーズン投手成績
///   - [standings]: 順位表（チーム成績）
///
/// データ量試算: 240 人 × 約 300 bytes = 約 72 KB / シーズン。50 シーズンでも
/// 3.5 MB 程度で、スマホで十分扱える範囲。
class SeasonSnapshot {
  final int year;
  final Map<String, BatterSeasonStats> batterStats;
  final Map<String, PitcherSeasonStats> pitcherStats;
  final Standings standings;

  const SeasonSnapshot({
    required this.year,
    required this.batterStats,
    required this.pitcherStats,
    required this.standings,
  });

  Map<String, dynamic> toJson() => {
        'year': year,
        'batterStats': {
          for (final entry in batterStats.entries)
            entry.key: entry.value.toJson(),
        },
        'pitcherStats': {
          for (final entry in pitcherStats.entries)
            entry.key: entry.value.toJson(),
        },
        'standings': standings.toJson(),
      };

  factory SeasonSnapshot.fromJson(
    Map<String, dynamic> json,
    Map<String, Player> playerById,
    Map<String, Team> teamById,
  ) {
    // 引退選手は現在の playerById には存在しないので、そのレコードはスキップする
    // （引退選手の通算成績は将来「リーグアーカイブ」で別管理する予定）。
    // 現役選手の年度別成績だけ復元できれば本機能の目的（前年成績の参照）は満たす。
    final batterStats = <String, BatterSeasonStats>{};
    final pitcherStats = <String, PitcherSeasonStats>{};
    for (final entry
        in (json['batterStats'] as Map<String, dynamic>).entries) {
      final js = entry.value as Map<String, dynamic>;
      final pid = js['playerId'] as String?;
      if (pid == null || !playerById.containsKey(pid)) continue;
      batterStats[entry.key] =
          BatterSeasonStats.fromJson(js, playerById, teamById);
    }
    for (final entry
        in (json['pitcherStats'] as Map<String, dynamic>).entries) {
      final js = entry.value as Map<String, dynamic>;
      final pid = js['playerId'] as String?;
      if (pid == null || !playerById.containsKey(pid)) continue;
      pitcherStats[entry.key] =
          PitcherSeasonStats.fromJson(js, playerById, teamById);
    }
    return SeasonSnapshot(
      year: json['year'] as int,
      batterStats: batterStats,
      pitcherStats: pitcherStats,
      standings: Standings.fromJson(
        json['standings'] as Map<String, dynamic>,
        teamById,
      ),
    );
  }
}

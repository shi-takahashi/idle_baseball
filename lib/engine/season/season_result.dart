import '../models/game_result.dart';
import 'player_season_stats.dart';
import 'schedule.dart';
import 'standings.dart';

/// 1シーズンの全結果
///
/// - `schedule`: 試合日程
/// - `games`: 各試合のシミュレーション結果（schedule.games と同順）
/// - `standings`: チーム順位表
/// - `batterStats` / `pitcherStats`: 選手ID → シーズン成績
class SeasonResult {
  final Schedule schedule;
  final List<GameResult> games;
  final Standings standings;
  final Map<String, BatterSeasonStats> batterStats;
  final Map<String, PitcherSeasonStats> pitcherStats;

  const SeasonResult({
    required this.schedule,
    required this.games,
    required this.standings,
    required this.batterStats,
    required this.pitcherStats,
  });
}

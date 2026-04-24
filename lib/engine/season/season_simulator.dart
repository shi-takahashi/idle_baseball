import 'dart:math';

import '../models/models.dart';
import '../simulation/simulation.dart';
import 'schedule.dart';
import 'season_aggregator.dart';
import 'season_result.dart';

/// シーズン全試合を一括でシミュレートする
///
/// 日ごとに進めたい場合は `SeasonController` を使う。
class SeasonSimulator {
  final GameSimulator _gameSimulator;

  SeasonSimulator({Random? random, GameSimulator? gameSimulator})
      : _gameSimulator = gameSimulator ?? GameSimulator(random: random);

  /// 指定チーム・日程でシーズン全試合をシミュレート
  SeasonResult simulate(List<Team> teams, Schedule schedule) {
    final aggregator = SeasonAggregator(teams);
    final results = <GameResult>[];
    for (final sg in schedule.games) {
      final result = _gameSimulator.simulate(sg.homeTeam, sg.awayTeam);
      results.add(result);
      aggregator.recordGame(result);
    }
    return SeasonResult(
      schedule: schedule,
      games: results,
      standings: aggregator.standings,
      batterStats: aggregator.batterStats,
      pitcherStats: aggregator.pitcherStats,
    );
  }
}

import 'dart:math';

import '../models/models.dart';
import '../simulation/simulation.dart';
import 'schedule.dart';
import 'season_controller.dart';
import 'season_result.dart';

/// シーズン全試合を一括でシミュレートする
///
/// 日ごとに進めたい場合は `SeasonController` を直接使う。
/// 内部実装としても、先発ローテーションなどの状態管理を共通化するために
/// `SeasonController.advanceAll` に委譲している。
class SeasonSimulator {
  final GameSimulator _gameSimulator;

  SeasonSimulator({Random? random, GameSimulator? gameSimulator})
      : _gameSimulator = gameSimulator ?? GameSimulator(random: random);

  /// 指定チーム・日程でシーズン全試合をシミュレート
  SeasonResult simulate(List<Team> teams, Schedule schedule) {
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      gameSimulator: _gameSimulator,
    );
    controller.advanceAll();

    // schedule.games の並びで結果を集める
    final results = <GameResult>[
      for (final sg in schedule.games)
        if (controller.resultFor(sg.gameNumber) != null)
          controller.resultFor(sg.gameNumber)!,
    ];

    return SeasonResult(
      schedule: schedule,
      games: results,
      standings: controller.standings,
      batterStats: controller.batterStats,
      pitcherStats: controller.pitcherStats,
    );
  }
}

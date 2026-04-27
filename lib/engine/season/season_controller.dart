import 'dart:math';

import 'package:flutter/foundation.dart';

import '../generators/generators.dart';
import '../models/models.dart';
import '../simulation/simulation.dart';
import 'player_season_stats.dart';
import 'schedule.dart';
import 'schedule_generator.dart';
import 'scheduled_game.dart';
import 'season_aggregator.dart';
import 'standings.dart';

/// シーズン進行を管理するコントローラー（可変状態）
///
/// 1日ずつ試合を進めるための状態管理:
/// - `advanceDay()`: 次の日（3試合）をシミュレート
/// - `advanceAll()`: 残り全日を一括シミュレート（デバッグ用）
///
/// 進行状況:
/// - `currentDay == 0` → シーズン開始前（まだ1試合も消化していない）
/// - `currentDay == N (1〜totalDays)` → N日目まで消化済み
/// - `isSeasonOver == true` → 全日消化済み
///
/// [ChangeNotifier] を継承しているため、進行操作（advanceDay/advanceAll）を呼ぶと
/// UI 側が `ListenableBuilder` 経由で再ビルドできる。
class SeasonController extends ChangeNotifier {
  final List<Team> teams;
  final Schedule schedule;
  final String myTeamId;
  final SeasonAggregator _aggregator;
  final GameSimulator _gameSimulator;

  /// gameNumber → GameResult のマップ（未実行の試合はキーなし）
  final Map<int, GameResult> _results = {};

  int _currentDay = 0;

  SeasonController({
    required this.teams,
    required this.schedule,
    required this.myTeamId,
    GameSimulator? gameSimulator,
    Random? random,
  })  : _aggregator = SeasonAggregator(teams),
        _gameSimulator = gameSimulator ?? GameSimulator(random: random);

  /// 6チームを自動生成して新しいシーズンを開始するファクトリ
  factory SeasonController.newSeason({
    Random? random,
    String myTeamId = 'team_phoenix',
  }) {
    final teams = TeamGenerator(random: random).generateLeague();
    final schedule = const ScheduleGenerator().generate(teams);
    return SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: myTeamId,
      random: random,
    );
  }

  // ---- 状態の参照 ----
  int get currentDay => _currentDay;
  int get totalDays => schedule.totalDays;
  bool get isSeasonOver => _currentDay >= schedule.totalDays;
  Team get myTeam => teams.firstWhere((t) => t.id == myTeamId);
  Standings get standings => _aggregator.standings;
  Map<String, BatterSeasonStats> get batterStats => _aggregator.batterStats;
  Map<String, PitcherSeasonStats> get pitcherStats => _aggregator.pitcherStats;

  /// 指定日の予定試合一覧
  List<ScheduledGame> scheduledGamesOnDay(int day) =>
      schedule.gamesOnDay(day);

  /// 指定 gameNumber の結果（未実行なら null）
  GameResult? resultFor(int gameNumber) => _results[gameNumber];

  // ---- 進行操作 ----

  /// 1日分（3試合）をシミュレート
  /// シーズン終了済みなら何もせず空リストを返す
  List<GameResult> advanceDay() {
    if (isSeasonOver) return const [];
    _currentDay++;
    final games = scheduledGamesOnDay(_currentDay);
    final results = <GameResult>[];
    for (final sg in games) {
      final result = _gameSimulator.simulate(sg.homeTeam, sg.awayTeam);
      _results[sg.gameNumber] = result;
      _aggregator.recordGame(result);
      results.add(result);
    }
    notifyListeners();
    return results;
  }

  /// 残り全日を一括シミュレート（デバッグ用）
  /// 内部で advanceDay を呼ぶたびに通知が走るため、ここでは追加通知しない
  void advanceAll() {
    while (!isSeasonOver) {
      advanceDay();
    }
  }
}

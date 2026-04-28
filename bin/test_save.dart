import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

void main() {
  final teams = TeamGenerator(random: Random(42)).generateLeague();
  final schedule = const ScheduleGenerator().generate(teams);
  final simulator = SeasonSimulator(random: Random(42));
  final result = simulator.simulate(teams, schedule);

  int totalSaves = 0;
  int totalWins = 0;
  for (final p in result.pitcherStats.values) {
    totalSaves += p.saves;
    totalWins += p.wins;
  }
  int totalGames = 0;
  int draws = 0;
  for (final g in result.games) {
    totalGames++;
    if (g.winner == null) draws++;
  }
  final decisiveGames = totalGames - draws;
  print('全試合: $totalGames / 引分: $draws / 勝負あり: $decisiveGames');
  print('勝利: $totalWins (= $decisiveGames であるべき)');
  print('セーブ: $totalSaves');
  print('セーブ率（勝負あり試合に対する）: '
      '${(totalSaves / decisiveGames * 100).toStringAsFixed(1)}%');

  // 役割別のセーブ集計
  final byRole = <String, int>{
    'starter': 0,
    'closer': 0,
    'reliever': 0,
    'bench': 0,
  };
  for (final team in teams) {
    final spIds = team.startingRotation.map((p) => p.id).toSet();
    final closerId = team.closer?.id;
    final bpIds = team.bullpen.map((p) => p.id).toSet();
    for (final p in result.pitcherStats.values
        .where((s) => s.team.id == team.id)) {
      if (p.saves == 0) continue;
      if (spIds.contains(p.player.id)) {
        byRole['starter'] = byRole['starter']! + p.saves;
      } else if (p.player.id == closerId) {
        byRole['closer'] = byRole['closer']! + p.saves;
      } else if (bpIds.contains(p.player.id)) {
        byRole['reliever'] = byRole['reliever']! + p.saves;
      } else {
        byRole['bench'] = byRole['bench']! + p.saves;
      }
    }
  }
  print('役割別セーブ: 先発=${byRole['starter']} / 抑え=${byRole['closer']} '
      '/ 中継ぎ=${byRole['reliever']} / その他=${byRole['bench']}');

  print('');
  print('=== 各チームの抑え投手 ===');
  for (final team in teams) {
    final closer = team.closer;
    if (closer == null) {
      print('${team.name}: 抑え未指名');
      continue;
    }
    final stats = result.pitcherStats[closer.id];
    if (stats == null) {
      print('${team.name}: ${closer.name}（成績なし）');
      continue;
    }
    print('${team.name}: ${closer.name.padRight(8)} '
        '${stats.games}試合 ${stats.inningsPitchedDisplay}回 '
        '${stats.wins}勝${stats.losses}敗${stats.saves}S '
        '${stats.strikeoutsRecorded}K 失${stats.runsAllowed}');
  }

  // セーブ機会候補の試合数
  print('');
  print('=== セーブ機会候補の試合数 ===');
  int saveOpportunityGames = 0;
  for (final game in result.games) {
    if (game.winner == null) continue;
    final homeWon = game.winner == game.homeTeamName;
    final lead = homeWon
        ? game.homeScore - game.awayScore
        : game.awayScore - game.homeScore;
    if (game.inningScores.length >= 9 && lead > 0 && lead <= 3) {
      saveOpportunityGames++;
    }
  }
  print('最終リード ≤ 3 の勝利試合数: $saveOpportunityGames');
  print('（うちセーブ記録: $totalSaves）');
}

import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

void main() {
  for (final seed in [1, 7, 42, 100, 2024]) {
    final teams = TeamGenerator(random: Random(seed)).generateLeague();
    final schedule = const ScheduleGenerator().generate(teams);
    final simulator = SeasonSimulator(random: Random(seed));
    final result = simulator.simulate(teams, schedule);

    print('=== seed=$seed ===');
    final byRole = <ReliefRole, _RoleAgg>{
      for (final r in ReliefRole.values) r: _RoleAgg(),
    };
    int totalSaves = 0;
    int totalHolds = 0;
    int totalWins = 0;
    int totalLosses = 0;

    for (final team in teams) {
      for (final p in team.bullpen) {
        final role = p.reliefRole;
        if (role == null) continue;
        final stats = result.pitcherStats[p.id];
        if (stats == null) continue;
        final agg = byRole[role]!;
        agg.players++;
        agg.games += stats.games;
        agg.outs += stats.outsRecorded;
        agg.saves += stats.saves;
        agg.holds += stats.holds;
        agg.wins += stats.wins;
        agg.losses += stats.losses;
        agg.runsAllowed += stats.runsAllowed;
        totalSaves += stats.saves;
        totalHolds += stats.holds;
        totalWins += stats.wins;
        totalLosses += stats.losses;
      }
    }

    print('総セーブ=$totalSaves 総ホールド=$totalHolds '
        '総勝=$totalWins 総敗=$totalLosses');
    print('ロール別（リーグ全体での合計）:');
    for (final role in ReliefRole.values) {
      final agg = byRole[role]!;
      if (agg.players == 0) continue;
      final ip = agg.outs / 3.0;
      final ipPerG =
          agg.games > 0 ? (ip / agg.games).toStringAsFixed(2) : '-';
      final gPerPlayer =
          agg.players > 0 ? (agg.games / agg.players).toStringAsFixed(1) : '-';
      print('  ${role.displayName.padRight(12)} '
          '人数=${agg.players} '
          '登板計=${agg.games} (1人${gPerPlayer}試合) '
          'IP=${ip.toStringAsFixed(1)} (1試合${ipPerG}IP) '
          '勝${agg.wins}敗${agg.losses} S${agg.saves}H${agg.holds} '
          '失点=${agg.runsAllowed}');
    }
    print('');
  }
}

class _RoleAgg {
  int players = 0;
  int games = 0;
  int outs = 0;
  int saves = 0;
  int holds = 0;
  int wins = 0;
  int losses = 0;
  int runsAllowed = 0;
}

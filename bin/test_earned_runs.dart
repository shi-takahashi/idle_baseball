import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 自責点と防御率の動作確認
void main() {
  for (final seed in [1, 7, 42, 100, 2024]) {
    final teams = TeamGenerator(random: Random(seed)).generateLeague();
    final schedule = const ScheduleGenerator().generate(teams);
    final simulator = SeasonSimulator(random: Random(seed));
    final result = simulator.simulate(teams, schedule);

    int totalRuns = 0;
    int totalEarned = 0;
    int errorReached = 0;
    int wpRuns = 0;
    int pbRuns = 0;
    for (final game in result.games) {
      for (final half in game.halfInnings) {
        for (final ab in half.atBats) {
          if (ab.isIncomplete) continue;
          totalRuns +=
              ab.runsByPitcher.values.fold<int>(0, (s, v) => s + v);
          totalEarned +=
              ab.earnedRunsByPitcher.values.fold<int>(0, (s, v) => s + v);
          if (ab.result == AtBatResultType.reachedOnError) errorReached++;
          for (final p in ab.pitches) {
            if (p.batteryError == null) continue;
            if (p.batteryError!.type == BatteryErrorType.wildPitch) {
              wpRuns += p.batteryError!.runsScored;
            } else {
              pbRuns += p.batteryError!.runsScored;
            }
          }
        }
      }
    }

    int sumRunsAllowed = 0;
    int sumEarned = 0;
    for (final p in result.pitcherStats.values) {
      sumRunsAllowed += p.runsAllowed;
      sumEarned += p.earnedRuns;
    }

    final unearned = totalRuns - totalEarned;
    final earnedPct = totalRuns > 0
        ? (totalEarned / totalRuns * 100).toStringAsFixed(1)
        : '-';
    print('seed=$seed: 失点=$totalRuns 自責点=$totalEarned '
        '不自責=$unearned (${earnedPct}% earned)');
    print('  集計整合: runs $sumRunsAllowed=$totalRuns '
        '${sumRunsAllowed == totalRuns ? "✓" : "✗"} / '
        'ER $sumEarned=$totalEarned '
        '${sumEarned == totalEarned ? "✓" : "✗"}');
    print('  エラー出塁=$errorReached / WP得点=$wpRuns / PB得点=$pbRuns');
  }

  print('');
  print('=== seed=42 トップ防御率 ===');
  final teams = TeamGenerator(random: Random(42)).generateLeague();
  final schedule = const ScheduleGenerator().generate(teams);
  final result = SeasonSimulator(random: Random(42)).simulate(teams, schedule);
  final qualified = result.pitcherStats.values
      .where((p) => p.inningsPitched >= 30)
      .toList()
    ..sort((a, b) => a.era.compareTo(b.era));
  for (final p in qualified.take(5)) {
    print('  ${p.era.toStringAsFixed(2)}  ${p.player.name.padRight(8)} '
        '(${p.team.name}) '
        '${p.inningsPitchedDisplay}回 '
        '失${p.runsAllowed}/自責${p.earnedRuns}');
  }
}

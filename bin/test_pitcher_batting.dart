import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 投手の打撃成績を確認
void main() {
  for (final seed in [1, 7, 42, 100, 2024, 99, 555]) {
    final teams = TeamGenerator(random: Random(seed)).generateLeague();
    final schedule = const ScheduleGenerator().generate(teams);
    final result = SeasonSimulator(random: Random(seed)).simulate(teams, schedule);

    print('=== seed=$seed ===');
    int totalPitcherPA = 0;
    int totalPitcherHR = 0;
    final hittingPitchers = <BatterSeasonStats>[];
    for (final stats in result.batterStats.values) {
      if (!stats.player.isPitcher) continue;
      totalPitcherPA += stats.plateAppearances;
      totalPitcherHR += stats.homeRuns;
      if (stats.homeRuns > 0) {
        hittingPitchers.add(stats);
      }
    }
    print('  投手の打席合計: $totalPitcherPA / 投手のHR合計: $totalPitcherHR');
    if (hittingPitchers.isNotEmpty) {
      hittingPitchers.sort((a, b) => b.homeRuns.compareTo(a.homeRuns));
      for (final s in hittingPitchers.take(3)) {
        print('    ${s.homeRuns}HR ${s.player.name} (${s.team.name}) '
            '${s.atBats}打数${s.hits}安');
      }
    }
  }
}

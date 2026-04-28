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
    int totalAB = 0;
    int totalHits = 0;
    int totalK = 0;
    for (final stats in result.batterStats.values) {
      if (!stats.player.isPitcher) continue;
      totalAB += stats.atBats;
      totalHits += stats.hits;
      totalK += stats.strikeouts;
    }
    final ba = totalAB > 0 ? (totalHits / totalAB) : 0;
    final hrPct = totalPitcherPA > 0 ? (totalPitcherHR / totalPitcherPA * 100) : 0;
    final kPct = totalPitcherPA > 0 ? (totalK / totalPitcherPA * 100) : 0;
    print('  投手の打席合計: $totalPitcherPA  '
        '打率: ${ba.toStringAsFixed(3)}  '
        'HR率: ${hrPct.toStringAsFixed(2)}%  '
        'K率: ${kPct.toStringAsFixed(1)}%  '
        '($totalHits安/${totalAB}打数 ${totalPitcherHR}本 ${totalK}三振)');
    if (hittingPitchers.isNotEmpty) {
      hittingPitchers.sort((a, b) => b.homeRuns.compareTo(a.homeRuns));
      for (final s in hittingPitchers.take(3)) {
        print('    ${s.homeRuns}HR ${s.player.name} (${s.team.name}) '
            '${s.atBats}打数${s.hits}安');
      }
    }
  }
}

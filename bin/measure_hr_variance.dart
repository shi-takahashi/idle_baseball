import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 同一 power 値の選手の HR ばらつき(同シーズン内・同能力)を計測。
/// NPB 想定では SD ~6本/150試合。現状がそれより大きいとランダム性過大。
///
/// 経年・加齢・コンディションの影響を排除するため、毎回新規生成のシーズン1で
/// 「打席400+」を満たす選手を power 別に集計。
void main() {
  const numSeasons = 40;
  const gamesPerTeam = 150;
  const minPA = 400;

  // power -> [各サンプル選手の HR/打席400+/打席/打数/打率]
  final samples = <int, List<_Sample>>{};

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(8800 + s)).generateLeague();
    final schedule =
        ScheduleGenerator().generateForGamesPerTeam(teams, gamesPerTeam);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      gamesPerTeam: gamesPerTeam,
      random: Random(8800 + s),
    );
    controller.advanceAll();

    for (final st in controller.batterStats.values) {
      if (st.player.isPitcher) continue;
      if (st.plateAppearances < minPA) continue;
      final p = (st.player.power ?? 5).clamp(1, 10);
      samples
          .putIfAbsent(p, () => [])
          .add(_Sample(st.homeRuns, st.plateAppearances, st.atBats, st.hits));
    }
  }

  print(
      '===== 同 power 値の選手の HR ばらつき(${numSeasons}シーズン × ${gamesPerTeam}試合, 打席$minPA+) =====');
  print('NPB 目安: 150試合での同実力選手の HR 標準偏差 ≒ 6本');
  print('');
  print(
      '| power | n  | HR平均 | HR SD | HR範囲(min-max) | HR/600PA | 打率平均 | 打率 SD |');
  print(
      '|-------|----|--------|-------|------------------|----------|---------|--------|');
  for (int p = 4; p <= 10; p++) {
    final list = samples[p] ?? [];
    if (list.isEmpty) {
      print('| $p | 0 | - | - | - | - | - | - |');
      continue;
    }
    final hrs = list.map((e) => e.hr.toDouble()).toList();
    final hrMean = hrs.reduce((a, b) => a + b) / hrs.length;
    final hrVar =
        hrs.map((v) => (v - hrMean) * (v - hrMean)).reduce((a, b) => a + b) /
            hrs.length;
    final hrSd = sqrt(hrVar);
    final hrMin = hrs.reduce(min);
    final hrMax = hrs.reduce(max);
    final hrPer600 =
        hrMean * 600 / (list.map((e) => e.pa).reduce((a, b) => a + b) / list.length);
    final avgs = list
        .map((e) => e.ab == 0 ? 0.0 : e.hits / e.ab)
        .toList();
    final avgMean = avgs.reduce((a, b) => a + b) / avgs.length;
    final avgVar = avgs
            .map((v) => (v - avgMean) * (v - avgMean))
            .reduce((a, b) => a + b) /
        avgs.length;
    final avgSd = sqrt(avgVar);
    print(
        '| $p | ${list.length} | ${hrMean.toStringAsFixed(1)} | ${hrSd.toStringAsFixed(1)} | ${hrMin.toInt()}-${hrMax.toInt()} | ${hrPer600.toStringAsFixed(1)} | ${avgMean.toStringAsFixed(3)} | ${avgSd.toStringAsFixed(3)} |');
  }
}

class _Sample {
  final int hr;
  final int pa;
  final int ab;
  final int hits;
  _Sample(this.hr, this.pa, this.ab, this.hits);
}

import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// リーグ全体の打率・出塁率・長打率・OPS・K率・BB率を計測。
/// NPB 目安: 打率 .250 / OBP .320 / SLG .380 / OPS .700 / K率 ~20% / BB率 ~8%
void main() {
  const numSeasons = 3;

  int totalAB = 0, totalH = 0, totalHR = 0, total2B = 0, total3B = 0;
  int totalBB = 0, totalK = 0, totalPA = 0;

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(700 + s)).generateLeague();
    final schedule = const ScheduleGenerator().generate(teams);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      random: Random(700 + s),
    );
    controller.advanceAll();

    for (final stats in controller.batterStats.values) {
      // 投手の打席は除外（投手は打撃を諦める傾向で平均を歪めるため）
      if (stats.player.isPitcher) continue;
      totalAB += stats.atBats;
      totalH += stats.hits;
      totalHR += stats.homeRuns;
      total2B += stats.doubles;
      total3B += stats.triples;
      totalBB += stats.walks;
      totalK += stats.strikeouts;
      totalPA += stats.atBats + stats.walks; // 簡易PA（犠飛・死球は無視）
    }
  }

  final avg = totalH / totalAB;
  final obp = (totalH + totalBB) / (totalAB + totalBB);
  final singles = totalH - total2B - total3B - totalHR;
  final tb = singles + 2 * total2B + 3 * total3B + 4 * totalHR;
  final slg = tb / totalAB;
  final ops = obp + slg;
  final kRate = totalK / totalPA;
  final bbRate = totalBB / totalPA;

  String f3(double v) => v.toStringAsFixed(3);
  String pct(double v) => '${(v * 100).toStringAsFixed(1)}%';

  print('===== リーグ全体の打撃成績（${numSeasons}シーズン、投手の打席を除く） =====');
  print('打数: $totalAB / 安打: $totalH / 本塁打: $totalHR / 二塁打: $total2B / 三塁打: $total3B');
  print('四球: $totalBB / 三振: $totalK / 簡易PA: $totalPA');
  print('');
  print('打率: ${f3(avg)} (NPB ~.250)');
  print('出塁率: ${f3(obp)} (NPB ~.320)');
  print('長打率: ${f3(slg)} (NPB ~.380)');
  print('OPS: ${f3(ops)} (NPB ~.700)');
  print('K率: ${pct(kRate)} (NPB ~20%)');
  print('BB率: ${pct(bbRate)} (NPB ~8%)');
}

import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 1リーグを複数シーズン進行させ、各シーズンの本塁打王・防御率1位を見る。
/// 単発計測(seed 別の新規リーグ × N 回)と「複数シーズン進行」で結果が変わるかを確認。
void main() {
  const seasons = 12;
  const gamesPerTeam = 150;
  final qualifiedPA = (gamesPerTeam * 3.1).round();
  final qualifiedOuts = (gamesPerTeam * 1.0).round() * 3;

  print(
      '===== 1リーグ ${seasons}シーズン連続進行 (規定打席$qualifiedPA / 規定投球回${qualifiedOuts ~/ 3}) =====');

  final teams = TeamGenerator(random: Random(3300)).generateLeague();
  final schedule =
      ScheduleGenerator().generateForGamesPerTeam(teams, gamesPerTeam);
  final controller = SeasonController(
    teams: teams,
    schedule: schedule,
    myTeamId: teams.first.id,
    gamesPerTeam: gamesPerTeam,
    random: Random(3300),
  );

  print(
      '| Yr | HR王 | 2位 | 3位 | 20本+人数 | ERA1位 | TOP5平均 | 1点台投手数 | リーグ打率 | OPS |');
  print(
      '|----|------|-----|-----|-----------|--------|----------|-------------|----------|-----|');

  for (int y = 1; y <= seasons; y++) {
    controller.advanceAll();

    final batters = controller.batterStats.values
        .where((st) =>
            !st.player.isPitcher && st.plateAppearances >= qualifiedPA)
        .toList()
      ..sort((a, b) => b.homeRuns.compareTo(a.homeRuns));

    final pitchers = controller.pitcherStats.values
        .where((st) => st.outsRecorded >= qualifiedOuts)
        .toList()
      ..sort((a, b) => a.era.compareTo(b.era));

    final hr1 = batters.isNotEmpty ? batters[0].homeRuns : 0;
    final hr2 = batters.length > 1 ? batters[1].homeRuns : 0;
    final hr3 = batters.length > 2 ? batters[2].homeRuns : 0;
    final over20 = batters.where((st) => st.homeRuns >= 20).length;

    final era1 = pitchers.isNotEmpty ? pitchers[0].era : 99;
    final eraTop5 =
        pitchers.take(5).map((st) => st.era).fold<double>(0, (a, b) => a + b) /
            min(5, pitchers.length);
    final under2 = pitchers.where((st) => st.era < 2.0).length;

    // リーグ全体打撃
    int totalAB = 0, totalH = 0, totalHR = 0, total2B = 0, total3B = 0;
    int totalBB = 0, totalHBP = 0;
    for (final st in controller.batterStats.values) {
      if (st.player.isPitcher) continue;
      totalAB += st.atBats;
      totalH += st.hits;
      totalHR += st.homeRuns;
      total2B += st.doubles;
      total3B += st.triples;
      totalBB += st.walks;
      totalHBP += st.hitByPitch;
    }
    final avg = totalAB == 0 ? 0 : totalH / totalAB;
    final obp = (totalH + totalBB + totalHBP) / (totalAB + totalBB + totalHBP);
    final tb = (totalH - total2B - total3B - totalHR) +
        2 * total2B +
        3 * total3B +
        4 * totalHR;
    final slg = tb / totalAB;
    final ops = obp + slg;

    print(
        '| $y | $hr1 | $hr2 | $hr3 | $over20 | ${era1.toStringAsFixed(2)} | ${eraTop5.toStringAsFixed(2)} | $under2 | ${avg.toStringAsFixed(3)} | ${ops.toStringAsFixed(3)} |');

    if (y < seasons) {
      // オフシーズンを「触らずに」次年へ。引退・新人加入をデフォルト推奨で適用。
      final plan = controller.prepareOffseason();
      final selection = OffseasonSelection.recommended(plan);
      controller.commitOffseason(plan: plan, selection: selection);
    }
  }
}

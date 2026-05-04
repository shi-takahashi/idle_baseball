import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

void main() {
  num totalErrors = 0;
  num totalGames = 0;
  num totalAtBats = 0;
  num totalSeasons = 5;
  for (int s = 0; s < totalSeasons; s++) {
    final c = SeasonController.newSeason(
        random: Random(100 + s), gamesPerTeam: 30);
    c.advanceAll();
    for (final r in c.standings.records) {
      totalErrors += r.errors;
    }
    totalGames += c.schedule.games.length;
    for (final st in c.batterStats.values) {
      totalAtBats += st.atBats;
    }
  }
  final perTeamPerSeason = totalErrors / (6 * totalSeasons);
  print('5 シーズン (30試合シーズン × 5) の累計:');
  print('  全試合数 (リーグ累計): $totalGames');
  print('  全打数 (リーグ累計): $totalAtBats');
  print('  全失策 (リーグ累計): $totalErrors');
  print('  1チーム30試合あたりの失策: ${perTeamPerSeason.toStringAsFixed(2)}');
  print('  143試合換算: ${(perTeamPerSeason * 143 / 30).toStringAsFixed(1)}');
  print('NPB水準（参考）: 1チーム143試合で 60〜80 失策程度');
}

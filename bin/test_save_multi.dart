import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

void main() {
  for (final seed in [1, 7, 42, 100, 2024]) {
    final teams = TeamGenerator(random: Random(seed)).generateLeague();
    final schedule = const ScheduleGenerator().generate(teams);
    final simulator = SeasonSimulator(random: Random(seed));
    final result = simulator.simulate(teams, schedule);

    int totalSaves = 0;
    int closerSaves = 0;
    int closerGames = 0;
    int closerOuts = 0;
    int topSaves = 0;
    for (final team in teams) {
      final closerId = team.closer?.id;
      for (final p in result.pitcherStats.values
          .where((s) => s.team.id == team.id)) {
        totalSaves += p.saves;
        if (p.player.id == closerId) {
          closerSaves += p.saves;
          closerGames += p.games;
          closerOuts += p.outsRecorded;
          if (p.saves > topSaves) topSaves = p.saves;
        }
      }
    }
    final ipPerG = closerGames > 0
        ? (closerOuts / 3.0 / closerGames).toStringAsFixed(2)
        : '-';
    print('seed=$seed : total=$totalSaves '
        '抑え=$closerSaves IP/G=$ipPerG topSaves=$topSaves');
  }
}

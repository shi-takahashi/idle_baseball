import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// gameSummaryFor の動作確認
void main() {
  final teams = TeamGenerator(random: Random(42)).generateLeague();
  final schedule = const ScheduleGenerator().generate(teams);
  final controller = SeasonController(
    teams: teams,
    schedule: schedule,
    myTeamId: teams.first.id,
    random: Random(42),
  );
  controller.advanceAll();

  // 最初の3日と20日目のサマリー
  for (final day in [1, 2, 3, 20]) {
    print('=== Day $day ===');
    final games = controller.scheduledGamesOnDay(day);
    for (final sg in games) {
      final game = controller.resultFor(sg.gameNumber)!;
      final summary = controller.gameSummaryFor(sg.gameNumber);
      print(
          '${game.awayTeamName} ${game.awayScore}-${game.homeScore} ${game.homeTeamName}');
      if (summary.winning != null) {
        final r = summary.winning!;
        print('  W: ${r.pitcher.name} (${r.wins}勝${r.losses}敗${r.saves}S)');
      }
      if (summary.losing != null) {
        final r = summary.losing!;
        print('  L: ${r.pitcher.name} (${r.wins}勝${r.losses}敗${r.saves}S)');
      }
      if (summary.saving != null) {
        final r = summary.saving!;
        print('  S: ${r.pitcher.name} (${r.wins}勝${r.losses}敗${r.saves}S)');
      }
      for (final hr in summary.homeRuns) {
        final teamName =
            hr.isAway ? game.awayTeamName : game.homeTeamName;
        print('  HR: ${hr.batter.name} 第${hr.seasonNumber}号 '
            '($teamName ${hr.inning}回${hr.isAway ? "表" : "裏"})');
      }
      print('');
    }
  }
}

import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// ワイルドピッチ（WP）・パスボール（PB）の発生頻度を計測。
///
/// NPB 目安: WP は 1チーム143試合で 40〜60 程度（~0.3-0.4/試合）、
///           PB は 1チーム143試合で 5〜15 程度（~0.05-0.1/試合）。
///
/// WP/PB は「ボール球 + 走者あり」の投球でのみ判定される。
/// 投手の制球力別 WP 発生率も併せて出す。
void main() {
  const numSeasons = 6;
  const gamesPerTeam = 150;

  int wp = 0, pb = 0, teamGames = 0;

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(4400 + s)).generateLeague();
    final schedule =
        ScheduleGenerator().generateForGamesPerTeam(teams, gamesPerTeam);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      gamesPerTeam: gamesPerTeam,
      random: Random(4400 + s),
    );
    controller.advanceAll();

    for (final sg in schedule.games) {
      final result = controller.resultFor(sg.gameNumber);
      if (result == null) continue;
      teamGames += 2;
      for (final half in result.halfInnings) {
        for (final ab in half.atBats) {
          for (final pitch in ab.pitches) {
            final be = pitch.batteryError;
            if (be == null) continue;
            if (be.type == BatteryErrorType.wildPitch) wp++;
            if (be.type == BatteryErrorType.passedBall) pb++;
          }
        }
      }
    }
  }

  String per(int n) => (n / teamGames).toStringAsFixed(3);
  String per143(int n) => (n / teamGames * 143).toStringAsFixed(1);

  print('===== WP / PB の発生頻度（$numSeasons シーズン × $gamesPerTeam 試合'
      ' / $teamGames team-games） =====');
  print('');
  print('              1試合あたり   143試合換算   NPB目安');
  print('  ワイルドピッチ : ${per(wp)}        ${per143(wp)}        40〜60');
  print('  パスボール     : ${per(pb)}        ${per143(pb)}        5〜15');
}

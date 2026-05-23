import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// ワイルドピッチ（WP）・パスボール（PB）・捕手送球エラー（CT）の発生頻度を計測。
///
/// NPB 目安: WP は 1チーム143試合で 40〜60 程度（~0.3-0.4/試合）、
///           PB は 1チーム143試合で 5〜15 程度（~0.05-0.1/試合）、
///           CT（捕手の PB 除く失策）は 1チーム150試合で 3〜5 程度。
///
/// WP/PB は「ボール球 + 走者あり」、CT は「走者あり投球全般」で独立試行。
/// 守備力別の CT 発生率も併せて出す。
void main() {
  const numSeasons = 6;
  const gamesPerTeam = 150;

  int wp = 0, pb = 0, ct = 0, teamGames = 0;
  // 捕手守備力 → CT 件数（捕手スタメンの守備力で集計）
  final ctByFielding = <int, int>{for (var k = 1; k <= 10; k++) k: 0};
  final ctGamesByFielding = <int, int>{for (var k = 1; k <= 10; k++) k: 0};

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

    // 捕手スタメンの守備力で出場試合数を集計
    for (final team in teams) {
      final catcher = team.players[0];
      final f = catcher.getFielding(DefensePosition.catcher);
      final st = controller.batterStats[catcher.id];
      if (st == null) continue;
      ctGamesByFielding[f] = (ctGamesByFielding[f] ?? 0) + st.games;
    }

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
            if (be.type == BatteryErrorType.catcherThrowing) {
              ct++;
              // 守備チームの捕手 (players[0]) を取得
              final defensiveTeam =
                  half.isTop ? sg.homeTeam : sg.awayTeam;
              final f = defensiveTeam.players[0]
                  .getFielding(DefensePosition.catcher);
              ctByFielding[f] = (ctByFielding[f] ?? 0) + 1;
            }
          }
        }
      }
    }
  }

  String per(int n) => (n / teamGames).toStringAsFixed(3);
  String per143(int n) => (n / teamGames * 143).toStringAsFixed(1);
  String per150(int n) => (n / teamGames * 150).toStringAsFixed(1);

  print('===== WP / PB / CT の発生頻度（$numSeasons シーズン × $gamesPerTeam 試合'
      ' / $teamGames team-games） =====');
  print('');
  print('              1試合あたり   143試合換算   NPB目安');
  print('  ワイルドピッチ : ${per(wp)}        ${per143(wp)}        40〜60');
  print('  パスボール     : ${per(pb)}        ${per143(pb)}        5〜15');
  print('  捕手送球エラー : ${per(ct)}        ${per150(ct)} (150換算)  3〜5');
  print('');
  print('--- 捕手送球エラーの守備力別内訳（捕手スタメンの守備力で集計） ---');
  print(' 守備力 | のべ試合 | エラー数 | 150試合換算');
  print('--------|----------|----------|------------');
  for (int f = 1; f <= 10; f++) {
    final g = ctGamesByFielding[f] ?? 0;
    final e = ctByFielding[f] ?? 0;
    final per150val = g == 0 ? 0.0 : e / g * 150;
    print('   ${f.toString().padLeft(2)}   '
        '| ${g.toString().padLeft(8)} '
        '| ${e.toString().padLeft(8)} '
        '| ${per150val.toStringAsFixed(2).padLeft(10)}');
  }
}

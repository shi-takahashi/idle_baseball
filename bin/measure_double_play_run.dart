import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 併殺打時の3塁ランナー生還挙動を検証。
///
/// 期待:
///   - 1アウト未満で 3塁ランナーありの併殺打 → 3塁ランナーがホームインする
///   - 1アウトで 3塁ランナーありの併殺打 → 3アウトで終わるので得点は入らない
///   - 併殺打で得点が入っても打者には打点がつかない（NPB 公式記録規則）
///
/// runsScored / rbiCount の関係:
///   - doublePlay → rbiCount は必ず 0
///   - runsScored は 3塁ランナーがいれば 1 になりうる
void main() {
  const numSeasons = 3;

  int totalDoublePlays = 0;
  int dpWith3rdRunner = 0;
  int dpWith3rdAndScored = 0;
  int dpWith3rdAt0Out = 0;
  int dpWith3rdAt0OutScored = 0;
  int dpWith3rdAt1Out = 0;
  int dpWith3rdAt1OutScored = 0;
  int dpRbiNonzero = 0;
  int totalRbi = 0;
  int totalRunsScored = 0;
  int dpRunsScoredTotal = 0;
  int dpRbiTotal = 0;

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

    for (final sg in schedule.games) {
      final result = controller.resultFor(sg.gameNumber);
      if (result == null) continue;
      for (final half in result.halfInnings) {
        for (final ab in half.atBats) {
          if (ab.isIncomplete) continue;
          totalRbi += ab.rbiCount;
          totalRunsScored += ab.runsScored;

          if (ab.result.isDoublePlay) {
            totalDoublePlays++;
            dpRunsScoredTotal += ab.runsScored;
            dpRbiTotal += ab.rbiCount;

            // 打席開始時の3塁走者・アウト
            final hadThird = ab.runnersBefore.third != null;
            final outsBefore = ab.outsBefore;
            if (hadThird) {
              dpWith3rdRunner++;
              if (ab.runsScored > 0) {
                dpWith3rdAndScored++;
              }
              if (outsBefore == 0) {
                dpWith3rdAt0Out++;
                if (ab.runsScored > 0) dpWith3rdAt0OutScored++;
              } else if (outsBefore == 1) {
                dpWith3rdAt1Out++;
                if (ab.runsScored > 0) dpWith3rdAt1OutScored++;
              }
            }

            if (ab.rbiCount != 0) {
              dpRbiNonzero++;
              print('🚨 NG: 併殺打で打点 ${ab.rbiCount} '
                  '(runsScored ${ab.runsScored}, batter ${ab.batter.name})');
            }
          }
        }
      }
    }
  }

  print('===== 併殺打の3塁ランナー生還挙動の検証（${numSeasons}シーズン） =====');
  print('総併殺打: $totalDoublePlays');
  print('  うち3塁ランナーあり: $dpWith3rdRunner');
  print('    うち得点が入った: $dpWith3rdAndScored');
  print('  3塁あり 0アウト時: $dpWith3rdAt0Out / うち得点 $dpWith3rdAt0OutScored');
  print('  3塁あり 1アウト時: $dpWith3rdAt1Out / うち得点 $dpWith3rdAt1OutScored '
      '(3アウト終了のため得点 0 が期待値)');
  print('');
  print('===== 打点ルール =====');
  print('併殺打で rbiCount > 0 の件数: $dpRbiNonzero');
  if (dpRbiNonzero == 0) {
    print('✓ 併殺打時の打点は全て 0 になっている');
  } else {
    print('🚨 併殺打時に打点が記録されている打席が $dpRbiNonzero 件あった');
  }
  print('');
  print('併殺打 合計 runsScored: $dpRunsScoredTotal');
  print('併殺打 合計 rbiCount:   $dpRbiTotal');
  print('');
  print('===== リーグ全体 =====');
  print('合計打点: $totalRbi');
  print('合計得点 (runsScored): $totalRunsScored');
  print('差分: ${totalRunsScored - totalRbi}');
}

import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// エラー出塁による打点が0になっているか検証。
/// runsScored と rbiCount の関係:
///   reachedOnError → runsScored ≥ 0、rbiCount は必ず 0
///   その他 → runsScored == rbiCount（押し出しエラーなどの特殊ケースを除けば）
///
/// またリーグ全体の得失点と打点の差分も確認:
///   sum(rbiCount) は エラー出塁絡みのぶんだけ sum(runsScored) より少なくなる。
void main() {
  const numSeasons = 3;

  int errorAtBats = 0;
  int errorAtBatsWithRuns = 0;
  int errorRbiNonzero = 0;
  int errorRunsScoredTotal = 0;

  int totalRbi = 0;
  int totalRunsScored = 0;

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(900 + s)).generateLeague();
    final schedule = const ScheduleGenerator().generate(teams);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      random: Random(900 + s),
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

          if (ab.result == AtBatResultType.reachedOnError) {
            errorAtBats++;
            if (ab.runsScored > 0) {
              errorAtBatsWithRuns++;
              errorRunsScoredTotal += ab.runsScored;
            }
            if (ab.rbiCount != 0) {
              errorRbiNonzero++;
              print('🚨 NG: エラー出塁で打点 ${ab.rbiCount} '
                  '(runsScored ${ab.runsScored}, batter ${ab.batter.name})');
            }
          }
        }
      }
    }
  }

  print('===== エラー出塁による打点の検証（${numSeasons}シーズン） =====');
  print('総エラー出塁数: $errorAtBats');
  print('うち得点が入った打席: $errorAtBatsWithRuns');
  print('得点合計: $errorRunsScoredTotal 点');
  print('エラー出塁で rbiCount > 0 の打席数: $errorRbiNonzero');
  if (errorRbiNonzero == 0) {
    print('✓ エラー出塁時の打点は全て 0 になっている');
  } else {
    print('🚨 エラー出塁時に打点が記録されている打席が $errorRbiNonzero 件あった');
  }
  print('');
  print('===== リーグ全体 =====');
  print('合計打点: $totalRbi');
  print('合計得点 (runsScored): $totalRunsScored');
  print('差分（エラー出塁絡みで打点にならない得点）: ${totalRunsScored - totalRbi}');
}

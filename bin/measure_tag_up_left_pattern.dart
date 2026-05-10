import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 2,3塁ランナーありのレフトフライ時のタッチアップパターンを計測。
///
/// 期待:
/// - 「3塁ランナーのみタッチアップ」と「3塁・2塁ランナー両方タッチアップ」の
///   両方が発生するはず
/// - 「2塁ランナーのみタッチアップ」は発生しない
void main() {
  const numSeasons = 5;

  int total = 0; // 2,3塁あり レフトフライ
  int neither = 0; // 両方動かず
  int onlyThird = 0; // 3塁のみタッチアップ試行
  int both = 0; // 3塁・2塁両方タッチアップ試行
  int onlySecond = 0; // 2塁のみ（発生しないはず）

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(800 + s)).generateLeague();
    final schedule = const ScheduleGenerator().generate(teams);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      random: Random(800 + s),
    );
    controller.advanceAll();

    for (final sg in schedule.games) {
      final result = controller.resultFor(sg.gameNumber);
      if (result == null) continue;
      for (final half in result.halfInnings) {
        for (final ab in half.atBats) {
          if (ab.isIncomplete) continue;
          if (ab.result != AtBatResultType.flyOut &&
              ab.result != AtBatResultType.sacrificeFly) continue;
          if (ab.fieldPosition != FieldPosition.left) continue;

          final hadSecond = ab.runnersBefore.second != null;
          final hadThird = ab.runnersBefore.third != null;
          if (!hadSecond || !hadThird) continue;

          total++;

          bool thirdAttempted = false;
          bool secondAttempted = false;
          if (ab.tagUps != null) {
            for (final t in ab.tagUps!) {
              if (t.fromBase == Base.third) thirdAttempted = true;
              if (t.fromBase == Base.second) secondAttempted = true;
            }
          }

          if (!thirdAttempted && !secondAttempted) {
            neither++;
          } else if (thirdAttempted && !secondAttempted) {
            onlyThird++;
          } else if (!thirdAttempted && secondAttempted) {
            onlySecond++;
          } else {
            both++;
          }
        }
      }
    }
  }

  print('===== 2,3塁ありレフトフライ時のタッチアップパターン（${numSeasons}シーズン）=====');
  print('総件数: $total');
  print('  ① 動かず:                    $neither');
  print('  ② 3塁のみタッチアップ試行:   $onlyThird');
  print('  ③ 3塁・2塁両方タッチアップ:  $both');
  print('  ④ 2塁のみ(発生してはいけない): $onlySecond');
  if (onlySecond == 0) {
    print('✓ 2塁のみのタッチアップは発生していない');
  } else {
    print('🚨 2塁のみのタッチアップが $onlySecond 件発生');
  }
}

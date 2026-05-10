import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 外野フライ時の 2塁ランナーのタッチアップ挙動を方向別に計測。
///
/// 期待値:
/// - 単独タッチアップ(2塁のみ→3塁): レフトでは 0 件（3塁が近くアウトになりやすい）
/// - 同時タッチアップ(2,3塁あり): レフトでもたまに発生（外野手は本塁送球を選ぶため）
void main() {
  const numSeasons = 5;

  // [position] -> count
  final flyOutCount = <FieldPosition, int>{
    FieldPosition.left: 0,
    FieldPosition.center: 0,
    FieldPosition.right: 0,
  };
  // 2塁ランナーありの外野フライ件数（単独 / 同時）
  final flyOutWith2nd = <FieldPosition, int>{
    FieldPosition.left: 0,
    FieldPosition.center: 0,
    FieldPosition.right: 0,
  };
  final flyOutWith2ndAnd3rd = <FieldPosition, int>{
    FieldPosition.left: 0,
    FieldPosition.center: 0,
    FieldPosition.right: 0,
  };
  // 単独タッチアップ件数
  final soloTagUp2to3 = <FieldPosition, int>{
    FieldPosition.left: 0,
    FieldPosition.center: 0,
    FieldPosition.right: 0,
  };
  // 同時タッチアップ件数（2塁→3塁が成立した）
  final simultTagUp2to3 = <FieldPosition, int>{
    FieldPosition.left: 0,
    FieldPosition.center: 0,
    FieldPosition.right: 0,
  };

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

          final pos = ab.fieldPosition;
          if (pos == null || !pos.isOutfield) continue;
          if (!flyOutCount.containsKey(pos)) continue;

          flyOutCount[pos] = flyOutCount[pos]! + 1;

          final hadSecond = ab.runnersBefore.second != null;
          final hadThird = ab.runnersBefore.third != null;
          if (hadSecond) {
            flyOutWith2nd[pos] = flyOutWith2nd[pos]! + 1;
            if (hadThird) {
              flyOutWith2ndAnd3rd[pos] = flyOutWith2ndAnd3rd[pos]! + 1;
            }
          }

          if (ab.tagUps != null) {
            for (final t in ab.tagUps!) {
              if (t.fromBase == Base.second &&
                  t.toBase == Base.third &&
                  t.success) {
                if (hadThird) {
                  simultTagUp2to3[pos] = simultTagUp2to3[pos]! + 1;
                } else {
                  soloTagUp2to3[pos] = soloTagUp2to3[pos]! + 1;
                }
              }
            }
          }
        }
      }
    }
  }

  print('===== 外野フライ時の 2塁ランナータッチアップ計測（${numSeasons}シーズン）=====');
  for (final pos in [
    FieldPosition.left,
    FieldPosition.center,
    FieldPosition.right
  ]) {
    final fly = flyOutCount[pos]!;
    final w2 = flyOutWith2nd[pos]!;
    final w23 = flyOutWith2ndAnd3rd[pos]!;
    final solo2 = w2 - w23;
    final solo = soloTagUp2to3[pos]!;
    final sim = simultTagUp2to3[pos]!;
    print('${pos.displayName}フライ:');
    print('  総件数: $fly');
    print('  2塁あり(3塁なし): $solo2 / 単独タッチアップ成功: $solo');
    print('  2,3塁あり: $w23 / 同時タッチアップ(2塁→3塁)成功: $sim');
  }
}

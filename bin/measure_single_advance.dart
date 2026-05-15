import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 単打時の走者進塁を計測する。
/// - 1塁走者: 単打で 2塁止まり / 3塁進塁 の比率
/// - 2塁走者: 単打で 3塁止まり / ホーム生還 の比率
/// フルカウント（3-2）で決着した単打は走者がスタートを切っているため
/// 追加進塁率が上がるはず。カウント別にも内訳を出す。
void main() {
  const numSeasons = 5;

  // [全体, フルカウント]
  int first1to2 = 0, first1to3 = 0;
  int firstFull1to2 = 0, firstFull1to3 = 0;
  int second2to3 = 0, second2home = 0;
  int secondFull2to3 = 0, secondFull2home = 0;

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(2600 + s)).generateLeague();
    final schedule = const ScheduleGenerator().generate(teams);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      random: Random(2600 + s),
    );
    controller.advanceAll();

    for (final sg in schedule.games) {
      final result = controller.resultFor(sg.gameNumber);
      if (result == null) continue;
      for (final half in result.halfInnings) {
        for (int i = 0; i < half.atBats.length; i++) {
          final ab = half.atBats[i];
          if (ab.result != AtBatResultType.single) continue;

          final before = ab.runnersBefore;
          final scorers = ab.scoringRunners;
          final isFull = _isFullCount(ab.pitches);

          AtBatResult? next;
          if (i + 1 < half.atBats.length) next = half.atBats[i + 1];
          if (next == null) continue; // 進塁先が確認できない打席は除外
          final after = next.runnersBefore;

          if (before.first != null) {
            final r = before.first!;
            if (after.third?.id == r.id) {
              first1to3++;
              if (isFull) firstFull1to3++;
            } else if (after.second?.id == r.id) {
              first1to2++;
              if (isFull) firstFull1to2++;
            }
          }
          if (before.second != null) {
            final r = before.second!;
            if (scorers.any((p) => p.id == r.id)) {
              second2home++;
              if (isFull) secondFull2home++;
            } else if (after.third?.id == r.id) {
              second2to3++;
              if (isFull) secondFull2to3++;
            }
          }
        }
      }
    }
  }

  String pct(int a, int total) =>
      total == 0 ? '-' : '${(a / total * 100).toStringAsFixed(1)}%';

  final firstTotal = first1to2 + first1to3;
  final secondTotal = second2to3 + second2home;
  final firstFullTotal = firstFull1to2 + firstFull1to3;
  final secondFullTotal = secondFull2to3 + secondFull2home;

  print('===== 単打時の走者進塁（${numSeasons}シーズン） =====');
  print('');
  print('【1塁走者】 計 $firstTotal 件');
  print('  1塁→2塁: $first1to2 (${pct(first1to2, firstTotal)})');
  print('  1塁→3塁: $first1to3 (${pct(first1to3, firstTotal)})  ※NPB 1st-to-third ~27-30%');
  print('');
  print('【2塁走者】 計 $secondTotal 件');
  print('  2塁→3塁:   $second2to3 (${pct(second2to3, secondTotal)})');
  print('  2塁→ホーム: $second2home (${pct(second2home, secondTotal)})  ※NPB ~58-62%');
  print('');
  print('--- フルカウント（3-2）で決着した単打のみ ---');
  print('【1塁走者】 計 $firstFullTotal 件');
  print('  1塁→2塁: $firstFull1to2 (${pct(firstFull1to2, firstFullTotal)})');
  print('  1塁→3塁: $firstFull1to3 (${pct(firstFull1to3, firstFullTotal)})');
  print('【2塁走者】 計 $secondFullTotal 件');
  print('  2塁→3塁:   $secondFull2to3 (${pct(secondFull2to3, secondFullTotal)})');
  print('  2塁→ホーム: $secondFull2home (${pct(secondFull2home, secondFullTotal)})');
}

/// 打席の最後の投球時点のカウントがフルカウント（3-2）かどうか。
bool _isFullCount(List<PitchResult> pitches) {
  int balls = 0;
  int strikes = 0;
  for (int i = 0; i < pitches.length - 1; i++) {
    switch (pitches[i].type) {
      case PitchResultType.ball:
        balls++;
        break;
      case PitchResultType.strikeLooking:
      case PitchResultType.strikeSwinging:
        strikes++;
        break;
      case PitchResultType.foul:
        if (strikes < 2) strikes++;
        break;
      case PitchResultType.inPlay:
      case PitchResultType.hitByPitch:
        break;
    }
  }
  return balls == 3 && strikes == 2;
}

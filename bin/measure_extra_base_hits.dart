import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 二塁打・三塁打・本塁打の発生数を計測。
///
/// NPB 目安（143試合・1チーム）:
///   二塁打 ~210-240本（~1.5/試合）/ 三塁打 ~20-30本（~0.16/試合）
///   二塁打:三塁打 ≒ 9:1〜11:1
void main() {
  const numSeasons = 5;

  int singles = 0, doubles = 0, triples = 0, homers = 0;
  int triplesByError = 0; // 外野エラーで二塁打→三塁打に昇格したぶん
  int doublesByError = 0; // 外野エラーで単打→二塁打に昇格したぶん
  int teamGames = 0;

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(3700 + s)).generateLeague();
    final schedule = const ScheduleGenerator().generate(teams);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      random: Random(3700 + s),
    );
    controller.advanceAll();

    for (final sg in schedule.games) {
      final result = controller.resultFor(sg.gameNumber);
      if (result == null) continue;
      teamGames += 2;
      for (final half in result.halfInnings) {
        for (final ab in half.atBats) {
          switch (ab.result) {
            case AtBatResultType.single:
            case AtBatResultType.infieldHit:
              singles++;
              break;
            case AtBatResultType.double_:
              doubles++;
              if (ab.fieldingError != null) doublesByError++;
              break;
            case AtBatResultType.triple:
              triples++;
              if (ab.fieldingError != null) triplesByError++;
              break;
            case AtBatResultType.homeRun:
              homers++;
              break;
            default:
              break;
          }
        }
      }
    }
  }

  String per(int n) => (n / teamGames).toStringAsFixed(3);
  String per143(int n) => (n / teamGames * 143).toStringAsFixed(0);

  print('===== 長打の発生数（${numSeasons}シーズン / $teamGames team-games） =====');
  print('');
  print('              1チーム1試合   143試合換算');
  print('  単打      : ${per(singles)}        ${per143(singles)}');
  print('  二塁打    : ${per(doubles)}        ${per143(doubles)}   ← NPB ~210-240');
  print('  三塁打    : ${per(triples)}        ${per143(triples)}   ← NPB ~20-30');
  print('  本塁打    : ${per(homers)}        ${per143(homers)}');
  print('');
  print('  二塁打:三塁打 = ${(doubles / triples).toStringAsFixed(1)}:1   ← NPB ~9-11:1');
  print('');
  print('  うち外野エラー昇格: 二塁打 $doublesByError / 三塁打 $triplesByError');
}

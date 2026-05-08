import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 内野安打時の走者進塁を検証。
/// 期待: 内野安打では追加進塁は発生しない
///   - 1塁ランナーは2塁まで（3塁には行かない）
///   - 2塁ランナーは3塁まで（ホーム生還しない）
///   - 3塁ランナーは生還
void main() {
  const numSeasons = 3;

  int infieldHits = 0;
  int infieldHitsWithRunnerOn1 = 0;
  int firstRunnerTo3rd = 0; // NG: 1塁ランナーが3塁まで行ったケース
  int firstRunnerTo2nd = 0;
  int secondRunnerHome = 0; // NG: 2塁ランナーが内野安打でホーム生還
  int secondRunnerTo3rd = 0;

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(1300 + s)).generateLeague();
    final schedule = const ScheduleGenerator().generate(teams);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      random: Random(1300 + s),
    );
    controller.advanceAll();

    for (final sg in schedule.games) {
      final result = controller.resultFor(sg.gameNumber);
      if (result == null) continue;
      for (final half in result.halfInnings) {
        for (int i = 0; i < half.atBats.length; i++) {
          final ab = half.atBats[i];
          if (ab.result != AtBatResultType.infieldHit) continue;
          infieldHits++;

          final before = ab.runnersBefore;
          final scorers = ab.scoringRunners;

          // 次打席の runnersBefore を見て、各走者がどこに進んだかを確認
          AtBatResult? next;
          if (i + 1 < half.atBats.length) next = half.atBats[i + 1];

          if (before.first != null) {
            infieldHitsWithRunnerOn1++;
            final firstRunner = before.first!;
            if (next != null) {
              final after = next.runnersBefore;
              if (after.third?.id == firstRunner.id) {
                firstRunnerTo3rd++;
                print('🚨 NG: 1塁ランナー ${firstRunner.name} が内野安打で3塁まで進んだ '
                    '(${ab.batter.name}, ${ab.inning}回${ab.isTop ? "表" : "裏"})');
              } else if (after.second?.id == firstRunner.id) {
                firstRunnerTo2nd++;
              }
            }
          }
          if (before.second != null) {
            final secondRunner = before.second!;
            if (scorers.any((p) => p.id == secondRunner.id)) {
              secondRunnerHome++;
            } else if (next != null) {
              final after = next.runnersBefore;
              if (after.third?.id == secondRunner.id) {
                secondRunnerTo3rd++;
              }
            }
          }
        }
      }
    }
  }

  print('===== 内野安打時の走者進塁（${numSeasons}シーズン） =====');
  print('総内野安打数: $infieldHits');
  print('うち1塁ランナーありの内野安打: $infieldHitsWithRunnerOn1');
  print('  1塁→2塁: $firstRunnerTo2nd');
  print('  1塁→3塁: $firstRunnerTo3rd ${firstRunnerTo3rd == 0 ? "✓" : "🚨 NG"}');
  print('2塁ランナーがホーム生還: $secondRunnerHome ${secondRunnerHome == 0 ? "✓" : "🚨 NG"}');
  print('2塁ランナーが3塁: $secondRunnerTo3rd');
}

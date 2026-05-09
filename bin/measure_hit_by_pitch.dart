import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 死球の発生数・分布を計測。
/// NPB 目安: 1チーム143試合で 70〜80 件 ≒ 0.5/試合 ≒ 0.10/30試合シーズン換算
void main() {
  const numSeasons = 3;

  int totalGames = 0;
  int totalHbp = 0;
  int totalPa = 0;
  int totalPitches = 0;
  // 投手の制球力別の発生数
  final hbpByControl = <int, int>{};
  final pitchesByControl = <int, int>{};

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

    for (final g in controller.schedule.games) {
      final result = controller.resultFor(g.gameNumber);
      if (result == null) continue;
      // 1試合 = 2チームぶんの守備機会なので team-game = 2
      totalGames += 2;
      for (final half in result.halfInnings) {
        for (final ab in half.atBats) {
          if (ab.isIncomplete) continue;
          totalPa++;
          totalPitches += ab.pitches.length;
          final control = ab.pitcher.control ?? 5;
          pitchesByControl[control] =
              (pitchesByControl[control] ?? 0) + ab.pitches.length;
          if (ab.result == AtBatResultType.hitByPitch) {
            totalHbp++;
            hbpByControl[control] = (hbpByControl[control] ?? 0) + 1;
          }
        }
      }
    }
  }

  String pct(num n, num d) =>
      d == 0 ? '-' : '${(n * 100 / d).toStringAsFixed(3)}%';
  String f2(double v) => v.toStringAsFixed(2);

  print('===== 死球発生数（${numSeasons}シーズン） =====');
  print('team-games: $totalGames');
  print('総打席: $totalPa');
  print('総投球: $totalPitches');
  print('死球: $totalHbp');
  print('');
  print('1 team-game あたり死球: ${f2(totalHbp / totalGames)} (NPB ~0.5)');
  print('1 打席あたり死球: ${pct(totalHbp, totalPa)}');
  print('1 投球あたり死球: ${pct(totalHbp, totalPitches)}');
  print('');
  print('--- 投手制球力別 ---');
  final controls = {...hbpByControl.keys, ...pitchesByControl.keys}.toList()
    ..sort();
  for (final c in controls) {
    final h = hbpByControl[c] ?? 0;
    final p = pitchesByControl[c] ?? 0;
    print('  制球 $c: 死球 $h / 投球 $p (${pct(h, p)})');
  }
}

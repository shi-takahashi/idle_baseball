import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 制球（control）と先発投手の成績の関係を計測。
///
/// 制球は四球・死球の数に直結し、甘い球が増えて被打率も上がる。
/// 先発投手を制球値ごとにビンに分け、BB/9・HBP/9・被打率・防御率を見る。
void main() {
  const numSeasons = 8;
  const gamesPerTeam = 150;

  final bb = List<int>.filled(11, 0);
  final hbp = List<int>.filled(11, 0);
  final outs = List<int>.filled(11, 0);
  final hits = List<int>.filled(11, 0);
  final er = List<int>.filled(11, 0);
  final cnt = List<int>.filled(11, 0);

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(9600 + s)).generateLeague();
    final schedule =
        ScheduleGenerator().generateForGamesPerTeam(teams, gamesPerTeam);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      gamesPerTeam: gamesPerTeam,
      random: Random(9600 + s),
    );
    controller.advanceAll();

    for (final team in teams) {
      for (final p in team.startingRotation) {
        final st = controller.pitcherStats[p.id];
        if (st == null || st.outsRecorded < 150) continue;
        final c = (p.control ?? 5).clamp(1, 10);
        bb[c] += st.walksAllowed;
        hbp[c] += st.hitBatsmen;
        outs[c] += st.outsRecorded;
        hits[c] += st.hitsAllowed;
        er[c] += st.earnedRuns;
        cnt[c]++;
      }
    }
  }

  print('===== 制球 × 先発投手成績（$numSeasons シーズン × $gamesPerTeam 試合） =====');
  print('');
  print(' 制球 | 投手数 | BB/9 | HBP/9 | 被打率 | 防御率');
  print('------|--------|------|-------|--------|--------');
  for (int c = 1; c <= 10; c++) {
    if (cnt[c] == 0) {
      print('  ${c.toString().padLeft(2)}  |   0    |  -   |   -   |   -    |   -');
      continue;
    }
    final ip = outs[c] / 3.0;
    final bbPer9 = bb[c] / ip * 9;
    final hbpPer9 = hbp[c] / ip * 9;
    final baa = hits[c] / (outs[c] + hits[c]);
    final era = er[c] / ip * 9;
    print('  ${c.toString().padLeft(2)}  '
        '|  ${cnt[c].toString().padLeft(4)}  '
        '| ${bbPer9.toStringAsFixed(1).padLeft(4)} '
        '| ${hbpPer9.toStringAsFixed(2).padLeft(5)} '
        '| ${baa.toStringAsFixed(3)} '
        '| ${era.toStringAsFixed(2).padLeft(5)}');
  }
}

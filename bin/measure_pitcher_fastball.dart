import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 伸び（fastball クオリティ）と先発投手の成績の関係を計測。
///
/// 伸びはストレートの空振り率・被打率に効く（球速とは独立）。
/// 「球速の割に空振りが取れる」が伸びの推測材料になるはず。
/// 先発投手を伸び値ごとにビンに分け、K/9・被打率・防御率を見る。
void main() {
  const numSeasons = 8;
  const gamesPerTeam = 150;

  // 伸び値ごとの集計（先発投手のみ、十分なイニングを投げた者）
  final k = List<int>.filled(11, 0);
  final outs = List<int>.filled(11, 0);
  final hits = List<int>.filled(11, 0);
  final earnedRuns = List<int>.filled(11, 0);
  final pitchers = List<int>.filled(11, 0);

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(9700 + s)).generateLeague();
    final schedule =
        ScheduleGenerator().generateForGamesPerTeam(teams, gamesPerTeam);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      gamesPerTeam: gamesPerTeam,
      random: Random(9700 + s),
    );
    controller.advanceAll();

    for (final team in teams) {
      for (final p in team.startingRotation) {
        final st = controller.pitcherStats[p.id];
        if (st == null) continue;
        // 規定投球回（150試合 × 1.0 = 150IP = 450 アウト）の 1/3 以上を投げた先発
        if (st.outsRecorded < 150) continue;
        final f = (p.fastball ?? 5).clamp(1, 10);
        k[f] += st.strikeoutsRecorded;
        outs[f] += st.outsRecorded;
        hits[f] += st.hitsAllowed;
        earnedRuns[f] += st.earnedRuns;
        pitchers[f]++;
      }
    }
  }

  print('===== 伸び × 先発投手成績（$numSeasons シーズン × $gamesPerTeam 試合） =====');
  print('');
  print(' 伸び | 投手数 | K/9  | 被打率 | 防御率');
  print('------|--------|------|--------|--------');
  for (int f = 1; f <= 10; f++) {
    if (pitchers[f] == 0) {
      print('  ${f.toString().padLeft(2)}  |   0    |  -   |   -    |   -');
      continue;
    }
    final ip = outs[f] / 3.0;
    final kPer9 = k[f] / ip * 9;
    final baa = hits[f] / (outs[f] + hits[f]); // 簡易被打率
    final era = earnedRuns[f] / ip * 9;
    print('  ${f.toString().padLeft(2)}  '
        '|  ${pitchers[f].toString().padLeft(4)}  '
        '| ${kPer9.toStringAsFixed(1).padLeft(4)} '
        '| ${baa.toStringAsFixed(3)} '
        '| ${era.toStringAsFixed(2).padLeft(5)}');
  }
}

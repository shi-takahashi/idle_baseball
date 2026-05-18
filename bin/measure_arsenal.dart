import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 持ち球数（ストレート + 投げられる変化球の種類数）と先発投手成績の関係を計測。
///
/// 球種が多い投手は打者が待ち球を絞れず、わずかに有利になるはず。
/// 持ち球数ごとに先発をビン分けし、K/9・被打率・防御率を見る。
/// あわせてリーグ全体の持ち球数の平均（基準値の設定に使う）も出す。
int _arsenal(Player p) {
  var n = 1;
  if (p.slider != null) n++;
  if (p.curve != null) n++;
  if (p.splitter != null) n++;
  if (p.changeup != null) n++;
  if (p.shoot != null) n++;
  if (p.cutter != null) n++;
  if (p.sinker != null) n++;
  return n;
}

void main() {
  const numSeasons = 8;
  const gamesPerTeam = 150;

  final k = List<int>.filled(9, 0);
  final bb = List<int>.filled(9, 0);
  final outs = List<int>.filled(9, 0);
  final hits = List<int>.filled(9, 0);
  final er = List<int>.filled(9, 0);
  final cnt = List<int>.filled(9, 0);

  // リーグ全体の持ち球数分布（全投手）
  final arsenalDist = <int, int>{};

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(6400 + s)).generateLeague();
    final schedule =
        ScheduleGenerator().generateForGamesPerTeam(teams, gamesPerTeam);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      gamesPerTeam: gamesPerTeam,
      random: Random(6400 + s),
    );
    controller.advanceAll();

    for (final team in teams) {
      for (final p in [
        ...team.startingRotation,
        ...team.bullpen,
      ]) {
        arsenalDist[_arsenal(p)] = (arsenalDist[_arsenal(p)] ?? 0) + 1;
      }
      for (final p in team.startingRotation) {
        final st = controller.pitcherStats[p.id];
        if (st == null || st.outsRecorded < 150) continue;
        final a = _arsenal(p);
        k[a] += st.strikeoutsRecorded;
        bb[a] += st.walksAllowed;
        outs[a] += st.outsRecorded;
        hits[a] += st.hitsAllowed;
        er[a] += st.earnedRuns;
        cnt[a]++;
      }
    }
  }

  var distTotal = 0;
  var distSum = 0;
  arsenalDist.forEach((a, c) {
    distTotal += c;
    distSum += a * c;
  });

  print('===== 持ち球数 × 先発投手成績（$numSeasons シーズン × $gamesPerTeam 試合） =====');
  print('');
  print(' 持ち球 | 投手数 | K/9  | BB/9 | 被打率 | 防御率');
  print('--------|--------|------|------|--------|--------');
  for (int a = 3; a <= 8; a++) {
    if (cnt[a] == 0) {
      print('   $a    |   0    |  -   |  -   |   -    |   -');
      continue;
    }
    final ip = outs[a] / 3.0;
    print('   $a    '
        '| ${cnt[a].toString().padLeft(5)}  '
        '| ${(k[a] / ip * 9).toStringAsFixed(1).padLeft(4)} '
        '| ${(bb[a] / ip * 9).toStringAsFixed(1).padLeft(4)} '
        '| ${(hits[a] / (outs[a] + hits[a])).toStringAsFixed(3)} '
        '| ${(er[a] / ip * 9).toStringAsFixed(2).padLeft(5)}');
  }
  print('');
  print('全投手の持ち球数の平均: '
      '${(distSum / distTotal).toStringAsFixed(2)}（n=$distTotal）');
}

import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 球速（averageSpeed）と先発投手の成績の関係を計測。
///
/// 球速は見える主指標。「速い＝三振が取れて打たれにくい」が明確に出るか、
/// 隠しパラメータ（伸び）より影響が強いかを確認する。
void main() {
  const numSeasons = 8;
  const gamesPerTeam = 150;

  // 球速バケツごとの集計（先発投手のみ）。バケツは 2km 刻み。
  String bucketOf(int speed) {
    if (speed <= 142) return '〜142';
    if (speed <= 144) return '143-144';
    if (speed <= 146) return '145-146';
    if (speed <= 148) return '147-148';
    if (speed <= 150) return '149-150';
    if (speed <= 152) return '151-152';
    return '153〜';
  }

  const buckets = ['〜142', '143-144', '145-146', '147-148', '149-150', '151-152', '153〜'];
  final k = {for (final b in buckets) b: 0};
  final outs = {for (final b in buckets) b: 0};
  final hits = {for (final b in buckets) b: 0};
  final er = {for (final b in buckets) b: 0};
  final cnt = {for (final b in buckets) b: 0};

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(9800 + s)).generateLeague();
    final schedule =
        ScheduleGenerator().generateForGamesPerTeam(teams, gamesPerTeam);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      gamesPerTeam: gamesPerTeam,
      random: Random(9800 + s),
    );
    controller.advanceAll();

    for (final team in teams) {
      for (final p in team.startingRotation) {
        final st = controller.pitcherStats[p.id];
        if (st == null || st.outsRecorded < 150) continue;
        final b = bucketOf(p.averageSpeed ?? 145);
        k[b] = k[b]! + st.strikeoutsRecorded;
        outs[b] = outs[b]! + st.outsRecorded;
        hits[b] = hits[b]! + st.hitsAllowed;
        er[b] = er[b]! + st.earnedRuns;
        cnt[b] = cnt[b]! + 1;
      }
    }
  }

  print('===== 球速 × 先発投手成績（$numSeasons シーズン × $gamesPerTeam 試合） =====');
  print('');
  print(' 球速帯   | 投手数 | K/9  | 被打率 | 防御率');
  print('----------|--------|------|--------|--------');
  for (final b in buckets) {
    if (cnt[b] == 0) {
      print(' ${b.padRight(8)} |   0    |  -   |   -    |   -');
      continue;
    }
    final ip = outs[b]! / 3.0;
    final kPer9 = k[b]! / ip * 9;
    final baa = hits[b]! / (outs[b]! + hits[b]!);
    final era = er[b]! / ip * 9;
    print(' ${b.padRight(8)} '
        '|  ${cnt[b].toString().padLeft(4)}  '
        '| ${kPer9.toStringAsFixed(1).padLeft(4)} '
        '| ${baa.toStringAsFixed(3)} '
        '| ${era.toStringAsFixed(2).padLeft(5)}');
  }
}

import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// ミート（meet）と打率・三振率の関係を計測。
///
/// ミートが高い → 三振が減り打率が上がる、という関係が能力値ごとに
/// はっきり出ているかを確認する。150 試合では極端な値どうしは明確に差が
/// 付き、隣接値はある程度ばらつく、というカーブが理想（設計の柱②）。
void main() {
  // ミート値ごとの集計（投手の打席は除外）
  const numSeasons = 8;
  const gamesPerTeam = 150;

  final ab = List<int>.filled(11, 0);
  final hits = List<int>.filled(11, 0);
  final k = List<int>.filled(11, 0);
  final pa = List<int>.filled(11, 0);
  final players = List<int>.filled(11, 0);
  // 規定打席（150試合 × 3.1 ≒ 465）到達者だけの別集計
  final abReg = List<int>.filled(11, 0);
  final hitsReg = List<int>.filled(11, 0);
  final kReg = List<int>.filled(11, 0);
  final paReg = List<int>.filled(11, 0);
  final playersReg = List<int>.filled(11, 0);

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(5100 + s)).generateLeague();
    final schedule =
        ScheduleGenerator().generateForGamesPerTeam(teams, gamesPerTeam);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      gamesPerTeam: gamesPerTeam,
      random: Random(5100 + s),
    );
    controller.advanceAll();

    for (final st in controller.batterStats.values) {
      if (st.player.isPitcher) continue;
      final m = (st.player.meet ?? 5).clamp(1, 10);
      ab[m] += st.atBats;
      hits[m] += st.hits;
      k[m] += st.strikeouts;
      pa[m] += st.plateAppearances;
      players[m]++;
      if (st.plateAppearances >= 465) {
        abReg[m] += st.atBats;
        hitsReg[m] += st.hits;
        kReg[m] += st.strikeouts;
        paReg[m] += st.plateAppearances;
        playersReg[m]++;
      }
    }
  }

  String avg(int h, int a) => a == 0 ? '  -  ' : (h / a).toStringAsFixed(3);
  String pct(int x, int p) =>
      p == 0 ? ' - ' : '${(x / p * 100).toStringAsFixed(1)}%';

  print('===== ミート × 打率・三振率（$numSeasons シーズン × $gamesPerTeam 試合） =====');
  print('');
  print(' meet | 選手数 | 打率(全体) | K率(全体) || 規定到達 | 打率 | K率');
  print('------|--------|------------|-----------|----------|-------|------');
  for (int m = 1; m <= 10; m++) {
    final mm = m.toString().padLeft(2);
    print('  $mm  '
        '|  ${players[m].toString().padLeft(4)}  '
        '|   ${avg(hits[m], ab[m])}    '
        '|   ${pct(k[m], pa[m]).padLeft(6)}  '
        '||  ${playersReg[m].toString().padLeft(4)}    '
        '| ${avg(hitsReg[m], abReg[m])} '
        '| ${pct(kReg[m], paReg[m]).padLeft(6)}');
  }
}

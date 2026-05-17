import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 選球眼（eye）と四球率・打率の関係を計測。
///
/// 期待する形:
/// - 選球眼が高い → 四球が増える（一番はっきり効く指標）
/// - 打率はミートほどは動かないが、選球眼が高いと結果的に少し上がる程度
/// これにより「ミート低・長打高・選球眼高」の一発屋タイプが再現できる。
void main() {
  const numSeasons = 8;
  const gamesPerTeam = 150;

  // eye 値ごとの集計（投手の打席は除外）。規定打席（465）到達者のみ。
  final pa = List<int>.filled(11, 0);
  final bb = List<int>.filled(11, 0);
  final ab = List<int>.filled(11, 0);
  final hits = List<int>.filled(11, 0);
  final hbp = List<int>.filled(11, 0);
  final players = List<int>.filled(11, 0);
  // 選抜バイアス検証用: eye ビンごとの規定到達者の平均ミート・長打力
  final meetSum = List<int>.filled(11, 0);
  final powerSum = List<int>.filled(11, 0);

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(6200 + s)).generateLeague();
    final schedule =
        ScheduleGenerator().generateForGamesPerTeam(teams, gamesPerTeam);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      gamesPerTeam: gamesPerTeam,
      random: Random(6200 + s),
    );
    controller.advanceAll();

    for (final st in controller.batterStats.values) {
      if (st.player.isPitcher) continue;
      if (st.plateAppearances < 465) continue;
      final e = (st.player.eye ?? 5).clamp(1, 10);
      pa[e] += st.plateAppearances;
      bb[e] += st.walks;
      ab[e] += st.atBats;
      hits[e] += st.hits;
      hbp[e] += st.hitByPitch;
      meetSum[e] += st.player.meet ?? 5;
      powerSum[e] += st.player.power ?? 5;
      players[e]++;
    }
  }

  String avg(int h, int a) => a == 0 ? '  -  ' : (h / a).toStringAsFixed(3);
  String pct(int x, int p) =>
      p == 0 ? ' - ' : '${(x / p * 100).toStringAsFixed(1)}%';

  print('===== 選球眼 × 四球率・打率'
      '（$numSeasons シーズン × $gamesPerTeam 試合、規定打席到達者） =====');
  print('');
  print(' eye | 選手数 | BB率 | 打率 | 150試合BB | 平均ミート | 平均長打');
  print('-----|--------|-------|-------|-----------|------------|----------');
  for (int e = 1; e <= 10; e++) {
    if (players[e] == 0) {
      print('  ${e.toString().padLeft(2)} |   0    |   -   |   -   |    -      |     -      |    -');
      continue;
    }
    final bbPer = bb[e] / players[e];
    final meetAvg = meetSum[e] / players[e];
    final powerAvg = powerSum[e] / players[e];
    print('  ${e.toString().padLeft(2)} '
        '|  ${players[e].toString().padLeft(4)}  '
        '| ${pct(bb[e], pa[e]).padLeft(5)} '
        '| ${avg(hits[e], ab[e])} '
        '|   ${bbPer.toStringAsFixed(1).padLeft(5)}   '
        '|    ${meetAvg.toStringAsFixed(2)}    '
        '|   ${powerAvg.toStringAsFixed(2)}');
  }
  print('');
  print('※ 規定打席到達者だけを見ると、高 eye ほど平均ミートが低い傾向が出れば');
  print('  「打率が下がって見える」のは選抜バイアス（eye 自体は打率に無影響）。');
}

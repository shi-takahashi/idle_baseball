import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 長打力（power）と本塁打数の関係を計測。
///
/// 各野手の本塁打を power 値ごとにビンに集計し、150 試合換算で表示する。
/// 「power 9 で 40 本前後 / power 4 以下は 1 桁」が目標イメージ。
void main() {
  // power9/10 はリーグに数人しかいないため、tail を見るにはシーズン数が要る。
  const numSeasons = 8;
  const gamesPerTeam = 150;

  // power 値ごとの集計
  final hrByPower = List<int>.filled(11, 0);
  final gamesByPower = List<int>.filled(11, 0);
  final paByPower = List<int>.filled(11, 0);
  final abByPower = List<int>.filled(11, 0);
  final playersByPower = List<int>.filled(11, 0);
  // 規定打席（150試合 × 3.1 ≒ 465）以上の野手のみ「主力」として別集計
  final hrRegular = List<int>.filled(11, 0);
  final playersRegular = List<int>.filled(11, 0);

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(9100 + s)).generateLeague();
    final schedule = ScheduleGenerator()
        .generateForGamesPerTeam(teams, gamesPerTeam);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      gamesPerTeam: gamesPerTeam,
      random: Random(9100 + s),
    );
    controller.advanceAll();

    for (final st in controller.batterStats.values) {
      if (st.player.isPitcher) continue;
      final p = (st.player.power ?? 5).clamp(1, 10);
      hrByPower[p] += st.homeRuns;
      gamesByPower[p] += st.games;
      paByPower[p] += st.plateAppearances;
      abByPower[p] += st.atBats;
      playersByPower[p]++;
      if (st.plateAppearances >= 465) {
        hrRegular[p] += st.homeRuns;
        playersRegular[p]++;
      }
    }
  }

  print('===== 長打力 × 本塁打（$numSeasons シーズン × $gamesPerTeam 試合） =====');
  print('');
  print(' power | 選手数 | 平均HR(全体) | 150試合換算HR | 規定打席到達者の平均HR');
  print('-------|--------|--------------|---------------|------------------------');
  for (int p = 1; p <= 10; p++) {
    if (playersByPower[p] == 0) {
      print('   $p   |   0    |      -       |       -       |       -');
      continue;
    }
    final avgHr = hrByPower[p] / playersByPower[p];
    final per150 = gamesByPower[p] == 0
        ? 0.0
        : hrByPower[p] / gamesByPower[p] * 150;
    final regAvg = playersRegular[p] == 0
        ? null
        : hrRegular[p] / playersRegular[p];
    final pp = p.toString().padLeft(2);
    print('   $pp  |  ${playersByPower[p].toString().padLeft(4)}  '
        '|    ${avgHr.toStringAsFixed(1).padLeft(5)}     '
        '|     ${per150.toStringAsFixed(1).padLeft(5)}     '
        '|   ${regAvg == null ? '  -  (n=0)' : '${regAvg.toStringAsFixed(1)} (n=${playersRegular[p]})'}');
  }
}

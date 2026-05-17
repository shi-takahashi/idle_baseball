import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 走力（speed）と盗塁・三塁打・内野安打の関係を計測。
///
/// 期待する形:
/// - 盗塁は走力上位（おおむね 6〜7 以上）に集中する（発動カーブが非線形）
/// - 走力が中位以下の選手は盗塁をほぼしないので、速い/遅いの差は
///   内野安打・三塁打の数に現れるはず
void main() {
  const numSeasons = 8;
  const gamesPerTeam = 150;

  // speed 値ごとの集計（投手除く・規定打席 465 到達者のみ）
  final sb = List<int>.filled(11, 0);
  final cs = List<int>.filled(11, 0);
  final triples = List<int>.filled(11, 0);
  final infieldHits = List<int>.filled(11, 0);
  final players = List<int>.filled(11, 0);

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(7300 + s)).generateLeague();
    final schedule =
        ScheduleGenerator().generateForGamesPerTeam(teams, gamesPerTeam);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      gamesPerTeam: gamesPerTeam,
      random: Random(7300 + s),
    );
    controller.advanceAll();

    // 内野安打は BatterSeasonStats に独立カウントが無いので、
    // 試合結果の打席を走査して打者 id ごとに数える。
    final infieldHitById = <String, int>{};
    for (final sg in schedule.games) {
      final result = controller.resultFor(sg.gameNumber);
      if (result == null) continue;
      for (final half in result.halfInnings) {
        for (final ab in half.atBats) {
          if (ab.result == AtBatResultType.infieldHit) {
            infieldHitById[ab.batter.id] =
                (infieldHitById[ab.batter.id] ?? 0) + 1;
          }
        }
      }
    }

    for (final st in controller.batterStats.values) {
      if (st.player.isPitcher) continue;
      if (st.plateAppearances < 465) continue;
      final sp = (st.player.speed ?? 5).clamp(1, 10);
      sb[sp] += st.stolenBases;
      cs[sp] += st.caughtStealing;
      triples[sp] += st.triples;
      infieldHits[sp] += infieldHitById[st.player.id] ?? 0;
      players[sp]++;
    }
  }

  String per(int x, int p) => p == 0 ? '  -  ' : (x / p).toStringAsFixed(1);

  print('===== 走力 × 盗塁・三塁打・内野安打'
      '（$numSeasons シーズン × $gamesPerTeam 試合、規定打席到達者の150試合平均） =====');
  print('');
  print(' 走力 | 選手数 | 盗塁 | 盗塁死 | 成功率 | 三塁打 | 内野安打');
  print('------|--------|------|--------|--------|--------|----------');
  for (int sp = 1; sp <= 10; sp++) {
    if (players[sp] == 0) {
      print('  ${sp.toString().padLeft(2)}  |   0    |   -  |    -   |   -    |   -    |    -');
      continue;
    }
    final att = sb[sp] + cs[sp];
    final rate = att == 0 ? ' - ' : '${(sb[sp] / att * 100).toStringAsFixed(0)}%';
    print('  ${sp.toString().padLeft(2)}  '
        '|  ${players[sp].toString().padLeft(4)}  '
        '| ${per(sb[sp], players[sp]).padLeft(4)} '
        '|  ${per(cs[sp], players[sp]).padLeft(4)}  '
        '|  ${rate.padLeft(4)}  '
        '|  ${per(triples[sp], players[sp]).padLeft(4)}  '
        '|   ${per(infieldHits[sp], players[sp]).padLeft(4)}');
  }
}

import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 本塁打ランキング・防御率ランキング上位を表示。
/// NPB 近年(投高打低): 本塁打王 30〜35 / 防御率1位 1.50〜2.00 / 上位5名 2.00〜2.50
void main() {
  const numSeasons = 5;
  const gamesPerTeam = 150;
  final qualifiedPA = (gamesPerTeam * 3.1).round();
  final qualifiedOuts = (gamesPerTeam * 1.0).round() * 3;

  print(
      '===== タイトル争い (${numSeasons}シーズン × ${gamesPerTeam}試合, 規定打席 $qualifiedPA / 規定投球回 ${qualifiedOuts ~/ 3}) =====');
  print('');

  final allHrLeaders = <int>[]; // 各シーズンの本塁打王
  final allEra1 = <double>[]; // 各シーズンの防御率1位
  final allEraTop5 = <List<double>>[]; // 各シーズンの防御率トップ5

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(2200 + s)).generateLeague();
    final schedule =
        ScheduleGenerator().generateForGamesPerTeam(teams, gamesPerTeam);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      gamesPerTeam: gamesPerTeam,
      random: Random(2200 + s),
    );
    controller.advanceAll();

    // 本塁打ランキング(規定打席以上の野手)
    final batterEntries = controller.batterStats.values
        .where((st) => !st.player.isPitcher && st.plateAppearances >= qualifiedPA)
        .toList()
      ..sort((a, b) => b.homeRuns.compareTo(a.homeRuns));
    final top10Hr = batterEntries.take(10).toList();

    // 防御率ランキング(規定投球回以上)
    final pitcherEntries = controller.pitcherStats.values
        .where((st) => st.outsRecorded >= qualifiedOuts)
        .toList()
      ..sort((a, b) => a.era.compareTo(b.era));
    final top10Era = pitcherEntries.take(10).toList();

    print('--- Season ${s + 1} ---');
    print('本塁打 TOP5:');
    for (int i = 0; i < 5 && i < top10Hr.length; i++) {
      final st = top10Hr[i];
      final avg = st.battingAverage.toStringAsFixed(3);
      print(
          '  ${i + 1}. ${st.player.name} (power=${st.player.power}) HR=${st.homeRuns} / 打率$avg / 打席${st.plateAppearances}');
    }
    print('防御率 TOP5:');
    final eraTop5 = <double>[];
    for (int i = 0; i < 5 && i < top10Era.length; i++) {
      final st = top10Era[i];
      eraTop5.add(st.era);
      print(
          '  ${i + 1}. ${st.player.name} (球速=${st.player.averageSpeed} 制球=${st.player.control} 伸び=${st.player.fastball}) ERA=${st.era.toStringAsFixed(2)} / IP=${st.inningsPitchedDisplay}');
    }
    print('');

    allHrLeaders.add(top10Hr.isNotEmpty ? top10Hr.first.homeRuns : 0);
    allEra1.add(top10Era.isNotEmpty ? top10Era.first.era : 99);
    allEraTop5.add(eraTop5);
  }

  print('===== サマリ (${numSeasons}シーズン平均) =====');
  final avgHrKing = allHrLeaders.reduce((a, b) => a + b) / allHrLeaders.length;
  final avgEra1 = allEra1.reduce((a, b) => a + b) / allEra1.length;
  print(
      '本塁打王 平均: ${avgHrKing.toStringAsFixed(1)} (NPB近年 30〜35) / 各シーズン: ${allHrLeaders.join(", ")}');
  print(
      '防御率1位 平均: ${avgEra1.toStringAsFixed(2)} (NPB近年 1.50〜2.00) / 各シーズン: ${allEra1.map((e) => e.toStringAsFixed(2)).join(", ")}');

  // 防御率トップ5の平均(リーグ全体での投手強さの目安)
  final allTop5 = allEraTop5.expand((e) => e).toList();
  if (allTop5.isNotEmpty) {
    final avgTop5 = allTop5.reduce((a, b) => a + b) / allTop5.length;
    print('防御率TOP5平均: ${avgTop5.toStringAsFixed(2)} (NPB近年 2.00〜2.50)');
  }
}

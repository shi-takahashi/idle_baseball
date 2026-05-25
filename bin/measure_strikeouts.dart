import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 奪三振ランキング・IP 分布・K/9 分布を計測。
/// NPB 近年: 最多奪三振 145-195、200K 以上はほぼゼロ、規定到達投手の K/9 6-9
void main() {
  const numSeasons = 6;
  const gamesPerTeam = 150;
  final qualifiedOuts = (gamesPerTeam * 1.0).round() * 3;

  print(
      '===== 奪三振 / IP / K9 分布 ($numSeasons シーズン × $gamesPerTeam 試合, 規定投球回${qualifiedOuts ~/ 3}) =====');
  print('NPB 近年: 最多奪三振 145-195 / 200K+ はほぼ 0 / 規定到達 K/9 6-9');
  print('');

  final allKLeaders = <int>[];
  final over200K = <int>[];
  final allIPLeaders = <double>[];
  final allTopKs = <List<int>>[];
  final allK9 = <double>[];
  final allIPRegular = <double>[];

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(7700 + s)).generateLeague();
    final schedule =
        ScheduleGenerator().generateForGamesPerTeam(teams, gamesPerTeam);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      gamesPerTeam: gamesPerTeam,
      random: Random(7700 + s),
    );
    controller.advanceAll();

    final pitchers = controller.pitcherStats.values
        .where((st) => st.outsRecorded >= qualifiedOuts)
        .toList();

    pitchers.sort((a, b) => b.strikeoutsRecorded.compareTo(a.strikeoutsRecorded));
    final topK = pitchers.take(5).toList();

    final byIP = [...pitchers]..sort((a, b) => b.outsRecorded.compareTo(a.outsRecorded));

    print('--- Season ${s + 1} ---');
    print('K TOP5:');
    for (int i = 0; i < topK.length; i++) {
      final p = topK[i];
      final k9 = p.outsRecorded == 0 ? 0.0 : p.strikeoutsRecorded * 27 / p.outsRecorded;
      print(
          '  ${i + 1}. ${p.player.name} K=${p.strikeoutsRecorded} / IP=${p.inningsPitchedDisplay} / K9=${k9.toStringAsFixed(1)} (球速${p.player.averageSpeed} 伸${p.player.fastball} 制${p.player.control})');
    }
    print('IP TOP3:');
    for (int i = 0; i < 3 && i < byIP.length; i++) {
      final p = byIP[i];
      print('  ${i + 1}. ${p.player.name} IP=${p.inningsPitchedDisplay} K=${p.strikeoutsRecorded}');
    }
    print('');

    allKLeaders.add(topK.isNotEmpty ? topK.first.strikeoutsRecorded : 0);
    over200K.add(pitchers.where((p) => p.strikeoutsRecorded >= 200).length);
    allIPLeaders.add(byIP.isNotEmpty ? byIP.first.inningsPitched : 0);
    allTopKs.add(topK.map((p) => p.strikeoutsRecorded).toList());
    for (final p in pitchers) {
      final k9 = p.outsRecorded == 0 ? 0.0 : p.strikeoutsRecorded * 27 / p.outsRecorded;
      allK9.add(k9);
      allIPRegular.add(p.inningsPitched);
    }
  }

  print('===== サマリ =====');
  final avgKLeader = allKLeaders.reduce((a, b) => a + b) / allKLeaders.length;
  final avg200K = over200K.reduce((a, b) => a + b) / over200K.length;
  final avgIPLeader = allIPLeaders.reduce((a, b) => a + b) / allIPLeaders.length;
  print('最多奪三振 平均: ${avgKLeader.toStringAsFixed(0)} (NPB 145-195) / 各シーズン: ${allKLeaders.join(", ")}');
  print('200K+ 人数 平均: ${avg200K.toStringAsFixed(1)} (NPB ~0) / 各シーズン: ${over200K.join(", ")}');
  print('最多イニング 平均: ${avgIPLeader.toStringAsFixed(1)} (NPB 180-200) / 各シーズン: ${allIPLeaders.map((v) => v.toStringAsFixed(1)).join(", ")}');

  final avgK9 = allK9.reduce((a, b) => a + b) / allK9.length;
  final avgIP = allIPRegular.reduce((a, b) => a + b) / allIPRegular.length;
  print('規定到達 K/9 平均: ${avgK9.toStringAsFixed(2)} (NPB 6-9)');
  print('規定到達 IP 平均: ${avgIP.toStringAsFixed(1)}');
}

import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 送りバントが発動した走者状況の分布を計測する。
/// 修正後は 3 塁ランナーがいる状況（1,3塁 / 2,3塁 / 満塁）の発動が 0 になっていること。
void main() {
  const numSeasons = 3;
  final buntSituations = <String, int>{};
  int totalBunts = 0;
  int totalAtBats = 0;

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(8000 + s)).generateLeague();
    final schedule = const ScheduleGenerator().generate(teams);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      random: Random(9000 + s),
    );
    controller.advanceAll();

    for (final sg in schedule.games) {
      final result = controller.resultFor(sg.gameNumber);
      if (result == null) continue;
      for (final half in result.halfInnings) {
        for (final atBat in half.atBats) {
          totalAtBats++;
          if (!atBat.isBunt) continue;
          totalBunts++;
          final r = atBat.runnersBefore;
          final has1 = r.first != null;
          final has2 = r.second != null;
          final has3 = r.third != null;
          final key =
              '${atBat.outsBefore}OUT ${_runnersLabel(has1, has2, has3)}';
          buntSituations[key] = (buntSituations[key] ?? 0) + 1;
        }
      }
    }
  }

  print('=== 送りバント発動状況の分布 ===');
  print('総打席数: $totalAtBats');
  print('バント打席数: $totalBunts (${(totalBunts / totalAtBats * 100).toStringAsFixed(2)}%)');
  print('');
  final sorted = buntSituations.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in sorted) {
    final pct = e.value / totalBunts * 100;
    print('  ${e.key.padRight(20)} ${e.value.toString().padLeft(5)} '
        '(${pct.toStringAsFixed(1).padLeft(5)}%)');
  }

  // 3 塁ランナーありの集計
  final has3rdRunner = buntSituations.entries
      .where((e) => e.key.contains('三'))
      .fold<int>(0, (sum, e) => sum + e.value);
  print('\n  ▶ 3 塁ランナーあり: '
      '${has3rdRunner == 0 ? "0 件 ✓" : "$has3rdRunner 件 ✗"}');
}

String _runnersLabel(bool has1, bool has2, bool has3) {
  final bases = <String>[];
  if (has1) bases.add('一');
  if (has2) bases.add('二');
  if (has3) bases.add('三');
  if (bases.isEmpty) return 'ランナーなし';
  return '${bases.join(",")}塁';
}

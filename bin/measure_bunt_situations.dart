import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 送りバントが発動した走者状況の分布を計測する。
/// 修正後は 3 塁ランナーがいる状況（1,3塁 / 2,3塁 / 満塁）の発動が 0 になっていること。
void main() {
  const numSeasons = 3;
  final buntSituations = <String, int>{};
  int totalBunts = 0;
  int totalAtBats = 0;
  // 2塁単独バントが「7回以降+接戦」のみであることを検証
  final secondAloneSamples = <String>[];

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
      int awayScore = 0;
      int homeScore = 0;
      for (final half in result.halfInnings) {
        int battingScore = half.isTop ? awayScore : homeScore;
        final pitchingScore = half.isTop ? homeScore : awayScore;
        for (final atBat in half.atBats) {
          totalAtBats++;
          if (atBat.isBunt) {
            totalBunts++;
            final r = atBat.runnersBefore;
            final has1 = r.first != null;
            final has2 = r.second != null;
            final has3 = r.third != null;
            final key =
                '${atBat.outsBefore}OUT ${_runnersLabel(has1, has2, has3)}';
            buntSituations[key] = (buntSituations[key] ?? 0) + 1;
            if (has2 && !has1 && !has3) {
              final diff = battingScore - pitchingScore;
              secondAloneSamples.add(
                  '${atBat.inning}回 ${atBat.outsBefore}OUT 攻撃$battingScore-$pitchingScore守備 (差 $diff)');
            }
          }
          battingScore += atBat.runsScored;
        }
        if (half.isTop) {
          awayScore += half.runs;
        } else {
          homeScore += half.runs;
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

  // 2塁単独（1塁空き）の発動状況
  print('\n=== 2塁単独バントの発動局面 ===');
  print('総件数: ${secondAloneSamples.length}');
  int earlyOrBlowout = 0;
  for (final s in secondAloneSamples) {
    print('  $s');
    final inningMatch = RegExp(r'^(\d+)回').firstMatch(s);
    final diffMatch = RegExp(r'差 (-?\d+)').firstMatch(s);
    if (inningMatch != null && diffMatch != null) {
      final inning = int.parse(inningMatch.group(1)!);
      final diff = int.parse(diffMatch.group(1)!);
      if (inning < 7 || diff.abs() > 1) earlyOrBlowout++;
    }
  }
  print('  ▶ 「7回以降+接戦」以外の件数: '
      '${earlyOrBlowout == 0 ? "0 件 ✓" : "$earlyOrBlowout 件 ✗"}');
}

String _runnersLabel(bool has1, bool has2, bool has3) {
  final bases = <String>[];
  if (has1) bases.add('一');
  if (has2) bases.add('二');
  if (has3) bases.add('三');
  if (bases.isEmpty) return 'ランナーなし';
  return '${bases.join(",")}塁';
}

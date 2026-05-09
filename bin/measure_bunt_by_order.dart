import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 打順別の送りバント発動数を計測。
/// クリーンアップ（3,4,5番）はほぼバントしないことを確認する。
void main() {
  const numSeasons = 3;
  // 打順 (0-8) → [総打席数, バント数]
  final paByOrder = List.filled(9, 0);
  final buntsByOrder = List.filled(9, 0);
  // 投手の打席は除外して比較したい場合の集計
  final nonPitcherPaByOrder = List.filled(9, 0);
  final nonPitcherBuntsByOrder = List.filled(9, 0);

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(2000 + s)).generateLeague();
    final schedule = const ScheduleGenerator().generate(teams);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      random: Random(2500 + s),
    );
    controller.advanceAll();

    for (final sg in schedule.games) {
      final result = controller.resultFor(sg.gameNumber);
      if (result == null) continue;
      for (final half in result.halfInnings) {
        for (final atBat in half.atBats) {
          if (atBat.isIncomplete) continue;
          final order = atBat.battingOrder;
          if (order < 0 || order > 8) continue;
          paByOrder[order]++;
          if (atBat.isBunt) buntsByOrder[order]++;
          if (!atBat.batter.isPitcher) {
            nonPitcherPaByOrder[order]++;
            if (atBat.isBunt) nonPitcherBuntsByOrder[order]++;
          }
        }
      }
    }
  }

  String pct(int n, int d) =>
      d == 0 ? '-' : '${(n * 100 / d).toStringAsFixed(2)}%';

  print('===== 打順別の送りバント発動数（${numSeasons}シーズン） =====');
  print('');
  print('打順 | 総PA   | バント | 比率   | (投手除く) PA   | バント | 比率');
  print('-----+--------+--------+--------+----------------+--------+-------');
  for (int i = 0; i < 9; i++) {
    final orderName = '${i + 1}番'.padLeft(3);
    final pa = paByOrder[i].toString().padLeft(6);
    final b = buntsByOrder[i].toString().padLeft(5);
    final r = pct(buntsByOrder[i], paByOrder[i]).padLeft(6);
    final nPa = nonPitcherPaByOrder[i].toString().padLeft(6);
    final nB = nonPitcherBuntsByOrder[i].toString().padLeft(5);
    final nR = pct(nonPitcherBuntsByOrder[i], nonPitcherPaByOrder[i])
        .padLeft(6);
    print(' $orderName | $pa | $b  | $r | $nPa         | $nB  | $nR');
  }

  final totalBunts = buntsByOrder.fold<int>(0, (a, b) => a + b);
  final cleanupBunts =
      buntsByOrder[2] + buntsByOrder[3] + buntsByOrder[4]; // 3,4,5番
  print('');
  print('総バント数: $totalBunts');
  print('クリーンアップ(3,4,5番)バント: $cleanupBunts '
      '(${pct(cleanupBunts, totalBunts)})');
  print('1番バント: ${buntsByOrder[0]} (${pct(buntsByOrder[0], totalBunts)})');
  print('2番バント: ${buntsByOrder[1]} (${pct(buntsByOrder[1], totalBunts)})');
  print('6〜9番バント: '
      '${buntsByOrder[5] + buntsByOrder[6] + buntsByOrder[7] + buntsByOrder[8]} '
      '(${pct(buntsByOrder[5] + buntsByOrder[6] + buntsByOrder[7] + buntsByOrder[8], totalBunts)})');
}

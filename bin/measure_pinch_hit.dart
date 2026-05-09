import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 代打起用の打順分布と、投手代打の発生数を計測する。
///
/// 期待値:
///   - クリーンアップ(3,4,5番)への代打: ほぼゼロ
///   - 投手(通常9番)への代打: 試合終盤の劣勢時に多発
///   - 1番への代打: 控えめ
void main() {
  const numSeasons = 3;

  final phByOrder = List.filled(9, 0);
  int phForPitcher = 0;
  int phForNonPitcher = 0;
  int totalPh = 0;
  int totalGames = 0;

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(3000 + s)).generateLeague();
    final schedule = const ScheduleGenerator().generate(teams);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      random: Random(3500 + s),
    );
    controller.advanceAll();

    for (final sg in schedule.games) {
      final result = controller.resultFor(sg.gameNumber);
      if (result == null) continue;
      totalGames++;
      for (final half in result.halfInnings) {
        for (final fc in half.fielderChanges) {
          if (fc.type != FielderChangeType.pinchHit) continue;
          totalPh++;
          final order = fc.battingOrder;
          if (order >= 0 && order < 9) phByOrder[order]++;
          if (fc.outgoing.isPitcher) {
            phForPitcher++;
          } else {
            phForNonPitcher++;
          }
        }
      }
    }
  }

  String pct(int n, int d) =>
      d == 0 ? '-' : '${(n * 100 / d).toStringAsFixed(2)}%';

  print('===== 代打起用の打順分布（${numSeasons}シーズン、$totalGames 試合） =====');
  print('総代打数: $totalPh');
  print('  投手への代打: $phForPitcher (${pct(phForPitcher, totalPh)})');
  print('  野手への代打: $phForNonPitcher (${pct(phForNonPitcher, totalPh)})');
  print('');
  print('打順 | 件数  | 比率');
  print('-----+-------+--------');
  for (int i = 0; i < 9; i++) {
    final orderName = '${i + 1}番'.padLeft(3);
    final count = phByOrder[i].toString().padLeft(5);
    final ratio = pct(phByOrder[i], totalPh).padLeft(7);
    print(' $orderName | $count | $ratio');
  }

  print('');
  final cleanup = phByOrder[2] + phByOrder[3] + phByOrder[4];
  print('クリーンアップ(3,4,5番)への代打: $cleanup '
      '(${pct(cleanup, totalPh)})');
}

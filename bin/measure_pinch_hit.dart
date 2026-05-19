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
  int phForCloser = 0;
  int phForReliefNonCloser = 0;
  int phForStarter = 0;
  int phForStarterLeading = 0;
  int phForStarterTiedOrLosing = 0;
  int phForReliefLeading = 0;
  int phForReliefTiedOrLosing = 0;
  int phForPitcherLeading = 0;
  int phForPitcherTiedOrLosing = 0;
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
      int awayScore = 0;
      int homeScore = 0;
      for (final half in result.halfInnings) {
        final battingScore = half.isTop ? awayScore : homeScore;
        final pitchingScore = half.isTop ? homeScore : awayScore;
        for (final fc in half.fielderChanges) {
          if (fc.type != FielderChangeType.pinchHit) continue;
          totalPh++;
          final order = fc.battingOrder;
          if (order >= 0 && order < 9) phByOrder[order]++;
          if (fc.outgoing.isPitcher) {
            phForPitcher++;
            final diff = battingScore - pitchingScore;
            final leading = diff > 0;
            if (fc.outgoing.pitcherRole == PitcherRole.closer) {
              phForCloser++;
            } else if (fc.outgoing.pitcherRole != null) {
              phForReliefNonCloser++;
              if (leading) {
                phForReliefLeading++;
              } else {
                phForReliefTiedOrLosing++;
              }
            } else {
              phForStarter++;
              if (leading) {
                phForStarterLeading++;
              } else {
                phForStarterTiedOrLosing++;
              }
            }
            if (leading) {
              phForPitcherLeading++;
            } else {
              phForPitcherTiedOrLosing++;
            }
          } else {
            phForNonPitcher++;
          }
        }
        if (half.isTop) {
          awayScore += half.runs;
        } else {
          homeScore += half.runs;
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

  print('');
  print('===== 投手への代打の内訳 =====');
  print('  リリーフ（非クローザー）: $phForReliefNonCloser '
      '(${pct(phForReliefNonCloser, phForPitcher)})');
  print('    リード時: $phForReliefLeading / 同点・負け: $phForReliefTiedOrLosing');
  print('  クローザー: $phForCloser (${pct(phForCloser, phForPitcher)})');
  print('  先発（pitcherRole=null）: $phForStarter '
      '(${pct(phForStarter, phForPitcher)})');
  print('    リード時: $phForStarterLeading / 同点・負け: $phForStarterTiedOrLosing');
  print('');
  print('  攻撃側リード時 合計: $phForPitcherLeading '
      '(${pct(phForPitcherLeading, phForPitcher)})');
  print('  攻撃側 同点 or ビハインド時 合計: $phForPitcherTiedOrLosing '
      '(${pct(phForPitcherTiedOrLosing, phForPitcher)})');
}

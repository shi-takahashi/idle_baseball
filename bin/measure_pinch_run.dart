import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 代走起用の塁別分布を計測する。
///
/// 期待値:
///   - 1塁、2塁にランナーがいる時の代走: **2塁側のみ**（1塁への代走は 0 件）
///     ＝「先行ランナーを残して後続ランナーへ代走」の不自然な采配を排除
void main() {
  const numSeasons = 3;

  int totalPr = 0;
  int prFirst = 0;
  int prSecond = 0;
  int prThird = 0;
  int prFirstWhileSecondOccupied = 0;
  int totalGames = 0;

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(6000 + s)).generateLeague();
    final schedule = const ScheduleGenerator().generate(teams);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      random: Random(6500 + s),
    );
    controller.advanceAll();

    for (final sg in schedule.games) {
      final result = controller.resultFor(sg.gameNumber);
      if (result == null) continue;
      totalGames++;
      for (final half in result.halfInnings) {
        // 打席ごとに「打席後のランナー状況」を追跡し、代走発動時の塁状況を判定
        for (int i = 0; i < half.atBats.length; i++) {
          final atBat = half.atBats[i];
          // 代走は打席終了後に発動するので、この打席の後の代走を見る
          final relevantPrs = half.fielderChanges
              .where((fc) =>
                  fc.type == FielderChangeType.pinchRun &&
                  fc.atBatIndex == i)
              .toList();
          if (relevantPrs.isEmpty) continue;

          // 打席後のランナー状況を再構築（簡易: scoringRunners を除外した
          // 残塁ランナーの推定は複雑なので、ここでは fielderChanges 側の base を直接見る）
          for (final pr in relevantPrs) {
            totalPr++;
            // PinchRun の base は fielderChanges ではなく、ロジック側で
            // 別途記録される（_applyPinchRunDecisions の base）。
            // FielderChangeEvent には base が無いので、別の方法で判定する。
            // 代わりに「打席後ランナー状況」を構築して判定する。
            final runnersAfter = _computeRunnersAfter(half.atBats, i);
            // 代走者がどの塁にいるか
            final at1 = runnersAfter.first?.id == pr.incoming.id;
            final at2 = runnersAfter.second?.id == pr.incoming.id;
            final at3 = runnersAfter.third?.id == pr.incoming.id;
            if (at1) {
              prFirst++;
              // 2塁にも別のランナーがいた場合
              if (runnersAfter.second != null) {
                prFirstWhileSecondOccupied++;
              }
            } else if (at2) {
              prSecond++;
            } else if (at3) {
              prThird++;
            }
          }
        }
      }
    }
  }

  String pct(int n, int d) =>
      d == 0 ? '-' : '${(n * 100 / d).toStringAsFixed(2)}%';

  print('===== 代走起用の塁別分布（${numSeasons}シーズン、$totalGames 試合） =====');
  print('総代走数: $totalPr');
  print('  1塁への代走: $prFirst (${pct(prFirst, totalPr)})');
  print('  2塁への代走: $prSecond (${pct(prSecond, totalPr)})');
  print('  3塁への代走: $prThird (${pct(prThird, totalPr)})');
  print('');
  print('▶ 1塁代走のうち 2塁にもランナーがいた件数: '
      '${prFirstWhileSecondOccupied == 0 ? "0 件 ✓" : "$prFirstWhileSecondOccupied 件 ✗"}');
}

/// 打席 i の打席後ランナー状況を、その打席の `runnersBefore` と、
/// 直後の打席（i+1）の `runnersBefore` を比較して構築する。
/// イニング最終打席の場合は `runnersBefore` の変化が読めないので簡易的に
/// `runnersBefore + 打球結果` で推定するのではなく、直後の打席の runnersBefore を使う。
BaseRunners _computeRunnersAfter(List<AtBatResult> atBats, int i) {
  if (i + 1 < atBats.length) {
    return atBats[i + 1].runnersBefore;
  }
  // イニング最終打席（後続が無い）の場合は近似不能だが、
  // 代走発動シーンは通常イニング途中なので頻度は低い
  return atBats[i].runnersBefore;
}

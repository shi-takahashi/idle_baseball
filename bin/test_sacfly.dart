// 犠飛 + タッチアップ物理整合性 + 個人得点集計の検証。
//
// 確認項目:
// 1. タッチアップで「2塁走者と3塁走者の両方がアウト」になることがない
//    （tagUps の中で 2 つ以上の failure が同じ AtBat に含まれないこと）
// 2. AtBatResultType.sacrificeFly が発生していること
// 3. 犠飛が打数に含まれていない（plateAppearances - walks - sacrificeBunts -
//    sacFlies == atBats が成り立つ）
// 4. 犠飛は打点付き（rbiCount >= 1）であること
// 5. runs（個人得点）の合計が、リーグ全体の runsAllowed 合計と一致すること
//
// 実行: dart run bin/test_sacfly.dart
import 'dart:math';

import 'package:idle_baseball/engine/engine.dart';

void main() {
  // 150 試合シーズンでサンプル数を稼ぐ。Random 種は固定で再現性を確保。
  final c = SeasonController.newSeason(
    random: Random(7),
    gamesPerTeam: 150,
  );
  c.advanceAll();

  // 全試合の AtBat を走査
  int totalAtBats = 0;
  int incompletePAs = 0;
  int sacFlyCount = 0;
  int flyOutCount = 0;
  int sacFlyWithRbi = 0;
  int sacFlyWithoutRbi = 0;
  int doubleTagUpFailureCount = 0; // 2 つ以上の失敗タッチアップを含む打席数（NG ケース）
  int totalScoringRunnerEntries = 0;
  int sacFlySingleScorer = 0;
  int sacFlyMultiScorer = 0;

  // schedule から GameResult を取り出して走査
  for (final scheduled in c.schedule.games) {
    final gameResult = c.resultFor(scheduled.gameNumber);
    if (gameResult == null) continue;
    for (final half in gameResult.halfInnings) {
      for (final ab in half.atBats) {
        totalAtBats++;
        if (ab.isIncomplete) {
          incompletePAs++;
          continue;
        }
        if (ab.result == AtBatResultType.flyOut) flyOutCount++;
        if (ab.result == AtBatResultType.sacrificeFly) {
          sacFlyCount++;
          if (ab.rbiCount > 0) {
            sacFlyWithRbi++;
          } else {
            sacFlyWithoutRbi++;
          }
          if (ab.scoringRunners.length == 1) sacFlySingleScorer++;
          if (ab.scoringRunners.length >= 2) sacFlyMultiScorer++;
        }
        // タッチアップ失敗が 2 つ以上同じ打席にある？
        if (ab.tagUps != null) {
          final fails = ab.tagUps!.where((t) => !t.success).length;
          if (fails >= 2) doubleTagUpFailureCount++;
        }
        totalScoringRunnerEntries += ab.scoringRunners.length;
      }
    }
  }

  print('--- サンプル ---');
  print('完了打席数: $totalAtBats (うち未完了: $incompletePAs)');
  print('フライアウト: $flyOutCount');
  print('犠飛 (sacrificeFly): $sacFlyCount');
  print('  打点あり: $sacFlyWithRbi / 打点 0: $sacFlyWithoutRbi');
  print('  得点者 1 人: $sacFlySingleScorer / 2 人以上: $sacFlyMultiScorer');
  print('タッチアップで 2 つ以上の失敗を含む打席: $doubleTagUpFailureCount');

  // 個別チェック: 統計の整合性
  int sumPA = 0;
  int sumAB = 0;
  int sumWalks = 0;
  int sumSacFly = 0;
  int sumSacBunt = 0;
  int sumRuns = 0;
  for (final s in c.batterStats.values) {
    sumPA += s.plateAppearances;
    sumAB += s.atBats;
    sumWalks += s.walks;
    sumSacFly += s.sacFlies;
    sumSacBunt += s.sacrificeBunts;
    sumRuns += s.runs;
  }
  final paMinusExclusions = sumPA - sumWalks - sumSacFly - sumSacBunt;
  print('\n--- 集計整合性 ---');
  print('合計打席: $sumPA');
  print('合計打数: $sumAB');
  print('合計四球: $sumWalks');
  print('合計犠飛: $sumSacFly');
  print('合計犠打: $sumSacBunt');
  print('打席 - 四球 - 犠飛 - 犠打 = $paMinusExclusions (期待: $sumAB)');

  // 個人得点合計 vs 投手失点合計
  int sumRunsAllowed = 0;
  for (final p in c.pitcherStats.values) {
    sumRunsAllowed += p.runsAllowed;
  }
  print('\n--- 得点 vs 失点 ---');
  print('合計得点 (個人 runs): $sumRuns');
  print('合計失点 (投手 runsAllowed): $sumRunsAllowed');

  // 結果判定
  final ok1 = doubleTagUpFailureCount == 0;
  final ok2 = sacFlyCount > 0;
  final ok3 = paMinusExclusions == sumAB;
  final ok4 = sacFlyWithoutRbi == 0; // 犠飛は必ず打点あり
  final ok5 = sumRuns == sumRunsAllowed;

  print('\n========== 結果 ==========');
  print('1. タッチアップ二重失敗が起きない:        ${ok1 ? "OK" : "NG ($doubleTagUpFailureCount 件)"}');
  print('2. 犠飛が発生している:                   ${ok2 ? "OK" : "NG"}');
  print('3. 打席 - 除外 = 打数 が成立:            ${ok3 ? "OK" : "NG (差: ${paMinusExclusions - sumAB})"}');
  print('4. 犠飛は必ず打点あり:                   ${ok4 ? "OK" : "NG ($sacFlyWithoutRbi 件)"}');
  print('5. 個人得点合計 == 投手失点合計:         ${ok5 ? "OK" : "NG (差: ${sumRuns - sumRunsAllowed})"}');
  final allOk = ok1 && ok2 && ok3 && ok4 && ok5;
  print('TOTAL: ${allOk ? "PASS" : "FAIL"}');
}

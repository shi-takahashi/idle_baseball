import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 送りバントの動作確認スクリプト
///
/// 30試合シーズン × 5 seed を回して、構造化バント解決の結果分布と
/// 守備位置別の傾向、スリーバント失敗、球数分布などを確認する。
///
/// 「成功」の定義: 走者を進められたか = sacrificeBunt + infieldHit
/// （sacrificeBunt = 打者OUT・走者進塁、infieldHit = 打者出塁・走者進塁）
void main() {
  // 集計用カウンタ
  int total = 0;
  int sacBunt = 0;
  int infieldHit = 0;
  int fc = 0;
  int dp = 0;
  int popOut = 0;
  int strikeout = 0;
  int walk = 0;
  // ヒッティング切替で出る打席結果
  int hitSingle = 0;
  int hitDouble = 0;
  int hitTriple = 0;
  int hitHR = 0;
  int hitGroundOut = 0;
  int hitFlyOut = 0;
  int hitLineOut = 0;

  // 球数分布 (バント打席の総球数別)
  final pitchCountDist = <int, int>{};
  // スリーバント失敗（2ストライク後のファール三振）数
  // 判定: 結果が strikeout かつ 最後の球が foul
  int threeBuntFails = 0;

  // 守備位置別: バントゴロが飛んだ方向の分布
  final byPosition = <FieldPosition, int>{};
  // 守備位置別: 1塁送球成功率（送りバント / (送り + バント安打)）
  final firstOutByPos = <FieldPosition, int>{};
  final firstAttemptsByPos = <FieldPosition, int>{};
  // 守備位置別: 先頭走者狙いの発生率
  final leadAttemptsByPos = <FieldPosition, int>{};

  // 投手 vs 野手の犠打成功率
  int pitcherBunts = 0;
  int pitcherSacBunts = 0;
  int nonPitcherBunts = 0;
  int nonPitcherSacBunts = 0;

  for (final seed in [1, 7, 42, 100, 2024]) {
    final c = SeasonController.newSeason(random: Random(seed));
    c.advanceAll();

    for (int g = 1; g <= c.totalDays * 3; g++) {
      final result = c.resultFor(g);
      if (result == null) continue;
      for (final half in result.halfInnings) {
        for (final ab in half.atBats) {
          if (ab.isIncomplete) continue;
          if (!ab.isBunt) continue;

          total++;
          pitchCountDist[ab.pitches.length] =
              (pitchCountDist[ab.pitches.length] ?? 0) + 1;
          switch (ab.result) {
            case AtBatResultType.sacrificeBunt:
              sacBunt++;
              break;
            case AtBatResultType.infieldHit:
              infieldHit++;
              break;
            case AtBatResultType.fieldersChoice:
              fc++;
              break;
            case AtBatResultType.doublePlay:
              dp++;
              break;
            case AtBatResultType.flyOut:
              popOut++;
              break;
            case AtBatResultType.strikeout:
              strikeout++;
              // スリーバント失敗判定: 最後の球がファール
              if (ab.pitches.isNotEmpty &&
                  ab.pitches.last.type == PitchResultType.foul) {
                threeBuntFails++;
              }
              break;
            case AtBatResultType.walk:
              walk++;
              break;
            case AtBatResultType.single:
              hitSingle++;
              break;
            case AtBatResultType.double_:
              hitDouble++;
              break;
            case AtBatResultType.triple:
              hitTriple++;
              break;
            case AtBatResultType.homeRun:
              hitHR++;
              break;
            case AtBatResultType.groundOut:
              hitGroundOut++;
              break;
            case AtBatResultType.lineOut:
              hitLineOut++;
              break;
            case AtBatResultType.sacrificeFly:
              // バントから sacrificeFly はあり得ない想定だが念のため
              break;
            case AtBatResultType.reachedOnError:
              break;
          }
          if (ab.batter.isPitcher) {
            pitcherBunts++;
            if (ab.result == AtBatResultType.sacrificeBunt) {
              pitcherSacBunts++;
            }
          } else {
            nonPitcherBunts++;
            if (ab.result == AtBatResultType.sacrificeBunt) {
              nonPitcherSacBunts++;
            }
          }

          // 方向 / 守備位置の集計
          if (ab.fieldPosition != null) {
            byPosition[ab.fieldPosition!] =
                (byPosition[ab.fieldPosition!] ?? 0) + 1;
            if (ab.result == AtBatResultType.sacrificeBunt ||
                ab.result == AtBatResultType.infieldHit) {
              firstAttemptsByPos[ab.fieldPosition!] =
                  (firstAttemptsByPos[ab.fieldPosition!] ?? 0) + 1;
              if (ab.result == AtBatResultType.sacrificeBunt) {
                firstOutByPos[ab.fieldPosition!] =
                    (firstOutByPos[ab.fieldPosition!] ?? 0) + 1;
              }
            }
            if (ab.result == AtBatResultType.fieldersChoice ||
                ab.result == AtBatResultType.doublePlay) {
              leadAttemptsByPos[ab.fieldPosition!] =
                  (leadAttemptsByPos[ab.fieldPosition!] ?? 0) + 1;
            }
          }
        }
      }
    }
  }

  String pct(int n, int d) =>
      d == 0 ? '-' : '${(n * 100 / d).toStringAsFixed(1)}%';

  // 「進塁成功」の定義
  final advanceSuccess = sacBunt + infieldHit;
  final advanceFail = fc + dp + popOut + strikeout +
      hitGroundOut + hitFlyOut + hitLineOut;

  print('========== バント結果分布（30試合シーズン × 5 seed） ==========');
  print('合計バント試行数: $total');
  print('');
  print('--- 進塁成功率（成功 = 走者進塁 = sacrificeBunt + infieldHit） ---');
  print('  進塁成功: $advanceSuccess   ${pct(advanceSuccess, total)}');
  print('  進塁失敗: $advanceFail   ${pct(advanceFail, total)}');
  print('  四球（中立）: $walk   ${pct(walk, total)}');
  print('  ヒッティング切替→安打: ${hitSingle + hitDouble + hitTriple + hitHR}');
  print('');
  print('--- バント結果別 ---');
  print('  送りバント成功:    $sacBunt   ${pct(sacBunt, total)}');
  print('  バント安打:        $infieldHit   ${pct(infieldHit, total)}');
  print('  野選 (FC):         $fc   ${pct(fc, total)}');
  print('  バント併殺:        $dp   ${pct(dp, total)}');
  print('  ポップアウト:      $popOut   ${pct(popOut, total)}');
  print('  三振:              $strikeout   ${pct(strikeout, total)}');
  print('    うちスリーバント失敗（2S からのファール）: $threeBuntFails');
  print('  四球:              $walk   ${pct(walk, total)}');
  print('');
  print('--- ヒッティング切替後の結果（バント途中で止めて打ちに行ったケース） ---');
  print('  単打:    $hitSingle');
  print('  二塁打:  $hitDouble');
  print('  三塁打:  $hitTriple');
  print('  本塁打:  $hitHR');
  print('  ゴロ:    $hitGroundOut');
  print('  ライナー: $hitLineOut');
  print('  切替合計: ${hitSingle + hitDouble + hitTriple + hitHR + hitGroundOut + hitLineOut}');

  print('');
  print('--- 打者別 ---');
  print('  投手のバント:    $pitcherBunts   送り成功率 ${pct(pitcherSacBunts, pitcherBunts)}');
  print('  野手のバント:    $nonPitcherBunts   送り成功率 ${pct(nonPitcherSacBunts, nonPitcherBunts)}');

  print('');
  print('--- 球数分布（バント打席が決着するまで） ---');
  final sortedCounts = pitchCountDist.keys.toList()..sort();
  for (final n in sortedCounts) {
    final cnt = pitchCountDist[n]!;
    print('  $n 球: $cnt   ${pct(cnt, total)}');
  }

  print('');
  print('--- 打球方向の分布 ---');
  for (final pos in [
    FieldPosition.pitcher,
    FieldPosition.third,
    FieldPosition.first,
    FieldPosition.catcher,
  ]) {
    final n = byPosition[pos] ?? 0;
    print('  ${pos.shortName}前: $n   ${pct(n, total)}');
  }

  print('');
  print('--- 守備位置別の 1塁送球成功率（送りバント / (送り + バント安打)） ---');
  for (final pos in [
    FieldPosition.pitcher,
    FieldPosition.third,
    FieldPosition.first,
    FieldPosition.catcher,
  ]) {
    final out = firstOutByPos[pos] ?? 0;
    final tot = firstAttemptsByPos[pos] ?? 0;
    print('  ${pos.shortName}前: ${pct(out, tot)}  ($out / $tot)');
  }

  print('');
  print('--- 守備位置別の 先頭走者狙い 発生率 ---');
  for (final pos in [
    FieldPosition.pitcher,
    FieldPosition.third,
    FieldPosition.first,
    FieldPosition.catcher,
  ]) {
    final lead = leadAttemptsByPos[pos] ?? 0;
    final all = byPosition[pos] ?? 0;
    print('  ${pos.shortName}前: ${pct(lead, all)}  ($lead / $all)');
  }

  // 統計整合性チェック
  final c = SeasonController.newSeason(random: Random(2024));
  c.advanceAll();
  int statsBunts = 0;
  int abIsBuntSacs = 0;
  for (final s in c.batterStats.values) {
    statsBunts += s.sacrificeBunts;
  }
  for (int g = 1; g <= c.totalDays * 3; g++) {
    final result = c.resultFor(g);
    if (result == null) continue;
    for (final half in result.halfInnings) {
      for (final ab in half.atBats) {
        if (!ab.isIncomplete &&
            ab.isBunt &&
            ab.result == AtBatResultType.sacrificeBunt) {
          abIsBuntSacs++;
        }
      }
    }
  }
  print('');
  print('--- 統計整合性 (seed=2024) ---');
  print('  AtBat.isBunt + sacrificeBunt: $abIsBuntSacs');
  print('  BatterSeasonStats.sacrificeBunts 合計: $statsBunts');
  print('  整合: ${abIsBuntSacs == statsBunts ? "OK" : "NG"}');
}

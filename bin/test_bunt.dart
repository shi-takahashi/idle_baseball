import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 送りバントの動作確認スクリプト
///
/// 90試合シーズンを回して、結果タイプ別の発生数と
/// 投手の犠打・成功率を確認する。
void main() {
  for (final seed in [1, 7, 42, 100, 2024]) {
    final c = SeasonController.newSeason(random: Random(seed));
    c.advanceAll();

    int sacBunt = 0;
    int fc = 0;
    int buntDP = 0;
    int buntStrikeout = 0; // 推測困難（区別なし）
    int totalBuntAttempts = 0;

    int pitcherSacBunts = 0;
    int pitcherBuntAttempts = 0;
    int nonPitcherSacBunts = 0;

    // 各試合の打席を走査
    for (int g = 1; g <= c.totalDays * 3; g++) {
      final result = c.resultFor(g);
      if (result == null) continue;
      for (final half in result.halfInnings) {
        for (final ab in half.atBats) {
          if (ab.isIncomplete) continue;
          // 簡易判定: 打球種類が groundBall でかつ fieldPosition がバント位置(投手/捕手) で
          // かつ投球数が少ないものをバント疑いとして数えるのは難しいので、明確な結果のみ集計
          if (ab.result == AtBatResultType.sacrificeBunt) {
            sacBunt++;
            totalBuntAttempts++;
            if (ab.batter.isPitcher) {
              pitcherSacBunts++;
              pitcherBuntAttempts++;
            } else {
              nonPitcherSacBunts++;
            }
          } else if (ab.result == AtBatResultType.fieldersChoice) {
            fc++;
            totalBuntAttempts++;
            if (ab.batter.isPitcher) pitcherBuntAttempts++;
          }
          // 注: doublePlay/strikeout/flyOut/infieldHit/walk はバント以外でも起こるため
          //     正確なバント由来カウントは現状の AtBatResult からは判別不可
        }
      }
    }

    print(
        'seed=$seed : 送りバント=$sacBunt  野選=$fc  (確実なバント結果計=$totalBuntAttempts)');
    print(
        '          投手の送りバント=$pitcherSacBunts (バント試行 $pitcherBuntAttempts)  野手の送りバント=$nonPitcherSacBunts');

    // BatterSeasonStats の sacrificeBunts もチェック
    int totalSacBuntsInStats = 0;
    int topPitcherSacBunts = 0;
    String? topPitcherName;
    for (final s in c.batterStats.values) {
      totalSacBuntsInStats += s.sacrificeBunts;
      if (s.player.isPitcher && s.sacrificeBunts > topPitcherSacBunts) {
        topPitcherSacBunts = s.sacrificeBunts;
        topPitcherName = s.player.name;
      }
    }
    print(
        '          stats集計の犠打計=$totalSacBuntsInStats (敬語の整合: ${totalSacBuntsInStats == sacBunt ? "OK" : "NG!"})');
    if (topPitcherName != null) {
      print('          投手最多犠打: $topPitcherName ($topPitcherSacBunts)');
    }
    print('');
  }
}

import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 外国人 vs 日本人の能力分布比較 + 本塁打ランキング上位の構成。
///
/// ユーザー報告「外国人が本塁打ランキングにほとんど載らない」を裏付けるための計測。
/// 仮説: 外国人 power mean 5.5 が、ポジションオフセット込みの日本人一塁手・三塁手・
/// 外野強打型 (power 6.0〜6.5) より低いので、長距離砲ランキングで日本人優位になる。
void main() {
  // 1. S1 開幕時の power 分布を国籍別に集計（10リーグぶん）
  final jpDist = {for (int v = 1; v <= 10; v++) v: 0};
  final fgDist = {for (int v = 1; v <= 10; v++) v: 0};
  // ポジション別の日本人 power 分布も
  final jpByPos = <DefensePosition, Map<int, int>>{
    for (final pos in DefensePosition.values)
      pos: {for (int v = 1; v <= 10; v++) v: 0},
  };

  const numLeagues = 10;
  for (int seed = 0; seed < numLeagues; seed++) {
    final c = SeasonController.newSeason(random: Random(seed));
    for (final t in c.teams) {
      final all = <Player>[...t.players, ...t.bench];
      final seen = <String>{};
      for (final p in all) {
        if (!seen.add(p.id)) continue;
        if (p.isPitcher) continue;
        if (p.power == null) continue;
        if (p.isForeign) {
          fgDist[p.power!] = fgDist[p.power!]! + 1;
        } else {
          jpDist[p.power!] = jpDist[p.power!]! + 1;
          // 主守備位置を取得
          final pos = p.fielding?.entries
                  .firstWhere(
                      (e) => e.value > 0,
                      orElse: () => MapEntry(DefensePosition.outfield, 0))
                  .key ??
              DefensePosition.outfield;
          jpByPos[pos]![p.power!] = jpByPos[pos]![p.power!]! + 1;
        }
      }
    }
  }

  void printDist(String label, Map<int, int> dist) {
    final total = dist.values.fold<int>(0, (a, b) => a + b);
    final mean = total == 0
        ? 0.0
        : dist.entries.fold<double>(
                0, (sum, e) => sum + e.key * e.value) /
            total;
    print('$label (n=$total, mean=${mean.toStringAsFixed(2)})');
    for (int v = 1; v <= 10; v++) {
      final n = dist[v]!;
      final p = total == 0 ? 0.0 : (n / total * 100);
      final bar = '#' * (n * 40 ~/ (total == 0 ? 1 : total));
      print('  $v: ${p.toStringAsFixed(2).padLeft(5)}%  $bar');
    }
  }

  print('=== S1 開幕時 power 分布の比較 ($numLeagues リーグ) ===\n');
  printDist('日本人野手', jpDist);
  print('');
  printDist('外国人野手', fgDist);
  print('');
  print('--- 日本人 ポジション別 power 平均 ---');
  for (final pos in DefensePosition.values) {
    final d = jpByPos[pos]!;
    final total = d.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) continue;
    final mean = d.entries.fold<double>(
            0, (sum, e) => sum + e.key * e.value) /
        total;
    print('  $pos: n=$total mean=${mean.toStringAsFixed(2)}');
  }

  // 2. 3シーズン回して、本塁打ランキング上位 10 人の外国人比率を計測
  print('\n=== 本塁打ランキング上位 10 の構成 ($numLeagues リーグ × 3シーズン) ===');
  int totalTop10 = 0;
  int foreignInTop10 = 0;
  int totalTop20 = 0;
  int foreignInTop20 = 0;
  final hrLeader = <bool>[]; // 各シーズンの本塁打王が外国人かどうか

  for (int seed = 0; seed < numLeagues; seed++) {
    final c = SeasonController.newSeason(random: Random(seed));
    for (int season = 0; season < 3; season++) {
      // 150試合シーズンで計測（HRの絶対数を十分にする）
      if (season == 0) {
        // newSeason のデフォルトでは 30試合。150 に変更。
        // SeasonController に setter があるか確認 → なければ
        // commitOffseason の引数で次年 gamesPerTeam を変えられる
      }
      c.advanceAll();
      final byPlayer = <String, int>{};
      final isForeign = <String, bool>{};
      for (final entry in c.batterStats.entries) {
        byPlayer[entry.key] = entry.value.homeRuns;
        // Player を team から探す
        for (final t in c.teams) {
          for (final p in [...t.players, ...t.bench]) {
            if (p.id == entry.key) {
              isForeign[entry.key] = p.isForeign;
              break;
            }
          }
        }
      }
      final ranked = byPlayer.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final top10 = ranked.take(10);
      final top20 = ranked.take(20);
      for (final e in top10) {
        totalTop10++;
        if (isForeign[e.key] == true) foreignInTop10++;
      }
      for (final e in top20) {
        totalTop20++;
        if (isForeign[e.key] == true) foreignInTop20++;
      }
      // 本塁打王
      if (ranked.isNotEmpty) {
        hrLeader.add(isForeign[ranked.first.key] == true);
      }
      // 次シーズンへ
      c.commitOffseason();
    }
  }

  print('  上位10: 外国人 $foreignInTop10 / $totalTop10 '
      '(${(foreignInTop10 / totalTop10 * 100).toStringAsFixed(1)}%)');
  print('  上位20: 外国人 $foreignInTop20 / $totalTop20 '
      '(${(foreignInTop20 / totalTop20 * 100).toStringAsFixed(1)}%)');
  final leaderForeign = hrLeader.where((b) => b).length;
  print('  本塁打王: 外国人 $leaderForeign / ${hrLeader.length} '
      '(${(leaderForeign / hrLeader.length * 100).toStringAsFixed(1)}%)');
  print('  期待値: リーグの外国人野手は 12 / 156 = 7.7%（捕手なしのため野手枠の比率）');
  print('  ※ 外国人は power mean 5.5 で「長距離砲」設計のため、HR ランキング比率は');
  print('     人口比 7.7% より高いはずだが、現状どうなっているか');
}

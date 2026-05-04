import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// リーグ生成を 200 回繰り返して、スタメン野手の長打力 (power) の
/// 分布を計測する。
///
/// スタメン野手の power はデフォルト分布 (mean=5, sd=デフォルト) で生成されるため、
/// `RandomUtils.normalInt` のデフォルト sd 変更の影響を素直に確認できる。
void main() {
  final counts = <int, int>{for (int v = 1; v <= 10; v++) v: 0};
  int total = 0;

  for (int i = 0; i < 200; i++) {
    final teams = TeamGenerator(random: Random(1000 + i)).generateLeague();
    for (final t in teams) {
      // スタメンの先頭 8 名のみ（投手 = players[8] は別分布なので除外）。
      // ただし守備位置を確認して投手を除外する。
      for (final p in t.players.take(8)) {
        if (p.isPitcher) continue;
        if (p.power == null) continue;
        counts[p.power!] = (counts[p.power!] ?? 0) + 1;
        total++;
      }
    }
  }

  print('スタメン野手の長打力 (power) 分布 (n=$total)');
  for (int v = 1; v <= 10; v++) {
    final n = counts[v]!;
    final pct = (n / total * 100).toStringAsFixed(2);
    final bar = '#' * (n * 60 ~/ total);
    print('  $v : $pct%  $bar');
  }
  // mean / sd
  num sum = 0;
  num sumSq = 0;
  for (int v = 1; v <= 10; v++) {
    sum += v * counts[v]!;
    sumSq += v * v * counts[v]!;
  }
  final mean = sum / total;
  final variance = sumSq / total - mean * mean;
  final sd = sqrt(variance);
  print('  mean = ${mean.toStringAsFixed(2)}, sd = ${sd.toStringAsFixed(2)}');
}

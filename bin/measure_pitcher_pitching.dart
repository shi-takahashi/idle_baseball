import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 投手の投球能力の分布を計測する。
/// - fastball / control / slider / curve / splitter / changeup: 1〜10
/// - averageSpeed (km/h): 130〜160
/// - stamina: 1〜10
void main() {
  final intCats = [
    'fastball',
    'control',
    'slider',
    'curve',
    'splitter',
    'changeup',
    'stamina',
  ];
  final intCountsStarter = <String, Map<int, int>>{
    for (final c in intCats) c: {for (int v = 1; v <= 10; v++) v: 0},
  };
  final intCountsRelief = <String, Map<int, int>>{
    for (final c in intCats) c: {for (int v = 1; v <= 10; v++) v: 0},
  };
  final speedBucketsStarter = <int, int>{};
  final speedBucketsRelief = <int, int>{};

  int? get(int? v) => v;

  for (int i = 0; i < 200; i++) {
    final teams = TeamGenerator(random: Random(3000 + i)).generateLeague();
    for (final t in teams) {
      void record(Player p, bool isStarter) {
        final intC = isStarter ? intCountsStarter : intCountsRelief;
        final speedB = isStarter ? speedBucketsStarter : speedBucketsRelief;

        final fastball = get(p.fastball);
        final control = get(p.control);
        final slider = get(p.slider);
        final curve = get(p.curve);
        final splitter = get(p.splitter);
        final changeup = get(p.changeup);
        final stamina = get(p.stamina);

        if (fastball != null) intC['fastball']![fastball] = intC['fastball']![fastball]! + 1;
        if (control != null) intC['control']![control] = intC['control']![control]! + 1;
        if (slider != null) intC['slider']![slider] = intC['slider']![slider]! + 1;
        if (curve != null) intC['curve']![curve] = intC['curve']![curve]! + 1;
        if (splitter != null) intC['splitter']![splitter] = intC['splitter']![splitter]! + 1;
        if (changeup != null) intC['changeup']![changeup] = intC['changeup']![changeup]! + 1;
        if (stamina != null) intC['stamina']![stamina] = intC['stamina']![stamina]! + 1;

        if (p.averageSpeed != null) {
          speedB[p.averageSpeed!] = (speedB[p.averageSpeed!] ?? 0) + 1;
        }
      }

      for (final p in t.startingRotation) {
        record(p, true);
      }
      for (final p in t.bullpen) {
        record(p, false);
      }
    }
  }

  void printIntDist(String label, Map<String, Map<int, int>> data) {
    print('=== $label ===\n');
    for (final cat in intCats) {
      final m = data[cat]!;
      num sum = 0;
      int n = 0;
      for (int v = 1; v <= 10; v++) {
        sum += v * m[v]!;
        n += m[v]!;
      }
      if (n == 0) {
        print('$cat: (該当なし)\n');
        continue;
      }
      final mean = sum / n;
      print('$cat (mean=${mean.toStringAsFixed(2)}, n=$n):');
      for (int v = 1; v <= 10; v++) {
        final c = m[v]!;
        if (c == 0) continue;
        final pct = (c / n * 100).toStringAsFixed(2);
        final bar = '#' * (c * 50 ~/ n);
        print('  $v : $pct%  $bar');
      }
      print('');
    }
  }

  void printSpeedDist(String label, Map<int, int> buckets) {
    print('=== $label の球速 ===\n');
    final keys = buckets.keys.toList()..sort();
    int n = 0;
    num sum = 0;
    for (final k in keys) {
      n += buckets[k]!;
      sum += k * buckets[k]!;
    }
    if (n == 0) return;
    final mean = sum / n;
    print('球速 mean=${mean.toStringAsFixed(1)} km/h, n=$n');
    // 5 km/h バケット表示
    final binnedKeys = <int>{};
    for (final k in keys) {
      binnedKeys.add((k ~/ 5) * 5);
    }
    final sorted = binnedKeys.toList()..sort();
    for (final low in sorted) {
      int c = 0;
      for (final k in keys) {
        if (k >= low && k < low + 5) c += buckets[k]!;
      }
      final pct = (c / n * 100).toStringAsFixed(2);
      final bar = '#' * (c * 40 ~/ n);
      print('  ${low}-${low + 4} km/h : $pct%  $bar');
    }
    // 上位 (>= 155) と最高
    int hi155 = 0;
    int hi158 = 0;
    int hi160 = 0;
    for (final k in keys) {
      if (k >= 155) hi155 += buckets[k]!;
      if (k >= 158) hi158 += buckets[k]!;
      if (k >= 160) hi160 += buckets[k]!;
    }
    print('  >=155 km/h : ${(hi155 / n * 100).toStringAsFixed(2)}%');
    print('  >=158 km/h : ${(hi158 / n * 100).toStringAsFixed(2)}%');
    print('  >=160 km/h : ${(hi160 / n * 100).toStringAsFixed(2)}%');
    print('');
  }

  printIntDist('先発投手', intCountsStarter);
  printIntDist('救援投手', intCountsRelief);
  printSpeedDist('先発', speedBucketsStarter);
  printSpeedDist('救援', speedBucketsRelief);
}

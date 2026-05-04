import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 投手の打撃能力（meet/power/eye/speed）の分布を計測する。
void main() {
  final cats = ['meet', 'power', 'eye', 'speed'];
  final counts = <String, Map<int, int>>{
    for (final c in cats) c: {for (int v = 1; v <= 10; v++) v: 0},
  };
  int total = 0;

  for (int i = 0; i < 200; i++) {
    final teams = TeamGenerator(random: Random(2000 + i)).generateLeague();
    for (final t in teams) {
      final pitchers = [
        ...t.startingRotation,
        ...t.bullpen,
      ];
      for (final p in pitchers) {
        if (p.meet != null) counts['meet']![p.meet!] = counts['meet']![p.meet!]! + 1;
        if (p.power != null) counts['power']![p.power!] = counts['power']![p.power!]! + 1;
        if (p.eye != null) counts['eye']![p.eye!] = counts['eye']![p.eye!]! + 1;
        if (p.speed != null) counts['speed']![p.speed!] = counts['speed']![p.speed!]! + 1;
        total++;
      }
    }
  }

  print('投手の打撃能力分布 (n=$total 投手 × 200 リーグ)\n');
  for (final cat in cats) {
    final m = counts[cat]!;
    num sum = 0;
    int n = 0;
    for (int v = 1; v <= 10; v++) {
      sum += v * m[v]!;
      n += m[v]!;
    }
    final mean = sum / n;
    print('$cat (mean=${mean.toStringAsFixed(2)}):');
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

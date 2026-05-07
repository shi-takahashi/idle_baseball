import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 投手の持ち球（球種数 + 球種組み合わせ）の分布を計測する。
/// 修正後の期待値:
///   合計 3 種類 (extra 2): 50%
///   合計 4 種類 (extra 3): 40%
///   合計 5 種類 (extra 4): 10%
void main() {
  final arsenalCounts = <int, int>{2: 0, 3: 0, 4: 0, 5: 0};
  final extraCombos = <String, int>{};
  int total = 0;

  for (int i = 0; i < 500; i++) {
    final teams = TeamGenerator(random: Random(7000 + i)).generateLeague();
    for (final t in teams) {
      for (final p in t.players) {
        if (!p.isPitcher) continue;
        total++;

        final extras = <String>[];
        if (p.slider != null) extras.add('スラ');
        if (p.curve != null) extras.add('カブ');
        if (p.splitter != null) extras.add('スプ');
        if (p.changeup != null) extras.add('チェ');

        final arsenal = 1 + extras.length; // ストレート + 変化球
        arsenalCounts[arsenal] = (arsenalCounts[arsenal] ?? 0) + 1;

        extras.sort();
        final key = '直+${extras.join(",")}';
        extraCombos[key] = (extraCombos[key] ?? 0) + 1;
      }
    }
  }

  print('=== 球種数分布 (n=$total 投手) ===');
  for (final entry in arsenalCounts.entries) {
    final pct = entry.value / total * 100;
    print('  ${entry.key} 種類: ${entry.value.toString().padLeft(5)} '
        '(${pct.toStringAsFixed(1).padLeft(5)}%)');
  }

  final twoPitch = arsenalCounts[2] ?? 0;
  print('\n  ▶ 2 種類のみ (NG): ${twoPitch == 0 ? "0 件 ✓" : "$twoPitch 件 ✗"}');

  print('\n=== 持ち球の組み合わせ Top 15 ===');
  final sorted = extraCombos.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final entry in sorted.take(15)) {
    final pct = entry.value / total * 100;
    print('  ${entry.key.padRight(28)} ${entry.value.toString().padLeft(5)} '
        '(${pct.toStringAsFixed(1).padLeft(5)}%)');
  }
}

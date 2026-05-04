import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 5 シーズン経過後の球速分布を計測（インフレ確認用）。
void main() {
  final dist1 = <int, int>{};
  final dist5 = <int, int>{};

  for (int seed = 0; seed < 30; seed++) {
    final c = SeasonController.newSeason(random: Random(seed));
    _collect(c, dist1);
    for (int s = 0; s < 4; s++) {
      c.advanceAll();
      c.commitOffseason();
    }
    _collect(c, dist5);
  }

  void show(String label, Map<int, int> d) {
    final total = d.values.fold<int>(0, (a, b) => a + b);
    num sum = 0;
    for (final e in d.entries) {
      sum += e.key * e.value;
    }
    final mean = sum / total;
    int over155 = 0, over160 = 0, over165 = 0;
    for (final e in d.entries) {
      if (e.key >= 155) over155 += e.value;
      if (e.key >= 160) over160 += e.value;
      if (e.key >= 165) over165 += e.value;
    }
    print('$label (mean=${mean.toStringAsFixed(1)}, n=$total)');
    print('  >=155: ${(over155 / total * 100).toStringAsFixed(2)}%');
    print('  >=158: ${(_over(d, 158) / total * 100).toStringAsFixed(2)}%');
    print('  >=160: ${(over160 / total * 100).toStringAsFixed(2)}%');
    print('  >=163: ${(_over(d, 163) / total * 100).toStringAsFixed(2)}%');
    print('  >=165: ${(over165 / total * 100).toStringAsFixed(2)}%');
    print('');
  }

  show('シーズン 1 開幕時', dist1);
  show('シーズン 5 開幕時', dist5);
}

int _over(Map<int, int> d, int threshold) {
  int n = 0;
  for (final e in d.entries) {
    if (e.key >= threshold) n += e.value;
  }
  return n;
}

void _collect(SeasonController c, Map<int, int> d) {
  for (final t in c.teams) {
    for (final p in [...t.startingRotation, ...t.bullpen]) {
      if (p.averageSpeed != null) {
        d[p.averageSpeed!] = (d[p.averageSpeed!] ?? 0) + 1;
      }
    }
  }
}

import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 数シーズン経過後にリーグ内の能力分布がどうなっているかを測る。
/// 特に 9 / 10 の発生率がインフレしていないかを確認。
void main() {
  // 開幕直後 (シーズン 1 開始時) と、シーズン 5 開始時で比較。
  // 全選手の meet / power / speed / eye / fastball / control を集計。
  final cats = ['meet', 'power', 'speed', 'eye', 'fastball', 'control'];

  Map<String, Map<int, int>> emptyDist() => {
        for (final c in cats) c: {for (int v = 1; v <= 10; v++) v: 0},
      };

  final dist1 = emptyDist();
  final dist5 = emptyDist();

  for (int seed = 0; seed < 30; seed++) {
    final c = SeasonController.newSeason(random: Random(seed));
    _collect(c, dist1);
    // 5 シーズン回す（advanceAll → commitOffseason × 4 で 5シーズン目突入時）
    for (int s = 0; s < 4; s++) {
      c.advanceAll();
      c.commitOffseason();
    }
    _collect(c, dist5);
  }

  print('シーズン 1 開幕時 vs シーズン 5 開幕時 の能力分布比較');
  print('（30 リーグ × 全選手）\n');
  for (final cat in cats) {
    print('--- $cat ---');
    print('値 |  S1     |  S5     | 変化');
    for (int v = 1; v <= 10; v++) {
      final n1 = dist1[cat]![v]!;
      final n5 = dist5[cat]![v]!;
      final t1 = dist1[cat]!.values.fold<int>(0, (a, b) => a + b);
      final t5 = dist5[cat]!.values.fold<int>(0, (a, b) => a + b);
      final p1 = (n1 / t1 * 100);
      final p5 = (n5 / t5 * 100);
      final diff = p5 - p1;
      final sign = diff >= 0 ? '+' : '';
      print('  $v | ${p1.toStringAsFixed(2).padLeft(5)}%  |'
          ' ${p5.toStringAsFixed(2).padLeft(5)}%  | $sign${diff.toStringAsFixed(2)}%');
    }
    // 9-10 合計
    final hi1 = (dist1[cat]![9]! + dist1[cat]![10]!) /
        dist1[cat]!.values.fold<int>(0, (a, b) => a + b) *
        100;
    final hi5 = (dist5[cat]![9]! + dist5[cat]![10]!) /
        dist5[cat]!.values.fold<int>(0, (a, b) => a + b) *
        100;
    print('  9-10合計: ${hi1.toStringAsFixed(2)}% → ${hi5.toStringAsFixed(2)}%  '
        '(x${(hi5 / hi1).toStringAsFixed(1)})');
    print('');
  }
}

void _collect(SeasonController c, Map<String, Map<int, int>> dist) {
  for (final t in c.teams) {
    final all = <Player>[
      ...t.players,
      ...t.startingRotation,
      ...t.bullpen,
      ...t.bench,
    ];
    final seen = <String>{};
    for (final p in all) {
      if (!seen.add(p.id)) continue;
      void add(String key, int? v) {
        if (v == null) return;
        dist[key]![v] = dist[key]![v]! + 1;
      }
      // 投手の打撃は除外したいので、投手は fastball/control のみ集計
      if (p.isPitcher) {
        add('fastball', p.fastball);
        add('control', p.control);
      } else {
        add('meet', p.meet);
        add('power', p.power);
        add('speed', p.speed);
        add('eye', p.eye);
      }
    }
  }
}

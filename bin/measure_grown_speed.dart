import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 複数の経過年数で投手球速分布を計測し、定常状態を確認する。
void main() {
  const gamesPerTeam = 150;
  const checkpoints = [0, 4, 8, 12, 16, 20];
  const numLeagues = 24;

  // 各 checkpoint でのリーグ平均集計
  final results = <int, Map<String, num>>{};

  for (final cp in checkpoints) {
    final buckets = <int, int>{};
    int total = 0;

    for (int i = 0; i < numLeagues; i++) {
      final c = SeasonController.newSeason(
          random: Random(7700 + i), gamesPerTeam: gamesPerTeam);
      for (int s = 0; s < cp; s++) {
        c.advanceAll();
        c.prepareOffseason();
        c.commitOffseason();
      }
      for (final t in c.teams) {
        for (final p in [...t.startingRotation, ...t.bullpen]) {
          final speed = p.averageSpeed;
          if (speed != null) {
            buckets[speed] = (buckets[speed] ?? 0) + 1;
            total++;
          }
        }
      }
    }

    num sum = 0;
    int hi155 = 0, hi158 = 0;
    for (final entry in buckets.entries) {
      sum += entry.key * entry.value;
      if (entry.key >= 155) hi155 += entry.value;
      if (entry.key >= 158) hi158 += entry.value;
    }
    results[cp] = {
      'mean': sum / total,
      'total': total,
      'hi155': hi155,
      'hi158': hi158,
      'pct155': hi155 / total * 100,
      'pct158': hi158 / total * 100,
      'perLeague155': hi155 / numLeagues,
      'perLeague158': hi158 / numLeagues,
    };
  }

  print('=== 球速分布の経年変化（$numLeagues リーグ平均） ===');
  print('');
  print(' 経過年 | mean  | n     | 155+(%)  | 155+(人/リーグ) | 158+(人/リーグ)');
  print('--------|-------|-------|----------|-----------------|----------------');
  for (final cp in checkpoints) {
    final r = results[cp]!;
    print(' ${cp.toString().padLeft(4)}年  '
        '| ${(r['mean'] as num).toStringAsFixed(1)} '
        '| ${(r['total'] as num).toString().padLeft(5)} '
        '|  ${(r['pct155'] as num).toStringAsFixed(2)}%    '
        '|    ${(r['perLeague155'] as num).toStringAsFixed(2)}         '
        '|    ${(r['perLeague158'] as num).toStringAsFixed(2)}');
  }
}

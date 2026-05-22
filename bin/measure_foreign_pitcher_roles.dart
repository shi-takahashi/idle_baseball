import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 外国人投手のロール分布を確認する。
/// 旧版は全員 starter で生成されていた問題を、抽選方式に変更したことの検証。
void main() {
  final dist = <PitcherRole, int>{};
  const numLeagues = 200;
  for (int seed = 0; seed < numLeagues; seed++) {
    final teams = TeamGenerator(random: Random(seed)).generateLeague();
    for (final t in teams) {
      for (final p in [...t.startingRotation, ...t.bullpen]) {
        if (!p.isForeign || !p.isPitcher) continue;
        final role = p.pitcherRole ?? PitcherRole.starter;
        dist[role] = (dist[role] ?? 0) + 1;
      }
    }
  }
  final total = dist.values.fold<int>(0, (a, b) => a + b);
  print('外国人投手のロール分布 ($numLeagues リーグ × 6 チーム × 2 名 = '
      '${numLeagues * 12} 名)');
  for (final role in PitcherRole.values) {
    final n = dist[role] ?? 0;
    if (n == 0) {
      print('  ${role.name}: 0');
      continue;
    }
    final pct = (n / total * 100).toStringAsFixed(1);
    print('  ${role.name.padRight(12)}: $n ($pct%)');
  }
  print('');
  print('期待値（1 チームあたり 2 名 = 200リーグ × 12 = 2400 名）:');
  print('  starter ~ 56% / closer ~ 22% / setup ~ 7% / middle ~ 9% / long ~ 3% / mopUp ~ 3%');
}

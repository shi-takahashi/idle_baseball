// Chunk 3 動作確認: 加齢と能力変動。
//
// 5シーズン進めて以下を観測:
// - 若手（初期 18-23 歳）の平均能力推移
// - ベテラン（初期 32+ 歳）の平均能力推移
// - 全体の平均年齢推移（毎年 +1 のはず）
// - 個別選手の能力変化サンプル
//
// 実行: dart run bin/test_aging.dart
import 'dart:math';

import 'package:idle_baseball/engine/engine.dart';
import 'package:idle_baseball/engine/offseason/player_aging.dart';

void main() {
  final c = SeasonController.newSeason(random: Random(42));

  // 初期スナップショット
  final initial = _snapshot(c);

  print('=== シーズン 1 開始時 ===');
  _printSummary(initial);

  // 5シーズン進める（試合は飛ばして、aging のみ）
  for (int i = 1; i <= 5; i++) {
    c.advanceAll();
    c.advanceToNextSeason();
    final snap = _snapshot(c);
    print('\n=== シーズン ${c.seasonYear} 開始時 ===');
    _printSummary(snap);
  }

  // 個別選手のキャリア追跡（初期で年齢の極端な選手 3名）
  print('\n--- 初期データ ---');
  print('合計選手数: ${initial.players.length}');
  print('平均年齢: ${initial.avgAge.toStringAsFixed(1)}');

  // 検証: PlayerAging 単独で 1 年加齢して age が +1 になること
  final c2 = SeasonController.newSeason(random: Random(7));
  final p = c2.teams.first.players.first;
  final aging = PlayerAging(random: Random(0));
  final aged = aging.ageOneYear(p);
  if (aged.age != p.age + 1) {
    throw '加齢処理で age が +1 になっていない (${p.age} → ${aged.age})';
  }
  print('\nOK: 加齢が動作している');
}

class _Snapshot {
  final List<Player> players;
  final double avgAge;
  final double avgPower;
  final double avgSpeed;
  final double avgControlForPitchers;
  _Snapshot(this.players, this.avgAge, this.avgPower, this.avgSpeed,
      this.avgControlForPitchers);
}

_Snapshot _snapshot(SeasonController c) {
  final all = <Player>[];
  final ids = <String>{};
  for (final t in c.teams) {
    for (final p in [
      ...t.players,
      ...t.startingRotation,
      ...t.bullpen,
      ...t.bench,
    ]) {
      if (ids.add(p.id)) all.add(p);
    }
  }
  double mean(Iterable<num> xs) {
    final list = xs.toList();
    if (list.isEmpty) return 0;
    return list.reduce((a, b) => a + b) / list.length;
  }

  return _Snapshot(
    all,
    mean(all.map((p) => p.age)),
    mean(all.where((p) => p.power != null).map((p) => p.power!)),
    mean(all.where((p) => p.speed != null).map((p) => p.speed!)),
    mean(all.where((p) => p.control != null).map((p) => p.control!)),
  );
}

void _printSummary(_Snapshot s) {
  print('  平均年齢: ${s.avgAge.toStringAsFixed(1)}');
  print('  平均長打力: ${s.avgPower.toStringAsFixed(2)}');
  print('  平均走力:   ${s.avgSpeed.toStringAsFixed(2)}');
  print('  投手平均制球: ${s.avgControlForPitchers.toStringAsFixed(2)}');

  // 年齢分布
  final buckets = <String, int>{
    '18-21': 0,
    '22-24': 0,
    '25-28': 0,
    '29-31': 0,
    '32-34': 0,
    '35-37': 0,
    '38+': 0,
  };
  for (final p in s.players) {
    if (p.age <= 21) {
      buckets['18-21'] = buckets['18-21']! + 1;
    } else if (p.age <= 24) {
      buckets['22-24'] = buckets['22-24']! + 1;
    } else if (p.age <= 28) {
      buckets['25-28'] = buckets['25-28']! + 1;
    } else if (p.age <= 31) {
      buckets['29-31'] = buckets['29-31']! + 1;
    } else if (p.age <= 34) {
      buckets['32-34'] = buckets['32-34']! + 1;
    } else if (p.age <= 37) {
      buckets['35-37'] = buckets['35-37']! + 1;
    } else {
      buckets['38+'] = buckets['38+']! + 1;
    }
  }
  print('  年齢分布: $buckets');
}

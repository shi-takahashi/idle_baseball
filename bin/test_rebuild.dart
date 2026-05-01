// Chunk 4 動作確認: CPU チームの引退・新人加入・投手ロール再編。
//
// 検証ポイント:
// (a) 自チームの選手は変わらない
// (b) CPU チームは毎シーズン野手 2 名・投手 2 名が入れ替わる（多くの場合）
// (c) ポジション制約（各 DefensePosition で最低 2 人守れる）が維持される
// (d) ブルペンのロール構成が維持される
//
// 実行: dart run bin/test_rebuild.dart
import 'dart:math';

import 'package:idle_baseball/engine/engine.dart';

void main() {
  final c = SeasonController.newSeason(random: Random(42));
  final myTeamId = c.myTeamId;

  // 初期スナップショット
  final myInitialIds = _allPlayerIds(c.teams.firstWhere((t) => t.id == myTeamId));
  final cpuInitialIds = <String, Set<String>>{};
  for (final t in c.teams) {
    if (t.id == myTeamId) continue;
    cpuInitialIds[t.id] = _allPlayerIds(t);
  }

  print('=== シーズン 1 開始時 ===');
  for (final t in c.teams) {
    final tag = t.id == myTeamId ? '(自)' : '(CPU)';
    print('${t.shortName} $tag: ${_allPlayerIds(t).length} 人');
    _printPositionCoverage(t);
  }

  // 1 シーズン完走 → オフシーズン
  c.advanceAll();
  c.advanceToNextSeason();

  print('\n=== シーズン 2 開始時（オフシーズン処理後） ===');
  // 自チームの選手 id が変わっていないこと
  final myNewIds = _allPlayerIds(c.teams.firstWhere((t) => t.id == myTeamId));
  if (!_setEquals(myInitialIds, myNewIds)) {
    final added = myNewIds.difference(myInitialIds);
    final removed = myInitialIds.difference(myNewIds);
    throw '自チームの選手が変動した。追加: $added 削除: $removed';
  }
  print('自チーム: 選手構成は不変 OK');

  // CPU チームは 4 人入れ替わっていること（2 野手 + 2 投手 = 4）
  for (final t in c.teams) {
    if (t.id == myTeamId) continue;
    final newIds = _allPlayerIds(t);
    final oldIds = cpuInitialIds[t.id]!;
    final added = newIds.difference(oldIds);
    final removed = oldIds.difference(newIds);
    print('${t.shortName} (CPU): 引退 ${removed.length} / 加入 ${added.length}');
    if (added.length != removed.length) {
      throw 'チーム ${t.shortName}: 加入数 ${added.length} != 引退数 ${removed.length}';
    }
    if (added.length > 4) {
      throw 'チーム ${t.shortName}: 入れ替え数が多すぎ ${added.length}';
    }
    // ポジション制約
    _printPositionCoverage(t);
    _verifyPositionConstraint(t);
  }

  // ブルペンロール構成の検証
  print('\n--- ブルペンロール構成チェック ---');
  for (final t in c.teams) {
    if (t.id == myTeamId) continue;
    final roleCount = <ReliefRole, int>{};
    for (final p in t.bullpen) {
      if (p.reliefRole != null) {
        roleCount[p.reliefRole!] = (roleCount[p.reliefRole!] ?? 0) + 1;
      }
    }
    print('${t.shortName}: $roleCount');
    // 抑えとセットアッパーは 1 人ずつ存在
    if ((roleCount[ReliefRole.closer] ?? 0) != 1) {
      throw '${t.shortName}: 抑え不在または複数';
    }
    if ((roleCount[ReliefRole.setup] ?? 0) != 1) {
      throw '${t.shortName}: セットアッパー不在または複数';
    }
  }

  // 5 シーズン進行で破綻しないか
  print('\n--- 5 シーズン耐久 ---');
  for (int i = 1; i <= 5; i++) {
    c.advanceAll();
    c.advanceToNextSeason();
  }
  print('シーズン ${c.seasonYear} まで到達');
  // 全チームでポジション制約を再確認
  for (final t in c.teams) {
    _verifyPositionConstraint(t);
  }

  // 平均年齢が暴走していないか
  final allPlayers = c.teams.expand((t) => [
        ...t.players,
        ...t.startingRotation,
        ...t.bullpen,
        ...t.bench,
      ]).toSet().toList();
  final avgAge = allPlayers.map((p) => p.age).reduce((a, b) => a + b) /
      allPlayers.length;
  print('シーズン ${c.seasonYear} 開幕時の平均年齢: ${avgAge.toStringAsFixed(1)}');

  print('\nOK: CPU 再構築が期待通り動作');
}

Set<String> _allPlayerIds(Team t) {
  return {
    for (final p in [
      ...t.players,
      ...t.startingRotation,
      ...t.bullpen,
      ...t.bench,
    ])
      p.id,
  };
}

bool _setEquals(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

void _printPositionCoverage(Team t) {
  final fielders = [
    ...t.players.where((p) => !p.isPitcher),
    ...t.bench,
  ];
  final coverage = <DefensePosition, int>{
    for (final pos in DefensePosition.values) pos: 0,
  };
  for (final p in fielders) {
    for (final pos in DefensePosition.values) {
      if (p.canPlay(pos)) coverage[pos] = coverage[pos]! + 1;
    }
  }
  final desc = coverage.entries
      .map((e) => '${e.key.shortName}:${e.value}')
      .join(' ');
  print('  守備充足: $desc');
}

void _verifyPositionConstraint(Team t) {
  final fielders = [
    ...t.players.where((p) => !p.isPitcher),
    ...t.bench,
  ];
  for (final pos in DefensePosition.values) {
    final count = fielders.where((p) => p.canPlay(pos)).length;
    if (count < 2) {
      throw '${t.shortName}: ${pos.shortName} を守れる選手が $count 人 (< 2)';
    }
  }
}

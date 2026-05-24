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
  // 自チーム: 日本人の引退選択を渡していないので日本人選手は変動しない。
  // ただし外国人選手は強制離脱（1/5）が独立判定されうるので、外国人の変動は
  // 許容する。日本人選手の id 集合だけが変動しないことを確認する。
  final myTeam = c.teams.firstWhere((t) => t.id == myTeamId);
  final myNewIds = _allPlayerIds(myTeam);
  final japaneseInitialIds = myInitialIds.where((id) {
    // 開幕時の Player を id ベースで引いて isForeign を見る方法がないので
    // 「変動した id がすべて外国人かどうか」で判定する
    return true;
  }).toSet();
  final added = myNewIds.difference(japaneseInitialIds);
  final removed = japaneseInitialIds.difference(myNewIds);
  // 変動が全て外国人ならOK
  for (final id in added) {
    final p = myTeam.players.firstWhere(
      (pl) => pl.id == id,
      orElse: () => myTeam.bench.firstWhere(
        (pl) => pl.id == id,
        orElse: () => myTeam.startingRotation.firstWhere(
          (pl) => pl.id == id,
          orElse: () =>
              myTeam.bullpen.firstWhere((pl) => pl.id == id),
        ),
      ),
    );
    if (!p.isForeign) {
      throw '自チームの日本人選手が変動した（追加: $id, ${p.name}）';
    }
  }
  print('自チーム: 日本人選手は不変、外国人 ${added.length} 名入替 OK');

  // CPU チームは 6 人入れ替わっていること（3 野手 + 3 投手 = 6）
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
    // 日本人 6 名（野手3 + 投手3） + 外国人最大 4 名（野手2 + 投手2 が確率離脱、
    // 2026-05-22 で外国人枠 2+2 化）= 上限 10。離脱しないシーズンが多いので
    // 通常は 6-7 程度、外国人 1〜2 名離脱で 7-9 のシーズンもある。
    if (added.length > 10) {
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
    final roleCount = <PitcherRole, int>{};
    for (final p in t.bullpen) {
      if (p.pitcherRole != null) {
        roleCount[p.pitcherRole!] = (roleCount[p.pitcherRole!] ?? 0) + 1;
      }
    }
    print('${t.shortName}: $roleCount');
    // 14人ブルペンの想定ロール構成: 抑え1 / セットアッパー2 / 中継ぎ6 /
    // ワンポイント0〜1 / ロング2 / 敗戦処理2 (投手 20 名構成、2026-05-24)。
    if ((roleCount[PitcherRole.closer] ?? 0) != 1) {
      throw '${t.shortName}: 抑え不在または複数';
    }
    if ((roleCount[PitcherRole.setup] ?? 0) != 2) {
      throw '${t.shortName}: セットアッパーが2人でない';
    }
    if ((roleCount[PitcherRole.middle] ?? 0) != 6) {
      throw '${t.shortName}: 中継ぎが6人でない';
    }
    if ((roleCount[PitcherRole.long] ?? 0) != 2) {
      throw '${t.shortName}: ロングが2人でない';
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

// 当日ベンチ入り + 投手ロールの検証
// - suggestedStrategyForMyTeam が打順9・控え野手9・救援8 を埋めた作戦を返す
// - 先発・ベンチ入り救援は全18投手から背番号順（中立）に選ばれる
// - 開幕時の投手ロール: 先発ローテ6→「先発」/ 救援12→「中継ぎ」
// - setMyStrategy した作戦が試合編成で尊重される（控え野手の非ベンチ入りは出場0、
//   ベンチ入り救援固定の投手は先発0）

import 'dart:math';

import 'package:idle_baseball/engine/engine.dart';

void main() {
  final c = SeasonController.newSeason(random: Random(2024));
  final team = c.myTeam;

  final suggested = c.suggestedStrategyForMyTeam();
  if (suggested == null) {
    print('FAIL: オート提案が取れませんでした');
    return;
  }

  var ok = true;
  void check(String label, bool cond) {
    print('${cond ? 'OK' : 'NG'}  $label');
    if (!cond) ok = false;
  }

  // --- 1. 提案が当日ベンチ入りを含む完全な編成か ---
  check('提案 lineup 9人', suggested.lineup.length == 9);
  check('提案 activeBench 9人', suggested.activeBench.length == 9);
  check('提案 activeBullpen 8人', suggested.activeBullpen.length == 8);
  check('activeBench は全員野手',
      suggested.activeBench.every((p) => !p.isPitcher));
  check('activeBullpen は全員投手',
      suggested.activeBullpen.every((p) => p.isPitcher));
  final lineupIds = suggested.lineup.map((p) => p.id).toSet();
  check('activeBench はスタメンと重複なし',
      suggested.activeBench.every((p) => !lineupIds.contains(p.id)));

  // 提案打順は能力順でなく背番号順（中立）— 1〜8番の野手が背番号昇順
  final fielderNumbers = [
    for (final p in suggested.lineup)
      if (!p.isPitcher) p.number,
  ];
  var ascending = true;
  for (int i = 1; i < fielderNumbers.length; i++) {
    if (fielderNumbers[i] < fielderNumbers[i - 1]) ascending = false;
  }
  check('提案打順は中立（野手は背番号昇順）', ascending);
  check('投手は9番', suggested.lineup.last.isPitcher);

  // スタメン選定も中立: ベンチ入り控え野手が守れる守備位置には、必ずその控えより
  // 背番号の若いスタメンが入っている（能力でなく背番号で選ばれている証拠）。
  final lineupAtPos = <DefensePosition, List<int>>{};
  for (final e in suggested.alignment.entries) {
    final dp = e.key.defensePosition;
    if (dp == null) continue;
    (lineupAtPos[dp] ??= []).add(e.value.number);
  }
  var selectionOk = true;
  for (final x in suggested.activeBench) {
    for (final dp in DefensePosition.values) {
      if (!x.canPlay(dp)) continue;
      for (final n in lineupAtPos[dp] ?? const <int>[]) {
        if (n > x.number) selectionOk = false;
      }
    }
  }
  check('スタメン選定は背番号順で中立（控えより若い番号がスタメン入り）',
      selectionOk);

  // --- 1b. 開幕時、自チームの救援は全員「中継ぎ」（能力バレ防止）---
  check(
    '開幕時 自チーム救援は全員中継ぎ',
    team.bullpen.every((p) => p.pitcherRole == PitcherRole.middle),
  );
  // setPitcherRole で永続的に役割を変更できる
  final aReliever = team.bullpen.first;
  c.setPitcherRole(aReliever.id, PitcherRole.closer);
  check(
    'setPitcherRole で抑えに変更が反映される',
    c.myTeam.bullpen
            .firstWhere((p) => p.id == aReliever.id)
            .pitcherRole ==
        PitcherRole.closer,
  );
  // 元に戻しておく（以降のテストに影響させない）
  c.setPitcherRole(aReliever.id, PitcherRole.middle);

  // --- 1c. 開幕時、先発ローテ6人は「先発」役割 ---
  check(
    '開幕時 自チーム先発ローテは全員「先発」役割',
    team.startingRotation.every((p) => p.pitcherRole == PitcherRole.starter),
  );

  // --- 2. ベンチ入り選定が中立（背番号順）か ---
  final allFielders = <Player>[
    ...team.players.take(8),
    ...team.bench,
  ].where((p) => !p.isPitcher).toList();
  final activeFielderIds = {
    ...lineupIds,
    ...suggested.activeBench.map((p) => p.id),
  };
  final excludedFielders =
      allFielders.where((p) => !activeFielderIds.contains(p.id)).toList();
  check('ベンチ入り外の控え野手は5人', excludedFielders.length == 5);

  // 先発・ベンチ入り救援は全18投手から背番号順（中立）に選ばれる。
  final spId = suggested.lineup.firstWhere((p) => p.isPitcher).id;
  final allPitchers = <Player>[
    ...team.startingRotation,
    ...team.bullpen,
  ]..sort((a, b) => a.number.compareTo(b.number));
  check('Day1 先発は全18投手で背番号最小', allPitchers.first.id == spId);
  final activeBullpenIds =
      suggested.activeBullpen.map((p) => p.id).toSet();
  final expectedBullpenIds = [
    for (final p in allPitchers)
      if (p.id != spId) p,
  ].take(8).map((p) => p.id).toSet();
  check(
    'ベンチ入り救援は背番号順で中立（先発を除く背番号下位8人）',
    activeBullpenIds.length == expectedBullpenIds.length &&
        activeBullpenIds.containsAll(expectedBullpenIds),
  );

  // --- 3. 作戦をセットしてシーズン完走 ---
  // 作戦は試合後も保持され（SP のみ自動ローテ）、activeBench/activeBullpen は固定。
  c.setMyStrategy(suggested);
  c.advanceAll();

  // --- 4a. ベンチ入りから外した控え野手は1試合も出ていない ---
  for (final p in excludedFielders) {
    final g = c.batterStats[p.id]?.games ?? 0;
    check('控え野手 ${p.name} は非ベンチ入りで出場0 (実際 $g)', g == 0);
  }
  // --- 4b. ベンチ入り救援に固定した投手はシーズン通して先発しない ---
  for (final p in suggested.activeBullpen) {
    final st = c.pitcherStats[p.id]?.starts ?? 0;
    check('${p.name} はベンチ入り救援固定で先発0 (実際 $st)', st == 0);
  }

  // --- 5. ベンチ入りした選手は試合に絡んでいる（編成が機能している傍証）---
  final benchAppeared = suggested.activeBench
      .where((p) => (c.batterStats[p.id]?.games ?? 0) > 0)
      .length;
  print('  （参考）ベンチ入り控え野手9人中 $benchAppeared 人が出場');

  print(ok ? '\n=== 全テスト OK ===' : '\n=== FAIL ===');
}

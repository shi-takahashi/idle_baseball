// Chunk 5 動作確認: 自チームのオフシーズン編成（引退・新人加入）。
//
// 検証ポイント:
// (a) prepareOffseason が候補リストを返し、teams は変更されない
// (b) 新人候補は野手 6 / 投手 6（高卒 2 + 大卒 2 + 社会人 2）で生成される
// (c) commitOffseason に推奨選択を渡すと、自チームの選手が引退・新人加入する
// (d) 加入した新人は引退者の背番号と先発／救援ロールを引き継ぐ
// (e) 自チーム再編成後にシーズン 2 を完走できる
// (f) commitOffseason() (selection なし) は従来通り自チームを変更しない
//
// 実行: dart run bin/test_offseason_user.dart
import 'dart:math';

import 'package:idle_baseball/engine/engine.dart';

void main() {
  final c = SeasonController.newSeason(random: Random(42));

  print('--- シーズン 1 完走 ---');
  c.advanceAll();
  print('isSeasonOver = ${c.isSeasonOver}');

  // (a) prepareOffseason は teams を変えない
  final preMyTeamIds =
      c.myTeam.players.map((p) => p.id).toList(growable: false);
  final preBenchIds = c.myTeam.bench.map((p) => p.id).toList(growable: false);
  final preRotationIds =
      c.myTeam.startingRotation.map((p) => p.id).toList(growable: false);
  final preBullpenIds =
      c.myTeam.bullpen.map((p) => p.id).toList(growable: false);

  final plan = c.prepareOffseason();
  if (!_listEq(c.myTeam.players.map((p) => p.id), preMyTeamIds) ||
      !_listEq(c.myTeam.bench.map((p) => p.id), preBenchIds) ||
      !_listEq(
          c.myTeam.startingRotation.map((p) => p.id), preRotationIds) ||
      !_listEq(c.myTeam.bullpen.map((p) => p.id), preBullpenIds)) {
    throw 'prepareOffseason がチームを変更している';
  }
  print('OK: prepareOffseason はチームを変更しない');

  print('引退候補野手 (上位 5):');
  for (final p in plan.retireCandidateFielders.take(5)) {
    final mark = plan.recommendedRetireFielderIds.contains(p.id) ? ' ★推奨' : '';
    print('  ${p.name} (${p.age}歳)$mark');
  }
  print('引退候補投手 (上位 5):');
  for (final p in plan.retireCandidatePitchers.take(5)) {
    final mark = plan.recommendedRetirePitcherIds.contains(p.id) ? ' ★推奨' : '';
    print('  ${p.name} (${p.age}歳)$mark');
  }
  print('新人野手候補 (${plan.rookieFielderCandidates.length}):');
  for (final c in plan.rookieFielderCandidates) {
    final mark =
        plan.recommendedTakeFielderIds.contains(c.id) ? ' ★推奨' : '';
    print('  [${c.type.displayName}] ${c.player.name} '
        '(${c.player.age}歳 '
        'ミ${c.player.meet} 長${c.player.power})$mark');
  }
  print('新人投手候補 (${plan.rookiePitcherCandidates.length}):');
  for (final c in plan.rookiePitcherCandidates) {
    final mark =
        plan.recommendedTakePitcherIds.contains(c.id) ? ' ★推奨' : '';
    print('  [${c.type.displayName}] ${c.player.name} '
        '(${c.player.age}歳 '
        '球${c.player.averageSpeed} 制${c.player.control})$mark');
  }

  // (b) 各タイプ 2 名ずつ
  for (final type in RookieType.values) {
    final fCount =
        plan.rookieFielderCandidates.where((c) => c.type == type).length;
    final pCount =
        plan.rookiePitcherCandidates.where((c) => c.type == type).length;
    if (fCount != 2 || pCount != 2) {
      throw '${type.displayName} の候補数が想定外: 野手 $fCount, 投手 $pCount';
    }
  }
  print('OK: 高卒 / 大卒 / 社会人 がそれぞれ 2 名ずつ生成されている');

  // (b) (c) commitOffseason に推奨選択を渡す
  final retiredFielderNumbers = plan.recommendedRetireFielderIds
      .map((id) =>
          plan.retireCandidateFielders.firstWhere((p) => p.id == id).number)
      .toList();
  final retiredPitcherIds = List.of(plan.recommendedRetirePitcherIds);
  final retiredPitcherWasStarter = {
    for (final id in retiredPitcherIds)
      id: c.myTeam.startingRotation.any((p) => p.id == id),
  };
  final retiredPitcherNumbers = retiredPitcherIds
      .map((id) =>
          plan.retireCandidatePitchers.firstWhere((p) => p.id == id).number)
      .toList();
  final retiredPitcherReliefRoles = {
    for (final id in retiredPitcherIds)
      id: plan.retireCandidatePitchers
          .firstWhere((p) => p.id == id)
          .reliefRole,
  };

  final selection = OffseasonSelection.recommended(plan);
  c.commitOffseason(plan: plan, selection: selection);

  print('\n--- commitOffseason 後 ---');
  print('シーズン: ${c.seasonYear} 年目');

  // 引退者は team から消えていること
  final allMyIds = <String>{
    ...c.myTeam.players.map((p) => p.id),
    ...c.myTeam.bench.map((p) => p.id),
    ...c.myTeam.startingRotation.map((p) => p.id),
    ...c.myTeam.bullpen.map((p) => p.id),
  };
  for (final retiredId in [
    ...plan.recommendedRetireFielderIds,
    ...plan.recommendedRetirePitcherIds,
  ]) {
    if (allMyIds.contains(retiredId)) {
      throw '引退済みの選手 $retiredId がまだチームに残っている';
    }
  }
  print('OK: 引退選手 ${plan.recommendedRetireFielderIds.length}+'
      '${plan.recommendedRetirePitcherIds.length} 名がチームから消えた');

  // 新人野手が引退者の背番号で加入していること
  final allMyPlayers = [
    ...c.myTeam.players,
    ...c.myTeam.bench,
    ...c.myTeam.startingRotation,
    ...c.myTeam.bullpen,
  ];
  for (int i = 0; i < plan.recommendedTakeFielderIds.length; i++) {
    final rookieId = plan.recommendedTakeFielderIds[i];
    final expectedNumber = retiredFielderNumbers[i];
    final type = plan.rookieFielderTypeOf(rookieId);
    final rookie =
        allMyPlayers.firstWhere((p) => p.id == rookieId, orElse: () {
      throw '新人野手 $rookieId がチームに加入していない';
    });
    if (rookie.number != expectedNumber) {
      throw '新人野手 ${rookie.name} の背番号 ${rookie.number} '
          '!= 引退者の背番号 $expectedNumber';
    }
    print('OK: [${type?.displayName}] ${rookie.name} (${rookie.age}歳) '
        'が背番号 ${rookie.number} で加入');
  }
  for (int i = 0; i < plan.recommendedTakePitcherIds.length; i++) {
    final rookieId = plan.recommendedTakePitcherIds[i];
    final expectedNumber = retiredPitcherNumbers[i];
    final wasStarter = retiredPitcherWasStarter[retiredPitcherIds[i]]!;
    final expectedRole = wasStarter
        ? null
        : (retiredPitcherReliefRoles[retiredPitcherIds[i]]);
    final type = plan.rookiePitcherTypeOf(rookieId);
    final rookie =
        allMyPlayers.firstWhere((p) => p.id == rookieId, orElse: () {
      throw '新人投手 $rookieId がチームに加入していない';
    });
    if (rookie.number != expectedNumber) {
      throw '新人投手 ${rookie.name} の背番号 ${rookie.number} '
          '!= 引退者の背番号 $expectedNumber';
    }
    final inStarter = c.myTeam.startingRotation.any((p) => p.id == rookieId);
    if (wasStarter && !inStarter) {
      throw '新人投手 ${rookie.name} が先発ローテに入っていない（引退者は先発）';
    }
    if (!wasStarter && inStarter) {
      throw '新人投手 ${rookie.name} が先発ローテに入っている（引退者は救援）';
    }
    print('OK: [${type?.displayName}] ${rookie.name} (${rookie.age}歳) '
        'が背番号 ${rookie.number} / ${wasStarter ? "先発" : "救援"} で加入'
        '${expectedRole != null ? " (${expectedRole.name} ロール継承を期待)" : ""}');
  }

  // (d) シーズン 2 を完走
  print('\n--- シーズン 2 シミュレート ---');
  c.advanceAll();
  print('完走 OK');

  // (e) selection なしの commit は自チームを変えない
  final beforeIds =
      c.myTeam.players.map((p) => p.id).toList(growable: false);
  c.commitOffseason();
  final afterIds = c.myTeam.players.map((p) => p.id).toList(growable: false);
  // 加齢で player object は差し替わるが id は同じはず
  if (!_listEq(afterIds, beforeIds)) {
    throw 'selection なしの commit で自チーム選手 id が変わっている';
  }
  print('\nOK: selection 省略時の commit は自チームの id 構成を変えない');
  print('シーズン: ${c.seasonYear} 年目');

  print('\n=== 全テスト OK ===');
}

bool _listEq(Iterable<String> a, List<String> b) {
  final la = a.toList();
  if (la.length != b.length) return false;
  for (int i = 0; i < la.length; i++) {
    if (la[i] != b[i]) return false;
  }
  return true;
}

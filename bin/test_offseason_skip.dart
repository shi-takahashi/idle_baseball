// オフシーズン進行 OFF の動作確認。
// 1. シーズン1完走 → offseasonProgressionEnabled = false で commitOffseason
//    → 全選手の id・年齢・能力（toJson 全フィールド）が変化していないこと
// 2. シーズン2完走 → 同じ flag のまま commit → 同じく不変
// 3. JSON 往復で flag が保存・復元されることを確認
// 4. flag を true に戻して commit → 加齢が発生する（年齢 +1 が観測される）こと
//
// 実行: dart run bin/test_offseason_skip.dart
import 'dart:convert';
import 'dart:math';

import 'package:idle_baseball/engine/engine.dart';

/// 全チーム・全在籍選手（players + rotation + bullpen + bench）を id 重複排除して返す。
Map<String, Map<String, dynamic>> _snapshotAllPlayers(SeasonController c) {
  final result = <String, Map<String, dynamic>>{};
  for (final team in c.teams) {
    for (final p in [
      ...team.players,
      ...team.startingRotation,
      ...team.bullpen,
      ...team.bench,
    ]) {
      result[p.id] = p.toJson();
    }
  }
  return result;
}

/// 2 つのスナップショットを比較し、差分の概要を表示する。
/// 返り値: 完全一致なら true。
bool _compareSnapshots(
  Map<String, Map<String, dynamic>> before,
  Map<String, Map<String, dynamic>> after, {
  required String label,
}) {
  final added = after.keys.where((id) => !before.containsKey(id)).toList();
  final removed = before.keys.where((id) => !after.containsKey(id)).toList();
  final changed = <String>[];
  for (final id in before.keys) {
    if (!after.containsKey(id)) continue;
    if (jsonEncode(before[id]) != jsonEncode(after[id])) {
      changed.add(id);
    }
  }
  print('[$label] 追加: ${added.length} / 削除: ${removed.length} / '
      '変更: ${changed.length} (合計 ${before.length} 名)');
  if (changed.isNotEmpty) {
    final sample = changed.first;
    print('  例: $sample');
    print('    before: ${before[sample]}');
    print('    after : ${after[sample]}');
  }
  if (added.isNotEmpty) {
    print('  追加 id 例: ${added.take(3).toList()}');
  }
  if (removed.isNotEmpty) {
    print('  削除 id 例: ${removed.take(3).toList()}');
  }
  return added.isEmpty && removed.isEmpty && changed.isEmpty;
}

void main() {
  // ---- (1) OFF で 1 シーズン → 不変確認 ----
  final c = SeasonController.newSeason(
    random: Random(42),
    offseasonProgressionEnabled: false,
  );
  print('seasonYear=${c.seasonYear}, '
      'offseasonProgressionEnabled=${c.offseasonProgressionEnabled}');

  final before = _snapshotAllPlayers(c);
  print('シーズン1 開始時の在籍選手: ${before.length} 名');

  c.advanceAll();
  c.commitOffseason();

  final afterFirst = _snapshotAllPlayers(c);
  print('\n[Round 1] OFF で commitOffseason 後');
  final ok1 = _compareSnapshots(before, afterFirst, label: 'OFF round 1');
  print('seasonYear=${c.seasonYear} (期待: 2)');
  print('currentDay=${c.currentDay} (期待: 0)');

  // ---- (2) OFF のまま 2 シーズン目も同様 ----
  c.advanceAll();
  c.commitOffseason();

  final afterSecond = _snapshotAllPlayers(c);
  print('\n[Round 2] OFF で commitOffseason 後 (シーズン2 → 3)');
  final ok2 = _compareSnapshots(before, afterSecond, label: 'OFF round 2');
  print('seasonYear=${c.seasonYear} (期待: 3)');

  // ---- (3) JSON 往復で flag が保存される ----
  final json = c.toJson();
  print('\n[JSON] offseasonProgressionEnabled in toJson: '
      '${json['offseasonProgressionEnabled']}');
  final restored = SeasonController.fromJson(jsonDecode(jsonEncode(json))
      as Map<String, dynamic>);
  print('  復元後: ${restored.offseasonProgressionEnabled} (期待: false)');
  final ok3 = restored.offseasonProgressionEnabled == false;

  // ---- (4) flag を ON に戻すと、次の commit で加齢が発生 ----
  restored.offseasonProgressionEnabled = true;
  print('\n[ON 復帰] enabled=${restored.offseasonProgressionEnabled}');

  // 一例のサンプル選手の年齢 before
  final sampleId = before.keys.first;
  final ageBefore = restored.teams
      .expand((t) => [
            ...t.players,
            ...t.startingRotation,
            ...t.bullpen,
            ...t.bench
          ])
      .firstWhere((p) => p.id == sampleId)
      .age;

  restored.advanceAll();
  restored.commitOffseason();

  // commit 後、同じ id の選手がまだ在籍していれば age が +1 されているはず
  final afterAging = _snapshotAllPlayers(restored);
  final stillInLeague = afterAging[sampleId];
  bool ok4;
  if (stillInLeague == null) {
    print('  サンプル選手 $sampleId は引退していて確認不可。'
        '別のサンプルで確認...');
    // 引退してない選手で確認し直す
    final survivor = before.keys.firstWhere(
      (id) => afterAging.containsKey(id),
      orElse: () => '',
    );
    if (survivor.isEmpty) {
      print('  全員入れ替わり？ ありえないので失敗扱い');
      ok4 = false;
    } else {
      final beforeAge = before[survivor]!['age'] as int;
      final afterAge = afterAging[survivor]!['age'] as int;
      print('  survivor=$survivor age $beforeAge → $afterAge '
          '(期待: +1 以上、または potential clamp で同値)');
      ok4 = afterAge >= beforeAge + 1;
    }
  } else {
    final ageAfter = stillInLeague['age'] as int;
    print('  $sampleId age $ageBefore → $ageAfter (期待: +1)');
    ok4 = ageAfter == ageBefore + 1;
  }

  print('\n========== 結果 ==========');
  print('Round 1 (OFF 1回目で不変):  ${ok1 ? "OK" : "NG"}');
  print('Round 2 (OFF 2回目で不変):  ${ok2 ? "OK" : "NG"}');
  print('JSON 往復で flag 保持:       ${ok3 ? "OK" : "NG"}');
  print('ON 復帰で加齢が発生:         ${ok4 ? "OK" : "NG"}');
  final allOk = ok1 && ok2 && ok3 && ok4;
  print('TOTAL: ${allOk ? "PASS" : "FAIL"}');
}

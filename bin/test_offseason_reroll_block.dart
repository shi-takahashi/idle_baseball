import 'dart:math';

import 'package:idle_baseball/engine/engine.dart';

/// アプリ再起動を挟んでも同じ新人候補が表示されることを検証する。
///
/// 想定フロー:
/// 1. シーズン消化 → 終了
/// 2. prepareOffseason() で新人候補 A を生成
/// 3. controller を JSON 化（= セーブ）
/// 4. 新規 controller を JSON から復元（= アプリ再起動）
/// 5. prepareOffseason() を再度呼ぶ → 候補 A と同じ（id 一致）であること
void main() {
  final teams = TeamGenerator(random: Random(42)).generateLeague();
  final schedule = const ScheduleGenerator().generate(teams, halves: 2);
  final controller = SeasonController(
    teams: teams,
    schedule: schedule,
    myTeamId: teams.first.id,
    random: Random(42),
  );
  controller.advanceAll();

  if (!controller.isSeasonOver) {
    throw StateError('シーズンが終了していません');
  }

  // 1回目の生成
  final plan1 = controller.prepareOffseason();
  final rookieFielderIds1 =
      plan1.rookieFielderCandidates.map((c) => c.id).toList();
  final rookiePitcherIds1 =
      plan1.rookiePitcherCandidates.map((c) => c.id).toList();
  print('1回目生成: 新人野手 ${rookieFielderIds1.length}名 / 新人投手 '
      '${rookiePitcherIds1.length}名');

  // セーブ → ロード（アプリ再起動相当）
  final json = controller.toJson();
  final restored = SeasonController.fromJson(json, random: Random(99));

  // 復元後に prepareOffseason を再度呼ぶ
  final plan2 = restored.prepareOffseason();
  final rookieFielderIds2 =
      plan2.rookieFielderCandidates.map((c) => c.id).toList();
  final rookiePitcherIds2 =
      plan2.rookiePitcherCandidates.map((c) => c.id).toList();

  print('復元後生成: 新人野手 ${rookieFielderIds2.length}名 / 新人投手 '
      '${rookiePitcherIds2.length}名');

  // 一致確認
  if (rookieFielderIds1.toString() != rookieFielderIds2.toString()) {
    throw StateError('新人野手 id が一致しません:\n'
        '1回目: $rookieFielderIds1\n'
        '復元後: $rookieFielderIds2');
  }
  if (rookiePitcherIds1.toString() != rookiePitcherIds2.toString()) {
    throw StateError('新人投手 id が一致しません:\n'
        '1回目: $rookiePitcherIds1\n'
        '復元後: $rookiePitcherIds2');
  }

  // 能力値も同じか確認（id だけでなく Player の中身も一致）
  for (int i = 0; i < plan1.rookieFielderCandidates.length; i++) {
    final a = plan1.rookieFielderCandidates[i].player;
    final b = plan2.rookieFielderCandidates[i].player;
    if (a.name != b.name ||
        a.meet != b.meet ||
        a.power != b.power ||
        a.speed != b.speed) {
      throw StateError('新人野手 ${a.name} の能力値が復元で変わりました');
    }
  }
  for (int i = 0; i < plan1.rookiePitcherCandidates.length; i++) {
    final a = plan1.rookiePitcherCandidates[i].player;
    final b = plan2.rookiePitcherCandidates[i].player;
    if (a.name != b.name ||
        a.averageSpeed != b.averageSpeed ||
        a.control != b.control) {
      throw StateError('新人投手 ${a.name} の能力値が復元で変わりました');
    }
  }

  print('OK: アプリ再起動を挟んでも新人候補が一致（リセマラ不可）');
}

import 'dart:math';

import 'package:idle_baseball/engine/engine.dart';

void main() {
  // 1. 各チームに外国人 1+1 が含まれることを確認
  final teams = TeamGenerator(random: Random(42)).generateLeague();
  for (final team in teams) {
    final allPlayers = <Player>{};
    for (final p in [
      ...team.players,
      ...team.startingRotation,
      ...team.bullpen,
      ...team.bench,
    ]) {
      allPlayers.add(p);
    }
    final foreigners = allPlayers.where((p) => p.isForeign).toList();
    final foreignFielders = foreigners.where((p) => !p.isPitcher).length;
    final foreignPitchers = foreigners.where((p) => p.isPitcher).length;
    if (foreignFielders != 1 || foreignPitchers != 1) {
      throw StateError(
          '${team.name}: 外国人野手 $foreignFielders / 投手 $foreignPitchers (期待: 1/1)');
    }
  }
  print('OK: 各チームに外国人野手1人 + 投手1人');

  // 2. シーズンを 5 年回して、外国人の入替が起きているか確認
  final schedule = const ScheduleGenerator().generate(teams, halves: 2);
  final controller = SeasonController(
    teams: teams,
    schedule: schedule,
    myTeamId: teams.first.id,
    random: Random(42),
  );

  // 初期外国人 id を記録
  final initialForeignIds = <String>{};
  for (final team in teams) {
    for (final p in [
      ...team.players,
      ...team.startingRotation,
      ...team.bullpen,
      ...team.bench,
    ]) {
      if (p.isForeign) initialForeignIds.add(p.id);
    }
  }
  print('初期外国人数: ${initialForeignIds.length}');

  for (int year = 0; year < 5; year++) {
    controller.advanceAll();
    controller.advanceToNextSeason();
  }

  // 5 シーズン後の外国人 id
  final finalForeignIds = <String>{};
  for (final team in controller.teams) {
    for (final p in [
      ...team.players,
      ...team.startingRotation,
      ...team.bullpen,
      ...team.bench,
    ]) {
      if (p.isForeign) finalForeignIds.add(p.id);
    }
  }
  final remaining = initialForeignIds.intersection(finalForeignIds);
  final departed = initialForeignIds.difference(finalForeignIds);
  print('5 シーズン後: 残留 ${remaining.length} / 離脱 ${departed.length}');
  print('  期待: 残留 ~33% (5^年で 約 5/12 残存)');

  // 各チームが依然 1+1 を保っているか
  for (final team in controller.teams) {
    final allPlayers = <Player>{};
    for (final p in [
      ...team.players,
      ...team.startingRotation,
      ...team.bullpen,
      ...team.bench,
    ]) {
      allPlayers.add(p);
    }
    final ff = allPlayers.where((p) => p.isForeign && !p.isPitcher).length;
    final fp = allPlayers.where((p) => p.isForeign && p.isPitcher).length;
    if (ff != 1 || fp != 1) {
      throw StateError(
          '${team.name}: 5年後の外国人野手 $ff / 投手 $fp (期待: 1/1)');
    }
  }
  print('OK: 5 シーズン後も各チームに外国人 1+1 維持');

  // 3. JSON 往復で isForeign が保持されるか
  final json = controller.toJson();
  final restored = SeasonController.fromJson(json, random: Random(99));
  final restoredForeignCount = restored.teams.fold<int>(0, (sum, team) {
    final allPlayers = <Player>{};
    for (final p in [
      ...team.players,
      ...team.startingRotation,
      ...team.bullpen,
      ...team.bench,
    ]) {
      allPlayers.add(p);
    }
    return sum + allPlayers.where((p) => p.isForeign).length;
  });
  if (restoredForeignCount != 12) {
    throw StateError(
        '復元後の外国人数: $restoredForeignCount (期待: 6チーム×2 = 12)');
  }
  print('OK: JSON 往復で isForeign 保持');

  print('\n=== 全テスト OK ===');
}

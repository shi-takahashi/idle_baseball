import 'dart:math';

import 'package:idle_baseball/engine/engine.dart';

/// 年度別成績の保持と永続化が正しく動くか検証。
void main() {
  final teams = TeamGenerator(random: Random(42)).generateLeague();
  final schedule = const ScheduleGenerator().generate(teams, halves: 2);
  final controller = SeasonController(
    teams: teams,
    schedule: schedule,
    myTeamId: teams.first.id,
    random: Random(42),
  );

  // 1 シーズン目を完走
  controller.advanceAll();
  if (!controller.isSeasonOver) {
    throw StateError('シーズンが終了していません');
  }
  // この時点ではまだ履歴は空
  if (controller.seasonHistory.isNotEmpty) {
    throw StateError('シーズン未確定で履歴に積まれている');
  }

  // 1 シーズン目の当季成績を控えておく（履歴に積まれたか確認するため）
  final samplePlayerId = teams.first.players.first.id;
  final season1Stats = controller.batterStats[samplePlayerId];
  print('1年目 ${teams.first.players.first.name}: '
      '試${season1Stats?.games ?? 0} ヒット${season1Stats?.hits ?? 0}');

  // 2 シーズン目へ
  controller.advanceToNextSeason();
  if (controller.seasonHistory.length != 1) {
    throw StateError('履歴が 1 件であるべき: ${controller.seasonHistory.length}');
  }
  if (controller.seasonHistory.first.year != 1) {
    throw StateError('1 シーズン目の year は 1');
  }
  // 前年成績を引いて 1 シーズン目と一致するか
  final prev = controller.previousBatterStatsOf(samplePlayerId);
  if (prev == null) {
    throw StateError('前年成績が見つからない');
  }
  if (prev.games != season1Stats?.games || prev.hits != season1Stats?.hits) {
    throw StateError('前年成績が不一致');
  }
  print('OK: 2 年目開幕時に 1 年目の成績が前年として参照できる');

  // 2 シーズン目を完走 → 3 シーズン目へ
  controller.advanceAll();
  controller.advanceToNextSeason();
  if (controller.seasonHistory.length != 2) {
    throw StateError('履歴が 2 件であるべき');
  }
  print('OK: 3 年目開幕時に履歴 2 件保持');

  // JSON 往復で履歴が保持されるか
  final json = controller.toJson();
  final restored = SeasonController.fromJson(json, random: Random(99));
  if (restored.seasonHistory.length != 2) {
    throw StateError('復元後の履歴件数が不一致');
  }
  final restoredPrev = restored.previousBatterStatsOf(samplePlayerId);
  if (restoredPrev == null) {
    throw StateError('復元後に前年成績が引けない');
  }
  // batterHistoryOf で全シーズンの履歴を取れるか
  final history = restored.batterHistoryOf(samplePlayerId);
  print('OK: JSON 往復後も履歴保持。$samplePlayerId の出場履歴数 = ${history.length}');

  print('\n=== 全テスト OK ===');
}

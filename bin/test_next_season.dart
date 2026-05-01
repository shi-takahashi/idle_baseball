// シーズン終了 → 次シーズン進入の動作確認。
// 1. 30 日完走
// 2. advanceToNextSeason() 呼び出し
// 3. Day 0 / シーズン2 で再開できているか
// 4. 統計・結果がリセットされているか
//
// 実行: dart run bin/test_next_season.dart
import 'dart:math';

import 'package:idle_baseball/engine/engine.dart';

void main() {
  final c = SeasonController.newSeason(random: Random(42));

  print('--- 1シーズン目 ---');
  print('seasonYear: ${c.seasonYear}');
  print('currentDay: ${c.currentDay} / ${c.totalDays}');
  print('isSeasonOver: ${c.isSeasonOver}');

  c.advanceAll();

  print('\n--- シーズン1 完走後 ---');
  print('seasonYear: ${c.seasonYear}');
  print('currentDay: ${c.currentDay} / ${c.totalDays}');
  print('isSeasonOver: ${c.isSeasonOver}');

  // 主要統計を取得
  final myTeamStandingS1 = c.standings.records
      .firstWhere((r) => r.team.id == c.myTeamId);
  final season1Wins = myTeamStandingS1.wins;
  final totalGamesS1 = c.batterStats.values.fold<int>(
      0, (sum, s) => sum + s.atBats);
  final hrLeaderS1 = c.batterStats.values
      .reduce((a, b) => a.homeRuns > b.homeRuns ? a : b);

  print('自チーム 勝: $season1Wins');
  print('リーグ全体 atBats 合計: $totalGamesS1');
  print('HR トップ: ${hrLeaderS1.player.name} '
      '(${hrLeaderS1.homeRuns}本)');

  // 次シーズンへ
  c.advanceToNextSeason();

  print('\n--- 2シーズン目開始直後 ---');
  print('seasonYear: ${c.seasonYear}');
  print('currentDay: ${c.currentDay} / ${c.totalDays}');
  print('isSeasonOver: ${c.isSeasonOver}');
  final myTeamStandingS2 = c.standings.records
      .firstWhere((r) => r.team.id == c.myTeamId);
  final season2Wins = myTeamStandingS2.wins;
  final totalGamesS2 = c.batterStats.values
      .fold<int>(0, (sum, s) => sum + s.atBats);
  print('自チーム 勝: $season2Wins (期待: 0)');
  print('リーグ全体 atBats 合計: $totalGamesS2 (期待: 0)');
  print('myStrategy: ${c.myStrategy} (期待: null)');

  // 試合をいくつか進めて統計が積み上がるか
  for (int i = 0; i < 5; i++) {
    c.advanceDay();
  }
  final s2Day5 = c.standings.records
      .firstWhere((r) => r.team.id == c.myTeamId);
  print('\n--- 2シーズン目 Day 5 ---');
  print('自チーム ${s2Day5.wins}勝 ${s2Day5.losses}敗 ${s2Day5.ties}分');
  print('総 atBats: ${c.batterStats.values.fold<int>(0, (sum, s) => sum + s.atBats)}');

  // 検証
  if (c.seasonYear != 2) throw 'seasonYear != 2';
  if (season2Wins != 0) throw 'season2Wins != 0 ($season2Wins)';
  if (totalGamesS2 != 0) throw 'リセット後の atBats が 0 でない ($totalGamesS2)';
  if (c.isSeasonOver) throw '2シーズン目で isSeasonOver=true は不正';
  if (c.totalDays != 30) throw 'totalDays が 30 でない (${c.totalDays})';
  if (c.myStrategy != null) throw 'myStrategy がリセットされていない';

  print('\nOK: シーズン跨ぎが期待通りに動作');
}

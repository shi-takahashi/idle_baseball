import 'dart:math';

import 'package:idle_baseball/engine/engine.dart';

/// 試合日程生成の動作確認
/// - 6チーム生成 → スケジュール生成
/// - 総試合数、日数、各チームのホーム/ビジター数、カードごとの出現回数を検証
/// - 日程一覧を出力
void main() {
  final teams = TeamGenerator(random: Random(42)).generateLeague();
  final schedule = const ScheduleGenerator().generate(teams);

  print('=== スケジュール概要 ===');
  print('総試合数: ${schedule.games.length}');
  print('総日数: ${schedule.totalDays}');
  print('');

  // ---- チームごとのホーム/ビジター数 ----
  print('=== チームごとの試合数 ===');
  for (final team in teams) {
    final home = schedule.games.where((g) => g.homeTeam.id == team.id).length;
    final away = schedule.games.where((g) => g.awayTeam.id == team.id).length;
    print('  ${team.name.padRight(10)}: ${(home + away).toString().padLeft(2)}試合 '
        '(ホーム$home / ビジター$away)');
  }
  print('');

  // ---- カードごとの出現回数 ----
  // key = "<teamId1>|<teamId2>"（idをソートして一意化）
  print('=== カードごとの出現回数 (ホーム-ビジター) ===');
  final cardCounts = <String, ({int aHome, int bHome})>{};
  for (final game in schedule.games) {
    final ids = [game.homeTeam.id, game.awayTeam.id]..sort();
    final key = '${ids[0]}|${ids[1]}';
    final isAHome = game.homeTeam.id == ids[0];
    final current = cardCounts[key] ?? (aHome: 0, bHome: 0);
    cardCounts[key] = isAHome
        ? (aHome: current.aHome + 1, bHome: current.bHome)
        : (aHome: current.aHome, bHome: current.bHome + 1);
  }
  for (final entry in cardCounts.entries) {
    final ids = entry.key.split('|');
    final teamA = teams.firstWhere((t) => t.id == ids[0]);
    final teamB = teams.firstWhere((t) => t.id == ids[1]);
    final counts = entry.value;
    print('  ${teamA.name.padRight(10)} vs ${teamB.name.padRight(10)}: '
        '合計${counts.aHome + counts.bHome}試合 '
        '(${teamA.name}ホーム${counts.aHome} / ${teamB.name}ホーム${counts.bHome})');
  }
  print('');

  // ---- 各チームの対戦相手シーケンスと6連戦チェック ----
  print('=== チームごとの対戦相手シーケンス（3連戦単位） ===');
  for (final team in teams) {
    final dailyOpponent = <String>[];
    for (int day = 1; day <= schedule.totalDays; day++) {
      final game = schedule.games.firstWhere(
        (g) => g.homeTeam.id == team.id || g.awayTeam.id == team.id,
        orElse: () => throw StateError('Day$day に ${team.name} の試合なし'),
      );
      final dayGames = schedule.gamesOnDay(day).where(
          (g) => g.homeTeam.id == team.id || g.awayTeam.id == team.id);
      final g = dayGames.first;
      final opp =
          g.homeTeam.id == team.id ? g.awayTeam.name : g.homeTeam.name;
      final ha = g.homeTeam.id == team.id ? 'H' : 'A';
      dailyOpponent.add('$opp($ha)');
      // gameの使用を抑える(未使用警告回避)
      // ignore: unused_local_variable
      final _ = game;
    }
    // 3日ごとに区切って表示
    final blocks = <String>[];
    for (int i = 0; i < dailyOpponent.length; i += 3) {
      blocks.add(dailyOpponent.sublist(i, i + 3).join('→'));
    }
    print('  ${team.name.padRight(10)}: ${blocks.join(' | ')}');
  }
  print('');

  // ---- 連戦の検証: 4日以上連続で同じ相手がいないかチェック ----
  print('=== 6連戦チェック（4日以上同じ相手と連続しないか） ===');
  bool hasIssue = false;
  for (final team in teams) {
    final opponents = <String>[];
    for (int day = 1; day <= schedule.totalDays; day++) {
      final g = schedule.gamesOnDay(day).firstWhere(
          (g) => g.homeTeam.id == team.id || g.awayTeam.id == team.id);
      opponents
          .add(g.homeTeam.id == team.id ? g.awayTeam.id : g.homeTeam.id);
    }
    // 連続している相手の最大連戦数を計算
    int maxStreak = 1;
    int currentStreak = 1;
    for (int i = 1; i < opponents.length; i++) {
      if (opponents[i] == opponents[i - 1]) {
        currentStreak++;
        if (currentStreak > maxStreak) maxStreak = currentStreak;
      } else {
        currentStreak = 1;
      }
    }
    if (maxStreak > 3) {
      hasIssue = true;
      print('  ❌ ${team.name}: 最大連戦数 $maxStreak');
    } else {
      print('  ✓ ${team.name}: 最大連戦数 $maxStreak');
    }
  }
  if (!hasIssue) print('  → 全チームOK');
  print('');

  // ---- Day 15 時点で各チームと3試合ずつ対戦しているか ----
  print('=== Day 15 時点の対戦回数（各チーム相手と3試合ずつか） ===');
  bool day15Ok = true;
  for (final team in teams) {
    final count = <String, int>{};
    for (int day = 1; day <= 15; day++) {
      final g = schedule.gamesOnDay(day).firstWhere(
          (g) => g.homeTeam.id == team.id || g.awayTeam.id == team.id);
      final oppId = g.homeTeam.id == team.id ? g.awayTeam.id : g.homeTeam.id;
      count[oppId] = (count[oppId] ?? 0) + 1;
    }
    final opps = count.entries
        .map((e) => '${teams.firstWhere((t) => t.id == e.key).name}:${e.value}')
        .join(', ');
    final allThree = count.values.every((v) => v == 3) && count.length == 5;
    if (!allThree) day15Ok = false;
    print('  ${team.name.padRight(10)}: $opps ${allThree ? '✓' : '❌'}');
  }
  if (day15Ok) print('  → 全チームOK（各相手と3試合ずつ）');
  print('');

  // ---- 日程全出力 ----
  print('=== 日程 ===');
  for (int day = 1; day <= schedule.totalDays; day++) {
    final games = schedule.gamesOnDay(day);
    print('[Day ${day.toString().padLeft(2)}]');
    for (final game in games) {
      print('  ${game.awayTeam.name.padRight(10)} @ ${game.homeTeam.name}');
    }
  }
}

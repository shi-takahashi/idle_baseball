import 'dart:math';

import 'package:idle_baseball/engine/engine.dart';

/// 1チームあたりの試合数（30 / 90 / 150）が正しくスケジュールに反映され、
/// 永続化往復・シーズン跨ぎでも保持されることを検証する。
void main() {
  // -- 1. ScheduleGenerator が halves を正しく算出するか
  for (final n in [30, 90, 150]) {
    final halves = ScheduleGenerator.halvesForGamesPerTeam(n);
    final expectedHalves = n ~/ 15;
    if (halves != expectedHalves) {
      throw 'gamesPerTeam=$n の halves が違う (expected=$expectedHalves, actual=$halves)';
    }
  }
  print('OK: ScheduleGenerator.halvesForGamesPerTeam');

  // -- 2. 各試合数で SeasonController を作って totalDays・試合総数を確認
  for (final n in [30, 90, 150]) {
    final c =
        SeasonController.newSeason(random: Random(7), gamesPerTeam: n);
    if (c.gamesPerTeam != n) {
      throw 'gamesPerTeam getter 不一致 ($n vs ${c.gamesPerTeam})';
    }
    if (c.totalDays != n) {
      throw 'totalDays が gamesPerTeam と一致しない (n=$n, totalDays=${c.totalDays})';
    }
    final totalGames = c.schedule.games.length;
    // 6 チーム × n 試合 / 2 (1試合は2チームで構成) = 3n
    if (totalGames != 3 * n) {
      throw '試合総数が想定と違う (n=$n, totalGames=$totalGames, expected=${3 * n})';
    }
    // チーム別出場数も確認
    for (final team in c.teams) {
      final count = c.schedule.games
          .where(
              (g) => g.homeTeam.id == team.id || g.awayTeam.id == team.id)
          .length;
      if (count != n) {
        throw 'チーム ${team.shortName} の試合数が違う (n=$n, count=$count)';
      }
    }
    print('OK: newSeason(gamesPerTeam=$n) → totalDays=${c.totalDays}, '
        'totalGames=$totalGames');
  }

  // -- 3. 永続化往復で gamesPerTeam が保持されるか
  final c = SeasonController.newSeason(random: Random(42), gamesPerTeam: 90);
  for (int i = 0; i < 3; i++) {
    c.advanceDay();
  }
  final json = c.toJson();
  final restored = SeasonController.fromJson(json);
  if (restored.gamesPerTeam != 90) {
    throw 'fromJson 後の gamesPerTeam が違う (${restored.gamesPerTeam})';
  }
  if (restored.totalDays != 90) {
    throw 'fromJson 後の totalDays が違う (${restored.totalDays})';
  }
  print('OK: 永続化往復 (gamesPerTeam=90 → 復元)');

  // -- 4. 旧フォーマット（gamesPerTeam フィールドなし）→ 30 にフォールバック
  final legacy = Map<String, dynamic>.from(json);
  legacy.remove('gamesPerTeam');
  // schedule もデフォルトの 30試合分に差し替えないと整合性が取れないので、
  // 新規 30 試合 controller の schedule を使って合成する
  final fresh30 = SeasonController.newSeason(random: Random(99));
  legacy['schedule'] = fresh30.schedule.toJson();
  legacy['teams'] = [for (final t in fresh30.teams) t.toJson()];
  legacy['players'] = {
    for (final t in fresh30.teams)
      for (final p in [
        ...t.players,
        ...t.startingRotation,
        ...t.bullpen,
        ...t.bench,
      ])
        p.id: p.toJson(),
  };
  legacy['results'] = <String, dynamic>{};
  legacy['standings'] = fresh30.standings.toJson();
  legacy['batterStats'] = <String, dynamic>{};
  legacy['pitcherStats'] = <String, dynamic>{};
  legacy['pitcherFreshness'] = <String, dynamic>{};
  legacy['pitcherLastStartDay'] = <String, dynamic>{};
  legacy['recentForms'] = <String, dynamic>{};
  legacy['batterConditions'] = <String, dynamic>{};
  legacy.remove('myStrategy');
  legacy['currentDay'] = 0;
  final legacyRestored = SeasonController.fromJson(legacy);
  if (legacyRestored.gamesPerTeam != 30) {
    throw '旧フォーマット復元の gamesPerTeam が 30 になっていない '
        '(${legacyRestored.gamesPerTeam})';
  }
  print('OK: 旧フォーマット (gamesPerTeam 欠落) → 30 にフォールバック');

  // -- 5. シーズン跨ぎで gamesPerTeam が継承されるか・指定で更新されるか
  final c2 = SeasonController.newSeason(random: Random(1), gamesPerTeam: 90);
  c2.advanceAll();
  // gamesPerTeam 未指定 → 90 を継承
  c2.commitOffseason();
  if (c2.gamesPerTeam != 90 || c2.totalDays != 90) {
    throw 'commitOffseason() 後の gamesPerTeam が 90 を維持していない '
        '(gamesPerTeam=${c2.gamesPerTeam}, totalDays=${c2.totalDays})';
  }
  // 次は 150 へ変更
  c2.advanceAll();
  c2.commitOffseason(gamesPerTeam: 150);
  if (c2.gamesPerTeam != 150 || c2.totalDays != 150) {
    throw 'commitOffseason(gamesPerTeam: 150) 後が 150 になっていない '
        '(gamesPerTeam=${c2.gamesPerTeam}, totalDays=${c2.totalDays})';
  }
  print('OK: シーズン跨ぎでの継承・上書き');

  // -- 6. 不正値はエラー
  bool caught = false;
  try {
    ScheduleGenerator.halvesForGamesPerTeam(40);
  } on ArgumentError {
    caught = true;
  }
  if (!caught) {
    throw '15 の倍数でない値を弾いていない';
  }
  print('OK: 不正な gamesPerTeam を弾く');

  print('\nすべてのテストが通った');
}

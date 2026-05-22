import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// CPU チームの外国人在籍年数を計測する。
/// 旧版は一律 20% 離脱で平均 5 年在籍。NPB 実態は 1〜2 年が中心。
void main() {
  const numLeagues = 30;
  const numSeasons = 20;

  // 外国人選手 id → 在籍開始年
  // シーズンを跨ぐと選手 id が変わって追跡できないので、別アプローチ:
  // 毎年「離脱した外国人数」を集計し、リーグ全体の在籍年数を割り出す
  int totalForeignDepartures = 0;
  int totalForeignSlotYears = 0; // 1 チーム × 1 年 × 4 枠 = 4 のような累計

  for (int seed = 0; seed < numLeagues; seed++) {
    final c = SeasonController.newSeason(random: Random(seed));
    final myId = c.myTeamId;

    for (int s = 0; s < numSeasons; s++) {
      // 各 CPU チームの現役外国人 id を記録
      final beforeIds = <String, Set<String>>{};
      for (final t in c.teams) {
        if (t.id == myId) continue;
        final ids = <String>{};
        for (final p in [
          ...t.players,
          ...t.startingRotation,
          ...t.bullpen,
          ...t.bench,
        ]) {
          if (p.isForeign) ids.add(p.id);
        }
        beforeIds[t.id] = ids;
        totalForeignSlotYears += ids.length;
      }
      c.advanceAll();
      final plan = c.prepareOffseason();
      final selection = OffseasonSelection.recommended(plan);
      c.commitOffseason(plan: plan, selection: selection);
      // commitOffseason 後、各 CPU チームの新しい外国人 id を比較し、消えた id をカウント
      for (final t in c.teams) {
        if (t.id == myId) continue;
        final afterIds = <String>{};
        for (final p in [
          ...t.players,
          ...t.startingRotation,
          ...t.bullpen,
          ...t.bench,
        ]) {
          if (p.isForeign) afterIds.add(p.id);
        }
        final departed = beforeIds[t.id]!.difference(afterIds);
        totalForeignDepartures += departed.length;
      }
    }
  }

  final avgDepartureRate = totalForeignDepartures / totalForeignSlotYears;
  final avgYears = 1.0 / avgDepartureRate;
  print('CPU チーム外国人離脱率（$numLeagues リーグ × $numSeasons シーズン）:');
  print('  延べ外国人枠年: $totalForeignSlotYears');
  print('  離脱: $totalForeignDepartures');
  print('  離脱率: ${(avgDepartureRate * 100).toStringAsFixed(1)}%');
  print('  平均在籍年数: ${avgYears.toStringAsFixed(2)} 年');
}

import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 複数シーズン経過後にリーグ内の能力分布がどうなっているかを測る。
/// 「9 = 数年に1人の逸材」が定常状態でも維持できているかを確認するのが主目的。
///
/// 目標分布（リーグ 132 野手中の各値の人数感）:
///   9: 0〜2人 (~0.5%)  - 「いる年といない年がある」
///   8: 3〜5人 (~3%)    - 「常時数人、タイトル争いができる」
///   7: 10〜15人 (~9%)  - 「結構いる、優秀レベル」
///   4-6: ~80%          - 「ほとんどここ」
///   1-3: ~7%           - 「かなり少ない」
void main() {
  final cats = ['meet', 'power', 'speed', 'eye', 'fastball', 'control'];
  const snapshots = [1, 5, 10, 20];

  Map<String, Map<int, int>> emptyDist() => {
        for (final c in cats) c: {for (int v = 1; v <= 10; v++) v: 0},
      };

  // snapshot 年ごとの分布
  final dists = {for (final y in snapshots) y: emptyDist()};

  const numLeagues = 30;
  for (int seed = 0; seed < numLeagues; seed++) {
    final c = SeasonController.newSeason(random: Random(seed));
    int year = 1;
    if (snapshots.contains(year)) _collect(c, dists[year]!);
    while (year < snapshots.last) {
      c.advanceAll();
      // 自チームも CPU と同じ推奨引退/新人加入で進める（実機で UI から
      // 「推奨どおりに進める」を選んだ場合と同じ状態）。引数なしで commitOffseason
      // を呼ぶと自チームに引退が走らず、衰え選手が累積して 1〜3 が極端に
      // インフレするので、リーグ全体の定常状態を測るためには必須。
      final plan = c.prepareOffseason();
      final selection = OffseasonSelection.recommended(plan);
      c.commitOffseason(plan: plan, selection: selection);
      year++;
      if (snapshots.contains(year)) _collect(c, dists[year]!);
    }
  }

  print('--- 能力分布の経年変化 ($numLeagues リーグ × 全選手） ---\n');
  for (final cat in cats) {
    print('=== $cat ===');
    final header = StringBuffer('値 |');
    for (final y in snapshots) {
      header.write(' S${y.toString().padLeft(2)}    |');
    }
    print(header.toString());
    for (int v = 1; v <= 10; v++) {
      final row = StringBuffer(' $v |');
      for (final y in snapshots) {
        final n = dists[y]![cat]![v]!;
        final total = dists[y]![cat]!.values.fold<int>(0, (a, b) => a + b);
        final p = total == 0 ? 0.0 : (n / total * 100);
        row.write(' ${p.toStringAsFixed(2).padLeft(5)}% |');
      }
      print(row.toString());
    }
    // 9 単独・8 単独・7 単独の比較行（目標と比べやすく）
    final summary = StringBuffer('1リーグ132野手換算で:\n');
    for (final v in [9, 8, 7]) {
      summary.write('  値$v ');
      for (final y in snapshots) {
        final n = dists[y]![cat]![v]!;
        final total = dists[y]![cat]!.values.fold<int>(0, (a, b) => a + b);
        final p = total == 0 ? 0.0 : (n / total);
        final perLeague = (p * 132).toStringAsFixed(1);
        summary.write('| S$y: ${perLeague.padLeft(4)}人 ');
      }
      summary.write('\n');
    }
    print(summary.toString());
  }
}

void _collect(SeasonController c, Map<String, Map<int, int>> dist) {
  for (final t in c.teams) {
    final all = <Player>[
      ...t.players,
      ...t.startingRotation,
      ...t.bullpen,
      ...t.bench,
    ];
    final seen = <String>{};
    for (final p in all) {
      if (!seen.add(p.id)) continue;
      void add(String key, int? v) {
        if (v == null) return;
        dist[key]![v] = dist[key]![v]! + 1;
      }
      // 投手の打撃は除外（meet/power 等は投手と野手で意味が違う）
      if (p.isPitcher) {
        add('fastball', p.fastball);
        add('control', p.control);
      } else {
        add('meet', p.meet);
        add('power', p.power);
        add('speed', p.speed);
        add('eye', p.eye);
      }
    }
  }
}

import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// ポテンシャル分布 vs 現在値分布 を投手・野手で比較。
///
/// 投手の値9 が野手より少ない原因切り分け:
/// - ポテンシャル 9 数が両者で同じ → 「世代交代速度の差」で現在値が少ない
/// - ポテンシャル 9 数が投手で少ない → 生成段階で差がある
void main() {
  const numLeagues = 30;
  const years = 20;

  final cats = ['eye', 'control'];

  // ポテンシャル分布 vs 現在値分布
  final pot = <String, Map<int, List<double>>>{
    for (final c in cats)
      c: {for (int v = 1; v <= 9; v++) v: <double>[]},
  };
  final cur = <String, Map<int, List<double>>>{
    for (final c in cats)
      c: {for (int v = 1; v <= 9; v++) v: <double>[]},
  };

  // 年齢分布も計測（ピーク年齢層にどれくらい選手がいるか）
  final ageDistByRole = <String, List<int>>{
    'fielder': [],
    'pitcher': [],
  };

  for (int seed = 0; seed < numLeagues; seed++) {
    final c = SeasonController.newSeason(random: Random(seed));
    for (int year = 0; year < years; year++) {
      c.advanceAll();
      final plan = c.prepareOffseason();
      final selection = OffseasonSelection.recommended(plan);
      c.commitOffseason(plan: plan, selection: selection);
    }
    _collect(c, pot, cur, ageDistByRole);
  }

  print('--- ポテンシャル vs 現在値 ($numLeagues リーグ, $years シーズン経過後） ---\n');

  for (final cat in cats) {
    print('=== $cat ===');
    print('値 | ポテンシャル 平均/リーグ | 現在値 平均/リーグ');
    for (int v = 1; v <= 9; v++) {
      final pList = pot[cat]![v]!;
      final cList = cur[cat]![v]!;
      final pMean = pList.fold<double>(0, (a, b) => a + b) / pList.length;
      final cMean = cList.fold<double>(0, (a, b) => a + b) / cList.length;
      print(' $v | ${pMean.toStringAsFixed(2).padLeft(15)} '
          '         | ${cMean.toStringAsFixed(2).padLeft(8)}');
    }
    print('');
  }

  // 年齢分布の比較
  print('--- 年齢分布 (S20 定常状態) ---');
  for (final role in ['fielder', 'pitcher']) {
    final ages = ageDistByRole[role]!;
    final counts = <int, int>{};
    for (final a in ages) {
      counts[a] = (counts[a] ?? 0) + 1;
    }
    print('\n$role:');
    final totalSamples = ages.length;
    for (int a = 18; a <= 40; a++) {
      final count = counts[a] ?? 0;
      final pct = totalSamples == 0 ? 0.0 : count / totalSamples * 100;
      print(' $a歳: ${pct.toStringAsFixed(1).padLeft(4)}%');
    }
  }

  // ピーク年齢層 (26-28) の比率
  print('\n--- ピーク年齢層 (26-28歳) の比率 ---');
  for (final role in ['fielder', 'pitcher']) {
    final ages = ageDistByRole[role]!;
    final peak = ages.where((a) => a >= 26 && a <= 28).length;
    final total = ages.length;
    print('$role: $peak / $total = ${(peak / total * 100).toStringAsFixed(1)}%');
  }
}

void _collect(
  SeasonController c,
  Map<String, Map<int, List<double>>> pot,
  Map<String, Map<int, List<double>>> cur,
  Map<String, List<int>> ageDist,
) {
  final perLeaguePot = <String, Map<int, int>>{
    for (final cat in pot.keys)
      cat: {for (int v = 1; v <= 9; v++) v: 0},
  };
  final perLeagueCur = <String, Map<int, int>>{
    for (final cat in cur.keys)
      cat: {for (int v = 1; v <= 9; v++) v: 0},
  };

  for (final t in c.teams) {
    final all = <Player>[
      ...t.players, ...t.startingRotation, ...t.bullpen, ...t.bench,
    ];
    final seen = <String>{};
    for (final p in all) {
      if (!seen.add(p.id)) continue;
      void addPot(String key, int? v) {
        if (v == null || v < 1 || v > 9) return;
        perLeaguePot[key]![v] = perLeaguePot[key]![v]! + 1;
      }
      void addCur(String key, int? v) {
        if (v == null || v < 1 || v > 9) return;
        perLeagueCur[key]![v] = perLeagueCur[key]![v]! + 1;
      }
      if (p.isPitcher) {
        addPot('control', p.potentials?['control']);
        addCur('control', p.control);
        ageDist['pitcher']!.add(p.age);
      } else {
        addPot('eye', p.potentials?['eye']);
        addCur('eye', p.eye);
        ageDist['fielder']!.add(p.age);
      }
    }
  }
  for (final cat in pot.keys) {
    for (int v = 1; v <= 9; v++) {
      pot[cat]![v]!.add(perLeaguePot[cat]![v]!.toDouble());
      cur[cat]![v]!.add(perLeagueCur[cat]![v]!.toDouble());
    }
  }
}

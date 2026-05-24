import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 投手 vs 野手で値9 の平均人数差が出る原因切り分け。
///
/// 4 通りの条件で比較:
///   A. S1 / 外国人込み: 初期生成のみ、リーグ生成直後
///   B. S1 / 外国人除外: 外国人オフセットの影響を見る
///   C. S20 / 外国人込み: 加齢・引退・新人加入を 20 シーズン回した定常状態
///   D. S20 / 外国人除外: 同上で外国人除外
void main() {
  const numLeagues = 30;
  const targetYears = 20;

  print('=== A. S1 / 外国人込み ===');
  _runScenario(numLeagues: numLeagues, years: 0, includeForeign: true);
  print('\n=== B. S1 / 外国人除外 ===');
  _runScenario(numLeagues: numLeagues, years: 0, includeForeign: false);
  print('\n=== C. S20 / 外国人込み ===');
  _runScenario(numLeagues: numLeagues, years: targetYears, includeForeign: true);
  print('\n=== D. S20 / 外国人除外 ===');
  _runScenario(numLeagues: numLeagues, years: targetYears, includeForeign: false);
}

void _runScenario({
  required int numLeagues,
  required int years,
  required bool includeForeign,
}) {
  final cats = ['meet', 'power', 'speed', 'eye', 'fastball', 'control'];
  final samples = <String, Map<int, List<double>>>{
    for (final c in cats)
      c: {for (int v = 1; v <= 9; v++) v: <double>[]},
  };

  for (int seed = 0; seed < numLeagues; seed++) {
    final c = SeasonController.newSeason(random: Random(seed));
    for (int year = 0; year < years; year++) {
      c.advanceAll();
      final plan = c.prepareOffseason();
      final selection = OffseasonSelection.recommended(plan);
      c.commitOffseason(plan: plan, selection: selection);
    }
    _collect(c, samples, includeForeign);
  }

  // 集計
  // 投手プールサイズと野手プールサイズも記録
  int pitcherCount = 0;
  int fielderCount = 0;
  for (int seed = 0; seed < numLeagues; seed++) {
    final c = SeasonController.newSeason(random: Random(seed));
    for (int year = 0; year < years; year++) {
      c.advanceAll();
      final plan = c.prepareOffseason();
      final selection = OffseasonSelection.recommended(plan);
      c.commitOffseason(plan: plan, selection: selection);
    }
    for (final t in c.teams) {
      final all = <Player>[
        ...t.players, ...t.startingRotation, ...t.bullpen, ...t.bench,
      ];
      final seen = <String>{};
      for (final p in all) {
        if (!seen.add(p.id)) continue;
        if (!includeForeign && p.isForeign) continue;
        if (p.isPitcher) {
          pitcherCount++;
        } else {
          fielderCount++;
        }
      }
    }
    break; // 1 リーグだけ数えれば十分
  }

  print('野手プールサイズ: $fielderCount / 投手プールサイズ: $pitcherCount');
  print('値9 の平均 (人/リーグ) ± sd:');
  for (final cat in cats) {
    final list = samples[cat]![9]!;
    final mean = list.fold<double>(0, (a, b) => a + b) / list.length;
    final variance =
        list.fold<double>(0, (a, b) => a + (b - mean) * (b - mean)) /
            list.length;
    final sd = sqrt(variance);
    print('  $cat: ${mean.toStringAsFixed(2).padLeft(4)} ± '
        '${sd.toStringAsFixed(2)}');
  }
}

void _collect(SeasonController c, Map<String, Map<int, List<double>>> samples,
    bool includeForeign) {
  final perLeague = <String, Map<int, int>>{
    for (final cat in samples.keys)
      cat: {for (int v = 1; v <= 9; v++) v: 0},
  };
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
      if (!includeForeign && p.isForeign) continue;
      void add(String key, int? v) {
        if (v == null || v < 1 || v > 9) return;
        perLeague[key]![v] = perLeague[key]![v]! + 1;
      }
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
  for (final cat in perLeague.keys) {
    for (int v = 1; v <= 9; v++) {
      samples[cat]![v]!.add(perLeague[cat]![v]!.toDouble());
    }
  }
}

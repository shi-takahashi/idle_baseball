import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 定常状態の能力分布を計測する。
///
/// `measure_growth.dart` は S1/S5/S10/S20 のスナップショットだが、各スナップ
/// 1 つは 1 シーズンぶんのサンプルなので、世代交代のばらつきが残る。
/// このスクリプトは S1〜S20 の全シーズンを集計して **平均と sd** を出し、
/// 「定常状態でどれぐらいに落ち着くか」を見る。
///
/// 出力:
///   各能力 × 各値 (1〜9) の「全シーズン平均人数/リーグ ± sd」
void main() {
  final cats = ['meet', 'power', 'speed', 'eye', 'fastball', 'control'];
  const numLeagues = 30;
  const numSeasons = 20;

  // cat -> value -> List<人数/リーグ> (各シーズン × 各リーグぶん)
  final samples = <String, Map<int, List<double>>>{
    for (final c in cats)
      c: {for (int v = 1; v <= 9; v++) v: <double>[]},
  };

  for (int seed = 0; seed < numLeagues; seed++) {
    final c = SeasonController.newSeason(random: Random(seed));
    // S1 (開幕直後)
    _collect(c, samples);
    for (int year = 1; year < numSeasons; year++) {
      c.advanceAll();
      final plan = c.prepareOffseason();
      final selection = OffseasonSelection.recommended(plan);
      c.commitOffseason(plan: plan, selection: selection);
      _collect(c, samples);
    }
  }

  print('--- 定常状態の能力分布 ($numLeagues リーグ × $numSeasons シーズン = '
      '${numLeagues * numSeasons} サンプル/値） ---\n');

  for (final cat in cats) {
    print('=== $cat ===');
    print('値 | 平均 (人/リーグ) | sd     | 最小 | 最大');
    for (int v = 1; v <= 9; v++) {
      final list = samples[cat]![v]!;
      final mean = list.fold<double>(0, (a, b) => a + b) / list.length;
      final variance = list.fold<double>(
              0, (a, b) => a + (b - mean) * (b - mean)) /
          list.length;
      final sd = sqrt(variance);
      final minV = list.reduce((a, b) => a < b ? a : b);
      final maxV = list.reduce((a, b) => a > b ? a : b);
      print(' $v | ${mean.toStringAsFixed(2).padLeft(14)} '
          '| ${sd.toStringAsFixed(2).padLeft(6)} '
          '| ${minV.toStringAsFixed(0).padLeft(4)} '
          '| ${maxV.toStringAsFixed(0).padLeft(4)}');
    }
    print('');
  }
}

void _collect(
    SeasonController c, Map<String, Map<int, List<double>>> samples) {
  // 1 リーグ分の集計
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

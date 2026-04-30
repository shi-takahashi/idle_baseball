// 編集機能で power=10 にした選手の HR 数が、
// 編集なしの power=7〜10 帯の選手と比べて妥当か確認する。
// 同じ選手 id で seed を変えながら複数シーズン回し、HR 分布を見る。

import 'dart:math';

import 'package:idle_baseball/engine/engine.dart';

({int hr, int ab, int hits}) _runOne(int seed, int? editedPower) {
  final c = SeasonController.newSeason(random: Random(seed));
  final team = c.myTeam;
  final target = team.players[0];

  if (editedPower != null) {
    final edited = Player(
      id: target.id,
      name: target.name,
      number: target.number,
      meet: 10,
      power: editedPower,
      speed: target.speed ?? 5,
      eye: 10,
      arm: target.arm ?? 5,
      lead: target.lead,
      fielding: target.fielding,
      bats: target.bats,
    );
    c.updatePlayer(edited);
  }

  c.advanceAll();
  final s = c.batterStats[target.id]!;
  return (hr: s.homeRuns, ab: s.atBats, hits: s.hits);
}

void main() {
  const seeds = [1, 7, 42, 100, 2024];

  print('=== 同じ選手 id で power を変えて 5 seed × 30試合 ===');
  for (final pw in [null, 5, 7, 10]) {
    final results = seeds.map((s) => _runOne(s, pw)).toList();
    final hrAvg =
        results.map((r) => r.hr).reduce((a, b) => a + b) / results.length;
    final abAvg =
        results.map((r) => r.ab).reduce((a, b) => a + b) / results.length;
    final hrRate =
        abAvg == 0 ? 0.0 : results.fold<int>(0, (a, r) => a + r.hr) /
            results.fold<int>(0, (a, r) => a + r.ab);
    final label = pw == null ? '編集なし' : '編集 power=$pw / meet=10 / eye=10';
    print('  $label');
    print('    各seed HR: ${results.map((r) => r.hr).toList()}');
    print('    各seed AB: ${results.map((r) => r.ab).toList()}');
    print('    平均HR=${hrAvg.toStringAsFixed(1)} '
        'AB=${abAvg.toStringAsFixed(0)} '
        'HR率=${(hrRate * 100).toStringAsFixed(2)}%');
  }

  print('\n=== リーグ全体の HR 分布（編集なし、seed=42） ===');
  final c = SeasonController.newSeason(random: Random(42));
  c.advanceAll();
  final all = c.batterStats.values.toList()
    ..sort((a, b) => b.homeRuns.compareTo(a.homeRuns));
  for (final s in all.take(10)) {
    print('  ${s.homeRuns} HR  '
        'power=${s.player.power ?? "-"} '
        'meet=${s.player.meet ?? "-"} '
        'AB=${s.atBats} '
        '${s.player.name} (${s.team.name})');
  }
}

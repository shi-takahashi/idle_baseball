import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';
import 'package:idle_baseball/engine/simulation/at_bat_simulator.dart';

/// 過剰分散の分解計測。各乱数源を 1 つずつ OFF にして、
/// power 9 の HR SD がどれだけ縮むかを測る。
///
/// 仮説: 「打席内乱数」(打球タイプ抽選・打球方向抽選・球速変動など)が
/// SD を膨らませている。コンディション(試合間揺らぎ)とどちらが寄与大きいか。
///
/// 比較対象 (全 40 シーズン × 150 試合, 規定打席400+):
///   0. baseline (現状)
///   1. 投手コンディション OFF
///   2. 野手コンディション OFF
///   3. 1 + 2 (両コンディション OFF)
///   4. + 球速の毎球変動 OFF
///   5. + 打球タイプ抽選 OFF (ゴロ固定)
///   6. + 打球方向抽選 OFF (遊撃/中堅固定)
///
/// power 9 の HR/600PA・SD・理論下限SD を表示。
void main() {
  const numSeasons = 40;
  const gamesPerTeam = 150;
  const minPA = 400;

  // 設定パターン
  final patterns = <String, Map<String, bool>>{
    '0. baseline': {},
    '1. PCond OFF': {'pitcherCond': true},
    '2. BCond OFF': {'batterCond': true},
    '3. 両Cond OFF': {'pitcherCond': true, 'batterCond': true},
    '4. +球速変動 OFF': {
      'pitcherCond': true,
      'batterCond': true,
      'speed': true,
    },
    '5. +打球タイプ OFF': {
      'pitcherCond': true,
      'batterCond': true,
      'speed': true,
      'ballType': true,
    },
    '6. +打球方向 OFF': {
      'pitcherCond': true,
      'batterCond': true,
      'speed': true,
      'ballType': true,
      'direction': true,
    },
  };

  final results = <String, _Result>{};

  for (final entry in patterns.entries) {
    final name = entry.key;
    final flags = entry.value;
    AtBatSimulator.disablePitcherCondition = flags['pitcherCond'] ?? false;
    AtBatSimulator.disableBatterCondition = flags['batterCond'] ?? false;
    AtBatSimulator.disableSpeedVariation = flags['speed'] ?? false;
    AtBatSimulator.disableBattedBallTypeRandomness = flags['ballType'] ?? false;
    AtBatSimulator.disableFieldPositionRandomness = flags['direction'] ?? false;

    final samples = <int, List<_Sample>>{};

    for (int s = 0; s < numSeasons; s++) {
      final teams = TeamGenerator(random: Random(5500 + s)).generateLeague();
      final schedule =
          ScheduleGenerator().generateForGamesPerTeam(teams, gamesPerTeam);
      final controller = SeasonController(
        teams: teams,
        schedule: schedule,
        myTeamId: teams.first.id,
        gamesPerTeam: gamesPerTeam,
        random: Random(5500 + s),
      );
      controller.advanceAll();

      for (final st in controller.batterStats.values) {
        if (st.player.isPitcher) continue;
        if (st.plateAppearances < minPA) continue;
        final p = (st.player.power ?? 5).clamp(1, 10);
        samples
            .putIfAbsent(p, () => [])
            .add(_Sample(st.homeRuns, st.plateAppearances));
      }
    }

    final p9 = samples[9] ?? [];
    final p8 = samples[8] ?? [];
    final p7 = samples[7] ?? [];

    results[name] = _Result(
      p9: _stats(p9),
      p8: _stats(p8),
      p7: _stats(p7),
    );
  }

  // 全 OFF に戻す
  AtBatSimulator.disablePitcherCondition = false;
  AtBatSimulator.disableBatterCondition = false;
  AtBatSimulator.disableSpeedVariation = false;
  AtBatSimulator.disableBattedBallTypeRandomness = false;
  AtBatSimulator.disableFieldPositionRandomness = false;

  print(
      '===== 過剰分散の分解計測 ($numSeasons シーズン × $gamesPerTeam 試合, 打席$minPA+) =====');
  print('');
  print(
      '| パターン                | p7 mean/SD | p8 mean/SD | p9 mean/SD | p9 理論SD | p9 過剰倍率 |');
  print(
      '|-------------------------|------------|------------|------------|-----------|-------------|');
  for (final entry in results.entries) {
    final r = entry.value;
    final theoreticalSd = r.p9.mean == 0
        ? 0.0
        : sqrt(r.p9.mean * (1 - r.p9.mean / r.p9.avgPA));
    final excess = theoreticalSd == 0 ? 0 : r.p9.sd / theoreticalSd;
    print(
        '| ${entry.key.padRight(23)} | ${_fmt(r.p7)} | ${_fmt(r.p8)} | ${_fmt(r.p9)} | ${theoreticalSd.toStringAsFixed(2)}      | ${excess.toStringAsFixed(2)}        |');
  }
}

class _Result {
  final _Stats p7;
  final _Stats p8;
  final _Stats p9;
  _Result({required this.p7, required this.p8, required this.p9});
}

class _Stats {
  final double mean;
  final double sd;
  final int n;
  final double avgPA;
  _Stats(this.mean, this.sd, this.n, this.avgPA);
}

class _Sample {
  final int hr;
  final int pa;
  _Sample(this.hr, this.pa);
}

_Stats _stats(List<_Sample> list) {
  if (list.isEmpty) return _Stats(0, 0, 0, 0);
  final hrs = list.map((e) => e.hr.toDouble()).toList();
  final mean = hrs.reduce((a, b) => a + b) / hrs.length;
  final variance =
      hrs.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
          hrs.length;
  final avgPA = list.map((e) => e.pa).reduce((a, b) => a + b) / list.length;
  return _Stats(mean, sqrt(variance), list.length, avgPA);
}

String _fmt(_Stats s) {
  if (s.n == 0) return ' -    -  ';
  return '${s.mean.toStringAsFixed(1).padLeft(4)} / ${s.sd.toStringAsFixed(1).padLeft(3)}';
}

import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 各チーム・各ポジションで守れる選手の人数を計測する。
///
/// 目標:
///   - 外野: 6 人以上（最低 5 人）
///   - 外野以外: 3 人以上（最低 2 人）
///
/// シーズン開幕時とオフシーズン経過後の両方を確認。
void main() {
  const numTrials = 30;
  print('===== チーム生成時の守備可能人数 ($numTrials リーグ) =====');
  _measureLeagues(numTrials, 'opening');

  print('');
  print('===== オフシーズン 5 回経過後 ($numTrials リーグ) =====');
  _measureAfterSeasons(numTrials, 5);
}

void _measureLeagues(int trials, String label) {
  final stats = <DefensePosition, _Stats>{
    for (final p in DefensePosition.values) p: _Stats(),
  };
  int totalTeams = 0;
  int violationsIdeal = 0;
  int violationsMin = 0;
  final samples = <String>[];

  for (int t = 0; t < trials; t++) {
    final teams = TeamGenerator(random: Random(9000 + t)).generateLeague();
    for (final team in teams) {
      totalTeams++;
      final counts = _countByPosition(team);
      for (final entry in counts.entries) {
        stats[entry.key]!.add(entry.value);
      }
      for (final pos in DefensePosition.values) {
        final count = counts[pos] ?? 0;
        final idealMin = pos == DefensePosition.outfield ? 6 : 3;
        final hardMin = pos == DefensePosition.outfield ? 5 : 2;
        if (count < idealMin) violationsIdeal++;
        if (count < hardMin) {
          violationsMin++;
          if (samples.length < 10) {
            samples.add(
              '  team=${team.shortName} pos=${pos.name} count=$count (min=$hardMin)',
            );
          }
        }
      }
    }
  }

  print('チーム数: $totalTeams');
  print('ポジション別 平均 / min / max:');
  for (final pos in DefensePosition.values) {
    final s = stats[pos]!;
    final idealMin = pos == DefensePosition.outfield ? 6 : 3;
    final hardMin = pos == DefensePosition.outfield ? 5 : 2;
    final mark = s.min < hardMin
        ? ' ❌'
        : s.min < idealMin
            ? ' ⚠'
            : '';
    print('  ${pos.name.padRight(10)} '
        'avg=${s.average.toStringAsFixed(2)} '
        'min=${s.min} max=${s.max} '
        '(ideal=$idealMin, hardmin=$hardMin)$mark');
  }
  print('理想値未満: $violationsIdeal / 最低ライン未満: $violationsMin');
  if (samples.isNotEmpty) {
    print('最低ライン違反サンプル:');
    for (final s in samples) {
      print(s);
    }
  }
}

void _measureAfterSeasons(int trials, int seasons) {
  final stats = <DefensePosition, _Stats>{
    for (final p in DefensePosition.values) p: _Stats(),
  };
  int totalTeams = 0;
  int violationsIdeal = 0;
  int violationsMin = 0;
  final samples = <String>[];

  for (int t = 0; t < trials; t++) {
    final teams = TeamGenerator(random: Random(9000 + t)).generateLeague();
    final schedule = const ScheduleGenerator().generate(teams);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      random: Random(9500 + t),
    );
    for (int y = 0; y < seasons; y++) {
      controller.advanceAll();
      controller.advanceToNextSeason();
    }
    for (final team in controller.teams) {
      totalTeams++;
      final counts = _countByPosition(team);
      for (final entry in counts.entries) {
        stats[entry.key]!.add(entry.value);
      }
      for (final pos in DefensePosition.values) {
        final count = counts[pos] ?? 0;
        final idealMin = pos == DefensePosition.outfield ? 6 : 3;
        final hardMin = pos == DefensePosition.outfield ? 5 : 2;
        if (count < idealMin) violationsIdeal++;
        if (count < hardMin) {
          violationsMin++;
          if (samples.length < 10) {
            samples.add(
              '  team=${team.shortName} year=${y(seasons)} '
              'pos=${pos.name} count=$count (min=$hardMin)',
            );
          }
        }
      }
    }
  }

  print('チーム数: $totalTeams');
  print('ポジション別 平均 / min / max:');
  for (final pos in DefensePosition.values) {
    final s = stats[pos]!;
    final idealMin = pos == DefensePosition.outfield ? 6 : 3;
    final hardMin = pos == DefensePosition.outfield ? 5 : 2;
    final mark = s.min < hardMin
        ? ' ❌'
        : s.min < idealMin
            ? ' ⚠'
            : '';
    print('  ${pos.name.padRight(10)} '
        'avg=${s.average.toStringAsFixed(2)} '
        'min=${s.min} max=${s.max} '
        '(ideal=$idealMin, hardmin=$hardMin)$mark');
  }
  print('理想値未満: $violationsIdeal / 最低ライン未満: $violationsMin');
  if (samples.isNotEmpty) {
    print('最低ライン違反サンプル:');
    for (final s in samples) {
      print(s);
    }
  }
}

String y(int s) => '$s';

Map<DefensePosition, int> _countByPosition(Team team) {
  final counts = <DefensePosition, int>{};
  final allFielders = <Player>[
    ...team.players.where((p) => !p.isPitcher),
    ...team.bench.where((p) => !p.isPitcher),
  ];
  for (final p in allFielders) {
    for (final pos in DefensePosition.values) {
      if (p.canPlay(pos)) {
        counts[pos] = (counts[pos] ?? 0) + 1;
      }
    }
  }
  return counts;
}

class _Stats {
  int min = 1 << 30;
  int max = 0;
  int sum = 0;
  int n = 0;

  void add(int v) {
    if (v < min) min = v;
    if (v > max) max = v;
    sum += v;
    n++;
  }

  double get average => n == 0 ? 0 : sum / n;
}

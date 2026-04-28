import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// インヘリット走者の失点が前任投手に正しく計上されることを確認
///
/// シーズン全試合をシミュレートして:
/// 1. 各打席の runsByPitcher の合計 = (rbiCount + batteryErrorRuns)
/// 2. 投手交代があり、かつ責任が前任投手に返っているケースを検出
/// 3. 失点の合計（投手別） = 試合の総得点
void main() {
  final teams = TeamGenerator(random: Random(42)).generateLeague();
  final schedule = const ScheduleGenerator().generate(teams);
  final simulator = SeasonSimulator(random: Random(42));
  final result = simulator.simulate(teams, schedule);

  int totalRunsByGames = 0;
  int totalRunsByPitcher = 0;
  int inheritedScoringEvents = 0;
  int inheritedRuns = 0;
  int rbiVsRunsByPitcherMismatch = 0;

  // サンプルとして数件、インヘリット失点が発生したケースを表示
  final samples = <String>[];

  for (final game in result.games) {
    totalRunsByGames += game.homeScore + game.awayScore;

    for (final half in game.halfInnings) {
      for (final ab in half.atBats) {
        if (ab.isIncomplete) {
          // 未完了打席は通常 runsByPitcher 空のはず
          continue;
        }
        // 期待: rbiCount + battery error 合計 == runsByPitcher 合計
        final batteryRuns = ab.pitches.fold<int>(
          0,
          (sum, p) => sum + (p.batteryError?.runsScored ?? 0),
        );
        final expected = ab.rbiCount + batteryRuns;
        final actual = ab.runsByPitcher.values.fold<int>(0, (s, v) => s + v);
        if (expected != actual) rbiVsRunsByPitcherMismatch++;

        totalRunsByPitcher += actual;

        // 現投手以外に責任が振られた失点をカウント（=インヘリット）
        for (final entry in ab.runsByPitcher.entries) {
          if (entry.key != ab.pitcher.id) {
            inheritedScoringEvents++;
            inheritedRuns += entry.value;
            if (samples.length < 5) {
              samples.add(
                '  ${game.awayTeamName} vs ${game.homeTeamName} '
                '${ab.inning}回${ab.isTop ? "表" : "裏"}: '
                '${ab.pitcher.name} がマウンド時に '
                '${entry.value}失点 → 前任投手 ${entry.key} に計上',
              );
            }
          }
        }
      }
    }
  }

  print('総試合得点: $totalRunsByGames');
  print('runsByPitcher 合計: $totalRunsByPitcher');
  print('rbiCount+battery と runsByPitcher の不一致: $rbiVsRunsByPitcherMismatch 打席');
  print('');
  print('インヘリット失点イベント: $inheritedScoringEvents 件');
  print('インヘリット失点合計: $inheritedRuns');
  print('（試合得点に対する割合: '
      '${(inheritedRuns / totalRunsByGames * 100).toStringAsFixed(1)}%）');
  print('');
  print('サンプル:');
  for (final s in samples) {
    print(s);
  }

  // 投手別失点合計の整合性
  int sumPitcherRunsAllowed = 0;
  for (final p in result.pitcherStats.values) {
    sumPitcherRunsAllowed += p.runsAllowed;
  }
  print('');
  print('投手別 runsAllowed 合計: $sumPitcherRunsAllowed');
  print('（試合得点と一致: ${sumPitcherRunsAllowed == totalRunsByGames ? "✓" : "✗"}）');
}

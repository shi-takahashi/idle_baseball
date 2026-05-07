import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 1 打席内での「同球種連続」の最大数を計測する。
/// 例: ストレート→ストレート→スライダー→ストレート の打席は最大連続 2。
/// 145km/h 級のストレートを 6 球連続で投げる打席が頻出していたため、
/// 同球種連続ペナルティ導入後に分布がどう変わるかを確認する。
void main() {
  const numSeasons = 3;
  final maxStreakCounts = <int, int>{};
  final fastballStreakCounts = <int, int>{};
  int totalAtBats = 0;
  int totalPitches = 0;
  int totalFastballs = 0;

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(8000 + s)).generateLeague();
    final schedule = const ScheduleGenerator().generate(teams);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      random: Random(9000 + s),
    );
    controller.advanceAll();

    for (final sg in schedule.games) {
      final result = controller.resultFor(sg.gameNumber);
      if (result == null) continue;

      for (final half in result.halfInnings) {
        for (final atBat in half.atBats) {
          if (atBat.pitches.isEmpty) continue;
          totalAtBats++;
          totalPitches = totalPitches + atBat.pitches.length;

          int currentStreak = 1;
          int maxStreak = 1;
          PitchType? lastType = atBat.pitches.first.pitchType;
          if (lastType == PitchType.fastball) totalFastballs++;
          int currentFastballStreak =
              lastType == PitchType.fastball ? 1 : 0;
          int maxFastballStreak = currentFastballStreak;

          for (int i = 1; i < atBat.pitches.length; i++) {
            final t = atBat.pitches[i].pitchType;
            if (t == PitchType.fastball) totalFastballs++;
            if (t == lastType) {
              currentStreak++;
              if (currentStreak > maxStreak) maxStreak = currentStreak;
            } else {
              currentStreak = 1;
            }
            if (t == PitchType.fastball) {
              currentFastballStreak++;
              if (currentFastballStreak > maxFastballStreak) {
                maxFastballStreak = currentFastballStreak;
              }
            } else {
              currentFastballStreak = 0;
            }
            lastType = t;
          }
          maxStreakCounts[maxStreak] = (maxStreakCounts[maxStreak] ?? 0) + 1;
          fastballStreakCounts[maxFastballStreak] =
              (fastballStreakCounts[maxFastballStreak] ?? 0) + 1;
        }
      }
    }
  }

  print('=== 1 打席内 最大同球種連続数の分布 (n=$totalAtBats 打席) ===');
  final sorted = maxStreakCounts.keys.toList()..sort();
  for (final k in sorted) {
    final v = maxStreakCounts[k]!;
    final pct = v / totalAtBats * 100;
    print('  ${k.toString().padLeft(2)} 球連続: '
        '${v.toString().padLeft(6)} (${pct.toStringAsFixed(2).padLeft(5)}%)');
  }

  print('\n=== 1 打席内 最大ストレート連続数の分布 ===');
  final fbSorted = fastballStreakCounts.keys.toList()..sort();
  for (final k in fbSorted) {
    final v = fastballStreakCounts[k]!;
    final pct = v / totalAtBats * 100;
    print('  ${k.toString().padLeft(2)} 球連続: '
        '${v.toString().padLeft(6)} (${pct.toStringAsFixed(2).padLeft(5)}%)');
  }

  final fastballRate = totalFastballs / totalPitches * 100;
  print('\n全球種に占めるストレート率: ${fastballRate.toStringAsFixed(1)}% '
      '(全 $totalPitches 球中 $totalFastballs 球)');
}

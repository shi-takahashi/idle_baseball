import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// リーグ全体の球種配分（ストレート / スライダー / カーブ / スプリット /
/// チェンジアップ）を計測する。
///
/// 「ストレートを投げすぎる」傾向の確認と、配球重み調整後の検証に使う。
void main() {
  const numSeasons = 4;
  final counts = <PitchType, int>{for (final t in PitchType.values) t: 0};
  int totalPitches = 0;

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
          for (final pitch in atBat.pitches) {
            counts[pitch.pitchType] = counts[pitch.pitchType]! + 1;
            totalPitches++;
          }
        }
      }
    }
  }

  const labels = {
    PitchType.fastball: 'ストレート',
    PitchType.slider: 'スライダー',
    PitchType.curveball: 'カーブ',
    PitchType.splitter: 'スプリット',
    PitchType.changeup: 'チェンジアップ',
    PitchType.shoot: 'シュート',
    PitchType.cutter: 'カットボール',
    PitchType.sinker: 'シンカー',
  };

  print('===== リーグ球種配分（$numSeasons シーズン・全 $totalPitches 球） =====');
  print('');
  print(' 球種         | 球数      | 比率');
  print('--------------|-----------|-------');
  for (final t in PitchType.values) {
    final c = counts[t]!;
    final pct = c / totalPitches * 100;
    print(' ${labels[t]!.padRight(12)} '
        '| ${c.toString().padLeft(9)} '
        '| ${pct.toStringAsFixed(1).padLeft(5)}%');
  }
}

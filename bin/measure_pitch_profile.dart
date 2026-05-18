import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 球種ごとの「特徴」が結果に出ているかを計測する。
///
/// 各球種について、1球ごとの結果分布（ボール / 見逃し / 空振り / ファウル /
/// インプレー）、ワイルドピッチ・パスボール率、インプレー時の打球結果
/// （アウト / 安打 / 本塁打）を集計する。
/// 「スプリットは三振を取りやすいが暴投しやすい」のような球種の個性が
/// 観測可能な形で出ているかを確認するのが目的。
void main() {
  const numSeasons = 4;

  final pitches = <PitchType, int>{for (final t in PitchType.values) t: 0};
  final ball = <PitchType, int>{for (final t in PitchType.values) t: 0};
  final looking = <PitchType, int>{for (final t in PitchType.values) t: 0};
  final swinging = <PitchType, int>{for (final t in PitchType.values) t: 0};
  final foul = <PitchType, int>{for (final t in PitchType.values) t: 0};
  final inPlay = <PitchType, int>{for (final t in PitchType.values) t: 0};
  final wp = <PitchType, int>{for (final t in PitchType.values) t: 0};
  final pb = <PitchType, int>{for (final t in PitchType.values) t: 0};

  // インプレー打球のうちゴロになった数（球種別ゴロ傾向の検証用）
  final ground = <PitchType, int>{for (final t in PitchType.values) t: 0};

  // インプレーで打席が決着した球の打球結果
  final contact = <PitchType, int>{for (final t in PitchType.values) t: 0};
  final contactOut = <PitchType, int>{for (final t in PitchType.values) t: 0};
  final contactHit = <PitchType, int>{for (final t in PitchType.values) t: 0};
  final contactHr = <PitchType, int>{for (final t in PitchType.values) t: 0};
  final contactDp = <PitchType, int>{for (final t in PitchType.values) t: 0};

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
            final t = pitch.pitchType;
            pitches[t] = pitches[t]! + 1;
            switch (pitch.type) {
              case PitchResultType.ball:
                ball[t] = ball[t]! + 1;
                break;
              case PitchResultType.strikeLooking:
                looking[t] = looking[t]! + 1;
                break;
              case PitchResultType.strikeSwinging:
                swinging[t] = swinging[t]! + 1;
                break;
              case PitchResultType.foul:
                foul[t] = foul[t]! + 1;
                break;
              case PitchResultType.inPlay:
                inPlay[t] = inPlay[t]! + 1;
                if (pitch.battedBallType == BattedBallType.groundBall) {
                  ground[t] = ground[t]! + 1;
                }
                break;
              case PitchResultType.hitByPitch:
                break;
            }
            final be = pitch.batteryError;
            if (be != null) {
              if (be.type == BatteryErrorType.wildPitch) {
                wp[t] = wp[t]! + 1;
              } else if (be.type == BatteryErrorType.passedBall) {
                pb[t] = pb[t]! + 1;
              }
            }
          }
          // 打席を決着させた球（最終球）がインプレーなら打球結果を集計
          if (atBat.pitches.isNotEmpty) {
            final last = atBat.pitches.last;
            if (last.type == PitchResultType.inPlay) {
              final t = last.pitchType;
              contact[t] = contact[t]! + 1;
              final r = atBat.result;
              if (r == AtBatResultType.homeRun) {
                contactHr[t] = contactHr[t]! + 1;
                contactHit[t] = contactHit[t]! + 1;
              } else if (r.isHit) {
                contactHit[t] = contactHit[t]! + 1;
              } else if (r == AtBatResultType.groundOut ||
                  r == AtBatResultType.flyOut ||
                  r == AtBatResultType.lineOut ||
                  r == AtBatResultType.doublePlay) {
                contactOut[t] = contactOut[t]! + 1;
                if (r == AtBatResultType.doublePlay) {
                  contactDp[t] = contactDp[t]! + 1;
                }
              }
            }
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
    PitchType.changeup: 'チェンジ',
    PitchType.shoot: 'シュート',
    PitchType.cutter: 'カット',
    PitchType.sinker: 'シンカー',
  };

  print('===== 球種ごとの 1 球結果プロファイル（$numSeasons シーズン） =====');
  print('');
  print(' 球種       | 球数   | ボール | 見逃S | 空振S | ファウル | インプレー');
  print('------------|--------|--------|-------|-------|----------|----------');
  for (final t in PitchType.values) {
    final n = pitches[t]!;
    if (n == 0) continue;
    String pct(int x) => (x / n * 100).toStringAsFixed(1).padLeft(5);
    print(' ${labels[t]!.padRight(10)} '
        '| ${n.toString().padLeft(6)} '
        '| ${pct(ball[t]!)}% '
        '| ${pct(looking[t]!)}%'
        '| ${pct(swinging[t]!)}%'
        '| ${pct(foul[t]!)}%  '
        '| ${pct(inPlay[t]!)}%');
  }

  print('');
  print(' 球種       | WP/千球 | PB/千球 | 被アウト | 被安打 | 被本塁打');
  print('            |         |         | (インプレー決着球)         ');
  print('------------|---------|---------|----------|--------|----------');
  for (final t in PitchType.values) {
    final n = pitches[t]!;
    if (n == 0) continue;
    final c = contact[t]!;
    final wpPerK = wp[t]! / n * 1000;
    final pbPerK = pb[t]! / n * 1000;
    String cpct(int x) => c == 0 ? '  -  ' : (x / c * 100).toStringAsFixed(1).padLeft(5);
    print(' ${labels[t]!.padRight(10)} '
        '| ${wpPerK.toStringAsFixed(2).padLeft(7)} '
        '| ${pbPerK.toStringAsFixed(2).padLeft(7)} '
        '| ${cpct(contactOut[t]!)}%   '
        '| ${cpct(contactHit[t]!)}% '
        '| ${cpct(contactHr[t]!)}%');
  }

  print('');
  print(' 球種       | ゴロ率  | 併殺打 | 併殺率（インプレー決着球あたり）');
  print('------------|---------|--------|----------------------------------');
  for (final t in PitchType.values) {
    final ip = inPlay[t]!;
    if (ip == 0) continue;
    final c = contact[t]!;
    final groundPct = ground[t]! / ip * 100;
    final dpPct = c == 0 ? 0.0 : contactDp[t]! / c * 100;
    print(' ${labels[t]!.padRight(10)} '
        '| ${groundPct.toStringAsFixed(1).padLeft(5)}%  '
        '| ${contactDp[t]!.toString().padLeft(6)} '
        '| ${dpPct.toStringAsFixed(2).padLeft(6)}%');
  }
}

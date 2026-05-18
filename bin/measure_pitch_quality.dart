import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 変化球の「質」が、その球を投げた時の被打率・空振り率に直結しているかを計測。
///
/// measure_pitcher_breaking はシーズン成績（全球種混在）で計測するため、特定
/// 球種の質の効果が他の球で希釈される。本スクリプトは「その球種の投球だけ」を
/// 抜き出し、投手の質パラメータごとにビン分けして per-pitch の結果を見る。
/// 例: スライダー質1 の投手とスライダー質9 の投手で、スライダーを投げた時の
/// 被打率に明確な差が出ているか。
int? _param(Player p, PitchType t) {
  switch (t) {
    case PitchType.slider:
      return p.slider;
    case PitchType.curveball:
      return p.curve;
    case PitchType.splitter:
      return p.splitter;
    case PitchType.changeup:
      return p.changeup;
    case PitchType.shoot:
      return p.shoot;
    case PitchType.cutter:
      return p.cutter;
    case PitchType.sinker:
      return p.sinker;
    case PitchType.fastball:
      return p.fastball;
  }
}

void main() {
  const numSeasons = 8;
  const gamesPerTeam = 150;

  const breakingTypes = [
    PitchType.slider,
    PitchType.curveball,
    PitchType.splitter,
    PitchType.changeup,
  ];
  const labels = {
    PitchType.slider: 'スライダー',
    PitchType.curveball: 'カーブ',
    PitchType.splitter: 'スプリット',
    PitchType.changeup: 'チェンジ',
  };

  // pitchType -> param(1..10) -> 集計
  final pitches = {for (final t in breakingTypes) t: List<int>.filled(11, 0)};
  final swinging = {for (final t in breakingTypes) t: List<int>.filled(11, 0)};
  final inPlay = {for (final t in breakingTypes) t: List<int>.filled(11, 0)};
  final contactEnd = {for (final t in breakingTypes) t: List<int>.filled(11, 0)};
  final hits = {for (final t in breakingTypes) t: List<int>.filled(11, 0)};
  final hrs = {for (final t in breakingTypes) t: List<int>.filled(11, 0)};

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(7100 + s)).generateLeague();
    final schedule =
        ScheduleGenerator().generateForGamesPerTeam(teams, gamesPerTeam);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      gamesPerTeam: gamesPerTeam,
      random: Random(7100 + s),
    );
    controller.advanceAll();

    for (final sg in schedule.games) {
      final result = controller.resultFor(sg.gameNumber);
      if (result == null) continue;
      for (final half in result.halfInnings) {
        for (final atBat in half.atBats) {
          final pitcher = atBat.pitcher;
          for (final pitch in atBat.pitches) {
            final t = pitch.pitchType;
            if (t == PitchType.fastball) continue;
            final raw = _param(pitcher, t);
            if (raw == null) continue;
            final v = raw.clamp(1, 10);
            pitches[t]![v]++;
            if (pitch.type == PitchResultType.strikeSwinging) {
              swinging[t]![v]++;
            } else if (pitch.type == PitchResultType.inPlay) {
              inPlay[t]![v]++;
            }
          }
          // 打席を決着させた球がインプレーなら被安打を集計
          if (atBat.pitches.isEmpty) continue;
          final last = atBat.pitches.last;
          if (last.type != PitchResultType.inPlay) continue;
          final t = last.pitchType;
          if (t == PitchType.fastball) continue;
          final raw = _param(pitcher, t);
          if (raw == null) continue;
          final v = raw.clamp(1, 10);
          contactEnd[t]![v]++;
          final r = atBat.result;
          if (r == AtBatResultType.homeRun) {
            hrs[t]![v]++;
            hits[t]![v]++;
          } else if (r.isHit) {
            hits[t]![v]++;
          }
        }
      }
    }
  }

  print('===== 変化球の質 × その球を投げた時の結果'
      '（$numSeasons シーズン × $gamesPerTeam 試合） =====');
  print('空振り率・インプレー率 = その球種の全投球あたり');
  print('被安打率 = 安打 / その球種の全投球（その球で打たれる確率）');
  print('インプレー被打率 = 安打 / その球で決着したインプレー数');

  for (final t in breakingTypes) {
    print('');
    print('--- ${labels[t]} ---');
    print(' 質 | 投球数  | 空振り率 | インプレー率 | 被安打率 | インプレー被打率');
    print('----|---------|----------|--------------|----------|------------------');
    for (int v = 1; v <= 10; v++) {
      final n = pitches[t]![v];
      if (n == 0) {
        print(' ${v.toString().padLeft(2)} |    0    |    -     |      -       |    -     |    -');
        continue;
      }
      final whiff = swinging[t]![v] / n * 100;
      final ipRate = inPlay[t]![v] / n * 100;
      final hitRate = hits[t]![v] / n * 100;
      final ce = contactEnd[t]![v];
      final babip = ce == 0 ? 0.0 : hits[t]![v] / ce;
      print(' ${v.toString().padLeft(2)} '
          '| ${n.toString().padLeft(7)} '
          '| ${whiff.toStringAsFixed(1).padLeft(6)}%  '
          '| ${ipRate.toStringAsFixed(1).padLeft(8)}%    '
          '| ${hitRate.toStringAsFixed(2).padLeft(6)}%  '
          '| ${babip.toStringAsFixed(3).padLeft(8)}');
    }
  }
}

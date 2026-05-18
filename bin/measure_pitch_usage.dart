import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 「得意な球種ほど多く投げる」が成立しているかを計測する。
///
/// 投手ごとに球種別の投球数を集計し、各変化球の質パラメータ値ごとに
/// 「その投手の全投球に占めるその球種の割合」の平均を出す。
/// 質9の球はよく投げ、質1の球はたまにしか投げない、という配球が
/// 出ているかを確認するのが目的。
void main() {
  const numSeasons = 10;
  const gamesPerTeam = 150;

  // pitchKey -> param(1..10) -> [share合計, 投手数]
  final types = <String, int? Function(Player)>{
    'スライダー': (p) => p.slider,
    'カーブ': (p) => p.curve,
    'スプリット': (p) => p.splitter,
    'チェンジ': (p) => p.changeup,
  };
  final typeEnum = <String, PitchType>{
    'スライダー': PitchType.slider,
    'カーブ': PitchType.curveball,
    'スプリット': PitchType.splitter,
    'チェンジ': PitchType.changeup,
  };

  final shareSum = <String, List<double>>{};
  final pitcherCnt = <String, List<int>>{};
  for (final key in types.keys) {
    shareSum[key] = List<double>.filled(11, 0.0);
    pitcherCnt[key] = List<int>.filled(11, 0);
  }

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(8000 + s)).generateLeague();
    final schedule =
        ScheduleGenerator().generateForGamesPerTeam(teams, gamesPerTeam);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      gamesPerTeam: gamesPerTeam,
      random: Random(9000 + s),
    );
    controller.advanceAll();

    // pitcherId -> pitchType -> count
    final counts = <String, Map<PitchType, int>>{};
    for (final sg in schedule.games) {
      final result = controller.resultFor(sg.gameNumber);
      if (result == null) continue;
      for (final half in result.halfInnings) {
        for (final atBat in half.atBats) {
          final pid = atBat.pitcher.id;
          final m = counts.putIfAbsent(pid, () => {});
          for (final pitch in atBat.pitches) {
            m[pitch.pitchType] = (m[pitch.pitchType] ?? 0) + 1;
          }
        }
      }
    }

    final playerById = <String, Player>{
      for (final t in teams)
        for (final p in [
          ...t.players,
          ...t.startingRotation,
          ...t.bullpen,
          ...t.bench,
        ])
          p.id: p,
    };

    for (final entry in counts.entries) {
      final p = playerById[entry.key];
      if (p == null) continue;
      final total = entry.value.values.fold(0, (a, b) => a + b);
      if (total < 200) continue; // 小サンプル除外
      for (final tk in types.entries) {
        final raw = tk.value(p);
        if (raw == null) continue;
        final v = raw.clamp(1, 10);
        final thrown = entry.value[typeEnum[tk.key]!] ?? 0;
        shareSum[tk.key]![v] += thrown / total;
        pitcherCnt[tk.key]![v]++;
      }
    }
  }

  print('===== 変化球の質 × その球種を投げる割合（$numSeasons シーズン） =====');
  print('質パラメータ値ごとに「投手の全投球に占めるその球種の割合」の平均');
  for (final key in types.keys) {
    print('');
    print('--- $key ---');
    print(' 質 | 投手数 | 投球割合');
    print('----|--------|---------');
    for (int v = 1; v <= 10; v++) {
      final c = pitcherCnt[key]![v];
      if (c == 0) {
        print(' ${v.toString().padLeft(2)} |   0    |   -');
        continue;
      }
      final avgShare = shareSum[key]![v] / c * 100;
      print(' ${v.toString().padLeft(2)} '
          '|  ${c.toString().padLeft(4)}  '
          '| ${avgShare.toStringAsFixed(1).padLeft(5)}%');
    }
  }
}

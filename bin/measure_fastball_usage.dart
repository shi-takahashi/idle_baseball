import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// ストレートを投げる比率が投手ごとに変動しているかを計測する。
///
/// 配球の重みは「ストレート: 1.2 + 球速ボーナス + 伸びボーナス」「変化球: 質」で
/// 決まるため、球の速い投手・伸びの良い投手はストレート比率が高く、球が遅く
/// 変化球の質が高い投手は低くなるはず。実際にそうなっているかを、球速帯・伸び
/// 帯ごとのストレート比率の平均で確認する。
void main() {
  const numSeasons = 8;
  const gamesPerTeam = 150;

  // pitcherId -> (球種別カウント, Player)
  final fastballByPitcher = <String, int>{};
  final totalByPitcher = <String, int>{};
  final playerById = <String, Player>{};

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(7700 + s)).generateLeague();
    final schedule =
        ScheduleGenerator().generateForGamesPerTeam(teams, gamesPerTeam);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      gamesPerTeam: gamesPerTeam,
      random: Random(7700 + s),
    );
    controller.advanceAll();

    fastballByPitcher.clear();
    totalByPitcher.clear();
    playerById.clear();

    for (final sg in schedule.games) {
      final result = controller.resultFor(sg.gameNumber);
      if (result == null) continue;
      for (final half in result.halfInnings) {
        for (final atBat in half.atBats) {
          final pid = atBat.pitcher.id;
          playerById[pid] = atBat.pitcher;
          for (final pitch in atBat.pitches) {
            totalByPitcher[pid] = (totalByPitcher[pid] ?? 0) + 1;
            if (pitch.pitchType == PitchType.fastball) {
              fastballByPitcher[pid] = (fastballByPitcher[pid] ?? 0) + 1;
            }
          }
        }
      }
    }

    _accumulate(fastballByPitcher, totalByPitcher, playerById);
  }

  _report();
}

// 球速帯 / 伸び帯ごとの [ストレート比率合計, 投手数]
final _bySpeed = <int, List<num>>{};
final _byRide = <int, List<num>>{};
// 個別投手の最小・最大ストレート比率
double _minShare = 1.0;
double _maxShare = 0.0;
String _minDesc = '';
String _maxDesc = '';

void _accumulate(
  Map<String, int> fastball,
  Map<String, int> total,
  Map<String, Player> players,
) {
  for (final entry in total.entries) {
    final n = entry.value;
    if (n < 300) continue; // 小サンプル除外
    final p = players[entry.key]!;
    final share = (fastball[entry.key] ?? 0) / n;
    final speed = p.averageSpeed ?? 145;
    final ride = p.fastball ?? 5;

    final speedBin = (speed ~/ 3) * 3; // 3km/h 刻み
    _bySpeed.putIfAbsent(speedBin, () => [0.0, 0]);
    _bySpeed[speedBin]![0] += share;
    _bySpeed[speedBin]![1] = (_bySpeed[speedBin]![1] as int) + 1;

    _byRide.putIfAbsent(ride, () => [0.0, 0]);
    _byRide[ride]![0] += share;
    _byRide[ride]![1] = (_byRide[ride]![1] as int) + 1;

    if (share < _minShare) {
      _minShare = share;
      _minDesc = '球速 $speed / 伸び $ride';
    }
    if (share > _maxShare) {
      _maxShare = share;
      _maxDesc = '球速 $speed / 伸び $ride';
    }
  }
}

void _report() {
  print('===== ストレート比率は投手ごとに変動するか =====');
  print('');
  print('--- 球速帯ごとの平均ストレート比率 ---');
  print(' 球速帯     | 投手数 | ストレート比率');
  print('-----------|--------|---------------');
  final speedKeys = _bySpeed.keys.toList()..sort();
  for (final k in speedKeys) {
    final sum = _bySpeed[k]![0] as double;
    final cnt = _bySpeed[k]![1] as int;
    print(' ${k}-${k + 2}km '
        '| ${cnt.toString().padLeft(5)}  '
        '| ${(sum / cnt * 100).toStringAsFixed(1).padLeft(6)}%');
  }

  print('');
  print('--- 伸び（ストレートの質）ごとの平均ストレート比率 ---');
  print(' 伸び | 投手数 | ストレート比率');
  print('------|--------|---------------');
  final rideKeys = _byRide.keys.toList()..sort();
  for (final k in rideKeys) {
    final sum = _byRide[k]![0] as double;
    final cnt = _byRide[k]![1] as int;
    print('  ${k.toString().padLeft(2)}  '
        '| ${cnt.toString().padLeft(5)}  '
        '| ${(sum / cnt * 100).toStringAsFixed(1).padLeft(6)}%');
  }

  print('');
  print('個別投手の振れ幅: '
      '最小 ${(_minShare * 100).toStringAsFixed(1)}% ($_minDesc) 〜 '
      '最大 ${(_maxShare * 100).toStringAsFixed(1)}% ($_maxDesc)');
}

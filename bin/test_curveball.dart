import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// カーブのテスト
void main() {
  print('=== カーブ実装テスト ===\n');

  final random = Random(42);

  // ストレートのみの投手（カーブなし）
  final fastballOnlyPitcher = const Player(
    id: 'fastball_only',
    name: '剛速球太郎',
    number: 18,
    averageSpeed: 150,
    control: 5,
    // curve: null（カーブ投げない）
  );

  // カーブが得意な投手
  final curveballPitcher = const Player(
    id: 'curveball',
    name: 'カーブ職人',
    number: 11,
    averageSpeed: 140,
    control: 5,
    curve: 8, // カーブ8
  );

  // カーブが苦手な投手
  final weakCurvePitcher = const Player(
    id: 'weak_curve',
    name: 'カーブ見習い',
    number: 15,
    averageSpeed: 145,
    control: 5,
    curve: 2, // カーブ2
  );

  // チーム作成
  Team createTeam(Player pitcher, String name) {
    return Team(
      id: name,
      name: name,
      players: [
        pitcher,
        ...List.generate(
          8,
          (i) => Player(
            id: '${name}_$i',
            name: '$name${i + 1}',
            number: i + 1,
            meet: 5,
            power: 5,
            speed: 5,
          ),
        ),
      ],
    );
  }

  final fastballTeam = createTeam(fastballOnlyPitcher, '速球チーム');
  final curveTeam = createTeam(curveballPitcher, 'カーブチーム');
  final weakCurveTeam = createTeam(weakCurvePitcher, '見習いチーム');

  // 対戦相手（普通のチーム）
  final opponent = Team(
    id: 'opponent',
    name: '相手チーム',
    players: [
      const Player(id: 'p', name: '投手', number: 18, averageSpeed: 145, control: 5),
      ...List.generate(
        8,
        (i) => Player(
          id: 'opp_$i',
          name: '相手${i + 1}',
          number: i + 1,
          meet: 5,
          power: 5,
          speed: 5,
        ),
      ),
    ],
  );

  // 各投手で10試合ずつシミュレーション
  void simulateGames(Team pitchingTeam, String label) {
    int totalPitches = 0;
    int fastballs = 0;
    int curveballs = 0;
    int strikeouts = 0;
    int totalAtBats = 0;
    int runsAllowed = 0;
    final curveballSpeeds = <int>[];
    final fastballSpeeds = <int>[];

    for (int i = 0; i < 10; i++) {
      final simulator = GameSimulator(random: Random(random.nextInt(10000)));
      final result = simulator.simulate(pitchingTeam, opponent);

      runsAllowed += result.awayScore;

      for (final half in result.halfInnings.where((h) => h.isTop)) {
        for (final ab in half.atBats) {
          totalAtBats++;
          if (ab.result == AtBatResultType.strikeout) strikeouts++;

          for (final pitch in ab.pitches) {
            totalPitches++;
            if (pitch.pitchType == PitchType.fastball) {
              fastballs++;
              fastballSpeeds.add(pitch.speed);
            } else {
              curveballs++;
              curveballSpeeds.add(pitch.speed);
            }
          }
        }
      }
    }

    print('--- $label ---');
    print('  総投球数: $totalPitches');
    print('  ストレート: $fastballs (${(fastballs / totalPitches * 100).toStringAsFixed(1)}%)');
    print('  カーブ: $curveballs (${(curveballs / totalPitches * 100).toStringAsFixed(1)}%)');
    if (fastballSpeeds.isNotEmpty) {
      final avgFastball = fastballSpeeds.reduce((a, b) => a + b) / fastballSpeeds.length;
      print('  ストレート平均球速: ${avgFastball.toStringAsFixed(1)} km/h');
    }
    if (curveballSpeeds.isNotEmpty) {
      final avgCurve = curveballSpeeds.reduce((a, b) => a + b) / curveballSpeeds.length;
      print('  カーブ平均球速: ${avgCurve.toStringAsFixed(1)} km/h');
    }
    print('  三振: $strikeouts / $totalAtBats (${(strikeouts / totalAtBats * 100).toStringAsFixed(1)}%)');
    print('  失点: $runsAllowed');
    print('');
  }

  simulateGames(fastballTeam, '${fastballOnlyPitcher.name}（球速150km、カーブなし）');
  simulateGames(curveTeam, '${curveballPitcher.name}（球速140km、カーブ8）');
  simulateGames(weakCurveTeam, '${weakCurvePitcher.name}（球速145km、カーブ2）');

  print('=== 期待される結果 ===');
  print('- 速球投手: ストレート100%');
  print('- カーブ職人: カーブ多め、カーブ球速約110km/h');
  print('- カーブ見習い: カーブ少なめ、効果も低い');
}

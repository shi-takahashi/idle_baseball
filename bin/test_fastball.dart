import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// ストレートの質（キレ、ノビ）のテスト
void main() {
  print('=== ストレートの質 実装テスト ===\n');

  final random = Random(42);

  // 球速は普通だが、質の高いストレートを持つ投手
  final qualityPitcher = const Player(
    id: 'quality',
    name: 'キレ職人',
    number: 18,
    averageSpeed: 140, // 球速は遅め
    fastball: 9, // キレ抜群
    control: 5,
  );

  // 球速は速いが、質が低いストレートの投手
  final speedPitcher = const Player(
    id: 'speed',
    name: '剛速球太郎',
    number: 11,
    averageSpeed: 155, // 球速は速い
    fastball: 2, // キレは今ひとつ
    control: 5,
  );

  // 球速も質も普通の投手（基準）
  final averagePitcher = const Player(
    id: 'average',
    name: '平均投手',
    number: 15,
    averageSpeed: 145, // 基準球速
    fastball: 5, // 基準質
    control: 5,
  );

  // fastball未設定の投手（nullはデフォルト5として扱う）
  final defaultPitcher = const Player(
    id: 'default',
    name: 'デフォルト投手',
    number: 20,
    averageSpeed: 145,
    // fastball: null（デフォルト）
    control: 5,
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

  final qualityTeam = createTeam(qualityPitcher, 'キレチーム');
  final speedTeam = createTeam(speedPitcher, '剛速球チーム');
  final averageTeam = createTeam(averagePitcher, '基準チーム');
  final defaultTeam = createTeam(defaultPitcher, 'デフォルトチーム');

  // 対戦相手（普通のチーム）
  final opponent = Team(
    id: 'opponent',
    name: '相手チーム',
    players: [
      const Player(
          id: 'p', name: '投手', number: 18, averageSpeed: 145, control: 5),
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
    int strikeouts = 0;
    int totalAtBats = 0;
    int runsAllowed = 0;
    int hits = 0;
    final speeds = <int>[];

    for (int i = 0; i < 10; i++) {
      final simulator = GameSimulator(random: Random(random.nextInt(10000)));
      final result = simulator.simulate(pitchingTeam, opponent);

      runsAllowed += result.awayScore;

      for (final half in result.halfInnings.where((h) => h.isTop)) {
        for (final ab in half.atBats) {
          totalAtBats++;
          if (ab.result == AtBatResultType.strikeout) strikeouts++;
          if (ab.result.isHit) hits++;

          for (final pitch in ab.pitches) {
            totalPitches++;
            if (pitch.pitchType == PitchType.fastball) {
              speeds.add(pitch.speed);
            }
          }
        }
      }
    }

    final avgSpeed = speeds.isNotEmpty
        ? (speeds.reduce((a, b) => a + b) / speeds.length).toStringAsFixed(1)
        : 'N/A';
    final strikeoutRate = (strikeouts / totalAtBats * 100).toStringAsFixed(1);
    final hitRate = (hits / totalAtBats * 100).toStringAsFixed(1);

    print('--- $label ---');
    print('  平均球速: $avgSpeed km/h');
    print('  三振: $strikeouts / $totalAtBats ($strikeoutRate%)');
    print('  被安打: $hits / $totalAtBats ($hitRate%)');
    print('  失点: $runsAllowed');
    print('');
  }

  simulateGames(qualityTeam, '${qualityPitcher.name}（球速140km、質9）');
  simulateGames(speedTeam, '${speedPitcher.name}（球速155km、質2）');
  simulateGames(averageTeam, '${averagePitcher.name}（球速145km、質5）');
  simulateGames(defaultTeam, '${defaultPitcher.name}（球速145km、質null）');

  print('=== 期待される結果 ===');
  print('- キレ職人: 球速は遅いが、質が高いので三振多め、被打率低め');
  print('- 剛速球太郎: 球速は速いが、質が低いので期待より打たれる');
  print('- 平均投手とデフォルト投手: ほぼ同じ結果（デフォルトは基準値5）');
}

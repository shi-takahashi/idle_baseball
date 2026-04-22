import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 併殺打のテスト
void main() {
  print('=== 併殺打テスト ===\n');

  final random = Random(42);

  // 走力1のチーム（鈍足）→ 併殺が多い
  final slowTeam = Team(
    id: 'slow_team',
    name: '鈍足チーム',
    players: List.generate(
      9,
      (i) => Player(
        id: 'slow_$i',
        name: '鈍足${i + 1}',
        number: i + 1,
        meet: 5,
        power: 5,
        speed: 1, // 走力1
      ),
    ),
  );

  // 走力10のチーム（俊足）→ 併殺崩れが多い
  final fastTeam = Team(
    id: 'fast_team',
    name: '俊足チーム',
    players: List.generate(
      9,
      (i) => Player(
        id: 'fast_$i',
        name: '俊足${i + 1}',
        number: i + 1,
        meet: 5,
        power: 5,
        speed: 10, // 走力10
      ),
    ),
  );

  // 対戦相手
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

  // 各チームで10試合ずつシミュレーション
  int slowTeamDoublePlays = 0;
  int slowTeamGroundOuts = 0;
  int fastTeamDoublePlays = 0;
  int fastTeamGroundOuts = 0;

  print('--- 鈍足チーム（走力1）の10試合 ---');
  for (int i = 0; i < 10; i++) {
    final simulator = GameSimulator(random: Random(random.nextInt(10000)));
    final result = simulator.simulate(opponent, slowTeam);

    for (final half in result.halfInnings.where((h) => h.isTop)) {
      for (final ab in half.atBats) {
        if (ab.result == AtBatResultType.doublePlay) {
          slowTeamDoublePlays++;
        }
        if (ab.result == AtBatResultType.groundOut) {
          slowTeamGroundOuts++;
        }
      }
    }
  }
  print('  併殺打: $slowTeamDoublePlays');
  print('  ゴロアウト: $slowTeamGroundOuts');

  print('\n--- 俊足チーム（走力10）の10試合 ---');
  for (int i = 0; i < 10; i++) {
    final simulator = GameSimulator(random: Random(random.nextInt(10000)));
    final result = simulator.simulate(opponent, fastTeam);

    for (final half in result.halfInnings.where((h) => h.isTop)) {
      for (final ab in half.atBats) {
        if (ab.result == AtBatResultType.doublePlay) {
          fastTeamDoublePlays++;
        }
        if (ab.result == AtBatResultType.groundOut) {
          fastTeamGroundOuts++;
        }
      }
    }
  }
  print('  併殺打: $fastTeamDoublePlays');
  print('  ゴロアウト: $fastTeamGroundOuts');

  print('\n=== 結果比較 ===');
  print('鈍足チーム: 併殺打 $slowTeamDoublePlays, ゴロアウト $slowTeamGroundOuts');
  print('俊足チーム: 併殺打 $fastTeamDoublePlays, ゴロアウト $fastTeamGroundOuts');
  print('');
  print('併殺打の差: ${slowTeamDoublePlays - fastTeamDoublePlays}');
  print('（鈍足チームは併殺打が多く、俊足チームは併殺崩れが多いはず）');

  print('\n=== 併殺成功率（理論値） ===');
  print('走力1: ${((0.70 + 0.06 * 4) * 100).toStringAsFixed(0)}%');
  print('走力5: ${(0.70 * 100).toStringAsFixed(0)}%');
  print('走力10: ${((0.70 - 0.06 * 5) * 100).toStringAsFixed(0)}%');
}

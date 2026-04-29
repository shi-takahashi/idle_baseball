import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 内野安打のテスト
void main() {
  print('=== 内野安打テスト ===\n');

  final random = Random(42);

  // 走力1のチーム（鈍足）
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

  // 走力10のチーム（俊足）
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
      const Player(id: 'p', name: '投手', number: 18, averageSpeed: 145, control: 5),
    ],
  );

  // 各チームで10試合ずつシミュレーション
  int slowTeamSingles = 0;
  int slowTeamInfieldHits = 0;
  int slowTeamGroundOuts = 0;
  int fastTeamSingles = 0;
  int fastTeamInfieldHits = 0;
  int fastTeamGroundOuts = 0;

  print('--- 鈍足チーム（走力1）の10試合 ---');
  for (int i = 0; i < 10; i++) {
    final simulator = GameSimulator(random: Random(random.nextInt(10000)));
    final result = simulator.simulate(opponent, slowTeam);

    for (final half in result.halfInnings.where((h) => h.isTop)) {
      for (final ab in half.atBats) {
        if (ab.result == AtBatResultType.single) {
          slowTeamSingles++;
        }
        if (ab.result == AtBatResultType.infieldHit) {
          slowTeamInfieldHits++;
        }
        if (ab.result == AtBatResultType.groundOut) {
          slowTeamGroundOuts++;
        }
      }
    }
  }
  print('  単打: $slowTeamSingles');
  print('  内野安打: $slowTeamInfieldHits');
  print('  ゴロアウト: $slowTeamGroundOuts');

  print('\n--- 俊足チーム（走力10）の10試合 ---');
  for (int i = 0; i < 10; i++) {
    final simulator = GameSimulator(random: Random(random.nextInt(10000)));
    final result = simulator.simulate(opponent, fastTeam);

    for (final half in result.halfInnings.where((h) => h.isTop)) {
      for (final ab in half.atBats) {
        if (ab.result == AtBatResultType.single) {
          fastTeamSingles++;
        }
        if (ab.result == AtBatResultType.infieldHit) {
          fastTeamInfieldHits++;
        }
        if (ab.result == AtBatResultType.groundOut) {
          fastTeamGroundOuts++;
        }
      }
    }
  }
  print('  単打: $fastTeamSingles');
  print('  内野安打: $fastTeamInfieldHits');
  print('  ゴロアウト: $fastTeamGroundOuts');

  print('\n=== 結果比較 ===');
  print('鈍足チーム: 単打 $slowTeamSingles, 内野安打 $slowTeamInfieldHits, ゴロアウト $slowTeamGroundOuts');
  print('俊足チーム: 単打 $fastTeamSingles, 内野安打 $fastTeamInfieldHits, ゴロアウト $fastTeamGroundOuts');
  print('');
  print('内野安打の差: ${fastTeamInfieldHits - slowTeamInfieldHits}');
  print('ゴロアウトの差: ${slowTeamGroundOuts - fastTeamGroundOuts}');
  print('（俊足チームは内野安打が多く、ゴロアウトが少ないはず）');

  print('\n=== 内野安打確率（理論値） ===');
  print('走力1 + ショートゴロ: ${(1 * 0.012 * 1.5 * 100).toStringAsFixed(1)}%');
  print('走力5 + ショートゴロ: ${(5 * 0.012 * 1.5 * 100).toStringAsFixed(1)}%');
  print('走力10 + ショートゴロ: ${(10 * 0.012 * 1.5 * 100).toStringAsFixed(1)}%');
  print('走力10 + ファーストゴロ: ${(10 * 0.012 * 0.3 * 100).toStringAsFixed(1)}%');
}

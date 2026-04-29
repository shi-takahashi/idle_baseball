import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 走力による追加進塁のテスト
void main() {
  // 走力別のテスト
  print('=== 走力による追加進塁テスト ===\n');

  // 同じシードで再現性を確保
  final random = Random(42);

  // 走力1のチーム
  final slowTeam = Team(
    id: 'slow_team',
    name: '鈍足チーム',
    players: List.generate(
      9,
      (i) => Player(
        id: 'slow_$i',
        name: '鈍足${i + 1}',
        number: i + 1,
        meet: 7,
        power: 7,
        speed: 1, // 走力1
      ),
    ),
  );

  // 走力10のチーム
  final fastTeam = Team(
    id: 'fast_team',
    name: '俊足チーム',
    players: List.generate(
      9,
      (i) => Player(
        id: 'fast_$i',
        name: '俊足${i + 1}',
        number: i + 1,
        meet: 7,
        power: 7,
        speed: 10, // 走力10
      ),
    ),
  );

  // 対戦相手（投手）
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
  int slowTeamRuns = 0;
  int fastTeamRuns = 0;
  int slowTeamHits = 0;
  int fastTeamHits = 0;

  print('--- 鈍足チーム（走力1）の10試合 ---');
  for (int i = 0; i < 10; i++) {
    final simulator = GameSimulator(random: Random(random.nextInt(10000)));
    final result = simulator.simulate(opponent, slowTeam);
    slowTeamRuns += result.awayScore;

    for (final half in result.halfInnings.where((h) => h.isTop)) {
      for (final ab in half.atBats) {
        if (ab.result.isHit) slowTeamHits++;
      }
    }
    print('  第${i + 1}試合: ${result.awayScore}点');
  }

  print('\n--- 俊足チーム（走力10）の10試合 ---');
  for (int i = 0; i < 10; i++) {
    final simulator = GameSimulator(random: Random(random.nextInt(10000)));
    final result = simulator.simulate(opponent, fastTeam);
    fastTeamRuns += result.awayScore;

    for (final half in result.halfInnings.where((h) => h.isTop)) {
      for (final ab in half.atBats) {
        if (ab.result.isHit) fastTeamHits++;
      }
    }
    print('  第${i + 1}試合: ${result.awayScore}点');
  }

  print('\n=== 結果比較 ===');
  print('鈍足チーム（走力1）:');
  print('  総得点: $slowTeamRuns (平均: ${(slowTeamRuns / 10).toStringAsFixed(1)}点/試合)');
  print('  安打数: $slowTeamHits');

  print('\n俊足チーム（走力10）:');
  print('  総得点: $fastTeamRuns (平均: ${(fastTeamRuns / 10).toStringAsFixed(1)}点/試合)');
  print('  安打数: $fastTeamHits');

  print('\n差分:');
  print('  得点差: ${fastTeamRuns - slowTeamRuns}点');
  print('  （同じ安打数でも俊足チームの方が得点効率が高いはず）');

  // 追加進塁確率の理論値
  print('\n=== 追加進塁確率（理論値） ===');
  print('走力1: ${1 * 0.05 * 100}%');
  print('走力5: ${5 * 0.05 * 100}%');
  print('走力10: ${10 * 0.05 * 100}%');
}

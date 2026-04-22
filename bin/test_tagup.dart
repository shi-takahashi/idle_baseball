import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// タッチアップのテスト
void main() {
  print('=== タッチアップテスト ===\n');

  final random = Random(42);

  // 走力1のチーム（鈍足）→ タッチアップ試行・成功が少ない
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
        power: 3, // 長打力低めでフライ多め
        speed: 1, // 走力1
      ),
    ),
  );

  // 走力10のチーム（俊足）→ タッチアップ試行・成功が多い
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
        power: 3,
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

  // 各チームで50試合ずつシミュレーション
  int slowTeamFlyOuts = 0;
  int slowTeamRuns = 0;
  int slowTeamTotalOuts = 0;
  int slowTeamAtBats = 0;
  int fastTeamFlyOuts = 0;
  int fastTeamRuns = 0;
  int fastTeamTotalOuts = 0;
  int fastTeamAtBats = 0;

  // 犠牲フライをカウント（3塁ランナーがいる状態でのフライアウト後に得点）
  int slowTeamSacFlies = 0;
  int fastTeamSacFlies = 0;

  print('--- 鈍足チーム（走力1）の50試合 ---');
  for (int i = 0; i < 50; i++) {
    final simulator = GameSimulator(random: Random(random.nextInt(10000)));
    final result = simulator.simulate(opponent, slowTeam);

    slowTeamRuns += result.awayScore;

    for (final half in result.halfInnings.where((h) => h.isTop)) {
      // 各イニングは3アウトで終了（タッチアップ失敗含む）
      slowTeamTotalOuts += 3;
      slowTeamAtBats += half.atBats.length;
      for (final ab in half.atBats) {
        if (ab.result == AtBatResultType.flyOut) {
          slowTeamFlyOuts++;
          // 外野フライで得点があれば犠牲フライとカウント
          if (ab.rbiCount > 0) {
            slowTeamSacFlies++;
          }
        }
      }
    }
  }
  print('  総得点: $slowTeamRuns');
  print('  打席数: $slowTeamAtBats');
  print('  フライアウト: $slowTeamFlyOuts');
  print('  犠牲フライ: $slowTeamSacFlies');
  if (slowTeamFlyOuts > 0) {
    print('  犠牲フライ率: ${(slowTeamSacFlies / slowTeamFlyOuts * 100).toStringAsFixed(1)}%');
  }

  print('\n--- 俊足チーム（走力10）の50試合 ---');
  for (int i = 0; i < 50; i++) {
    final simulator = GameSimulator(random: Random(random.nextInt(10000)));
    final result = simulator.simulate(opponent, fastTeam);

    fastTeamRuns += result.awayScore;

    for (final half in result.halfInnings.where((h) => h.isTop)) {
      fastTeamTotalOuts += 3;
      fastTeamAtBats += half.atBats.length;
      for (final ab in half.atBats) {
        if (ab.result == AtBatResultType.flyOut) {
          fastTeamFlyOuts++;
          if (ab.rbiCount > 0) {
            fastTeamSacFlies++;
          }
        }
      }
    }
  }
  print('  総得点: $fastTeamRuns');
  print('  打席数: $fastTeamAtBats');
  print('  フライアウト: $fastTeamFlyOuts');
  print('  犠牲フライ: $fastTeamSacFlies');
  if (fastTeamFlyOuts > 0) {
    print('  犠牲フライ率: ${(fastTeamSacFlies / fastTeamFlyOuts * 100).toStringAsFixed(1)}%');
  }

  print('\n=== 結果比較 ===');
  print('鈍足チーム: 得点 $slowTeamRuns, 犠牲フライ $slowTeamSacFlies');
  print('俊足チーム: 得点 $fastTeamRuns, 犠牲フライ $fastTeamSacFlies');
  print('');
  print('犠牲フライの差: ${fastTeamSacFlies - slowTeamSacFlies}');
  print('（俊足チームは犠牲フライが多いはず）');

  print('\n=== タッチアップ理論値 ===');
  print('走力1: 試行確率10%, 成功確率40%');
  print('走力5: 試行確率45%, 成功確率65%');
  print('走力10: 試行確率80%, 成功確率95%');
}

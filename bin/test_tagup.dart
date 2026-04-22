import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// タッチアップのテスト
void main() {
  print('=== タッチアップ情報記録テスト ===\n');

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
  int slowTeamTagUpSuccess = 0;
  int slowTeamTagUpFail = 0;
  int fastTeamFlyOuts = 0;
  int fastTeamRuns = 0;
  int fastTeamTagUpSuccess = 0;
  int fastTeamTagUpFail = 0;

  print('--- 鈍足チーム（走力1）の50試合 ---');
  for (int i = 0; i < 50; i++) {
    final simulator = GameSimulator(random: Random(random.nextInt(10000)));
    final result = simulator.simulate(opponent, slowTeam);

    slowTeamRuns += result.awayScore;

    for (final half in result.halfInnings.where((h) => h.isTop)) {
      for (final ab in half.atBats) {
        if (ab.result == AtBatResultType.flyOut) {
          slowTeamFlyOuts++;
        }
        // タッチアップ情報をカウント
        if (ab.hasTagUp) {
          for (final tagUp in ab.tagUps!) {
            if (tagUp.success) {
              slowTeamTagUpSuccess++;
              print('  [鈍足] タッチアップ成功: ${tagUp.runner.name} ${tagUp.fromBase.name}→${tagUp.toBase.name}');
            } else {
              slowTeamTagUpFail++;
              print('  [鈍足] タッチアップ失敗: ${tagUp.runner.name} ${tagUp.fromBase.name}→${tagUp.toBase.name}');
            }
          }
        }
      }
    }
  }
  print('統計:');
  print('  総得点: $slowTeamRuns');
  print('  フライアウト: $slowTeamFlyOuts');
  print('  タッチアップ成功: $slowTeamTagUpSuccess');
  print('  タッチアップ失敗: $slowTeamTagUpFail');

  print('\n--- 俊足チーム（走力10）の50試合 ---');
  for (int i = 0; i < 50; i++) {
    final simulator = GameSimulator(random: Random(random.nextInt(10000)));
    final result = simulator.simulate(opponent, fastTeam);

    fastTeamRuns += result.awayScore;

    for (final half in result.halfInnings.where((h) => h.isTop)) {
      for (final ab in half.atBats) {
        if (ab.result == AtBatResultType.flyOut) {
          fastTeamFlyOuts++;
        }
        // タッチアップ情報をカウント
        if (ab.hasTagUp) {
          for (final tagUp in ab.tagUps!) {
            if (tagUp.success) {
              fastTeamTagUpSuccess++;
              print('  [俊足] タッチアップ成功: ${tagUp.runner.name} ${tagUp.fromBase.name}→${tagUp.toBase.name}');
            } else {
              fastTeamTagUpFail++;
              print('  [俊足] タッチアップ失敗: ${tagUp.runner.name} ${tagUp.fromBase.name}→${tagUp.toBase.name}');
            }
          }
        }
      }
    }
  }
  print('統計:');
  print('  総得点: $fastTeamRuns');
  print('  フライアウト: $fastTeamFlyOuts');
  print('  タッチアップ成功: $fastTeamTagUpSuccess');
  print('  タッチアップ失敗: $fastTeamTagUpFail');

  print('\n=== 結果比較 ===');
  print('鈍足チーム: タッチアップ成功 $slowTeamTagUpSuccess, 失敗 $slowTeamTagUpFail');
  print('俊足チーム: タッチアップ成功 $fastTeamTagUpSuccess, 失敗 $fastTeamTagUpFail');
  print('');
  print('俊足チームはタッチアップが多く、成功率も高いはず');
}

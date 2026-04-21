import 'package:idle_baseball/engine/engine.dart';

void main() {
  // テスト用チームを作成
  final teamA = Team(
    id: 'team_a',
    name: 'タイガース',
    players: List.generate(
      9,
      (i) => Player(id: 'a_$i', name: '選手A${i + 1}', number: i + 1),
    ),
  );

  final teamB = Team(
    id: 'team_b',
    name: 'ジャイアンツ',
    players: List.generate(
      9,
      (i) => Player(id: 'b_$i', name: '選手B${i + 1}', number: i + 1),
    ),
  );

  // 試合シミュレーション
  final simulator = GameSimulator();
  final result = simulator.simulate(teamB, teamA); // homeがB、awayがA

  // スコアボード出力
  print('=== 試合結果 ===\n');
  print(result.toScoreBoard());

  // 勝敗
  if (result.winner != null) {
    print('\n勝者: ${result.winner}');
  } else {
    print('\n引き分け');
  }

  // 各イニングの詳細（最初の2イニングだけ表示）
  print('\n=== イニング詳細（1-2回） ===\n');
  for (final halfInning in result.halfInnings.take(4)) {
    final topBottom = halfInning.isTop ? '表' : '裏';
    print('--- ${halfInning.inning}回$topBottom (${halfInning.runs}点) ---');
    for (final atBat in halfInning.atBats) {
      final fieldPosStr = atBat.fieldPosition != null
          ? ' [${atBat.fieldPosition!.displayName}]'
          : '';
      print(
        '  ${atBat.batter.name}: ${atBat.result.displayName}$fieldPosStr '
        '(${atBat.pitchCount}球, 打点${atBat.rbiCount})',
      );
    }
    print('');
  }

  // 統計情報
  print('=== 統計 ===');
  int totalAtBats = 0;
  int totalHits = 0;
  int totalStrikeouts = 0;
  int totalWalks = 0;
  int totalHomeRuns = 0;
  int totalPitches = 0;

  for (final halfInning in result.halfInnings) {
    for (final atBat in halfInning.atBats) {
      totalAtBats++;
      totalPitches += atBat.pitchCount;
      if (atBat.result.isHit) totalHits++;
      if (atBat.result == AtBatResultType.strikeout) totalStrikeouts++;
      if (atBat.result == AtBatResultType.walk) totalWalks++;
      if (atBat.result == AtBatResultType.homeRun) totalHomeRuns++;
    }
  }

  print('総打席数: $totalAtBats');
  print('総投球数: $totalPitches');
  print('平均球数/打席: ${(totalPitches / totalAtBats).toStringAsFixed(1)}');
  print('安打数: $totalHits (打率: ${(totalHits / totalAtBats).toStringAsFixed(3)})');
  print('三振数: $totalStrikeouts');
  print('四球数: $totalWalks');
  print('本塁打数: $totalHomeRuns');
}

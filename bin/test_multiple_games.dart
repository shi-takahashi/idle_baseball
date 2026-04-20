import 'package:idle_baseball/engine/engine.dart';

void main() {
  // テスト用チームを作成
  // タイガース: 速球派投手 + 強打者ライナップ
  final teamA = Team(
    id: 'team_a',
    name: 'タイガース',
    players: [
      const Player(id: 'a_0', name: '剛速球太郎', number: 18, averageSpeed: 155, control: 4),
      const Player(id: 'a_1', name: '首位打者', number: 1, meet: 8, power: 5),  // 巧打タイプ
      const Player(id: 'a_2', name: '巧打者', number: 2, meet: 7, power: 4),    // 巧打タイプ
      const Player(id: 'a_3', name: '強打者', number: 3, meet: 6, power: 8),    // パワータイプ
      const Player(id: 'a_4', name: '四番打者', number: 4, meet: 7, power: 9),  // 主砲
      const Player(id: 'a_5', name: '中堅打者', number: 5, meet: 6, power: 6),  // バランス
      const Player(id: 'a_6', name: '堅実打者', number: 6, meet: 6, power: 5),  // バランス
      const Player(id: 'a_7', name: '下位打者', number: 7, meet: 5, power: 4),  // 平均
      const Player(id: 'a_8', name: '守備職人', number: 8, meet: 4, power: 3),  // 守備型
    ],
  );

  // ジャイアンツ: 技巧派投手 + 平均的ライナップ
  final teamB = Team(
    id: 'team_b',
    name: 'ジャイアンツ',
    players: [
      const Player(id: 'b_0', name: '技巧派次郎', number: 11, averageSpeed: 138, control: 8),
      const Player(id: 'b_1', name: '一番打者', number: 1, meet: 6, power: 4),
      const Player(id: 'b_2', name: '二番打者', number: 2, meet: 5, power: 3),
      const Player(id: 'b_3', name: '三番打者', number: 3, meet: 6, power: 6),
      const Player(id: 'b_4', name: '四番打者', number: 4, meet: 5, power: 7),  // 四番なのでやや高め
      const Player(id: 'b_5', name: '五番打者', number: 5, meet: 5, power: 5),
      const Player(id: 'b_6', name: '六番打者', number: 6, meet: 4, power: 4),
      const Player(id: 'b_7', name: '七番打者', number: 7, meet: 4, power: 3),
      const Player(id: 'b_8', name: '八番打者', number: 8, meet: 3, power: 2),
    ],
  );

  // 10試合シミュレーション
  final simulator = GameSimulator();

  int totalAtBats = 0;
  int totalHits = 0;
  int totalStrikeouts = 0;
  int totalWalks = 0;
  int totalHomeRuns = 0;
  int totalRuns = 0;
  int teamAWins = 0;
  int teamBWins = 0;
  int draws = 0;

  print('=== 10試合シミュレーション ===\n');

  for (int game = 1; game <= 10; game++) {
    final result = simulator.simulate(teamB, teamA);

    print('第$game試合: ${result.awayTeamName} ${result.awayScore} - ${result.homeScore} ${result.homeTeamName}');

    if (result.awayScore > result.homeScore) {
      teamAWins++;
    } else if (result.homeScore > result.awayScore) {
      teamBWins++;
    } else {
      draws++;
    }

    totalRuns += result.awayScore + result.homeScore;

    for (final halfInning in result.halfInnings) {
      for (final atBat in halfInning.atBats) {
        totalAtBats++;
        if (atBat.result.isHit) totalHits++;
        if (atBat.result == AtBatResultType.strikeout) totalStrikeouts++;
        if (atBat.result == AtBatResultType.walk) totalWalks++;
        if (atBat.result == AtBatResultType.homeRun) totalHomeRuns++;
      }
    }
  }

  print('\n=== 10試合の統計 ===');
  print('タイガース勝利: $teamAWins');
  print('ジャイアンツ勝利: $teamBWins');
  print('引き分け: $draws');
  print('');
  print('総打席数: $totalAtBats');
  print('総得点: $totalRuns (1試合平均: ${(totalRuns / 10).toStringAsFixed(1)}点)');
  print('');
  print('安打数: $totalHits');
  print('打率: ${(totalHits / totalAtBats).toStringAsFixed(3)}');
  print('三振数: $totalStrikeouts (三振率: ${(totalStrikeouts / totalAtBats * 100).toStringAsFixed(1)}%)');
  print('四球数: $totalWalks (四球率: ${(totalWalks / totalAtBats * 100).toStringAsFixed(1)}%)');
  print('本塁打数: $totalHomeRuns');
  print('');
  print('--- 目標値（プロ野球平均） ---');
  print('打率: .250〜.260');
  print('三振率: 18〜20%');
  print('四球率: 8〜9%');
  print('1試合平均得点: 3〜5点');
}

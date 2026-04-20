import 'package:idle_baseball/engine/engine.dart';

void main() {
  // テスト用チームを作成
  // タイガース: 速球派投手（155km、制球力4）
  final teamA = Team(
    id: 'team_a',
    name: 'タイガース',
    players: [
      const Player(id: 'a_0', name: '剛速球太郎', number: 18, averageSpeed: 155, control: 4),
      ...List.generate(
        8,
        (i) => Player(id: 'a_${i + 1}', name: '選手A${i + 2}', number: i + 2),
      ),
    ],
  );

  // ジャイアンツ: 技巧派投手（138km、制球力8）
  final teamB = Team(
    id: 'team_b',
    name: 'ジャイアンツ',
    players: [
      const Player(id: 'b_0', name: '技巧派次郎', number: 11, averageSpeed: 138, control: 8),
      ...List.generate(
        8,
        (i) => Player(id: 'b_${i + 1}', name: '選手B${i + 2}', number: i + 2),
      ),
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

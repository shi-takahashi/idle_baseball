import 'package:idle_baseball/engine/engine.dart';

/// 延長戦、サヨナラ、9回表ゲームセットの動作確認
/// - 100試合回して、延長・サヨナラ・引き分け・9回表終了の出現を確認
void main() {
  final teamA = _makeTeam('tigers', 'タイガース', 'a');
  final teamB = _makeTeam('giants', 'ジャイアンツ', 'b');

  int draws = 0;
  int extraInningGames = 0;
  int walkoffGames = 0; // 9回裏以降、裏で勝ち越して終了（bottom != null の最終イニング）
  int topGameSets = 0; // 9回以降の表でホーム勝ち → 裏スキップ（bottom == null の最終イニング）
  final inningCountDist = <int, int>{};

  const games = 200;
  for (int i = 0; i < games; i++) {
    final simulator = GameSimulator();
    final result = simulator.simulate(teamA, teamB); // homeA, awayB

    final inningCount = result.inningScores.length;
    inningCountDist[inningCount] = (inningCountDist[inningCount] ?? 0) + 1;

    if (inningCount > 9) extraInningGames++;
    if (result.winner == null) draws++;

    // 最終イニングのbottomがnull → 表で試合終了（ホームが勝っていた）
    final lastInning = result.inningScores.last;
    if (lastInning.bottom == null) {
      topGameSets++;
    } else if (inningCount >= 9 && result.homeScore > result.awayScore) {
      // 裏で勝ち越して終了（サヨナラ）を判定: 裏開始前にホームが負けている or 同点だった
      // ここでは緩めに「ホームが勝った試合」として数える
      walkoffGames++;
    }
  }

  print('=== $games試合シミュレーション結果 ===');
  print('延長試合: $extraInningGames');
  print('引き分け: $draws');
  print('ホーム勝ち（9回表で試合終了）: $topGameSets');
  print('ホーム勝ち（裏で決着）: $walkoffGames');
  print('');
  print('イニング数の分布:');
  final sortedKeys = inningCountDist.keys.toList()..sort();
  for (final k in sortedKeys) {
    print('  $k回終了: ${inningCountDist[k]}試合');
  }

  // 代表的な試合を2〜3試合詳しく表示
  print('\n=== サンプル試合 ===');
  for (int i = 0; i < 5; i++) {
    final simulator = GameSimulator();
    final result = simulator.simulate(teamA, teamB);
    print('\n--- 試合${i + 1} ---');
    print(result.toScoreBoard());
    print(
        '最終スコア: ${result.homeTeamName} ${result.homeScore} - ${result.awayScore} ${result.awayTeamName}');
    print('イニング数: ${result.inningScores.length}');
    if (result.winner == null) {
      print('引き分け');
    } else {
      print('勝者: ${result.winner}');
    }
    // 最終イニングのbottom状態
    final last = result.inningScores.last;
    if (last.bottom == null) {
      print('※ ${result.inningScores.length}回裏はなし（表で試合終了）');
    }
  }
}

Team _makeTeam(String id, String name, String prefix) {
  return Team(
    id: id,
    name: name,
    players: List.generate(
      9,
      (i) => Player(
        id: '${prefix}_$i',
        name: '選手${prefix.toUpperCase()}${i + 1}',
        number: i + 1,
        speed: 5,
        averageSpeed: i == 0 ? 145 : null,
        control: i == 0 ? 5 : null,
        fastball: i == 0 ? 5 : null,
        fielding: {
          DefensePosition.catcher: 5,
          DefensePosition.first: 5,
          DefensePosition.second: 5,
          DefensePosition.third: 5,
          DefensePosition.shortstop: 5,
          DefensePosition.outfield: 5,
        },
      ),
    ),
  );
}

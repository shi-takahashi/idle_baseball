// 作戦機能の検証
// - setMyStrategy でセットした打順・守備配置・先発投手が次の試合に反映される
// - 試合後に strategy が消費（クリア）される
// - 投手を 9 番以外に置いてもOK（大谷型ラインナップ）

import 'dart:math';

import 'package:idle_baseball/engine/engine.dart';

void main() {
  final c = SeasonController.newSeason(random: Random(42));
  final team = c.myTeam;

  // オート提案を取得
  final auto = c.suggestedStrategyForMyTeam();
  if (auto == null) {
    print('オート提案が取れませんでした');
    return;
  }
  print('--- オート提案 ---');
  for (int i = 0; i < auto.lineup.length; i++) {
    final p = auto.lineup[i];
    final pos = auto.alignment.entries
        .firstWhere((e) => e.value.id == p.id)
        .key
        .shortName;
    print('  ${i + 1}番 [$pos] ${p.name}');
  }

  // === ケース 1: 1番と4番を入れ替え + 先発を別 SP に ===
  final newLineup = [...auto.lineup];
  final tmp = newLineup[0];
  newLineup[0] = newLineup[3];
  newLineup[3] = tmp;

  final altSP = team.startingRotation
      .firstWhere((p) => p.id != auto.lineup.last.id);

  // 投手を 9 番枠で差し替え（auto では auto.lineup.last が投手）
  final autoPitcherIndex =
      newLineup.indexWhere((p) => p.id == auto.lineup.last.id);
  newLineup[autoPitcherIndex] = altSP;

  final newAlignment = {
    ...auto.alignment,
    FieldPosition.pitcher: altSP,
  };

  final strategy = NextGameStrategy(
    lineup: newLineup,
    alignment: newAlignment,
  );
  c.setMyStrategy(strategy);
  print('\n--- 作戦をセット (case 1: 1↔4 入れ替え + 先発変更) ---');
  print('1番: ${c.myStrategy!.lineup[0].name}');
  print('4番: ${c.myStrategy!.lineup[3].name}');
  print('指定した先発: ${c.myStrategy!.startingPitcher.name}');

  c.advanceDay();

  final myGame = c.schedule.gamesOnDay(1).firstWhere(
      (g) => g.homeTeam.id == c.myTeamId || g.awayTeam.id == c.myTeamId);
  final result = c.resultFor(myGame.gameNumber)!;
  final isHome = myGame.homeTeam.id == c.myTeamId;
  final actualSP =
      isHome ? result.homeTeam.pitcher : result.awayTeam.pitcher;
  print('実際の先発: ${actualSP.name} (指定通り? ${actualSP.id == altSP.id})');

  final actualOrder =
      isHome ? result.homeTeam.players : result.awayTeam.players;
  print('1番: ${actualOrder[0].name} (指定通り? ${actualOrder[0].id == newLineup[0].id})');
  print('4番: ${actualOrder[3].name} (指定通り? ${actualOrder[3].id == newLineup[3].id})');
  // myStrategy は試合後も保持（次の試合で再利用）。SP だけ翌日のオートに更新される。
  print('試合後 myStrategy 保持: ${c.myStrategy != null}');
  if (c.myStrategy != null) {
    print('  打順1番: ${c.myStrategy!.lineup[0].name} '
        '(編集した B のまま?)');
    print('  SP: ${c.myStrategy!.startingPitcher.name} '
        '(次の試合用に再選出されている可能性)');
  }

  // === ケース 2: 投手を 1 番に置く（大谷型）===
  final auto2 = c.suggestedStrategyForMyTeam()!;
  final pitcher2 = auto2.lineup.last; // 9 番投手
  final fielderAtOne = auto2.lineup[0]; // 1番野手
  final ohtaniLineup = [...auto2.lineup];
  // 1 番に投手、9 番に元 1 番野手 を入れ替え
  ohtaniLineup[0] = pitcher2;
  ohtaniLineup[8] = fielderAtOne;

  // alignment はそのまま（pitcher は同じ選手、捕手も同じ選手）
  final ohtaniStrategy = NextGameStrategy(
    lineup: ohtaniLineup,
    alignment: auto2.alignment,
  );
  c.setMyStrategy(ohtaniStrategy);
  print('\n--- 作戦をセット (case 2: 1番投手の大谷型) ---');
  print('1番: ${c.myStrategy!.lineup[0].name} '
      '(投手? ${c.myStrategy!.lineup[0].isPitcher})');
  print('9番: ${c.myStrategy!.lineup[8].name} '
      '(投手? ${c.myStrategy!.lineup[8].isPitcher})');
  print('startingPitcher: ${c.myStrategy!.startingPitcher.name}');

  c.advanceDay();
  final game2 = c.schedule.gamesOnDay(2).firstWhere(
      (g) => g.homeTeam.id == c.myTeamId || g.awayTeam.id == c.myTeamId);
  final result2 = c.resultFor(game2.gameNumber)!;
  final isHome2 = game2.homeTeam.id == c.myTeamId;
  final teamForGame =
      isHome2 ? result2.homeTeam : result2.awayTeam;
  print('1番打者: ${teamForGame.players[0].name} '
      '(投手? ${teamForGame.players[0].isPitcher})');
  print('Team.pitcher (= isPitcher で引いた先発): '
      '${teamForGame.pitcher.name} '
      '打順: ${teamForGame.pitcherBattingIndex + 1} 番');

  // 通常進行に戻る
  c.advanceDay();
  print('\nDay 3 オート進行: 自チーム ${c.standings.records.firstWhere((r) => r.team.id == c.myTeamId).wins} 勝');
}

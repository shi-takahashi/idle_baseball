// 作戦（NextGameStrategy）を保存した状態で選手を編集したとき、
// 編集が自チームの試合シミュレートに反映されるかを検証する。
//
// バグ: updatePlayer は teams 内の Player は差し替えるが、保存済みの
// _myStrategy 内の Player を差し替えていなかった。自チームの試合は
// _applyMyStrategy が strategy.fullLineup から編成するため、編集した
// 選手が旧能力のままシミュレートされていた。

import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

void main() {
  const gamesPerTeam = 150;
  final teams = TeamGenerator(random: Random(42)).generateLeague();
  final schedule =
      ScheduleGenerator().generateForGamesPerTeam(teams, gamesPerTeam);
  final c = SeasonController(
    teams: teams,
    schedule: schedule,
    myTeamId: teams.first.id,
    gamesPerTeam: gamesPerTeam,
    random: Random(42),
  );

  // 自チームのオート編成を作戦として保存する（実プレイで「試合開始」を
  // 押した状態に相当）。
  final suggestion = c.suggestedStrategyForMyTeam();
  if (suggestion == null) {
    print('NG: suggestedStrategyForMyTeam が null');
    return;
  }
  c.setMyStrategy(NextGameStrategy(
    lineup: suggestion.lineup,
    alignment: suggestion.alignment,
  ));

  // 打順の中の野手を 1 人選んで「ミート5 / 長打9 / 選球眼5 / 走力5」に編集。
  final target = c.myStrategy!.lineup.firstWhere((p) => !p.isPitcher);
  print('編集対象: ${target.name} '
      '(編集前 meet=${target.meet} power=${target.power})');

  final edited = Player(
    id: target.id,
    name: target.name,
    number: target.number,
    age: target.age,
    meet: 5,
    power: 9,
    eye: 5,
    speed: 5,
    arm: target.arm,
    fielding: target.fielding,
    bats: target.bats,
    throws: target.throws,
    potentials: target.potentials,
    potentialFielding: target.potentialFielding,
  );
  c.updatePlayer(edited);

  // 作戦内の Player が差し替わっているか
  final inStrategy =
      c.myStrategy!.lineup.firstWhere((p) => p.id == target.id);
  print('作戦内 lineup の power: ${inStrategy.power} '
      '(${inStrategy.power == 9 ? "OK" : "NG ★差し替えされていない"})');
  final inAlign = c.myStrategy!.alignment.values
      .firstWhere((p) => p.id == target.id);
  print('作戦内 alignment の power: ${inAlign.power} '
      '(${inAlign.power == 9 ? "OK" : "NG ★差し替えされていない"})');

  // 全試合シミュレートして編集選手の本塁打を確認
  c.advanceAll();
  final st = c.batterStats[target.id]!;
  print('');
  print('--- $gamesPerTeam 試合終了後の編集選手の成績 ---');
  print('${st.player.name}: 試合=${st.games} 打席=${st.plateAppearances} '
      '打数=${st.atBats} 安打=${st.hits} 本塁打=${st.homeRuns} '
      '打率=${st.battingAverage.toStringAsFixed(3)}');
  print('');
  if (st.homeRuns >= 30) {
    print('OK: 長打9 の編集が試合に反映されている（本塁打 ${st.homeRuns}）');
  } else {
    print('NG: 本塁打 ${st.homeRuns} 本 — 長打9 の編集が反映されていない可能性');
  }
}

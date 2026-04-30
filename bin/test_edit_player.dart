// 編集機能の動作検証用スクリプト
// SeasonController.updatePlayer で全参照が一括差し替えされることを確認する

import 'package:idle_baseball/engine/engine.dart';

void main() {
  final c = SeasonController.newSeason();
  final team = c.myTeam;

  // スタメン野手の1番打者を選んで編集してみる
  final original = team.players[0];
  print('--- 編集前 ---');
  print('${original.name} (#${original.number}) meet=${original.meet} '
      'power=${original.power} speed=${original.speed}');

  final edited = Player(
    id: original.id,
    name: '改造版${original.name}',
    number: 99,
    meet: 10,
    power: 10,
    speed: 10,
    eye: 10,
    arm: 10,
    fielding: original.fielding,
    bats: original.bats,
  );

  bool notified = false;
  c.addListener(() => notified = true);
  c.updatePlayer(edited);

  print('\n--- 編集後 ---');
  print('listener 通知: $notified');

  // 全参照ポイントで差し替えを確認
  final t = c.myTeam;
  final inPlayers = t.players[0];
  print('Team.players[0]: '
      '${inPlayers.name} #${inPlayers.number} meet=${inPlayers.meet}');

  // batterStats も更新されているか
  final bs = c.batterStats[original.id];
  if (bs != null) {
    print('batterStats.player: '
        '${bs.player.name} #${bs.player.number} meet=${bs.player.meet}');
  }

  // findPlayerById
  final fb = c.findPlayerById(original.id);
  print('findPlayerById: ${fb?.name} #${fb?.number} meet=${fb?.meet}');

  // 編集前と同じ id の old Player を覚えていたら、それは古い値のまま（参照）
  print('\n元の参照(original)はそのまま: '
      '${original.name} meet=${original.meet}');

  // 編集後にシーズンを少し進めて、実際に試合に編集後の値が使われるか確認
  c.advanceDay();
  final afterDay = c.findPlayerById(original.id);
  print('\n試合1日進行後: ${afterDay?.name} meet=${afterDay?.meet}');

  // ★ スケジュールに登録されている Team 参照経由でも編集が見えるか
  final upcoming = c.scheduledGamesOnDay(c.currentDay + 1);
  for (final sg in upcoming) {
    final inSched = [
      ...sg.homeTeam.players,
      ...sg.homeTeam.bench,
      ...sg.awayTeam.players,
      ...sg.awayTeam.bench,
    ].where((p) => p.id == original.id).toList();
    if (inSched.isNotEmpty) {
      print('スケジュール上の Team 経由: '
          'name=${inSched.first.name} meet=${inSched.first.meet}');
    }
  }

  // ★ 全試合進めて、編集した選手が試合中に new 能力で出ていることをHRで確認
  c.advanceAll();
  final finalStats = c.batterStats[original.id];
  if (finalStats != null) {
    print('\n--- シーズン全試合終了後の編集選手の打撃成績 ---');
    print('${finalStats.player.name} '
        '打数=${finalStats.atBats} 安打=${finalStats.hits} '
        '本塁打=${finalStats.homeRuns} '
        '打率=${finalStats.battingAverage.toStringAsFixed(3)}');
  }

  // 投手も編集してみる
  final pitcher = team.startingRotation[0];
  print('\n--- 投手編集前 ---');
  print('${pitcher.name} 球速=${pitcher.averageSpeed} '
      'control=${pitcher.control}');

  final editedP = Player(
    id: pitcher.id,
    name: pitcher.name,
    number: pitcher.number,
    averageSpeed: 160,
    fastball: 10,
    control: 10,
    stamina: 10,
    slider: 10,
    curve: 10,
    splitter: 10,
    changeup: 10,
    meet: 5,
    power: 5,
    eye: 5,
    throws: pitcher.throws,
    bats: pitcher.bats,
  );
  c.updatePlayer(editedP);

  final ap = c.findPlayerById(pitcher.id);
  print('--- 投手編集後 ---');
  print('${ap?.name} 球速=${ap?.averageSpeed} control=${ap?.control} '
      'slider=${ap?.slider}');

  // startingRotation 内も差し替わっているか
  final inRot = c.myTeam.startingRotation
      .firstWhere((p) => p.id == pitcher.id);
  print('startingRotation 内: 球速=${inRot.averageSpeed}');
}

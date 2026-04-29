import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 打順と調子による変動を確認するスクリプト
void main() {
  final controller = SeasonController.newSeason(random: Random(42));
  final myTeamId = controller.myTeamId;

  print('=== Day 1 のスタメン (まだ調子データなし) ===');
  controller.advanceDay();
  _printDay1Lineup(controller, myTeamId);

  // シーズンを進めて、調子データが溜まった後を確認
  for (int i = 0; i < 8; i++) {
    controller.advanceDay();
  }

  print('\n=== Day 9 のスタメン (調子反映後) ===');
  _printDay9Lineup(controller, myTeamId);

  // さらに進めてスタメンの変動を確認
  print('\n=== Day 10〜15 のスタメン (連続表示) ===');
  for (int day = 10; day <= 15; day++) {
    controller.advanceDay();
    _printLineupForDay(controller, myTeamId, day);
  }

  print('\n=== シーズン後半の打順傾向 (Day 25 のスタメンと素能力) ===');
  while (controller.currentDay < 25) {
    controller.advanceDay();
  }
  _printLineupWithStats(controller, myTeamId, 25);
}

void _printDay1Lineup(SeasonController c, String teamId) {
  final game = _findGameForTeam(c, teamId, c.currentDay);
  if (game == null) return;
  final team = game.homeTeam.id == teamId ? game.homeTeam : game.awayTeam;
  print('チーム: ${team.name}');
  for (int i = 0; i < 9; i++) {
    final p = team.players[i];
    print('  ${i + 1}番  ${p.name.padRight(10)}  '
        'ミ${p.meet ?? '-'} 長${p.power ?? '-'} 走${p.speed ?? '-'} 眼${p.eye ?? '-'}'
        '${p.isPitcher ? "  [投手]" : ""}');
  }
}

void _printDay9Lineup(SeasonController c, String teamId) {
  _printLineupForDay(c, teamId, c.currentDay);
}

void _printLineupForDay(SeasonController c, String teamId, int day) {
  final game = _findGameForTeam(c, teamId, day);
  if (game == null) {
    print('Day $day: 試合なし');
    return;
  }
  final team = game.homeTeam.id == teamId ? game.homeTeam : game.awayTeam;
  final names = <String>[];
  for (int i = 0; i < 9; i++) {
    names.add(team.players[i].name);
  }
  print('Day $day: ${names.join(" / ")}');
}

void _printLineupWithStats(SeasonController c, String teamId, int day) {
  final game = _findGameForTeam(c, teamId, day);
  if (game == null) return;
  final team = game.homeTeam.id == teamId ? game.homeTeam : game.awayTeam;
  print('チーム: ${team.name}');
  for (int i = 0; i < 9; i++) {
    final p = team.players[i];
    final s = c.batterStats[p.id];
    final ba = s == null || s.atBats == 0
        ? '----'
        : s.battingAverage.toStringAsFixed(3);
    final hr = s?.homeRuns ?? 0;
    print('  ${i + 1}番  ${p.name.padRight(10)}  '
        'ミ${p.meet ?? '-'} 長${p.power ?? '-'} 走${p.speed ?? '-'}  '
        '打率$ba ${hr}HR'
        '${p.isPitcher ? "  [投手]" : ""}');
  }
}

GameResult? _findGameForTeam(
    SeasonController c, String teamId, int day) {
  final games = c.scheduledGamesOnDay(day);
  for (final sg in games) {
    if (sg.homeTeam.id == teamId || sg.awayTeam.id == teamId) {
      return c.resultFor(sg.gameNumber);
    }
  }
  return null;
}

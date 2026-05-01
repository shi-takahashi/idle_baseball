// 永続化（toJson/fromJson）の動作確認。
// シーズンを進めて → JSON 化 → JSON から復元 → 主要な指標が一致するかをチェック。
//
// 実行: dart run bin/test_persist.dart
import 'dart:convert';
import 'dart:math';

import 'package:idle_baseball/engine/engine.dart';

void main() {
  const seed = 42;
  final controllerA = SeasonController.newSeason(random: Random(seed));

  // ある程度進めて履歴・統計を蓄積させる
  for (int i = 0; i < 10; i++) {
    controllerA.advanceDay();
  }

  // 自チーム作戦を 1 つセット（NextGameStrategy も復元できるか確認）
  final suggestion = controllerA.suggestedStrategyForMyTeam();
  if (suggestion != null) {
    controllerA.setMyStrategy(NextGameStrategy(
      lineup: suggestion.lineup,
      alignment: suggestion.alignment,
    ));
  }

  // toJson → JSON 文字列 → fromJson で往復
  final jsonStr = jsonEncode(controllerA.toJson());
  final controllerB =
      SeasonController.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);

  print('--- save サイズ ---');
  print('${(jsonStr.length / 1024).toStringAsFixed(1)} KB');

  print('\n--- 一致確認 ---');
  _check('myTeamId', controllerA.myTeamId, controllerB.myTeamId);
  _check('currentDay', controllerA.currentDay, controllerB.currentDay);
  _check('totalDays', controllerA.totalDays, controllerB.totalDays);
  _check('teams.length', controllerA.teams.length, controllerB.teams.length);
  _check(
      'schedule.games',
      controllerA.schedule.games.length,
      controllerB.schedule.games.length);
  _check(
      'standings.records',
      controllerA.standings.records.length,
      controllerB.standings.records.length);
  _check(
      'batterStats',
      controllerA.batterStats.length,
      controllerB.batterStats.length);
  _check(
      'pitcherStats',
      controllerA.pitcherStats.length,
      controllerB.pitcherStats.length);

  // チーム順位表の主要指標
  final aSorted = controllerA.standings.sorted;
  final bSorted = controllerB.standings.sorted;
  for (int i = 0; i < aSorted.length; i++) {
    _check('順位${i + 1} team', aSorted[i].team.id, bSorted[i].team.id);
    _check('順位${i + 1} W',  aSorted[i].wins, bSorted[i].wins);
    _check('順位${i + 1} L',  aSorted[i].losses, bSorted[i].losses);
    _check('順位${i + 1} 得点', aSorted[i].runsScored, bSorted[i].runsScored);
    _check('順位${i + 1} 失点', aSorted[i].runsAllowed, bSorted[i].runsAllowed);
    _check('順位${i + 1} E',  aSorted[i].errors, bSorted[i].errors);
  }

  // 個人成績（首位打者と最多本塁打）
  BatterSeasonStats? topAvg(SeasonController c) {
    BatterSeasonStats? best;
    for (final s in c.batterStats.values) {
      if (s.atBats < 30) continue;
      if (best == null || s.battingAverage > best.battingAverage) best = s;
    }
    return best;
  }

  BatterSeasonStats? topHR(SeasonController c) {
    BatterSeasonStats? best;
    for (final s in c.batterStats.values) {
      if (best == null || s.homeRuns > best.homeRuns) best = s;
    }
    return best;
  }

  final avgA = topAvg(controllerA);
  final avgB = topAvg(controllerB);
  if (avgA != null && avgB != null) {
    _check('首位打者 ID', avgA.player.id, avgB.player.id);
    _check('首位打者 H', avgA.hits, avgB.hits);
    _check('首位打者 AB', avgA.atBats, avgB.atBats);
  }
  final hrA = topHR(controllerA);
  final hrB = topHR(controllerB);
  if (hrA != null && hrB != null) {
    _check('最多HR ID', hrA.player.id, hrB.player.id);
    _check('最多HR HR', hrA.homeRuns, hrB.homeRuns);
  }

  // 自チームの作戦
  final stratA = controllerA.myStrategy;
  final stratB = controllerB.myStrategy;
  _check('myStrategy 有無', stratA != null, stratB != null);
  if (stratA != null && stratB != null) {
    for (int i = 0; i < 9; i++) {
      _check(
          '打順${i + 1} ID', stratA.lineup[i].id, stratB.lineup[i].id);
    }
    _check('SP ID', stratA.startingPitcher.id, stratB.startingPitcher.id);
  }

  // 進めた後も同じ方向に進むか（試合数だけ確認、結果は random によりズレるので比較しない）
  controllerA.advanceDay();
  controllerB.advanceDay();
  _check('再度進行後 currentDay', controllerA.currentDay, controllerB.currentDay);

  // 試合結果数
  int countResults(SeasonController c) {
    int count = 0;
    for (final sg in c.schedule.games) {
      if (c.resultFor(sg.gameNumber) != null) count++;
    }
    return count;
  }

  _check('試合結果数', countResults(controllerA), countResults(controllerB));

  print('\nOK: 全項目一致');
}

void _check(String label, Object? a, Object? b) {
  final ok = a == b;
  print('${ok ? "OK " : "NG "} $label: $a ${ok ? "==" : "!="} $b');
  if (!ok) {
    throw Exception('mismatch: $label');
  }
}

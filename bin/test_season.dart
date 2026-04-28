import 'dart:math';

import 'package:idle_baseball/engine/engine.dart';

/// シーズン全試合シミュレーションの動作確認
/// - 90試合を一括シミュレーション
/// - 順位表 + 打撃/投手ランキングを出力
void main() {
  final stopwatch = Stopwatch()..start();

  // チーム生成 & 日程生成
  final teams = TeamGenerator(random: Random(42)).generateLeague();
  final schedule = const ScheduleGenerator().generate(teams);

  // シーズン実行
  final simulator = SeasonSimulator(random: Random(42));
  final result = simulator.simulate(teams, schedule);

  stopwatch.stop();

  print('=== シーズン実行結果 ===');
  print('試合数: ${result.games.length}');
  print('実行時間: ${stopwatch.elapsedMilliseconds}ms');
  print('');

  // ---- 引き分け数 ----
  int draws = 0;
  int extraInnings = 0;
  int totalInnings = 0;
  int totalRuns = 0;
  for (final g in result.games) {
    if (g.winner == null) draws++;
    if (g.inningScores.length > 9) extraInnings++;
    totalInnings += g.inningScores.length;
    totalRuns += g.homeScore + g.awayScore;
  }
  print('引き分け: $draws 試合');
  print('延長試合: $extraInnings 試合');
  print('平均イニング数: ${(totalInnings / result.games.length).toStringAsFixed(1)}');
  print('平均得点（両チーム計）: ${(totalRuns / result.games.length).toStringAsFixed(2)}');
  print('');

  // ---- 順位表 ----
  print('=== 順位表 ===');
  print(
      '順位  チーム        試合  勝  負  分   勝率    GB    得点  失点  得失差');
  final sorted = result.standings.sorted;
  final leader = sorted.first;
  for (int i = 0; i < sorted.length; i++) {
    final r = sorted[i];
    final gb = i == 0 ? '-' : result.standings.gamesBehind(r, leader).toStringAsFixed(1);
    print('  ${(i + 1).toString().padLeft(2)}  '
        '${r.team.name.padRight(12)}  '
        '${r.games.toString().padLeft(3)}  '
        '${r.wins.toString().padLeft(2)}  '
        '${r.losses.toString().padLeft(2)}  '
        '${r.ties.toString().padLeft(2)}  '
        '${r.winningPct.toStringAsFixed(3)}  '
        '${gb.padLeft(4)}  '
        '${r.runsScored.toString().padLeft(4)}  '
        '${r.runsAllowed.toString().padLeft(4)}  '
        '${r.runDifferential.toString().padLeft(4)}');
  }
  print('');

  // ---- 打撃ランキング（規定打席以上: 30試合×3.1=93） ----
  const qualifiedPA = 93;
  final qualifiedBatters = result.batterStats.values
      .where((b) => b.plateAppearances >= qualifiedPA)
      .toList();
  print('=== 打撃ランキング（規定打席 $qualifiedPA 以上・${qualifiedBatters.length}人） ===');
  _printBatterRanking('首位打者 (打率)', qualifiedBatters,
      (b) => b.battingAverage, (v) => v.toStringAsFixed(3));
  _printBatterRanking('本塁打王', result.batterStats.values.toList(),
      (b) => b.homeRuns.toDouble(), (v) => v.toInt().toString(),
      min: 1);
  _printBatterRanking('打点王', result.batterStats.values.toList(),
      (b) => b.rbi.toDouble(), (v) => v.toInt().toString(),
      min: 1);
  _printBatterRanking('盗塁王', result.batterStats.values.toList(),
      (b) => b.stolenBases.toDouble(), (v) => v.toInt().toString(),
      min: 1);
  _printBatterRanking('OPS', qualifiedBatters, (b) => b.ops,
      (v) => v.toStringAsFixed(3));
  print('');

  // ---- 投手ランキング（規定投球回以上: 30イニング） ----
  const qualifiedIP = 30.0;
  final qualifiedPitchers = result.pitcherStats.values
      .where((p) => p.inningsPitched >= qualifiedIP)
      .toList();
  print('=== 投手ランキング（規定投球回 ${qualifiedIP.toInt()} 以上・${qualifiedPitchers.length}人） ===');
  _printPitcherRanking('最優秀防御率', qualifiedPitchers, (p) => p.era,
      (v) => v.toStringAsFixed(2),
      ascending: true);
  _printPitcherRanking('最多勝', result.pitcherStats.values.toList(),
      (p) => p.wins.toDouble(), (v) => v.toInt().toString(),
      min: 1);
  _printPitcherRanking('最多奪三振', result.pitcherStats.values.toList(),
      (p) => p.strikeoutsRecorded.toDouble(), (v) => v.toInt().toString(),
      min: 1);
  _printPitcherRanking('最多セーブ', result.pitcherStats.values.toList(),
      (p) => p.saves.toDouble(), (v) => v.toInt().toString(),
      min: 1);
  _printPitcherRanking('最多ホールド', result.pitcherStats.values.toList(),
      (p) => p.holds.toDouble(), (v) => v.toInt().toString(),
      min: 1);
  _printPitcherRanking('WHIP', qualifiedPitchers, (p) => p.whip,
      (v) => v.toStringAsFixed(2),
      ascending: true);
  print('');

  // ---- リーグ全体統計 ----
  print('=== リーグ全体の打撃指標 ===');
  int totalAB = 0, totalH = 0, totalHR = 0, totalBB = 0, totalSO = 0;
  for (final b in result.batterStats.values) {
    totalAB += b.atBats;
    totalH += b.hits;
    totalHR += b.homeRuns;
    totalBB += b.walks;
    totalSO += b.strikeouts;
  }
  print('  リーグ打率: ${(totalH / totalAB).toStringAsFixed(3)}');
  print(
      '  HR率: ${(totalHR / totalAB * 100).toStringAsFixed(2)}%（$totalHR/$totalAB）');
  print('  四球率: ${(totalBB / (totalAB + totalBB) * 100).toStringAsFixed(2)}%');
  print('  三振率: ${(totalSO / (totalAB + totalBB) * 100).toStringAsFixed(2)}%');
  print('');

  print('=== リーグ全体の投手指標 ===');
  int totalOuts = 0, totalRA = 0, totalHA = 0, totalBBA = 0, totalKA = 0;
  for (final p in result.pitcherStats.values) {
    totalOuts += p.outsRecorded;
    totalRA += p.runsAllowed;
    totalHA += p.hitsAllowed;
    totalBBA += p.walksAllowed;
    totalKA += p.strikeoutsRecorded;
  }
  final leagueERA = totalOuts == 0 ? 0.0 : (totalRA * 27) / totalOuts;
  final leagueWHIP = totalOuts == 0 ? 0.0 : (totalBBA + totalHA) * 3 / totalOuts;
  print('  リーグ防御率: ${leagueERA.toStringAsFixed(2)}');
  print('  リーグWHIP: ${leagueWHIP.toStringAsFixed(2)}');
  print('  総奪三振: $totalKA / 総与四球: $totalBBA');
}

void _printBatterRanking(
  String title,
  List<BatterSeasonStats> batters,
  double Function(BatterSeasonStats) getValue,
  String Function(double) format, {
  int topN = 10,
  double min = 0,
  bool ascending = false,
}) {
  final filtered = batters.where((b) => getValue(b) >= min).toList();
  filtered.sort((a, b) => ascending
      ? getValue(a).compareTo(getValue(b))
      : getValue(b).compareTo(getValue(a)));
  final top = filtered.take(topN).toList();
  if (top.isEmpty) {
    print('-- $title: データなし --');
    return;
  }
  print('-- $title --');
  for (int i = 0; i < top.length; i++) {
    final b = top[i];
    print('  ${(i + 1).toString().padLeft(2)}. '
        '${format(getValue(b)).padLeft(6)}  '
        '${b.player.name.padRight(8)} '
        '(${b.team.name}, ${b.atBats}打数${b.hits}安打 ${b.homeRuns}本${b.rbi}点)');
  }
}

void _printPitcherRanking(
  String title,
  List<PitcherSeasonStats> pitchers,
  double Function(PitcherSeasonStats) getValue,
  String Function(double) format, {
  int topN = 10,
  double min = 0,
  bool ascending = false,
}) {
  final filtered = pitchers.where((p) => getValue(p) >= min).toList();
  filtered.sort((a, b) => ascending
      ? getValue(a).compareTo(getValue(b))
      : getValue(b).compareTo(getValue(a)));
  final top = filtered.take(topN).toList();
  if (top.isEmpty) {
    print('-- $title: データなし --');
    return;
  }
  print('-- $title --');
  for (int i = 0; i < top.length; i++) {
    final p = top[i];
    final role = p.player.reliefRole?.displayName ?? '先発';
    print('  ${(i + 1).toString().padLeft(2)}. '
        '${format(getValue(p)).padLeft(6)}  '
        '${p.player.name.padRight(8)} '
        '[${role.padRight(6)}] '
        '(${p.team.name}, ${p.wins}勝${p.losses}敗${p.saves}S${p.holds}H '
        '${p.inningsPitchedDisplay}回 ${p.strikeoutsRecorded}K)');
  }
}

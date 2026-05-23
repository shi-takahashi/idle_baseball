import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 盗塁の発生状況を走力別に計測:
/// - 走力別の試行数 / 成功数 / 成功率
/// - 1チーム1試合あたりの盗塁数
/// - ダブルスチール件数
/// - **走力別の per-player 150試合換算 SB**（出場試合数で正規化）
void main() {
  const numSeasons = 6;
  const gamesPerTeam = 150;
  // 走力 → (attempts, successes)
  final attemptsBySpeed = <int, int>{};
  final successesBySpeed = <int, int>{};
  final initiatorSpeedHist = <int, int>{}; // 起動者（盗塁を仕掛けた走者）の走力分布
  int totalAttempts = 0;
  int totalSuccesses = 0;
  int totalDoubleSteals = 0;
  int totalGames = 0;
  int totalTeamGames = 0;

  // 走力別の per-player 集計
  final perPlayerGames = <int, int>{for (var k = 1; k <= 10; k++) k: 0};
  final perPlayerSB = <int, int>{for (var k = 1; k <= 10; k++) k: 0};

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(200 + s)).generateLeague();
    final schedule = ScheduleGenerator()
        .generateForGamesPerTeam(teams, gamesPerTeam);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      gamesPerTeam: gamesPerTeam,
      random: Random(200 + s),
    );
    controller.advanceAll();

    // per-player 集計（走力別出場試合数と盗塁数を蓄積）
    for (final st in controller.batterStats.values) {
      final player = st.player;
      if (player.isPitcher) continue;
      final sp = player.speed ?? 5;
      perPlayerGames[sp] = (perPlayerGames[sp] ?? 0) + st.games;
      perPlayerSB[sp] = (perPlayerSB[sp] ?? 0) + st.stolenBases;
    }

    for (final sg in schedule.games) {
      final result = controller.resultFor(sg.gameNumber);
      if (result == null) continue;
      totalGames++;
      totalTeamGames += 2;

      for (final half in result.halfInnings) {
        for (final ev in half.stealEvents) {
          final isDouble = ev.attempts.length >= 2;
          if (isDouble) totalDoubleSteals++;
          // 「起動者」= 単独なら本人、ダブルスチールなら2塁走者（3塁を狙う）
          final initiator = isDouble
              ? ev.attempts.firstWhere(
                  (a) => a.fromBase == Base.second,
                  orElse: () => ev.attempts.first,
                )
              : ev.attempts.first;
          final initSpeed = initiator.runner.speed ?? 5;
          initiatorSpeedHist[initSpeed] =
              (initiatorSpeedHist[initSpeed] ?? 0) + 1;

          for (final att in ev.attempts) {
            final speed = att.runner.speed ?? 5;
            attemptsBySpeed[speed] = (attemptsBySpeed[speed] ?? 0) + 1;
            totalAttempts++;
            if (att.success) {
              successesBySpeed[speed] =
                  (successesBySpeed[speed] ?? 0) + 1;
              totalSuccesses++;
            }
          }
        }
      }
    }
  }

  print('===== 盗塁の発生状況（${numSeasons}シーズン） =====');
  print('総試合数: $totalGames（チーム×試合: $totalTeamGames）');
  print('総盗塁試行: $totalAttempts');
  print('総盗塁成功: $totalSuccesses');
  print('成功率: ${totalAttempts > 0 ? (100.0 * totalSuccesses / totalAttempts).toStringAsFixed(1) : "-"}%');
  print('1チーム1試合あたり盗塁試行: '
      '${(totalAttempts / totalTeamGames).toStringAsFixed(2)}');
  print('1チーム1試合あたり盗塁成功: '
      '${(totalSuccesses / totalTeamGames).toStringAsFixed(2)}');
  print('シーズン換算（30試合）の1チーム盗塁: '
      '${(totalSuccesses / numSeasons / 6).toStringAsFixed(1)}');
  print('ダブルスチール: $totalDoubleSteals');
  print('');
  print('走力別 試行 / 成功 / 成功率:');
  for (int sp = 1; sp <= 10; sp++) {
    final att = attemptsBySpeed[sp] ?? 0;
    final suc = successesBySpeed[sp] ?? 0;
    final rate = att > 0 ? (100.0 * suc / att).toStringAsFixed(1) : '-';
    print('  走力$sp: 試行 $att / 成功 $suc / 成功率 $rate%');
  }
  print('');
  print('起動者の走力分布（仕掛けた走者）:');
  for (int sp = 1; sp <= 10; sp++) {
    final n = initiatorSpeedHist[sp] ?? 0;
    print('  走力$sp: $n');
  }
  print('');
  print('===== 走力別 per-player 150試合換算 SB =====');
  print(' 走力 | のべ試合 | のべSB | 150試合換算');
  print('------|----------|--------|------------');
  for (int sp = 1; sp <= 10; sp++) {
    final g = perPlayerGames[sp] ?? 0;
    final sb = perPlayerSB[sp] ?? 0;
    final per150 = g == 0 ? 0.0 : sb / g * 150;
    print('  ${sp.toString().padLeft(2)}  '
        '| ${g.toString().padLeft(8)} '
        '| ${sb.toString().padLeft(6)} '
        '| ${per150.toStringAsFixed(1).padLeft(10)}');
  }
}

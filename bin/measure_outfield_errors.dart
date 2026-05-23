import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 外野手の守備力ごとの 150 試合換算エラー数を計測する。
///
/// 各チームのスタメン外野手（players[5/6/7] = 左翼/中堅/右翼）の
/// outfield 守備力でグルーピングし、
///   のべエラー数 / のべ出場試合数 × 150
/// を表示する。
///
/// 目標: 守備力9で約1個、守備力5で約5個、守備力1で約9個（線形の目安）。
void main() {
  const seasons = 20;
  const gamesPerTeam = 150;

  // 守備力ごとに「のべ出場試合数」「のべエラー数」を集計
  final games = <int, int>{for (var k = 1; k <= 10; k++) k: 0};
  final errors = <int, int>{for (var k = 1; k <= 10; k++) k: 0};

  for (int s = 0; s < seasons; s++) {
    final c = SeasonController.newSeason(
      random: Random(2000 + s),
      gamesPerTeam: gamesPerTeam,
    );
    c.advanceAll();

    // スタメン外野手 (players[5/6/7]) の出場試合数を守備力で集計
    for (final team in c.teams) {
      for (final slot in [5, 6, 7]) {
        final starter = team.players[slot];
        final f = starter.getFielding(DefensePosition.outfield);
        final st = c.batterStats[starter.id];
        if (st == null) continue;
        games[f] = (games[f] ?? 0) + st.games;
      }
    }

    // 外野エラーを fielder の outfield 守備力で集計
    for (final g in c.schedule.games) {
      final result = c.resultFor(g.gameNumber);
      if (result == null) continue;
      for (final half in result.halfInnings) {
        for (final ab in half.atBats) {
          final fe = ab.fieldingError;
          if (fe == null) continue;
          if (!fe.position.isOutfield) continue;
          final fielder = fe.fielder;
          if (fielder == null) continue;
          final f = fielder.getFielding(DefensePosition.outfield);
          errors[f] = (errors[f] ?? 0) + 1;
        }
      }
    }
  }

  print('===== 外野手の守備力ごとの 150 試合換算エラー数 =====');
  print('  $seasons シーズン × $gamesPerTeam 試合 × 6 チーム × 3 ポジション');
  print('');
  print(' 守備力 | のべ試合 | のべエラー | 150試合換算');
  print('--------|----------|------------|------------');
  for (int f = 1; f <= 10; f++) {
    final gg = games[f] ?? 0;
    final ee = errors[f] ?? 0;
    final per150 = gg == 0 ? 0.0 : ee / gg * 150;
    print('   ${f.toString().padLeft(2)}   '
        '| ${gg.toString().padLeft(8)} '
        '| ${ee.toString().padLeft(10)} '
        '| ${per150.toStringAsFixed(2).padLeft(10)}');
  }

  // 全体合計
  final totalGames = games.values.fold<int>(0, (a, b) => a + b);
  final totalErrors = errors.values.fold<int>(0, (a, b) => a + b);
  print('');
  print('  全体: 試合 $totalGames / エラー $totalErrors '
      '(平均 ${(totalErrors / totalGames * 150).toStringAsFixed(2)} / 150試合)');
}

import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 内野手のポジション × 守備力ごとの 150 試合換算エラー数を計測する。
///
/// ポジションごとにスタメン選手の outfield 以外の守備力でグルーピングし、
///   のべエラー数 / のべ出場試合数 × 150
/// を表示する。
///
/// NPB 目安（150 試合換算、守備力 5 の選手相当）:
///   遊撃 10〜15 / 三塁 7〜12 / 二塁 5〜9 / 捕手 3〜5（パスボール除く）
///   一塁・投手は補助的に集計
void main() {
  const seasons = 20;
  const gamesPerTeam = 150;

  // ポジション → 守備力 → カウンタ
  final positions = [
    DefensePosition.catcher,
    DefensePosition.first,
    DefensePosition.second,
    DefensePosition.third,
    DefensePosition.shortstop,
  ];

  // ポジション → 守備力 → のべ試合数 / のべエラー数
  final games = <DefensePosition, Map<int, int>>{
    for (final p in positions) p: {for (var k = 1; k <= 10; k++) k: 0}
  };
  final errors = <DefensePosition, Map<int, int>>{
    for (final p in positions) p: {for (var k = 1; k <= 10; k++) k: 0}
  };

  // スタメンスロット → DefensePosition のマップ
  // (team.players[0..7] = 通常野手8人、players[8] = 投手)
  // ただし position は player.position から取得すべき。

  for (int s = 0; s < seasons; s++) {
    final c = SeasonController.newSeason(
      random: Random(3000 + s),
      gamesPerTeam: gamesPerTeam,
    );
    c.advanceAll();

    // スタメン野手 (players[0..7]) の出場試合数をポジション × 守備力で集計
    // スロット規約: 0=捕手, 1=一塁, 2=二塁, 3=三塁, 4=遊撃, 5=左翼, 6=中堅, 7=右翼
    const slotToInfieldPos = {
      0: DefensePosition.catcher,
      1: DefensePosition.first,
      2: DefensePosition.second,
      3: DefensePosition.third,
      4: DefensePosition.shortstop,
    };
    for (final team in c.teams) {
      slotToInfieldPos.forEach((slot, dp) {
        final starter = team.players[slot];
        if (starter.isPitcher) return;
        final f = starter.getFielding(dp);
        final st = c.batterStats[starter.id];
        if (st == null) return;
        games[dp]![f] = (games[dp]![f] ?? 0) + st.games;
      });
    }

    // 内野エラーを fielder のポジション × 守備力で集計
    for (final g in c.schedule.games) {
      final result = c.resultFor(g.gameNumber);
      if (result == null) continue;
      for (final half in result.halfInnings) {
        for (final ab in half.atBats) {
          final fe = ab.fieldingError;
          if (fe == null) continue;
          if (fe.position.isOutfield) continue;
          final dp = fe.position.defensePosition;
          if (dp == null || dp == DefensePosition.outfield) continue;
          final fielder = fe.fielder;
          if (fielder == null) continue;
          final f = fielder.getFielding(dp);
          errors[dp]![f] = (errors[dp]![f] ?? 0) + 1;
        }
      }
    }
  }

  print('===== 内野手のポジション × 守備力ごとの 150 試合換算エラー数 =====');
  print('  $seasons シーズン × $gamesPerTeam 試合 × 6 チーム');
  print('');

  for (final pos in positions) {
    print('--- ${pos.displayName} ---');
    print(' 守備力 | のべ試合 | のべエラー | 150試合換算');
    print('--------|----------|------------|------------');
    for (int f = 1; f <= 10; f++) {
      final gg = games[pos]![f] ?? 0;
      final ee = errors[pos]![f] ?? 0;
      final per150 = gg == 0 ? 0.0 : ee / gg * 150;
      print('   ${f.toString().padLeft(2)}   '
          '| ${gg.toString().padLeft(8)} '
          '| ${ee.toString().padLeft(10)} '
          '| ${per150.toStringAsFixed(2).padLeft(10)}');
    }
    final totalG = games[pos]!.values.fold<int>(0, (a, b) => a + b);
    final totalE = errors[pos]!.values.fold<int>(0, (a, b) => a + b);
    final avg = totalG == 0 ? 0.0 : totalE / totalG * 150;
    print('  平均: 試合 $totalG / エラー $totalE / 150試合 ${avg.toStringAsFixed(2)}');
    print('');
  }

  print('NPB 目安（150試合換算、守備力5相当）:');
  print('  遊撃 10〜15 / 三塁 7〜12 / 二塁 5〜9 / 捕手 3〜5（PB除く）');
}

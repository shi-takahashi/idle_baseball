import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 外国人野手がスタメン (players[0..7]) に入っている比率を計測する。
/// 旧版は外国人野手が必ず bench に入る構造だったので 0%。
/// 新版は能力ベース選定で、強い外国人はスタメンに上がる。
void main() {
  const numLeagues = 200;
  int totalForeignFielders = 0;
  int foreignInStarters = 0;
  final positionDist = <DefensePosition, int>{};
  // スタメン構成: 外国人比率
  int teamsWithForeignStarter = 0;
  int teamsWith2ForeignStarter = 0;

  for (int seed = 0; seed < numLeagues; seed++) {
    final teams = TeamGenerator(random: Random(seed)).generateLeague();
    // myTeamId 以外（CPU チーム）を対象。
    // generateLeague は myTeamId を知らないので、ここでは全チーム見る。
    // ただし SeasonController.newSeason の中立化を経由していないので、全チームが
    // 能力ベース配置のまま。それがそのまま CPU の挙動。
    for (final t in teams) {
      final starters = t.players.take(8).toList();
      final fielders = [...starters, ...t.bench];
      final foreign = fielders.where((p) => p.isForeign).toList();
      totalForeignFielders += foreign.length;
      int teamForeignInStarter = 0;
      for (final p in foreign) {
        if (starters.any((s) => s.id == p.id)) {
          foreignInStarters++;
          teamForeignInStarter++;
          // スタメンに入った外国人のポジション
          final pos = (p.fielding ?? {})
              .entries
              .firstWhere((e) => e.value > 0,
                  orElse: () => const MapEntry(
                      DefensePosition.outfield, 0))
              .key;
          positionDist[pos] = (positionDist[pos] ?? 0) + 1;
        }
      }
      if (teamForeignInStarter >= 1) teamsWithForeignStarter++;
      if (teamForeignInStarter == 2) teamsWith2ForeignStarter++;
    }
  }
  final totalTeams = numLeagues * 6;
  final pct = foreignInStarters / totalForeignFielders * 100;
  print('外国人野手がスタメンに入る比率 ($numLeagues リーグ × 6 チーム = '
      '$totalTeams チーム）');
  print('  外国人野手総数: $totalForeignFielders');
  print('  スタメン入り: $foreignInStarters '
      '(${pct.toStringAsFixed(1)}%)');
  print('');
  print('チーム単位の外国人スタメン構成:');
  print('  1名以上スタメン: $teamsWithForeignStarter / $totalTeams '
      '(${(teamsWithForeignStarter / totalTeams * 100).toStringAsFixed(1)}%)');
  print('  2名スタメン: $teamsWith2ForeignStarter / $totalTeams '
      '(${(teamsWith2ForeignStarter / totalTeams * 100).toStringAsFixed(1)}%)');
  print('');
  print('スタメン外国人のポジション分布:');
  for (final pos in DefensePosition.values) {
    final n = positionDist[pos] ?? 0;
    if (n == 0) continue;
    final p = n / foreignInStarters * 100;
    print('  ${pos.name}: $n (${p.toStringAsFixed(1)}%)');
  }
}

import 'dart:math';

import 'package:idle_baseball/engine/engine.dart';

/// 投手ローテーション動作確認
/// - 各 SP の登板日と登板間隔（中X日）を集計
/// - リーグ全体での中X日分布を出す
void main() {
  final teams = TeamGenerator(random: Random(7)).generateLeague();
  final schedule = const ScheduleGenerator().generate(teams);

  final controller = SeasonController(
    teams: teams,
    schedule: schedule,
    myTeamId: teams.first.id,
    random: Random(7),
  );
  controller.advanceAll();

  // 各 SP の登板日リストを収集
  // pitcherId -> List<day>
  // ついでに ERA も後で確認するため、Player → stats のマップも作る
  final startsByPitcher = <String, List<int>>{};
  for (final sg in schedule.games) {
    final result = controller.resultFor(sg.gameNumber);
    if (result == null) continue;
    final day = sg.day;
    final homeSP = result.homeTeam.pitcher;
    final awaySP = result.awayTeam.pitcher;
    startsByPitcher.putIfAbsent(homeSP.id, () => []).add(day);
    startsByPitcher.putIfAbsent(awaySP.id, () => []).add(day);
  }

  // 登板間隔の分布
  final gapHistogram = <int, int>{};
  int totalGaps = 0;

  // チームごとの結果を表示。簡易エーススコアも併記する
  double aceScore(Player p) {
    final speed = (((p.averageSpeed ?? 145) - 130) / 25).clamp(0.0, 1.0);
    final controlN = (p.control ?? 5) / 10.0;
    final fastballN = (p.fastball ?? 5) / 10.0;
    final pitches = [
      p.slider ?? 0,
      p.curve ?? 0,
      p.splitter ?? 0,
      p.changeup ?? 0,
    ];
    final best = pitches.reduce((a, b) => a > b ? a : b) / 10.0;
    return (speed + controlN + fastballN + best) / 4.0;
  }

  for (final team in teams) {
    print('=== ${team.name} (${team.shortName}) ===');
    // エース度順にソートして表示
    final sorted = team.startingRotation.toList()
      ..sort((a, b) => aceScore(b).compareTo(aceScore(a)));
    for (final sp in sorted) {
      final days = startsByPitcher[sp.id] ?? const <int>[];
      final ace = aceScore(sp);
      if (days.isEmpty) {
        print('  ${sp.name} (ace=${ace.toStringAsFixed(2)}, stamina ${sp.stamina ?? "-"}) - 登板なし');
        continue;
      }
      final gaps = <int>[];
      for (int i = 1; i < days.length; i++) {
        final gap = days[i] - days[i - 1];
        gaps.add(gap);
        final naka = gap - 1;
        gapHistogram[naka] = (gapHistogram[naka] ?? 0) + 1;
        totalGaps++;
      }
      final gapStr = gaps.isEmpty ? '-' : gaps.map((g) => '中${g - 1}日').join(', ');
      print('  ${sp.name} (ace=${ace.toStringAsFixed(2)}, stamina ${sp.stamina ?? "-"}) '
          '${days.length}登板 間隔=[$gapStr]');
    }
    print('');
  }

  // 全体の登板間隔ヒストグラム
  print('=== リーグ全体の登板間隔分布 ===');
  final keys = gapHistogram.keys.toList()..sort();
  for (final naka in keys) {
    final count = gapHistogram[naka]!;
    final pct = (100.0 * count / totalGaps).toStringAsFixed(1);
    print('  中$naka日: $count 件 ($pct%)');
  }
  print('  合計 $totalGaps 件');
}

import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 「1〜3 のインフレが引退ロジックで吸収できていないせい」仮説の検証用。
///
/// measure_growth.dart は commitOffseason() を引数なしで呼ぶため、
/// **自チームの引退・新人加入は実行されない**（CPU は rebuildCpuTeams で 3+3 引退）。
///
/// → 自チームには衰え選手が無限に溜まっていく可能性がある。これを実測で確認。
void main() {
  // 自チーム / CPU で別々に集計
  Map<int, int> emptyDist() => {for (int v = 1; v <= 10; v++) v: 0};

  final myDist = {'power': emptyDist(), 'meet': emptyDist()};
  final cpuDist = {'power': emptyDist(), 'meet': emptyDist()};

  const numLeagues = 30;
  for (int seed = 0; seed < numLeagues; seed++) {
    final c = SeasonController.newSeason(random: Random(seed));
    final myId = c.myTeamId;
    // S20 まで進める
    for (int s = 0; s < 19; s++) {
      c.advanceAll();
      c.commitOffseason(); // 自チームには plan/selection を渡さない（UIを通さない場合の挙動）
    }
    // S20 開幕時の野手能力を集計
    for (final t in c.teams) {
      final all = [...t.players, ...t.bench];
      final seen = <String>{};
      final target = t.id == myId ? myDist : cpuDist;
      for (final p in all) {
        if (!seen.add(p.id)) continue;
        if (p.isPitcher) continue;
        if (p.power != null) {
          target['power']![p.power!] = target['power']![p.power!]! + 1;
        }
        if (p.meet != null) {
          target['meet']![p.meet!] = target['meet']![p.meet!]! + 1;
        }
      }
    }
  }

  void printDist(String name, Map<String, Map<int, int>> dist) {
    print('--- $name ---');
    for (final cat in ['power', 'meet']) {
      final total = dist[cat]!.values.fold<int>(0, (a, b) => a + b);
      print('  $cat (n=$total)');
      for (int v = 1; v <= 10; v++) {
        final n = dist[cat]![v]!;
        final p = total == 0 ? 0.0 : (n / total * 100);
        print('    $v: ${p.toStringAsFixed(2).padLeft(5)}%');
      }
    }
    print('');
  }

  print('S20 開幕時 (自チーム vs CPU チームの能力分布)\n');
  printDist('自チーム（commitOffseason を引数なしで呼ぶ＝引退なし）', myDist);
  printDist('CPU チーム（rebuildCpuTeams で 3+3 引退）', cpuDist);
}

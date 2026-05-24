import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// **チーム全体（40人プール）** の野手ポジション充足を計測。
///
/// 結果: 「チーム全体で捕手 3 人未満」のチームが存在するか確認。
/// S1 (初期) と S6 (世代交代後) で計測。
void main() {
  const numLeagues = 30;
  const positions = [
    DefensePosition.catcher,
    DefensePosition.first,
    DefensePosition.second,
    DefensePosition.third,
    DefensePosition.shortstop,
    DefensePosition.outfield,
  ];

  for (final years in [0, 6]) {
    print('=== チーム全体 (40人) の野手ポジション充足 / S${years + 1} ===');
    final samples = <DefensePosition, List<int>>{
      for (final p in positions) p: <int>[],
    };
    int debugBadCount = 0;
    for (int seed = 0; seed < numLeagues; seed++) {
      final c = SeasonController.newSeason(random: Random(seed));
      for (int y = 0; y < years; y++) {
        c.advanceAll();
        final plan = c.prepareOffseason();
        final selection = OffseasonSelection.recommended(plan);
        c.commitOffseason(plan: plan, selection: selection);
      }
      for (final t in c.teams) {
        final fielders = <Player>[
          ...t.players.where((p) => !p.isPitcher),
          ...t.bench,
        ];
        for (final pos in positions) {
          final n = fielders.where((p) => p.canPlay(pos)).length;
          samples[pos]!.add(n);
        }
        // 捕手 < 3 のチームを debug
        final catchers =
            fielders.where((p) => p.canPlay(DefensePosition.catcher)).length;
        if (catchers < 3 && debugBadCount < 3) {
          print('  [debug] seed=$seed team=${t.shortName}: 捕手 $catchers 名');
          print('    野手数: ${fielders.length} (うち外国人 '
              '${fielders.where((p) => p.isForeign).length})');
          for (final p in fielders) {
            final positions = DefensePosition.values
                .where((pos) => p.canPlay(pos))
                .map((p) => p.toString().split('.').last)
                .join('/');
            final age = p.age;
            final flag = p.isForeign ? '★' : ' ';
            print('     $flag #${p.number} ${p.name.padRight(12)} '
                '$age歳 [$positions]');
          }
          debugBadCount++;
        }
      }
    }

    print('ポジション    | 平均 | 最小 | 最大 | 目標 3+ 未満%');
    for (final pos in positions) {
      final list = samples[pos]!;
      final mean = list.fold<int>(0, (a, b) => a + b) / list.length;
      final minV = list.reduce((a, b) => a < b ? a : b);
      final maxV = list.reduce((a, b) => a > b ? a : b);
      final target = pos == DefensePosition.outfield ? 8 : 3;
      final under = list.where((n) => n < target).length;
      print('${pos.toString().split('.').last.padRight(13)} '
          '| ${mean.toStringAsFixed(2).padLeft(4)} '
          '| ${minV.toString().padLeft(4)} '
          '| ${maxV.toString().padLeft(4)} '
          '| ${(under / list.length * 100).toStringAsFixed(1)}% (目標 $target+)');
    }
    print('');
  }
}

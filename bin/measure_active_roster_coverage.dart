import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 当日ベンチ入り 26 人での野手ポジション充足を確認。
///
/// スタメン 8 + 控え 8 = 16 名の中で、各ポジションを最低 2 人（外野は 5 人）
/// 守れるか。`_selectActiveBench` のポジション制約ロジックは neutral 関係なく
/// 同じなので、自チームの suggestedStrategy で測れば CPU でも同じ結果になる。
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
  final targetByPos = {
    DefensePosition.catcher: 2,
    DefensePosition.first: 2,
    DefensePosition.second: 2,
    DefensePosition.third: 2,
    DefensePosition.shortstop: 2,
    DefensePosition.outfield: 5,
  };

  final coverageByPos = <DefensePosition, List<int>>{
    for (final p in positions) p: <int>[],
  };
  int underTargetCount = 0;
  int totalSamples = 0;

  // 各リーグの S1 と S6 の 2 時点で計測 (世代交代後の制約遵守も見る)
  for (int seed = 0; seed < numLeagues; seed++) {
    final c = SeasonController.newSeason(random: Random(seed));
    _sample(c, coverageByPos, targetByPos, positions, () {
      bool any = false;
      for (final pos in positions) {
        if (coverageByPos[pos]!.last < targetByPos[pos]!) any = true;
      }
      if (any) underTargetCount++;
      totalSamples++;
    });

    for (int year = 0; year < 5; year++) {
      c.advanceAll();
      final plan = c.prepareOffseason();
      final selection = OffseasonSelection.recommended(plan);
      c.commitOffseason(plan: plan, selection: selection);
    }
    _sample(c, coverageByPos, targetByPos, positions, () {
      bool any = false;
      for (final pos in positions) {
        if (coverageByPos[pos]!.last < targetByPos[pos]!) any = true;
      }
      if (any) underTargetCount++;
      totalSamples++;
    });
  }

  print('=== 当日ベンチ入り 26 人の野手ポジション充足 ===');
  print('$numLeagues リーグ × 2 時点 (S1 と S6) = $totalSamples サンプル\n');
  print('ポジション    | 平均 | 最小 | 最大 | 目標未満%');
  for (final pos in positions) {
    final list = coverageByPos[pos]!;
    final mean = list.fold<int>(0, (a, b) => a + b) / list.length;
    final minV = list.reduce((a, b) => a < b ? a : b);
    final maxV = list.reduce((a, b) => a > b ? a : b);
    final target = targetByPos[pos]!;
    final under = list.where((n) => n < target).length;
    final underPct = under / list.length * 100;
    print('${pos.toString().split('.').last.padRight(13)} '
        '| ${mean.toStringAsFixed(2).padLeft(4)} '
        '| ${minV.toString().padLeft(4)} '
        '| ${maxV.toString().padLeft(4)} '
        '| ${underPct.toStringAsFixed(1)}% (目標 $target+)');
  }
  print('\n全制約を満たすサンプル: ${totalSamples - underTargetCount} / $totalSamples '
      '= ${((totalSamples - underTargetCount) / totalSamples * 100).toStringAsFixed(1)}%');
}

void _sample(
  SeasonController c,
  Map<DefensePosition, List<int>> coverageByPos,
  Map<DefensePosition, int> targetByPos,
  List<DefensePosition> positions,
  void Function() onAfterAdd,
) {
  final strategy = c.suggestedStrategyForMyTeam();
  if (strategy == null) return;
  final activeFielders = <Player>[
    ...strategy.lineup.where((p) => !p.isPitcher),
    ...strategy.activeBench,
  ];
  for (final pos in positions) {
    final n = activeFielders.where((p) => p.canPlay(pos)).length;
    coverageByPos[pos]!.add(n);
  }
  onAfterAdd();
}

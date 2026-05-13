import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 守備変更で「その選手が守れないポジション」に配置されていないか検証する。
///
/// 期待: 0 件。
/// 修正前: 池田賢治(捕)に代打→藤井亮(捕守備力0)を捕手に強引配置するケースが
///        発生し得た。
void main() {
  const numSeasons = 5;
  int violations = 0;
  int totalChanges = 0;
  int totalGames = 0;
  int extraInningsViolations = 0;
  int finalHalfInningViolations = 0;
  int totalPh = 0;
  int phInFinalHalfInning = 0;
  final byPosition = <FieldPosition, int>{};

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(7000 + s)).generateLeague();
    final schedule = const ScheduleGenerator().generate(teams);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      random: Random(7500 + s),
    );
    controller.advanceAll();

    for (final sg in schedule.games) {
      final result = controller.resultFor(sg.gameNumber);
      if (result == null) continue;
      totalGames++;
      for (final half in result.halfInnings) {
        for (final fc in half.fielderChanges) {
          if (fc.type != FielderChangeType.pinchHit) continue;
          totalPh++;
          if (half.inning >= 12 && !half.isTop) phInFinalHalfInning++;
        }
        for (final dc in half.defensiveChangesAtStart) {
          totalChanges++;
          final defPos = dc.toPosition.defensePosition;
          if (defPos == null) continue;
          if (!dc.player.canPlay(defPos)) {
            violations++;
            byPosition[dc.toPosition] =
                (byPosition[dc.toPosition] ?? 0) + 1;
            if (half.inning >= 10) extraInningsViolations++;
            if (half.inning >= 12 && !half.isTop) finalHalfInningViolations++;
          }
        }
      }
    }
  }

  print('===== 守備配置の整合性チェック ($numSeasons シーズン / $totalGames 試合) =====');
  print('総代打: $totalPh');
  print('  うち12回裏: $phInFinalHalfInning');
  print('総守備変更: $totalChanges');
  print('守れない位置への配置: $violations 件');
  print('  うち延長戦 (10回以降): $extraInningsViolations 件');
  print('  うち12回裏 (試合終了確定・許容): $finalHalfInningViolations 件');
  print('');
  print('ポジション別内訳:');
  for (final pos in FieldPosition.values) {
    final count = byPosition[pos] ?? 0;
    if (count > 0) {
      print('  ${pos.name}: $count');
    }
  }
}

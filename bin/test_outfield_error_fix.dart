import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 外野手送球エラー時の打席結果が正しく記録されているか検証。
///
/// 修正前のバグ: 二塁打 + 外野エラーが「三塁打」として記録され、走者が全員生還
/// （RBI 3）になっていた。
///
/// 期待する修正後の挙動:
///   - 外野手のフィールディングエラーを伴う打席結果は、自然な打撃タイプ
///     （single / double_）のまま記録される（triple に格上げされない）
///   - 押し出しで本塁を踏んだ走者は得点には含まれるが打点には算入されない
void main() {
  const numSeasons = 5;

  int outfieldErrorAtBats = 0;
  int outfieldErrorAsSingle = 0;
  int outfieldErrorAsDouble = 0;
  int outfieldErrorAsTriple = 0; // バグなら > 0
  int outfieldErrorAsReachedOnError = 0;
  int outfieldErrorAsOther = 0;

  int totalRbi = 0;
  int totalRuns = 0;

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(700 + s)).generateLeague();
    final schedule = const ScheduleGenerator().generate(teams);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      random: Random(700 + s),
    );
    controller.advanceAll();

    for (final sg in schedule.games) {
      final result = controller.resultFor(sg.gameNumber);
      if (result == null) continue;
      for (final half in result.halfInnings) {
        for (final ab in half.atBats) {
          if (ab.isIncomplete) continue;
          totalRbi += ab.rbiCount;
          totalRuns += ab.runsScored;

          final fe = ab.fieldingError;
          if (fe == null) continue;
          if (!fe.position.isOutfield) continue;

          outfieldErrorAtBats++;
          switch (ab.result) {
            case AtBatResultType.single:
              outfieldErrorAsSingle++;
              break;
            case AtBatResultType.double_:
              outfieldErrorAsDouble++;
              break;
            case AtBatResultType.triple:
              outfieldErrorAsTriple++;
              print('🚨 BUG: 外野エラーで triple になっている '
                  '(batter=${ab.batter.name}, pos=${fe.position.shortName})');
              break;
            case AtBatResultType.reachedOnError:
              outfieldErrorAsReachedOnError++;
              break;
            default:
              outfieldErrorAsOther++;
              break;
          }
        }
      }
    }
  }

  print('===== 外野エラー時の打席結果タイプ（$numSeasons シーズン）=====');
  print('総外野エラー: $outfieldErrorAtBats');
  print('  single:         $outfieldErrorAsSingle');
  print('  double_:        $outfieldErrorAsDouble');
  print('  triple:         $outfieldErrorAsTriple ${outfieldErrorAsTriple == 0 ? "✓" : "🚨"}');
  print('  reachedOnError: $outfieldErrorAsReachedOnError');
  print('  その他:         $outfieldErrorAsOther');
  print('');
  print('合計打点: $totalRbi');
  print('合計得点: $totalRuns');
  print('差分: ${totalRuns - totalRbi}（エラー出塁 + 外野エラー押し出しによる失策得点）');

  if (outfieldErrorAsTriple == 0) {
    print('');
    print('✓ 外野エラーが三塁打に格上げされていない（バグ修正済み）');
  }
}

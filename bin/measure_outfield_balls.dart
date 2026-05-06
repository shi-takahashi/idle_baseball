import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 外野方向の打球タイプごとのアウト率を測定。
///
/// プロ野球の現実値:
/// - 外野ライナー: アウト率 約27〜30%
/// - 外野フライ: アウト率 約67〜72%
///
/// 「外野ライナーアウト > 外野フライアウト」になっていたら NG。
void main() {
  const numSeasons = 5;
  // 外野方向 + 打球タイプ別の集計
  // outfield positions: leftField, centerField, rightField
  int linerTotal = 0;
  int linerOut = 0;
  int flyTotal = 0;
  int flyOut = 0;
  int groundTotal = 0;
  int groundOut = 0;

  bool isOutfield(FieldPosition? p) =>
      p == FieldPosition.left ||
      p == FieldPosition.center ||
      p == FieldPosition.right;

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(300 + s)).generateLeague();
    final schedule = const ScheduleGenerator().generate(teams);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      random: Random(300 + s),
    );
    controller.advanceAll();

    for (final sg in schedule.games) {
      final result = controller.resultFor(sg.gameNumber);
      if (result == null) continue;
      for (final half in result.halfInnings) {
        for (final ab in half.atBats) {
          // 各打席の最後の球がインプレー時の打球タイプを保持
          PitchResult? lastInPlay;
          for (final p in ab.pitches) {
            if (p.type == PitchResultType.inPlay) {
              lastInPlay = p;
            }
          }
          if (lastInPlay == null) continue;
          final btype = lastInPlay.battedBallType;
          final fpos = lastInPlay.fieldPosition;
          if (btype == null || fpos == null) continue;

          // 外野方向でフィルタ
          final outfield = isOutfield(fpos);

          if (btype == BattedBallType.lineDrive && outfield) {
            linerTotal++;
            if (ab.result.isOut) linerOut++;
          } else if (btype == BattedBallType.flyBall && outfield) {
            flyTotal++;
            if (ab.result.isOut) flyOut++;
          } else if (btype == BattedBallType.groundBall) {
            // 内野ゴロ統計（参考）
            groundTotal++;
            if (ab.result.isOut) groundOut++;
          }
        }
      }
    }
  }

  String pct(int o, int t) =>
      t == 0 ? '-' : '${(100.0 * o / t).toStringAsFixed(1)}%';

  print('===== 外野方向の打球タイプ別アウト率（${numSeasons}シーズン） =====');
  print('外野ライナー: 計 $linerTotal 件 / アウト $linerOut 件 / アウト率 ${pct(linerOut, linerTotal)}');
  print('外野フライ  : 計 $flyTotal 件 / アウト $flyOut 件 / アウト率 ${pct(flyOut, flyTotal)}');
  print('（参考）ゴロ : 計 $groundTotal 件 / アウト $groundOut 件 / アウト率 ${pct(groundOut, groundTotal)}');
  print('');
  print('現実値: ライナー 約27〜30% / フライ 約67〜72%');
  if (linerTotal > 0 && flyTotal > 0) {
    final linerRate = linerOut / linerTotal;
    final flyRate = flyOut / flyTotal;
    if (linerRate > flyRate) {
      print('🚨 ライナーのアウト率がフライのアウト率を上回っている。NG');
    } else {
      print('✓ ライナー < フライ の関係性は維持');
    }
  }
}

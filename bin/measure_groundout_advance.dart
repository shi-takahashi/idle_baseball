import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 内野ゴロアウト時の2塁走者進塁を検証。
///
/// 期待:
///  - 1塁走者なし（フォースなし）:
///      一・二・投・捕ゴロ → 2塁走者は高確率（~85%）で3塁へ
///      三・遊ゴロ         → 2塁走者は基本ステイ（進塁 ~15%）
///  - 1塁走者あり（フォース）+ 三・遊ゴロ + 1,2塁:
///      一定確率で2塁走者が3塁封殺（野選 / fieldersChoice）
void main() {
  const numSeasons = 3;

  // 1塁走者なし・2塁走者ありのゴロアウト
  int nfFrontTotal = 0, nfFrontAdvanced = 0;
  int nfLeftTotal = 0, nfLeftAdvanced = 0;

  // フォース（1,2塁）三・遊ゴロ
  int forceLeftGroundOut = 0; // 通常ゴロ（2塁走者は安全に3塁）
  int forceLeftFC = 0; // 野選（2塁走者3塁封殺）

  // 野選の妥当性チェック
  int fcFromGround = 0; // 非バントの fieldersChoice
  int fcBadPosition = 0; // 三・遊以外で発生（NG）
  int fcBadRunners = 0; // 1,2塁以外で発生（NG）

  bool isLeftSide(FieldPosition? p) =>
      p == FieldPosition.third || p == FieldPosition.shortstop;
  bool isInfieldFront(FieldPosition? p) =>
      p == FieldPosition.pitcher ||
      p == FieldPosition.catcher ||
      p == FieldPosition.first ||
      p == FieldPosition.second;

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(2600 + s)).generateLeague();
    final schedule = const ScheduleGenerator().generate(teams);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      random: Random(2600 + s),
    );
    controller.advanceAll();

    for (final sg in schedule.games) {
      final result = controller.resultFor(sg.gameNumber);
      if (result == null) continue;
      for (final half in result.halfInnings) {
        for (int i = 0; i < half.atBats.length; i++) {
          final ab = half.atBats[i];
          final before = ab.runnersBefore;
          final fp = ab.fieldPosition;

          // --- 非バント fieldersChoice（野選）の妥当性 ---
          if (ab.result == AtBatResultType.fieldersChoice && !ab.isBunt) {
            fcFromGround++;
            if (!isLeftSide(fp)) fcBadPosition++;
            if (before.first == null || before.second == null) fcBadRunners++;
            forceLeftFC++;
          }

          if (ab.result != AtBatResultType.groundOut) continue;

          // --- フォース（1,2塁）三・遊ゴロの通常ゴロ件数 ---
          // 2アウトは FC ロールに入らない（早期return）ので除外。
          if (before.first != null &&
              before.second != null &&
              before.third == null &&
              ab.outsBefore < 2 &&
              isLeftSide(fp)) {
            forceLeftGroundOut++;
          }

          // --- 1塁走者なし・2塁走者ありのゴロアウト ---
          if (before.first != null || before.second == null) continue;
          if (ab.outsBefore >= 2) continue; // 2アウトは進塁なし
          if (i + 1 >= half.atBats.length) continue; // 次打席なし（イニング終了）

          final secondRunner = before.second!;
          final after = half.atBats[i + 1].runnersBefore;
          final advanced = after.third?.id == secondRunner.id;

          if (isInfieldFront(fp)) {
            nfFrontTotal++;
            if (advanced) nfFrontAdvanced++;
          } else if (isLeftSide(fp)) {
            nfLeftTotal++;
            if (advanced) nfLeftAdvanced++;
          }
        }
      }
    }
  }

  String pct(int n, int d) =>
      d == 0 ? '-' : '${(n / d * 100).toStringAsFixed(1)}%';

  print('===== 内野ゴロアウト時の2塁走者進塁（${numSeasons}シーズン） =====');
  print('');
  print('【1塁走者なし・2塁走者あり】2塁走者が3塁へ進塁した割合');
  print('  一・二・投・捕ゴロ: $nfFrontAdvanced / $nfFrontTotal '
      '(${pct(nfFrontAdvanced, nfFrontTotal)})  ← 期待 ~85%');
  print('  三・遊ゴロ        : $nfLeftAdvanced / $nfLeftTotal '
      '(${pct(nfLeftAdvanced, nfLeftTotal)})  ← 期待 ~15%');
  print('');
  print('【フォース（1,2塁・3塁空き）三・遊ゴロ】');
  final forceLeftTotal = forceLeftGroundOut + forceLeftFC;
  print('  通常ゴロ（2塁走者は安全に3塁）: $forceLeftGroundOut');
  print('  野選（2塁走者3塁封殺）        : $forceLeftFC '
      '(${pct(forceLeftFC, forceLeftTotal)})');
  print('');
  print('【非バント fieldersChoice（野選）の妥当性】');
  print('  総数: $fcFromGround');
  print('  三・遊以外で発生: $fcBadPosition ${fcBadPosition == 0 ? "✓" : "🚨 NG"}');
  print('  1,2塁以外で発生: $fcBadRunners ${fcBadRunners == 0 ? "✓" : "🚨 NG"}');
}

import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 打者の左右（実効打席）ごとの内野安打・打撃成績を計測。
///
/// 確認したいこと:
/// - 左打者は一塁に近いぶん内野安打が多いはず。実際に差が出ているか
/// - 両打ちは対戦投手で左右が変わるため、at-bat ごとの実効打席で集計する
void main() {
  const numSeasons = 6;
  const gamesPerTeam = 150;

  // 実効打席（right / left）ごとの集計。投手の打席は除外。
  final pa = <Handedness, int>{Handedness.right: 0, Handedness.left: 0};
  final infieldHit = <Handedness, int>{Handedness.right: 0, Handedness.left: 0};
  final single = <Handedness, int>{Handedness.right: 0, Handedness.left: 0};
  final hits = <Handedness, int>{Handedness.right: 0, Handedness.left: 0};
  final ab = <Handedness, int>{Handedness.right: 0, Handedness.left: 0};

  const hitTypes = {
    AtBatResultType.single,
    AtBatResultType.infieldHit,
    AtBatResultType.double_,
    AtBatResultType.triple,
    AtBatResultType.homeRun,
  };
  // 打数に数えない結果（四球・死球・犠飛・犠打）
  const nonAbTypes = {
    AtBatResultType.walk,
    AtBatResultType.hitByPitch,
    AtBatResultType.sacrificeFly,
  };

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(8400 + s)).generateLeague();
    final schedule =
        ScheduleGenerator().generateForGamesPerTeam(teams, gamesPerTeam);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      gamesPerTeam: gamesPerTeam,
      random: Random(8400 + s),
    );
    controller.advanceAll();

    for (final sg in schedule.games) {
      final result = controller.resultFor(sg.gameNumber);
      if (result == null) continue;
      for (final half in result.halfInnings) {
        for (final atBat in half.atBats) {
          if (atBat.batter.isPitcher) continue;
          final side = atBat.batter.effectiveBatsAgainst(atBat.pitcher);
          // both は effectiveBatsAgainst で right/left に解決される
          if (side != Handedness.right && side != Handedness.left) continue;
          pa[side] = pa[side]! + 1;
          final r = atBat.result;
          if (atBat.isBunt) continue; // バントは打球性質が別なので除外
          if (!nonAbTypes.contains(r)) {
            ab[side] = ab[side]! + 1;
          }
          if (hitTypes.contains(r)) hits[side] = hits[side]! + 1;
          if (r == AtBatResultType.single) single[side] = single[side]! + 1;
          if (r == AtBatResultType.infieldHit) {
            infieldHit[side] = infieldHit[side]! + 1;
          }
        }
      }
    }
  }

  String f3(num v) => v.toStringAsFixed(3);
  String pct(num v) => '${(v * 100).toStringAsFixed(2)}%';

  print('===== 打者の左右 × 内野安打・打撃（$numSeasons シーズン × $gamesPerTeam 試合）=====');
  print('');
  for (final side in [Handedness.right, Handedness.left]) {
    final label = side == Handedness.right ? '右打席' : '左打席';
    final ihRate = infieldHit[side]! / ab[side]!;
    final ihShareOfHits = infieldHit[side]! / hits[side]!;
    print('[$label]  打席 ${pa[side]} / 打数 ${ab[side]}');
    print('  内野安打   : ${infieldHit[side]}'
        '  （打数あたり ${pct(ihRate)} / 安打に占める割合 ${pct(ihShareOfHits)}）');
    print('  単打(内野安打除く外野) : ${single[side]}');
    print('  打率       : ${f3(hits[side]! / ab[side]!)}');
    print('');
  }
  final rIh = infieldHit[Handedness.right]! / ab[Handedness.right]!;
  final lIh = infieldHit[Handedness.left]! / ab[Handedness.left]!;
  print('内野安打率（打数あたり）: 右 ${pct(rIh)} / 左 ${pct(lIh)}'
      '  → 左/右 = ${(lIh / rIh).toStringAsFixed(2)} 倍');
}

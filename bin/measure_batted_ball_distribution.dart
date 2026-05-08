import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 打球タイプ × 内野/外野方向の分布を計測。
///
/// NPB 実測の参考値:
/// - 打球種別: ゴロ ~46% / フライ ~33% / ライナー ~21%
/// - ライナーの方向: 外野ライナーの方が内野ライナーより多い
///   （角度のついた強い打球は外野に飛ぶため）
///
/// ユーザー指摘: 内野ライナーが多い印象 / 内野ゴロが少ないかも。
void main() {
  const numSeasons = 3;

  int totalInPlay = 0;
  int liner = 0, fly = 0, ground = 0;

  int linerInfield = 0, linerOutfield = 0;
  int flyInfield = 0, flyOutfield = 0;
  int groundInfield = 0, groundOutfield = 0;

  // アウト数
  int linerInfieldOut = 0, linerOutfieldOut = 0;
  int flyInfieldOut = 0, flyOutfieldOut = 0;
  int groundOut = 0;

  // 1試合あたりの内野ライナー件数を計測
  int games = 0;

  bool isOutfield(FieldPosition? p) =>
      p == FieldPosition.left ||
      p == FieldPosition.center ||
      p == FieldPosition.right;

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
      games++;
      for (final half in result.halfInnings) {
        for (final ab in half.atBats) {
          PitchResult? lastInPlay;
          for (final p in ab.pitches) {
            if (p.type == PitchResultType.inPlay) lastInPlay = p;
          }
          if (lastInPlay == null) continue;
          final btype = lastInPlay.battedBallType;
          final fpos = lastInPlay.fieldPosition;
          if (btype == null || fpos == null) continue;
          totalInPlay++;
          final outfield = isOutfield(fpos);

          switch (btype) {
            case BattedBallType.lineDrive:
              liner++;
              if (outfield) {
                linerOutfield++;
                if (ab.result.isOut) linerOutfieldOut++;
              } else {
                linerInfield++;
                if (ab.result.isOut) linerInfieldOut++;
              }
              break;
            case BattedBallType.flyBall:
              fly++;
              if (outfield) {
                flyOutfield++;
                if (ab.result.isOut) flyOutfieldOut++;
              } else {
                flyInfield++;
                if (ab.result.isOut) flyInfieldOut++;
              }
              break;
            case BattedBallType.groundBall:
              ground++;
              if (outfield) {
                groundOutfield++;
              } else {
                groundInfield++;
              }
              if (ab.result.isOut) groundOut++;
              break;
          }
        }
      }
    }
  }

  String pct(int x, int total) =>
      total == 0 ? '-' : '${(100.0 * x / total).toStringAsFixed(1)}%';
  String per(int x) =>
      games == 0 ? '-' : (x / games).toStringAsFixed(2);

  print('===== 打球タイプ × 方向分布（${numSeasons}シーズン × ${games}試合） =====');
  print('インプレー総数: $totalInPlay');
  print('');
  print('--- 打球タイプ内訳 ---');
  print('ゴロ    : $ground (${pct(ground, totalInPlay)}) ※ NPB ~46%');
  print('フライ  : $fly (${pct(fly, totalInPlay)}) ※ NPB ~33%');
  print('ライナー: $liner (${pct(liner, totalInPlay)}) ※ NPB ~21%');
  print('');
  print('--- ライナーの方向 ---');
  print('内野ライナー: $linerInfield (${pct(linerInfield, liner)}) / 1試合あたり ${per(linerInfield)} 件');
  print('外野ライナー: $linerOutfield (${pct(linerOutfield, liner)}) / 1試合あたり ${per(linerOutfield)} 件');
  print('  ※ NPB は外野ライナー > 内野ライナー（角度のついた強い打球は外野へ）');
  print('');
  print('--- フライの方向 ---');
  print('内野フライ: $flyInfield (${pct(flyInfield, fly)}) / 1試合あたり ${per(flyInfield)} 件');
  print('外野フライ: $flyOutfield (${pct(flyOutfield, fly)}) / 1試合あたり ${per(flyOutfield)} 件');
  print('');
  print('--- ゴロの方向 ---');
  print('内野ゴロ: $groundInfield (${pct(groundInfield, ground)}) / 1試合あたり ${per(groundInfield)} 件');
  print('外野ゴロ: $groundOutfield (${pct(groundOutfield, ground)}) / 1試合あたり ${per(groundOutfield)} 件');
  print('');
  print('--- アウト率 ---');
  print('内野ライナーアウト: $linerInfieldOut / $linerInfield = ${pct(linerInfieldOut, linerInfield)} / 1試合あたり ${per(linerInfieldOut)} 件');
  print('外野ライナーアウト: $linerOutfieldOut / $linerOutfield = ${pct(linerOutfieldOut, linerOutfield)}');
  print('内野フライアウト  : $flyInfieldOut / $flyInfield = ${pct(flyInfieldOut, flyInfield)}');
  print('外野フライアウト  : $flyOutfieldOut / $flyOutfield = ${pct(flyOutfieldOut, flyOutfield)}');
  print('ゴロアウト全体    : $groundOut / $ground = ${pct(groundOut, ground)}');
}

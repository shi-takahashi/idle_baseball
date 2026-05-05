import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 失策数を測定する。
/// 内訳: 内野捕球 / 内野送球 / 外野フライ落球 / クッション
///
/// NPB 水準の参考: 1チーム143試合で 60〜80 失策程度
void main() {
  num totalErrors = 0;
  num totalGames = 0;
  num totalAtBats = 0;
  num totalSeasons = 5;
  // 内訳カウンタ（FieldingErrorType x 内野/外野）
  int infieldFielding = 0;
  int infieldThrowing = 0;
  int outfieldThrowing = 0; // 単打→二塁打 / 二塁打→三塁打 の中継返球ミス
  int outfieldCushion = 0; // 二塁打→三塁打 のクッション処理ミス
  int outfieldFielding = 0; // 念のため計測（現状 0 想定）

  for (int s = 0; s < totalSeasons; s++) {
    final c = SeasonController.newSeason(
        random: Random(100 + s), gamesPerTeam: 30);
    c.advanceAll();
    for (final r in c.standings.records) {
      totalErrors += r.errors;
    }
    totalGames += c.schedule.games.length;
    for (final st in c.batterStats.values) {
      totalAtBats += st.atBats;
    }

    // 試合の at-bat を走査して失策の内訳を集計
    for (final g in c.schedule.games) {
      final result = c.resultFor(g.gameNumber);
      if (result == null) continue;
      for (final half in result.halfInnings) {
        for (final ab in half.atBats) {
          final fe = ab.fieldingError;
          if (fe == null) continue;
          final isOutfield = fe.position.isOutfield;
          switch (fe.type) {
            case FieldingErrorType.fielding:
              if (isOutfield) {
                outfieldFielding++;
              } else {
                infieldFielding++;
              }
              break;
            case FieldingErrorType.throwing:
              if (isOutfield) {
                outfieldThrowing++;
              } else {
                infieldThrowing++;
              }
              break;
            case FieldingErrorType.cushion:
              outfieldCushion++;
              break;
          }
        }
      }
    }
  }
  final perTeamPerSeason = totalErrors / (6 * totalSeasons);
  print('5 シーズン (30試合シーズン × 5) の累計:');
  print('  全試合数 (リーグ累計): $totalGames');
  print('  全打数 (リーグ累計): $totalAtBats');
  print('  全失策 (リーグ累計): $totalErrors');
  print('  1チーム30試合あたりの失策: ${perTeamPerSeason.toStringAsFixed(2)}');
  print('  143試合換算: ${(perTeamPerSeason * 143 / 30).toStringAsFixed(1)}');
  print('');
  print('--- 失策の内訳（リーグ累計） ---');
  final detailTotal = infieldFielding +
      infieldThrowing +
      outfieldThrowing +
      outfieldCushion +
      outfieldFielding;
  print('  内野・捕球失策: $infieldFielding');
  print('  内野・送球失策: $infieldThrowing');
  print('  外野・クッション処理: $outfieldCushion');
  print('  外野・中継返球ミス: $outfieldThrowing');
  print('  外野・捕球失策（参考、現状未実装で0想定）: $outfieldFielding');
  print('  内訳合計: $detailTotal');
  print('  ※ 内訳合計と全失策が一致しない場合: 内訳に出ない経路あり');
  print('');
  print('NPB水準（参考）: 1チーム143試合で 60〜80 失策程度');
}

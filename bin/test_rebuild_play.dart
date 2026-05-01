// オフシーズン後の整合性検証: シーズン 2 を実際にシミュレートして
// 守備位置不整合（players[i] が default position を守れない）が
// LineupPlanner の強制スワップで吸収されていることを確認。
import 'dart:math';

import 'package:idle_baseball/engine/engine.dart';

void main() {
  final c = SeasonController.newSeason(random: Random(42));

  // シーズン1 完走 → オフシーズン
  c.advanceAll();
  c.advanceToNextSeason();

  // CPU チームの players[0..7] と canPlay の不整合を集計
  // 再編成後は基本ゼロのはず（フォールバック発動の異常系のみ非ゼロ）
  print('--- シーズン 2 開幕時の不整合チェック ---');
  final defaultPositions = [
    DefensePosition.catcher,
    DefensePosition.first,
    DefensePosition.second,
    DefensePosition.third,
    DefensePosition.shortstop,
    DefensePosition.outfield,
    DefensePosition.outfield,
    DefensePosition.outfield,
  ];
  int totalMismatch = 0;
  for (final t in c.teams) {
    if (t.id == c.myTeamId) continue;
    int mismatch = 0;
    for (int i = 0; i < 8; i++) {
      if (!t.players[i].canPlay(defaultPositions[i])) {
        mismatch++;
        print('  NG: ${t.shortName} #$i (${defaultPositions[i].shortName}) '
            '=> ${t.players[i].name}');
      }
    }
    totalMismatch += mismatch;
    print('${t.shortName}: 不整合スロット $mismatch / 8');
  }
  if (totalMismatch != 0) {
    throw '不整合スロットが残っている: $totalMismatch';
  }

  // シーズン 2 を実際に回してエラーが出ないか
  print('\n--- シーズン 2 シミュレート ---');
  c.advanceAll();
  print('完走 OK');

  // 自チームの順位
  final st = c.standings.sorted;
  for (int i = 0; i < st.length; i++) {
    final r = st[i];
    final tag = r.team.id == c.myTeamId ? ' (自)' : '';
    print('${i + 1}位 ${r.team.shortName}$tag: '
        '${r.wins}勝${r.losses}敗${r.ties}分 '
        '得${r.runsScored}/失${r.runsAllowed}');
  }

  print('\nOK: シーズン 2 完走');
}

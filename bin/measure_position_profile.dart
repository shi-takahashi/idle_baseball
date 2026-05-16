import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// スタメン野手の能力をポジション別に集計し、守備位置パターン化を検証する。
void main() {
  const numLeagues = 200;
  final posOf = {
    0: '捕', 1: '一', 2: '二', 3: '三', 4: '遊',
    5: '左', 6: '中', 7: '右',
  };
  final sumPower = <int, int>{};
  final sumSpeed = <int, int>{};
  final sumMeet = <int, int>{};
  final sumArm = <int, int>{};
  final count = <int, int>{};
  // 例外カウント: 遊撃で長打7以上、捕手でミート7以上
  int bigSS = 0, ssTotal = 0, hitC = 0, cTotal = 0;

  for (int s = 0; s < numLeagues; s++) {
    final teams = TeamGenerator(random: Random(8000 + s)).generateLeague();
    for (final team in teams) {
      for (int i = 0; i < 8; i++) {
        final p = team.players[i];
        sumPower[i] = (sumPower[i] ?? 0) + (p.power ?? 0);
        sumSpeed[i] = (sumSpeed[i] ?? 0) + (p.speed ?? 0);
        sumMeet[i] = (sumMeet[i] ?? 0) + (p.meet ?? 0);
        sumArm[i] = (sumArm[i] ?? 0) + (p.arm ?? 0);
        count[i] = (count[i] ?? 0) + 1;
      }
      final ss = team.players[4];
      ssTotal++;
      if ((ss.power ?? 0) >= 7) bigSS++;
      final c = team.players[0];
      cTotal++;
      if ((c.meet ?? 0) >= 7) hitC++;
    }
  }

  print('===== スタメン野手 ポジション別平均能力（$numLeagues リーグ）=====');
  print('位置 | 長打 | 走力 | ミート | 肩');
  print('-----+------+------+--------+------');
  for (int i = 0; i < 8; i++) {
    final n = count[i]!;
    String f(Map<int, int> m) => (m[i]! / n).toStringAsFixed(2);
    print(' ${posOf[i]}  | ${f(sumPower).padLeft(4)} | '
        '${f(sumSpeed).padLeft(4)} | ${f(sumMeet).padLeft(5)}  | '
        '${f(sumArm).padLeft(4)}');
  }
  print('');
  print('例外の発生率:');
  print('  大型遊撃手（遊撃・長打7以上）: $bigSS / $ssTotal '
      '(${(bigSS / ssTotal * 100).toStringAsFixed(1)}%)');
  print('  打てる捕手（捕手・ミート7以上）: $hitC / $cTotal '
      '(${(hitC / cTotal * 100).toStringAsFixed(1)}%)');
}

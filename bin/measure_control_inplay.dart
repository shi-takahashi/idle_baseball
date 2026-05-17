import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 制球（control）がインプレー時の被安打率に与える影響を切り分ける制御計測。
/// `simulateInPlayResult` を制球だけ変えて多数回叩き、安打率を見る。
/// 季節計測で制球→被打率がフラットだった原因の切り分け用。
void main() {
  const trials = 300000;
  print('===== 制球 × インプレー被安打率（各 $trials 回、他は中庸固定） =====');
  print('');
  print(' 制球 | アウト率 | 安打率');
  print('------|----------|--------');
  for (int c = 1; c <= 10; c++) {
    final sim = AtBatSimulator(random: Random(1100 + c));
    int out = 0, hit = 0;
    for (int i = 0; i < trials; i++) {
      final r = sim.simulateInPlayResult(
        BattedBallType.flyBall, 145, c, 5, 5, 5,
        batterSpeed: 5,
        fieldPosition: FieldPosition.center,
        fielderArm: 5,
      );
      switch (r.result) {
        case AtBatResultType.flyOut:
        case AtBatResultType.groundOut:
        case AtBatResultType.lineOut:
          out++;
          break;
        case AtBatResultType.single:
        case AtBatResultType.infieldHit:
        case AtBatResultType.double_:
        case AtBatResultType.triple:
        case AtBatResultType.homeRun:
          hit++;
          break;
        default:
          break;
      }
    }
    String pct(int x) => '${(x / trials * 100).toStringAsFixed(1)}%';
    print('  ${c.toString().padLeft(2)}  '
        '|  ${pct(out).padLeft(6)}  '
        '| ${pct(hit).padLeft(6)}');
  }
}

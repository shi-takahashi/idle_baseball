import 'dart:math';
import 'package:idle_baseball/engine/simulation/error_simulator.dart';
import 'package:idle_baseball/engine/models/enums.dart';

/// `_forcedPlacementErrorMultiplier = 3.0` が正しく適用されるか、
/// 各 check メソッドの呼び出し回数をベースに 通常 vs 強制配置 で比較する。
void main() {
  const trials = 1000000;
  final sim = ErrorSimulator(random: Random(42));

  // 守備力 1 で内野ゴロエラー: 通常 vs 強制配置
  int normalGround = 0;
  int forcedGround = 0;
  for (int i = 0; i < trials; i++) {
    if (sim.checkGroundBallError(1, FieldPosition.shortstop)) normalGround++;
    if (sim.checkGroundBallError(1, FieldPosition.shortstop,
        isForcedPlacement: true)) forcedGround++;
  }
  _report('内野ゴロ (SS, 守備力1)', trials, normalGround, forcedGround);

  // 守備力 5 でも倍率が機能するか
  int normalGround5 = 0;
  int forcedGround5 = 0;
  for (int i = 0; i < trials; i++) {
    if (sim.checkGroundBallError(5, FieldPosition.shortstop)) normalGround5++;
    if (sim.checkGroundBallError(5, FieldPosition.shortstop,
        isForcedPlacement: true)) forcedGround5++;
  }
  _report('内野ゴロ (SS, 守備力5)', trials, normalGround5, forcedGround5);

  // 二塁打エラー (外野)
  int normalDouble = 0;
  int forcedDouble = 0;
  for (int i = 0; i < trials; i++) {
    if (sim.checkDoubleError(1, FieldPosition.left)) normalDouble++;
    if (sim.checkDoubleError(1, FieldPosition.left,
        isForcedPlacement: true)) forcedDouble++;
  }
  _report('二塁打エラー (LF, 守備力1)', trials, normalDouble, forcedDouble);

  // パスボール
  int normalPb = 0;
  int forcedPb = 0;
  for (int i = 0; i < trials; i++) {
    if (sim.checkPassedBall(1, PitchType.splitter)) normalPb++;
    if (sim.checkPassedBall(1, PitchType.splitter,
        isForcedPlacement: true)) forcedPb++;
  }
  _report('パスボール (捕守備力1, スプリッター)', trials, normalPb, forcedPb);
}

void _report(String label, int trials, int normal, int forced) {
  final ratio = normal == 0 ? double.nan : forced / normal;
  print('$label:');
  print('  通常: $normal / $trials (${(normal * 100 / trials).toStringAsFixed(3)}%)');
  print('  強制: $forced / $trials (${(forced * 100 / trials).toStringAsFixed(3)}%)');
  print('  比率: ${ratio.toStringAsFixed(2)}x  (目標 3.00x)');
}

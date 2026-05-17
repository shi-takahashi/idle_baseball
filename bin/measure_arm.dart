import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 肩（arm）の影響を計測する制御計測。
/// - 捕手の肩 → 盗塁成功率（強肩ほど成功率↓ = 盗塁阻止）
/// - 内野手の肩 → 内野安打率（強肩ほど内野安打↓）
/// - 外野手の肩 → タッチアップ（試行・成功とも arm で補正。式を末尾に表示）
void main() {
  print('===== 肩 × 各指標（制御計測、能力は中庸固定）=====');
  print('');
  _catcherArmVsSteal();
  print('');
  _infieldArmVsInfieldHit();
  print('');
  _tagUpReference();
}

/// 捕手の肩 1〜10 ごとの盗塁成功率。走者は走力8で固定。
void _catcherArmVsSteal() {
  const calls = 600000;
  print('--- 捕手の肩 × 盗塁成功率（走者の走力8で固定）---');
  print(' 肩 | 試行数 | 盗塁成功率 | （= 阻止率 100-）');
  print('----|--------|------------|------------------');
  final runner = Player(id: 'r', name: '走者', number: 1, speed: 8);
  final runners = BaseRunners(first: runner);
  for (int arm = 1; arm <= 10; arm++) {
    final sim = StealSimulator(random: Random(2000 + arm));
    int attempts = 0, success = 0;
    for (int i = 0; i < calls; i++) {
      for (final a in sim.simulateSteal(runners, 0, catcherArm: arm)) {
        attempts++;
        if (a.success) success++;
      }
    }
    final rate = success / attempts;
    print('  ${arm.toString().padLeft(2)}'
        '| ${attempts.toString().padLeft(6)} '
        '|   ${(rate * 100).toStringAsFixed(1).padLeft(5)}%   '
        '|   阻止 ${((1 - rate) * 100).toStringAsFixed(1)}%');
  }
}

/// 内野手の肩 1〜10 ごとの内野安打率。守備力5・打者走力7で固定。
void _infieldArmVsInfieldHit() {
  const trials = 300000;
  print('--- 内野手の肩 × 内野安打率（遊撃ゴロ、守備力5・打者走力7で固定）---');
  print(' 肩 | 内野安打率');
  print('----|------------');
  for (int arm = 1; arm <= 10; arm++) {
    final sim = AtBatSimulator(random: Random(3000 + arm));
    int infieldHit = 0;
    for (int i = 0; i < trials; i++) {
      final r = sim.simulateInPlayResult(
        BattedBallType.groundBall, 145, 5, 5, 5, 5,
        batterSpeed: 7,
        fieldPosition: FieldPosition.shortstop,
        fielderArm: arm,
      );
      if (r.result == AtBatResultType.infieldHit) infieldHit++;
    }
    print('  ${arm.toString().padLeft(2)}'
        '|   ${(infieldHit / trials * 100).toStringAsFixed(2)}%');
  }
}

/// 外野手の肩によるタッチアップ補正（中くらいのフライ時）。
/// 内部メソッドが private なので式を表示して参考とする。
void _tagUpReference() {
  print('--- 外野手の肩 × タッチアップ（中フライ時、走者走力5で計算）---');
  print(' 肩 | 試行確率 | 成功確率');
  print('----|----------|----------');
  for (int arm = 1; arm <= 10; arm++) {
    final attempt = (0.50 + (5 - 5) * 0.04 - (arm - 5) * 0.04).clamp(0.05, 0.95);
    final success =
        (0.85 + (5 - 5) * 0.015 - (arm - 5) * 0.015).clamp(0.50, 0.95);
    print('  ${arm.toString().padLeft(2)}'
        '|  ${(attempt * 100).toStringAsFixed(0).padLeft(4)}%   '
        '|  ${(success * 100).toStringAsFixed(1).padLeft(5)}%');
  }
  print('（浅い/深いフライは深さで決まり肩は無関係。中フライのみ肩が効く）');
}

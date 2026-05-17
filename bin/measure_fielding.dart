import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 守備力（fielding）がインプレー結果に与える影響を計測する制御計測。
///
/// 守備力は「エラー確率」だけでなく「アウトになる確率」そのものにも効く
/// （守備範囲 = 普通は抜ける打球を捕ってアウトにする）。
/// `simulateInPlayResult` を守備力だけ変えて多数回叩き、アウト率・安打率・
/// 失策率を守備力ごとに集計する。打者・投手・球種などは中庸（5 / 145km）で固定。
///
/// 末尾に「強制配置」（守れないポジションに無理やり配置 = 守備力1 +
/// isFielderForcedPlacement）の行を出し、守備力1の正規配置と比較する。
/// 期待: 強制配置はアウト率が守備力1と同等以下・失策率が約3倍。
void main() {
  const trials = 200000;

  print('===== 守備力 × インプレー結果（各 $trials 回、能力は中庸固定） =====');
  print('');
  _run('内野ゴロ（遊撃）', BattedBallType.groundBall, FieldPosition.shortstop,
      trials);
  print('');
  _run('外野フライ（中堅）', BattedBallType.flyBall, FieldPosition.center, trials);
  print('');
  _run('外野ライナー（左翼）', BattedBallType.lineDrive, FieldPosition.left, trials);
}

({int out, int hit, int error}) _tally(
    BattedBallType type, FieldPosition pos, int fielding, bool forced,
    int trials) {
  final sim = AtBatSimulator(random: Random(1000 + fielding + (forced ? 99 : 0)));
  int out = 0, hit = 0, error = 0;
  for (int i = 0; i < trials; i++) {
    final r = sim.simulateInPlayResult(
      type, 145, 5, 5, 5, fielding,
      batterSpeed: 5,
      fieldPosition: pos,
      fielderArm: 5,
      isFielderForcedPlacement: forced,
    );
    switch (r.result) {
      case AtBatResultType.groundOut:
      case AtBatResultType.flyOut:
      case AtBatResultType.lineOut:
        out++;
        break;
      case AtBatResultType.reachedOnError:
        error++;
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
  return (out: out, hit: hit, error: error);
}

void _run(String label, BattedBallType type, FieldPosition pos, int trials) {
  String pct(int x) => '${(x / trials * 100).toStringAsFixed(1)}%';

  print('--- $label ---');
  print(' 守備力 | アウト率 | 安打率 | 失策率');
  print('--------|----------|--------|--------');
  for (int f = 1; f <= 10; f++) {
    final t = _tally(type, pos, f, false, trials);
    print('   ${f.toString().padLeft(2)}   '
        '|  ${pct(t.out).padLeft(6)}  '
        '| ${pct(t.hit).padLeft(6)} '
        '| ${pct(t.error).padLeft(6)}');
  }
  // 強制配置（守れないポジション = 守備力1 + isForcedPlacement）
  final forced = _tally(type, pos, 1, true, trials);
  print('  強制  '
      '|  ${pct(forced.out).padLeft(6)}  '
      '| ${pct(forced.hit).padLeft(6)} '
      '| ${pct(forced.error).padLeft(6)}');
}

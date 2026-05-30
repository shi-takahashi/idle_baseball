import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 投手能力スイープ計測スクリプト。
///
/// 「他の能力を 5 固定、対象能力を 1〜9 でスイープ」して 150試合相当の
/// IP/K/BB/H/HR/ER と派生指標（ERA/WHIP/K9/BB9/被打率）を表で出す。
///
/// 使用例:
///   dart run bin/sweep_pitcher.dart velocity   # 球速 130-160 スイープ
///   dart run bin/sweep_pitcher.dart control    # 制球 1-9
///   dart run bin/sweep_pitcher.dart fastball   # 伸び 1-9
///   dart run bin/sweep_pitcher.dart stamina    # スタミナ 1-9（疲労開始球数）
///   dart run bin/sweep_pitcher.dart breaking   # 変化球（スライダーを代表）
///   dart run bin/sweep_pitcher.dart all
///
/// 対象投手 1 人を先発に固定して 30 登板（≒ NPB シーズン）させ、他は標準
/// 投手陣・標準野手陣で計測。打撃側の sweep_batter と対になる構成。
void main(List<String> args) {
  final target = args.isEmpty ? 'all' : args[0];
  // サンプル数を増やしてランダム性を平準化（30登板=1シーズンだと ERA ±0.5 のブレ）
  const numStarts = 90;
  // 通常能力（1〜9 スイープ）と、球速（130〜160 km/h スイープ）の値リスト
  const abilityValues = [1, 3, 5, 7, 9];
  const velocityValues = [135, 140, 145, 150, 155, 160];

  Player makeStarter({
    int averageSpeed = 147,
    int fastball = 5,
    int control = 5,
    int slider = 5,
    int curve = 5,
    int splitter = 5,
    int changeup = 5,
    int? shoot,
    int? cutter,
    int? sinker,
    int stamina = 5,
  }) {
    return Player(
      id: 'target',
      name: 'テスト対象',
      number: 11,
      averageSpeed: averageSpeed,
      fastball: fastball,
      control: control,
      slider: slider,
      curve: curve,
      splitter: splitter,
      changeup: changeup,
      shoot: shoot,
      cutter: cutter,
      sinker: sinker,
      stamina: stamina,
      pitcherRole: PitcherRole.starter,
    );
  }

  Player makeStdRelief(String id, int num) => Player(
        id: id,
        name: id,
        number: num,
        averageSpeed: 147,
        fastball: 5,
        control: 5,
        slider: 5,
        curve: 5,
        pitcherRole: PitcherRole.middle,
      );

  Player makeStdBatter(String id, int num) => Player(
        id: id,
        name: id,
        number: num,
        meet: 5,
        power: 5,
        speed: 5,
        eye: 5,
        arm: 5,
      );

  // 対象投手が先発のチーム（リリーフはダミー、対象投手だけが登板する想定）
  Team makePitchingTeam(Player starter) {
    return Team(
      id: 'pitching',
      name: 'P',
      players: [
        for (int i = 0; i < 8; i++) makeStdBatter('p_bat_$i', i + 1),
        starter,
      ],
    );
  }

  // 相手打者チーム（標準能力）
  Team makeBattingTeam() {
    return Team(
      id: 'batting',
      name: 'B',
      players: [
        for (int i = 0; i < 8; i++) makeStdBatter('b_$i', i + 1),
        makeStdRelief('b_pitcher', 18),
      ],
    );
  }

  ({int outs, int h, int hr, int bb, int k, int er, int batters}) simulate({
    required int averageSpeed,
    required int fastball,
    required int control,
    required int slider,
    required int curve,
    required int splitter,
    required int changeup,
    int? shoot,
    int? cutter,
    int? sinker,
    int stamina = 5,
    required int seed,
  }) {
    final starter = makeStarter(
      averageSpeed: averageSpeed,
      fastball: fastball,
      control: control,
      slider: slider,
      curve: curve,
      splitter: splitter,
      changeup: changeup,
      shoot: shoot,
      cutter: cutter,
      sinker: sinker,
      stamina: stamina,
    );
    final pitching = makePitchingTeam(starter);
    final batting = makeBattingTeam();

    int outs = 0, h = 0, hr = 0, bb = 0, k = 0, er = 0, batters = 0;
    final random = Random(seed);
    for (int g = 0; g < numStarts; g++) {
      final sim = GameSimulator(random: Random(random.nextInt(1 << 31)));
      final result = sim.simulate(pitching, batting); // pitching が home
      // pitching = home → 守備は「表」(away 攻撃) のイニング
      for (final half in result.halfInnings.where((h) => h.isTop)) {
        for (final ab in half.atBats) {
          // 対象投手が投げた打席のみ集計（リリーフ降板後は除く）
          if (ab.pitcher.id != 'target') continue;
          if (ab.isIncomplete) continue;
          batters++;
          final r = ab.result;
          if (r == AtBatResultType.walk) bb++;
          if (r == AtBatResultType.strikeout) {
            k++;
            outs++;
          }
          if (r.isHit) h++;
          if (r == AtBatResultType.homeRun) hr++;
          // アウト集計
          if (r == AtBatResultType.groundOut ||
              r == AtBatResultType.flyOut ||
              r == AtBatResultType.lineOut ||
              r == AtBatResultType.doublePlay ||
              r == AtBatResultType.sacrificeFly ||
              r == AtBatResultType.sacrificeBunt) {
            outs += (r == AtBatResultType.doublePlay) ? 2 : 1;
          }
          if (r == AtBatResultType.fieldersChoice) outs++;
          // 自責点（rbiCount は打点とは別）
          er += ab.runsScored;
        }
      }
    }
    return (
      outs: outs,
      h: h,
      hr: hr,
      bb: bb,
      k: k,
      er: er,
      batters: batters,
    );
  }

  void runSweep(
    String label,
    List<int> values,
    Player Function(int v) build,
    String unit,
  ) {
    print('===== $label スイープ（他能力 5 固定、$numStarts 登板）=====');
    print(' $unit | IP   | BF | K  | BB | H  | HR | ER | ERA   | WHIP | K/9  | BB/9 | HR/9 | 被打率');
    print('--------|------|----|----|----|----|----|----|-------|------|------|------|------|------');
    for (final v in values) {
      final p = build(v);
      final r = simulate(
        averageSpeed: p.averageSpeed ?? 147,
        fastball: p.fastball ?? 5,
        control: p.control ?? 5,
        slider: p.slider ?? 5,
        curve: p.curve ?? 5,
        splitter: p.splitter ?? 5,
        changeup: p.changeup ?? 5,
        stamina: p.stamina ?? 5,
        seed: 5000 + v,
      );
      final ip = r.outs / 3.0;
      final era = ip > 0 ? r.er / ip * 9 : 0.0;
      final whip = ip > 0 ? (r.bb + r.h) / ip : 0.0;
      final k9 = ip > 0 ? r.k / ip * 9 : 0.0;
      final bb9 = ip > 0 ? r.bb / ip * 9 : 0.0;
      final hr9 = ip > 0 ? r.hr / ip * 9 : 0.0;
      final baa = r.batters > 0
          ? r.h / (r.batters - r.bb - 0).clamp(1, 100000) // bb 引いた打数で割る
          : 0.0;
      print(' ${v.toString().padLeft(4)}   '
          '| ${ip.toStringAsFixed(1).padLeft(4)} '
          '| ${r.batters.toString().padLeft(3)} '
          '| ${r.k.toString().padLeft(3)} '
          '| ${r.bb.toString().padLeft(2)} '
          '| ${r.h.toString().padLeft(3)} '
          '| ${r.hr.toString().padLeft(2)} '
          '| ${r.er.toString().padLeft(3)} '
          '| ${era.toStringAsFixed(2).padLeft(5)} '
          '| ${whip.toStringAsFixed(2)} '
          '| ${k9.toStringAsFixed(1).padLeft(4)} '
          '| ${bb9.toStringAsFixed(1).padLeft(4)} '
          '| ${hr9.toStringAsFixed(1).padLeft(4)} '
          '| ${baa.toStringAsFixed(3)}');
    }
    print('');
  }

  if (target == 'velocity' || target == 'all') {
    runSweep('球速 km/h', velocityValues, (v) => makeStarter(averageSpeed: v),
        '球速');
  }
  if (target == 'control' || target == 'all') {
    runSweep('制球', abilityValues, (v) => makeStarter(control: v), '制球');
  }
  if (target == 'fastball' || target == 'all') {
    runSweep('伸び（ストレートの質）', abilityValues,
        (v) => makeStarter(fastball: v), '伸び');
  }
  if (target == 'stamina' || target == 'all') {
    // スタミナは疲労開始球数（1=50球〜10=100球）。先発が深いイニングまで投げると
    // 差が出る。低スタミナは中盤で崩れ ERA 悪化・IP 減になるはず。
    runSweep('スタミナ', abilityValues, (v) => makeStarter(stamina: v), 'スタ');
  }
  if (target == 'slider' || target == 'all') {
    runSweep('スライダー', abilityValues, (v) => makeStarter(slider: v), 'SL');
  }
  if (target == 'curve' || target == 'all') {
    runSweep('カーブ', abilityValues, (v) => makeStarter(curve: v), 'CV');
  }
  if (target == 'splitter' || target == 'all') {
    runSweep('スプリット', abilityValues, (v) => makeStarter(splitter: v), 'SF');
  }
  if (target == 'changeup' || target == 'all') {
    runSweep('チェンジアップ', abilityValues, (v) => makeStarter(changeup: v),
        'CU');
  }

  // 投手タイプ別の組み合わせ計測
  if (target == 'combo' || target == 'all') {
    print('===== 投手タイプ別の組み合わせ計測（30登板）=====');
    print(
        ' タイプ                          | IP   | BF | K  | BB | H  | HR | ER | ERA   | WHIP | K/9  | 被打率');
    print(
        '--------------------------------|------|----|----|----|----|----|----|-------|------|------|------');
    void runCombo(String label,
        {required int averageSpeed,
        required int fastball,
        required int control,
        required int slider,
        required int curve,
        required int splitter,
        required int changeup,
        int? shoot,
        int? cutter,
        int? sinker}) {
      final r = simulate(
        averageSpeed: averageSpeed,
        fastball: fastball,
        control: control,
        slider: slider,
        curve: curve,
        splitter: splitter,
        changeup: changeup,
        shoot: shoot,
        cutter: cutter,
        sinker: sinker,
        seed: 8000 + averageSpeed + fastball * 7 + control * 13,
      );
      final ip = r.outs / 3.0;
      final era = ip > 0 ? r.er / ip * 9 : 0.0;
      final whip = ip > 0 ? (r.bb + r.h) / ip : 0.0;
      final k9 = ip > 0 ? r.k / ip * 9 : 0.0;
      final baa = r.batters > 0
          ? r.h / (r.batters - r.bb).clamp(1, 100000)
          : 0.0;
      print(' ${label.padRight(31)}'
          '| ${ip.toStringAsFixed(1).padLeft(4)} '
          '| ${r.batters.toString().padLeft(3)} '
          '| ${r.k.toString().padLeft(3)} '
          '| ${r.bb.toString().padLeft(2)} '
          '| ${r.h.toString().padLeft(3)} '
          '| ${r.hr.toString().padLeft(2)} '
          '| ${r.er.toString().padLeft(3)} '
          '| ${era.toStringAsFixed(2).padLeft(5)} '
          '| ${whip.toStringAsFixed(2)} '
          '| ${k9.toStringAsFixed(1).padLeft(4)} '
          '| ${baa.toStringAsFixed(3)}');
    }

    // ユーザー実戦サンプル
    runCombo('A投手(球153/伸6/制7/SL5/CV8/SF8)',
        averageSpeed: 153, fastball: 6, control: 7,
        slider: 5, curve: 8, splitter: 8, changeup: 5);
    runCombo('B投手(球145/伸5/制7/SL8/CV7/SF7/シュ8)',
        averageSpeed: 145, fastball: 5, control: 7,
        slider: 8, curve: 7, splitter: 7, changeup: 5, shoot: 8);
    runCombo('C投手(球148/伸6/制6/SL7/CV3/SF6/シュ6)',
        averageSpeed: 148, fastball: 6, control: 6,
        slider: 7, curve: 3, splitter: 6, changeup: 5, shoot: 6);
    // pinpoint 比較: A投手から1能力だけ変えた仮想投手
    print(' [pinpoint] A投手から1能力だけ変える ↓');
    runCombo('  A+SL=7 (Aのスライダー5→7)',
        averageSpeed: 153, fastball: 6, control: 7,
        slider: 7, curve: 8, splitter: 8, changeup: 5);
    runCombo('  A+球速148 (球速だけ下げる)',
        averageSpeed: 148, fastball: 6, control: 7,
        slider: 5, curve: 8, splitter: 8, changeup: 5);
    runCombo('  A+制球6 (制球だけ下げる)',
        averageSpeed: 153, fastball: 6, control: 6,
        slider: 5, curve: 8, splitter: 8, changeup: 5);
    // C投手から1能力だけ変えた仮想投手
    print(' [pinpoint] C投手から1能力だけ変える ↓');
    runCombo('  C+SL=5 (CのSL7→5、Aと同等)',
        averageSpeed: 148, fastball: 6, control: 6,
        slider: 5, curve: 3, splitter: 6, changeup: 5, shoot: 6);
    runCombo('  C-シュート (持ち球を4種に減らす)',
        averageSpeed: 148, fastball: 6, control: 6,
        slider: 7, curve: 3, splitter: 6, changeup: 5);
    runCombo('エース型(球155/伸9/制8/SL9/SF9)',
        averageSpeed: 155, fastball: 9, control: 8,
        slider: 9, curve: 5, splitter: 9, changeup: 5);
    runCombo('剛球派(球158/伸9/制4/SL5)',
        averageSpeed: 158, fastball: 9, control: 4,
        slider: 5, curve: 5, splitter: 5, changeup: 5);
    runCombo('制球派(球143/伸5/制9/SL7/CV7)',
        averageSpeed: 143, fastball: 5, control: 9,
        slider: 7, curve: 7, splitter: 5, changeup: 5);
    runCombo('変化球派(球145/伸5/制7/SL8/CV8/SF8/CU8)',
        averageSpeed: 145, fastball: 5, control: 7,
        slider: 8, curve: 8, splitter: 8, changeup: 8);
    runCombo('オール9(球155/伸9/制9/全変9)',
        averageSpeed: 155, fastball: 9, control: 9,
        slider: 9, curve: 9, splitter: 9, changeup: 9);
    runCombo('平均(球147/全5)',
        averageSpeed: 147, fastball: 5, control: 5,
        slider: 5, curve: 5, splitter: 5, changeup: 5);
    runCombo('弱小(球140/伸3/制3/SL3)',
        averageSpeed: 140, fastball: 3, control: 3,
        slider: 3, curve: 3, splitter: 3, changeup: 3);
    print('');
  }
}

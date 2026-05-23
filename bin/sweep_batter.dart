import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 打者能力スイープ計測スクリプト。
///
/// 「他の能力を 5 固定、対象能力を 1〜9 でスイープ」して 150試合相当の
/// PA/AB/H/HR/BB/K と派生指標（打率/BB%/K%）を表で出す。
///
/// 使用例:
///   dart run bin/sweep_batter.dart eye       # 選球眼 1-9 スイープ
///   dart run bin/sweep_batter.dart meet
///   dart run bin/sweep_batter.dart power
///   dart run bin/sweep_batter.dart all       # 全部
///
/// 1チーム = 9人すべて同じ能力で 150試合、相手は平均能力チーム + 平均投手。
/// 出力の「PA/K/BB/H/HR」は **1選手 150試合あたり**（9 で割って per-player に正規化）。
void main(List<String> args) {
  final target = args.isEmpty ? 'all' : args[0];
  const numGames = 150;
  const values = [1, 3, 5, 7, 9];

  // リーグ平均投手（4変化球持ち、各能力 5）。
  // NPB の主力投手は変化球 4-5 種類が標準で、変化球数を絞ると打者に有利な
  // 「やや甘い投手」になる。本 sweep はリーグ実戦の打撃成績と一致する基準を
  // 提供することを目的に、変化球数を実戦の平均（4種類）に揃える。
  Player makePitcher() => const Player(
        id: 'pitcher',
        name: '相手投手',
        number: 18,
        averageSpeed: 147,
        fastball: 5,
        control: 5,
        slider: 5,
        curve: 5,
        splitter: 5,
        changeup: 5,
      );

  // 「対象選手 1 人 + 他は標準」ラインナップ。
  // 9人全員を同じ能力にすると、巧打者では出塁が連鎖して打席数が増え、絶対値の
  // 比較が歪む（同じK% でも打席数増で K数 が増える）。対象選手 1 人だけ特性を
  // 与え、他は中立にすることで「現実のスタメン 1 人」の絶対値が出る形にする。
  Team makeBatterTeam({
    required int meet,
    required int power,
    required int eye,
    required int speed,
  }) {
    return Team(
      id: 'b',
      name: '打者',
      players: [
        Player(
          id: 'target',
          name: 'テスト対象',
          number: 1,
          meet: meet,
          power: power,
          speed: speed,
          eye: eye,
          arm: 5,
        ),
        ...List.generate(
          7,
          (i) => Player(
            id: 'b_${i + 1}',
            name: '標準${i + 1}',
            number: i + 2,
            meet: 5,
            power: 5,
            speed: 5,
            eye: 5,
            arm: 5,
          ),
        ),
        makePitcher(),
      ],
    );
  }

  Team makeOpponent() {
    return Team(
      id: 'opp',
      name: '相手',
      players: [
        ...List.generate(
          8,
          (i) => Player(
            id: 'o_$i',
            name: '相手${i + 1}',
            number: i + 1,
            meet: 5,
            power: 5,
            speed: 5,
            eye: 5,
            arm: 5,
          ),
        ),
        makePitcher(),
      ],
    );
  }

  ({int pa, int ab, int h, int hr, int bb, int k, int sb}) simulate({
    required int meet,
    required int power,
    required int eye,
    required int speed,
    required int seed,
  }) {
    final batting = makeBatterTeam(meet: meet, power: power, eye: eye, speed: speed);
    final opp = makeOpponent();
    int pa = 0, ab = 0, h = 0, hr = 0, bb = 0, k = 0, sb = 0;
    final random = Random(seed);
    for (int g = 0; g < numGames; g++) {
      final sim = GameSimulator(random: Random(random.nextInt(1 << 31)));
      final result = sim.simulate(opp, batting); // 打者チームを away に
      for (final half in result.halfInnings.where((h) => h.isTop)) {
        for (final at in half.atBats) {
          if (at.batter.id != 'target') continue; // 対象選手のみ集計
          if (at.isIncomplete) continue;
          pa++;
          final r = at.result;
          final isBB = r == AtBatResultType.walk;
          final isHBP = r == AtBatResultType.hitByPitch;
          final isSacBunt = r == AtBatResultType.sacrificeBunt;
          final isSacFly = r == AtBatResultType.sacrificeFly;
          if (!isBB && !isHBP && !isSacBunt && !isSacFly) ab++;
          if (r.isHit) h++;
          if (r == AtBatResultType.homeRun) hr++;
          if (isBB) bb++;
          if (r == AtBatResultType.strikeout) k++;
        }
        // 盗塁集計（対象選手のみ）
        for (final ev in half.stealEvents) {
          for (final att in ev.attempts) {
            if (att.runner.id == 'target' && att.success) sb++;
          }
        }
      }
    }
    return (pa: pa, ab: ab, h: h, hr: hr, bb: bb, k: k, sb: sb);
  }

  void runSweep(String label, {required int Function(int v) meetFn,
      required int Function(int v) powerFn,
      required int Function(int v) eyeFn,
      required int Function(int v) speedFn}) {
    print('===== $label スイープ（他能力 5 固定、$numGames 試合 × 9人プール → per-player に正規化）=====');
    print(' val | PA | AB | H  | HR | BB | K  | SB | 打率 | BB%  | K%');
    print('-----|----|----|----|----|----|----|----|------|------|------');
    for (final v in values) {
      final r = simulate(
        meet: meetFn(v),
        power: powerFn(v),
        eye: eyeFn(v),
        speed: speedFn(v),
        seed: 1000 + v,
      );
      final avg = r.ab > 0 ? (r.h / r.ab).toStringAsFixed(3) : '-';
      final bbPct = r.pa > 0 ? '${(r.bb / r.pa * 100).toStringAsFixed(1)}%' : '-';
      final kPct = r.pa > 0 ? '${(r.k / r.pa * 100).toStringAsFixed(1)}%' : '-';
      print(' ${v.toString().padLeft(2)}  '
          '| ${r.pa.toString().padLeft(3)} '
          '| ${r.ab.toString().padLeft(3)} '
          '| ${r.h.toString().padLeft(2)} '
          '| ${r.hr.toString().padLeft(2)} '
          '| ${r.bb.toString().padLeft(2)} '
          '| ${r.k.toString().padLeft(3)} '
          '| ${r.sb.toString().padLeft(2)} '
          '| $avg '
          '| ${bbPct.padLeft(5)} '
          '| ${kPct.padLeft(5)}');
    }
    print('');
  }

  if (target == 'meet' || target == 'all') {
    runSweep('ミート力',
        meetFn: (v) => v, powerFn: (_) => 5, eyeFn: (_) => 5, speedFn: (_) => 5);
  }
  if (target == 'power' || target == 'all') {
    runSweep('長打力',
        meetFn: (_) => 5, powerFn: (v) => v, eyeFn: (_) => 5, speedFn: (_) => 5);
  }
  if (target == 'eye' || target == 'all') {
    runSweep('選球眼',
        meetFn: (_) => 5, powerFn: (_) => 5, eyeFn: (v) => v, speedFn: (_) => 5);
  }
  if (target == 'speed' || target == 'all') {
    runSweep('走力',
        meetFn: (_) => 5, powerFn: (_) => 5, eyeFn: (_) => 5, speedFn: (v) => v);
  }

  // 組み合わせモード: 代表的な選手タイプの再現確認
  if (target == 'combo' || target == 'all') {
    print('===== 選手タイプ別の組み合わせ計測（per-player 150試合）=====');
    print(' タイプ                     | PA | AB | H  | HR | BB | K  | SB | 打率 | BB%  | K%');
    print('---------------------------|----|----|----|----|----|----|----|------|------|------');
    void runCombo(String label, int meet, int power, int eye, int speed) {
      final r = simulate(meet: meet, power: power, eye: eye, speed: speed, seed: 7000 + meet + power * 11 + eye * 101);
      final avg = r.ab > 0 ? (r.h / r.ab).toStringAsFixed(3) : '-';
      final bbPct = r.pa > 0 ? '${(r.bb / r.pa * 100).toStringAsFixed(1)}%' : '-';
      final kPct = r.pa > 0 ? '${(r.k / r.pa * 100).toStringAsFixed(1)}%' : '-';
      print(' ${label.padRight(26)}'
          '| ${r.pa.toString().padLeft(3)} '
          '| ${r.ab.toString().padLeft(3)} '
          '| ${r.h.toString().padLeft(2)} '
          '| ${r.hr.toString().padLeft(2)} '
          '| ${r.bb.toString().padLeft(2)} '
          '| ${r.k.toString().padLeft(3)} '
          '| ${r.sb.toString().padLeft(2)} '
          '| $avg '
          '| ${bbPct.padLeft(5)} '
          '| ${kPct.padLeft(5)}');
    }

    runCombo('巧打者(ミ9/長7/眼9)', 9, 7, 9, 5);
    runCombo('巧打者(ミ8/長5/眼8)', 8, 5, 8, 5);
    runCombo('巧打者(ミ8/長3/眼7)', 8, 3, 7, 5);
    runCombo('強打者(ミ3/長9/眼5)', 3, 9, 5, 5);
    runCombo('強打者(ミ5/長9/眼7)', 5, 9, 7, 5);
    runCombo('シュワーバー型(ミ1/長9/眼3)', 1, 9, 3, 4);
    runCombo('5ツール(ミ8/長8/眼8/走8)', 8, 8, 8, 8);
    runCombo('オール9(ミ9/長9/眼9/走9)', 9, 9, 9, 9);
    runCombo('イチロー型(ミ10/長6/眼8/走9)', 10, 6, 8, 9);
    runCombo('ボンズ型(ミ8/長10/眼10)', 8, 10, 10, 5);
    runCombo('平均(5/5/5/5)', 5, 5, 5, 5);
    runCombo('弱打者(ミ3/長3/眼3)', 3, 3, 3, 3);
    print('');
  }
}

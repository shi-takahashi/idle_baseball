import 'dart:math';
import '../models/models.dart';
import 'at_bat_simulator.dart';

/// 試合シミュレーター
class GameSimulator {
  final AtBatSimulator _atBatSimulator;

  GameSimulator({Random? random})
      : _atBatSimulator = AtBatSimulator(random: random);

  /// 1試合をシミュレート
  GameResult simulate(Team homeTeam, Team awayTeam) {
    final inningScores = <InningScore>[];
    final halfInnings = <HalfInningResult>[];

    int homeScore = 0;
    int awayScore = 0;
    int homeBattingOrder = 0; // ホームチームの打順
    int awayBattingOrder = 0; // アウェイチームの打順

    for (int inning = 1; inning <= 9; inning++) {
      // 表（アウェイチームの攻撃）
      final topResult = _simulateHalfInning(
        inning: inning,
        isTop: true,
        battingTeam: awayTeam,
        pitchingTeam: homeTeam,
        battingOrder: awayBattingOrder,
      );
      halfInnings.add(topResult.halfInning);
      awayScore += topResult.halfInning.runs;
      awayBattingOrder = topResult.nextBattingOrder;

      // 裏（ホームチームの攻撃）
      final bottomResult = _simulateHalfInning(
        inning: inning,
        isTop: false,
        battingTeam: homeTeam,
        pitchingTeam: awayTeam,
        battingOrder: homeBattingOrder,
      );
      halfInnings.add(bottomResult.halfInning);
      homeScore += bottomResult.halfInning.runs;
      homeBattingOrder = bottomResult.nextBattingOrder;

      inningScores.add(InningScore(
        top: topResult.halfInning.runs,
        bottom: bottomResult.halfInning.runs,
      ));
    }

    return GameResult(
      homeTeamName: homeTeam.name,
      awayTeamName: awayTeam.name,
      inningScores: inningScores,
      halfInnings: halfInnings,
      homeScore: homeScore,
      awayScore: awayScore,
    );
  }

  /// 1イニング（表または裏）をシミュレート
  _HalfInningSimulationResult _simulateHalfInning({
    required int inning,
    required bool isTop,
    required Team battingTeam,
    required Team pitchingTeam,
    required int battingOrder,
  }) {
    final atBats = <AtBatResult>[];
    int outs = 0;
    int runs = 0;
    BaseRunners runners = BaseRunners.empty;
    int currentBattingOrder = battingOrder;

    while (outs < 3) {
      final batter = battingTeam.getBatter(currentBattingOrder);
      final pitcher = pitchingTeam.pitcher;

      // 打席前の状態を保存
      final outsBefore = outs;
      final runnersBefore = runners;

      // 打席シミュレーション
      final (resultType, pitches) = _atBatSimulator.simulateAtBat(pitcher, batter);

      // インプレー時の打球方向を取得（最後の投球結果から）
      FieldPosition? fieldPosition;
      if (pitches.isNotEmpty && pitches.last.type == PitchResultType.inPlay) {
        fieldPosition = pitches.last.fieldPosition;
      }

      // 走塁処理（アウトカウントを渡す）
      final advanceResult = _advanceRunners(runners, resultType, batter, outs);
      final rbiCount = advanceResult.runsScored;
      runs += rbiCount;
      runners = advanceResult.newRunners;

      // アウトカウント
      if (resultType.isOut) {
        outs++;
      }

      atBats.add(AtBatResult(
        batter: batter,
        pitcher: pitcher,
        inning: inning,
        isTop: isTop,
        pitches: pitches,
        result: resultType,
        fieldPosition: fieldPosition,
        rbiCount: rbiCount,
        outsBefore: outsBefore,
        runnersBefore: runnersBefore,
      ));

      currentBattingOrder = (currentBattingOrder + 1) % 9;
    }

    return _HalfInningSimulationResult(
      halfInning: HalfInningResult(
        inning: inning,
        isTop: isTop,
        atBats: atBats,
        runs: runs,
      ),
      nextBattingOrder: currentBattingOrder,
    );
  }

  /// 走塁処理（単純化版）
  _RunnerAdvanceResult _advanceRunners(
    BaseRunners runners,
    AtBatResultType result,
    Player batter,
    int outs,
  ) {
    int runsScored = 0;
    Player? newFirst;
    Player? newSecond;
    Player? newThird;

    switch (result) {
      case AtBatResultType.homeRun:
        // 全員生還（打者含む）
        runsScored = 1 + runners.count;
        // 走者クリア
        break;

      case AtBatResultType.triple:
        // 全走者生還、打者3塁
        runsScored = runners.count;
        newThird = batter;
        break;

      case AtBatResultType.double_:
        // 各走者2塁進む
        if (runners.third != null) runsScored++;
        if (runners.second != null) runsScored++;
        newThird = runners.first;
        newSecond = batter;
        break;

      case AtBatResultType.single:
        // 各走者1塁進む
        if (runners.third != null) runsScored++;
        newThird = runners.second;
        newSecond = runners.first;
        newFirst = batter;
        break;

      case AtBatResultType.walk:
        // 押し出し（満塁時のみ得点）
        if (runners.isLoaded) {
          runsScored = 1;
          newThird = runners.second;
          newSecond = runners.first;
          newFirst = batter;
        } else if (runners.first != null && runners.second != null) {
          newThird = runners.second;
          newSecond = runners.first;
          newFirst = batter;
        } else if (runners.first != null) {
          newSecond = runners.first;
          newFirst = batter;
          newThird = runners.third;
        } else {
          newFirst = batter;
          newSecond = runners.second;
          newThird = runners.third;
        }
        break;

      case AtBatResultType.groundOut:
        // ゴロアウト: 2アウト時は得点なし（3アウトチェンジ）
        // 0-1アウト時のみ走者進塁で得点の可能性
        if (outs < 2) {
          if (runners.third != null) runsScored++;
          newThird = runners.second;
          newSecond = runners.first;
        }
        // 2アウトの場合は打者アウトで3アウト、走者は進めない
        // 打者アウト、1塁空く
        break;

      case AtBatResultType.flyOut:
      case AtBatResultType.lineOut:
        // フライ/ライナー: 走者動かず（単純化、タッチアップなし）
        newFirst = runners.first;
        newSecond = runners.second;
        newThird = runners.third;
        break;

      case AtBatResultType.strikeout:
        // 三振: 走者動かず
        newFirst = runners.first;
        newSecond = runners.second;
        newThird = runners.third;
        break;
    }

    return _RunnerAdvanceResult(
      runsScored: runsScored,
      newRunners: BaseRunners(
        first: newFirst,
        second: newSecond,
        third: newThird,
      ),
    );
  }
}

/// イニング（表/裏）のシミュレーション結果
class _HalfInningSimulationResult {
  final HalfInningResult halfInning;
  final int nextBattingOrder;

  const _HalfInningSimulationResult({
    required this.halfInning,
    required this.nextBattingOrder,
  });
}

/// 走塁結果
class _RunnerAdvanceResult {
  final int runsScored;
  final BaseRunners newRunners;

  const _RunnerAdvanceResult({
    required this.runsScored,
    required this.newRunners,
  });
}

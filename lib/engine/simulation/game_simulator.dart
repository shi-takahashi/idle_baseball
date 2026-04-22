import 'dart:math';
import '../models/models.dart';
import 'at_bat_simulator.dart';
import 'steal_simulator.dart';

/// 試合シミュレーター
class GameSimulator {
  final Random _random;
  final AtBatSimulator _atBatSimulator;
  final StealSimulator _stealSimulator;

  GameSimulator({Random? random})
      : _random = random ?? Random(),
        _atBatSimulator = AtBatSimulator(random: random),
        _stealSimulator = StealSimulator(random: random);

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
    final stealEvents = <StealEvent>[];
    int outs = 0;
    int runs = 0;
    int stolenBases = 0;
    int caughtStealing = 0;
    BaseRunners runners = BaseRunners.empty;
    int currentBattingOrder = battingOrder;

    while (outs < 3) {
      final batter = battingTeam.getBatter(currentBattingOrder);
      final pitcher = pitchingTeam.pitcher;

      // 打席前の状態を保存
      final outsBefore = outs;
      final runnersBefore = runners;

      // 打席シミュレーション（盗塁判定を含む）
      final atBatResult = _atBatSimulator.simulateAtBat(
        pitcher,
        batter,
        pitchingTeam,
        runners: runners,
        outs: outs,
        stealSimulator: _stealSimulator,
      );

      // 盗塁失敗で3アウトになった場合
      if (outs + atBatResult.additionalOuts >= 3) {
        // 盗塁統計を更新
        stolenBases += atBatResult.stealAttempts.length;
        // caught stealingは投球から集計
        for (final pitch in atBatResult.pitches) {
          if (pitch.steals != null) {
            for (final attempt in pitch.steals!) {
              if (attempt.isOut) {
                caughtStealing++;
              }
            }
          }
        }
        outs += atBatResult.additionalOuts;
        runners = atBatResult.updatedRunners;

        // 盗塁イベントを記録
        _recordStealEvents(atBatResult.pitches, atBats.length, stealEvents);

        break;
      }

      // ランナー状態を更新（盗塁結果を反映）
      runners = atBatResult.updatedRunners;
      outs += atBatResult.additionalOuts;

      // 盗塁統計を更新
      stolenBases += atBatResult.stealAttempts.length;
      for (final pitch in atBatResult.pitches) {
        if (pitch.steals != null) {
          for (final attempt in pitch.steals!) {
            if (attempt.isOut) {
              caughtStealing++;
            }
          }
        }
      }

      // 盗塁イベントを記録
      _recordStealEvents(atBatResult.pitches, atBats.length, stealEvents);

      final resultType = atBatResult.result;
      final pitches = atBatResult.pitches;

      // インプレー時の打球方向を取得（最後の投球結果から）
      FieldPosition? fieldPosition;
      if (pitches.isNotEmpty && pitches.last.type == PitchResultType.inPlay) {
        fieldPosition = pitches.last.fieldPosition;
      }

      // 走塁処理（打席結果による進塁、盗塁後のランナー状態を使用）
      final advanceResult = _advanceRunners(runners, resultType, batter, outs);
      final rbiCount = advanceResult.runsScored;
      runs += rbiCount;
      runners = advanceResult.newRunners;

      // アウトカウント（打席結果によるアウト）
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
        stealEvents: stealEvents,
        stolenBases: stolenBases,
        caughtStealing: caughtStealing,
      ),
      nextBattingOrder: currentBattingOrder,
    );
  }

  /// 投球から盗塁イベントを記録
  void _recordStealEvents(List<PitchResult> pitches, int atBatIndex, List<StealEvent> stealEvents) {
    for (int i = 0; i < pitches.length; i++) {
      final pitch = pitches[i];
      if (pitch.steals != null && pitch.steals!.isNotEmpty) {
        stealEvents.add(StealEvent(
          attempts: pitch.steals!,
          beforeAtBatIndex: atBatIndex,
        ));
      }
    }
  }

  /// 追加進塁の確率を計算（走力に基づく）
  /// 走力1: 5%, 走力5: 25%, 走力10: 50%
  double _extraAdvanceProbability(int speed) {
    return speed * 0.05;
  }

  /// 追加進塁するかどうかを判定
  bool _shouldExtraAdvance(Player runner) {
    final speed = runner.speed ?? 5;
    return _random.nextDouble() < _extraAdvanceProbability(speed);
  }

  /// 走塁処理（走力考慮版）
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
        // 3塁ランナー: ホーム
        if (runners.third != null) runsScored++;
        // 2塁ランナー: ホーム
        if (runners.second != null) runsScored++;
        // 1塁ランナー: 基本3塁、走力次第でホーム
        if (runners.first != null) {
          if (_shouldExtraAdvance(runners.first!)) {
            runsScored++;
          } else {
            newThird = runners.first;
          }
        }
        newSecond = batter;
        break;

      case AtBatResultType.single:
      case AtBatResultType.infieldHit:
        // 3塁ランナー: ホーム（常に）
        if (runners.third != null) runsScored++;

        // 2塁ランナー: 基本3塁、走力次第でホーム
        if (runners.second != null) {
          if (_shouldExtraAdvance(runners.second!)) {
            runsScored++;
          } else {
            newThird = runners.second;
          }
        }

        // 1塁ランナー: 基本2塁、走力次第で3塁
        // ただし、2塁ランナーが3塁にいる場合は2塁止まり
        if (runners.first != null) {
          if (newThird == null && _shouldExtraAdvance(runners.first!)) {
            // 3塁が空いていて、追加進塁成功 → 3塁へ
            newThird = runners.first;
          } else {
            // 3塁が詰まっているか、追加進塁失敗 → 2塁へ
            newSecond = runners.first;
          }
        }

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

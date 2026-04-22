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
    int homePitcherPitchCount = 0; // ホーム投手の投球数
    int awayPitcherPitchCount = 0; // アウェイ投手の投球数

    for (int inning = 1; inning <= 9; inning++) {
      // 表（アウェイチームの攻撃、ホーム投手が投げる）
      final topResult = _simulateHalfInning(
        inning: inning,
        isTop: true,
        battingTeam: awayTeam,
        pitchingTeam: homeTeam,
        battingOrder: awayBattingOrder,
        pitcherPitchCount: homePitcherPitchCount,
      );
      halfInnings.add(topResult.halfInning);
      awayScore += topResult.halfInning.runs;
      awayBattingOrder = topResult.nextBattingOrder;
      homePitcherPitchCount += topResult.pitchesThrown;

      // 裏（ホームチームの攻撃、アウェイ投手が投げる）
      final bottomResult = _simulateHalfInning(
        inning: inning,
        isTop: false,
        battingTeam: homeTeam,
        pitchingTeam: awayTeam,
        battingOrder: homeBattingOrder,
        pitcherPitchCount: awayPitcherPitchCount,
      );
      halfInnings.add(bottomResult.halfInning);
      homeScore += bottomResult.halfInning.runs;
      homeBattingOrder = bottomResult.nextBattingOrder;
      awayPitcherPitchCount += bottomResult.pitchesThrown;

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
    int pitcherPitchCount = 0, // 投手の現在の投球数
  }) {
    final atBats = <AtBatResult>[];
    final stealEvents = <StealEvent>[];
    int outs = 0;
    int runs = 0;
    int stolenBases = 0;
    int caughtStealing = 0;
    BaseRunners runners = BaseRunners.empty;
    int currentBattingOrder = battingOrder;
    int currentPitchCount = pitcherPitchCount; // このイニングの投球数を追跡

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
        pitchCount: currentPitchCount, // 投球数を渡す
      );
      // 投球数を更新
      currentPitchCount += atBatResult.pitches.length;

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

      var resultType = atBatResult.result;
      final pitches = atBatResult.pitches;

      // インプレー時の打球方向を取得（最後の投球結果から）
      FieldPosition? fieldPosition;
      if (pitches.isNotEmpty && pitches.last.type == PitchResultType.inPlay) {
        fieldPosition = pitches.last.fieldPosition;
      }

      // ゴロアウト時に併殺判定
      // 条件: ゴロアウト、ランナー1塁がいる、アウト < 2
      if (resultType == AtBatResultType.groundOut &&
          _canAttemptDoublePlay(runners, outs) &&
          _shouldDoublePlay(batter)) {
        resultType = AtBatResultType.doublePlay;
      }

      // 走塁処理（打席結果による進塁、盗塁後のランナー状態を使用）
      final advanceResult = _advanceRunners(
        runners,
        resultType,
        batter,
        outs,
        fieldPosition: fieldPosition,
      );
      final rbiCount = advanceResult.runsScored;
      runs += rbiCount;
      runners = advanceResult.newRunners;

      // アウトカウント（打席結果によるアウト）
      if (resultType.isOut) {
        outs++;
      }
      // 併殺打の場合、追加で1アウト（1塁ランナー）
      if (resultType.isDoublePlay) {
        outs++;
      }
      // タッチアップ失敗などによる追加アウト
      outs += advanceResult.additionalOuts;

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
      pitchesThrown: currentPitchCount - pitcherPitchCount, // このイニングで投げた球数
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

  /// 併殺成功率を計算（打者の走力に基づく）
  /// 走力1: 94%, 走力5: 70%, 走力10: 40%
  /// 走力が高いほど併殺崩れが起きやすい
  double _doublePlayProbability(int batterSpeed) {
    const baseRate = 0.70;
    final speedModifier = (batterSpeed - 5) * 0.06;
    return (baseRate - speedModifier).clamp(0.30, 0.95);
  }

  /// 併殺が成立するかどうかを判定
  /// 条件: ランナー1塁がいる、アウト < 2、ゴロアウト
  /// 戻り値: true = 併殺成立、false = 併殺崩れ（通常のゴロアウト）
  bool _shouldDoublePlay(Player batter) {
    final batterSpeed = batter.speed ?? 5;
    return _random.nextDouble() < _doublePlayProbability(batterSpeed);
  }

  /// 併殺の条件を満たしているかチェック
  /// 条件: ランナー1塁がいる、アウト < 2
  bool _canAttemptDoublePlay(BaseRunners runners, int outs) {
    return runners.first != null && outs < 2;
  }

  /// タッチアップ試行確率を計算（走力に基づく）
  /// 走力1: 10%, 走力5: 45%, 走力10: 80%
  double _tagUpAttemptProbability(int speed) {
    return (speed * 0.078 + 0.02).clamp(0.10, 0.85);
  }

  /// タッチアップ成功確率を計算（走力に基づく）
  /// 走力1: 40%, 走力5: 65%, 走力10: 95%
  double _tagUpSuccessProbability(int speed) {
    return (speed * 0.06 + 0.34).clamp(0.35, 0.95);
  }

  /// タッチアップを試行するかどうかを判定
  bool _shouldAttemptTagUp(Player runner) {
    final speed = runner.speed ?? 5;
    return _random.nextDouble() < _tagUpAttemptProbability(speed);
  }

  /// タッチアップが成功するかどうかを判定
  bool _isTagUpSuccessful(Player runner) {
    final speed = runner.speed ?? 5;
    return _random.nextDouble() < _tagUpSuccessProbability(speed);
  }

  /// 2塁ランナーがタッチアップ可能な方向かチェック
  /// ライトフライとセンターフライのみ可能（レフトは3塁に近いので不可）
  bool _canSecondRunnerTagUp(FieldPosition? fieldPosition) {
    return fieldPosition == FieldPosition.right ||
        fieldPosition == FieldPosition.center;
  }

  /// 走塁処理（走力考慮版）
  /// fieldPosition: 打球方向（外野フライのタッチアップ判定に使用）
  _RunnerAdvanceResult _advanceRunners(
    BaseRunners runners,
    AtBatResultType result,
    Player batter,
    int outs, {
    FieldPosition? fieldPosition,
  }) {
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

      case AtBatResultType.doublePlay:
        // 併殺打: 1塁ランナーと打者がアウト（計2アウト追加）
        // 1塁ランナーは2塁でフォースアウト → 消える
        // 打者は1塁でアウト → 塁には出ない
        // 2塁ランナーは3塁に進む（併殺崩れで1塁ランナーが2塁に来る可能性を考慮）
        // 3塁ランナーは基本動かないが、満塁の場合はホームに進む

        // 併殺で3アウトになるかどうか（outs == 1の時、併殺で3アウト）
        final willBeThreeOuts = outs == 1;

        // 満塁の場合、3塁ランナーがホームへ（ただし3アウトにならない場合のみ得点）
        if (runners.isLoaded && !willBeThreeOuts) {
          runsScored++;
        }

        // 2塁ランナーは3塁に進む
        newThird = runners.second;
        // 1塁、2塁は空く
        break;

      case AtBatResultType.flyOut:
        // 外野フライ時のタッチアップ判定
        final isOutfield = fieldPosition?.isOutfield ?? false;
        int tagUpOuts = 0;

        if (isOutfield && outs < 2) {
          // タッチアップ可能な状況
          // フライアウトで1アウト追加済みなので、現在のアウト数は outs + 1

          // 3塁ランナーのタッチアップ判定
          bool thirdRunnerTaggedUp = false;
          bool thirdRunnerScored = false;
          bool thirdRunnerOut = false;
          if (runners.third != null && _shouldAttemptTagUp(runners.third!)) {
            thirdRunnerTaggedUp = true;
            if (_isTagUpSuccessful(runners.third!)) {
              thirdRunnerScored = true;
              runsScored++;
            } else {
              // タッチアップ失敗 → アウト
              thirdRunnerOut = true;
              tagUpOuts++;
            }
          }

          // 2塁ランナーのタッチアップ判定
          // 条件: ライト/センター方向、かつ3塁ランナーがタッチアップ試行中または3塁が空いている
          if (runners.second != null &&
              _canSecondRunnerTagUp(fieldPosition) &&
              (thirdRunnerTaggedUp || runners.third == null)) {
            if (_shouldAttemptTagUp(runners.second!)) {
              // 成功判定: 3塁ランナーがいた場合はバックホームなので3塁ランナーの走力で判定済み
              // 3塁ランナーがいない場合は2塁ランナーの走力で判定
              final successCheck = runners.third != null
                  ? thirdRunnerScored // バックホーム → 3塁ランナーが成功なら2塁ランナーも進塁
                  : _isTagUpSuccessful(runners.second!);

              if (successCheck) {
                newThird = runners.second;
              } else {
                // タッチアップ失敗 → アウト（2塁ランナーは消える）
                tagUpOuts++;
              }
            } else {
              newSecond = runners.second;
            }
          } else {
            newSecond = runners.second;
          }

          // 3塁ランナーの最終位置
          if (!thirdRunnerScored && !thirdRunnerOut) {
            newThird = runners.third;
          }

          // 1塁ランナーは動かない
          newFirst = runners.first;

          // タッチアップ失敗で3アウトになった場合、その後の得点は無効
          // （フライアウト+1、タッチアップ失敗で+tagUpOuts）
          // 例: 1アウトでフライ(+1=2アウト)、タッチアップ失敗(+1=3アウト) → 得点なし
          if (outs + 1 + tagUpOuts >= 3) {
            runsScored = 0;
          }
        } else {
          // 内野フライ or 2アウト: 走者動かず
          newFirst = runners.first;
          newSecond = runners.second;
          newThird = runners.third;
        }

        return _RunnerAdvanceResult(
          runsScored: runsScored,
          newRunners: BaseRunners(
            first: newFirst,
            second: newSecond,
            third: newThird,
          ),
          additionalOuts: tagUpOuts,
        );

      case AtBatResultType.lineOut:
        // ライナー: 走者動かず（タッチアップなし、捕球後の反応が難しい）
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
  final int pitchesThrown; // このイニングで投げた球数

  const _HalfInningSimulationResult({
    required this.halfInning,
    required this.nextBattingOrder,
    required this.pitchesThrown,
  });
}

/// 走塁結果
class _RunnerAdvanceResult {
  final int runsScored;
  final BaseRunners newRunners;
  final int additionalOuts; // タッチアップ失敗などによる追加アウト

  const _RunnerAdvanceResult({
    required this.runsScored,
    required this.newRunners,
    this.additionalOuts = 0,
  });
}

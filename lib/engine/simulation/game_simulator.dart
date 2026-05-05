import 'dart:math';
import '../models/models.dart';
import 'at_bat_simulator.dart';
import 'bunt_decision_strategy.dart';
import 'fielder_change_strategy.dart';
import 'pitcher_change_strategy.dart';
import 'steal_simulator.dart';
import 'team_fielding_state.dart';
import 'team_pitching_state.dart';

/// 試合シミュレーター
class GameSimulator {
  final Random _random;
  final AtBatSimulator _atBatSimulator;
  final StealSimulator _stealSimulator;
  final PitcherChangeStrategy _pitcherChangeStrategy;
  final FielderChangeStrategy _fielderChangeStrategy;
  final BuntDecisionStrategy _buntDecisionStrategy;

  GameSimulator({
    Random? random,
    PitcherChangeStrategy? pitcherChangeStrategy,
    FielderChangeStrategy? fielderChangeStrategy,
    BuntDecisionStrategy? buntDecisionStrategy,
  })  : _random = random ?? Random(),
        _atBatSimulator = AtBatSimulator(random: random),
        _stealSimulator = StealSimulator(random: random),
        _pitcherChangeStrategy =
            pitcherChangeStrategy ?? const SimplePitcherChangeStrategy(),
        _fielderChangeStrategy =
            fielderChangeStrategy ?? const SimplePinchHitStrategy(),
        _buntDecisionStrategy =
            buntDecisionStrategy ?? const SimpleBuntDecisionStrategy();

  /// ヒット（単打・二塁打・三塁打・本塁打）の場合、打球方向を外野に調整
  /// 内野安打以外で内野方向へのヒットは野球的に不自然なため
  FieldPosition? _adjustFieldPositionForHit(
    FieldPosition? fieldPosition,
    AtBatResultType resultType,
  ) {
    if (fieldPosition == null) return null;

    // ヒットでない場合はそのまま（内野安打は除く - 内野方向で正しい）
    final isHit = resultType == AtBatResultType.single ||
        resultType == AtBatResultType.double_ ||
        resultType == AtBatResultType.triple ||
        resultType == AtBatResultType.homeRun;
    if (!isHit) {
      return fieldPosition;
    }

    // 既に外野方向なら調整不要
    if (fieldPosition.isOutfield) {
      return fieldPosition;
    }

    // 内野方向へのヒットは外野方向にランダムで変更
    // 左翼30%, 中堅40%, 右翼30%
    final roll = _random.nextDouble();
    if (roll < 0.30) return FieldPosition.left;
    if (roll < 0.70) return FieldPosition.center;
    return FieldPosition.right;
  }

  /// 規定イニング数（9回で決着がつかなければ延長）
  static const int regulationInnings = 9;

  /// 延長戦の最終イニング（12回で同点なら引き分け）
  static const int maxInnings = 12;

  /// 1試合をシミュレート
  ///
  /// [batterConditionModifiers] は player.id → 調子補正値（-1/0/+1）のマップ。
  /// 渡された場合、各打者の能力（ミート/長打/走力/選球眼）に一律加算される。
  GameResult simulate(
    Team homeTeam,
    Team awayTeam, {
    Map<String, int> batterConditionModifiers = const {},
  }) {
    final inningScores = <InningScore>[];
    final halfInnings = <HalfInningResult>[];

    int homeScore = 0;
    int awayScore = 0;
    int homeBattingOrder = 0; // ホームチームの打順
    int awayBattingOrder = 0; // アウェイチームの打順

    // 各チームの投手運用状態（先発投手 + ブルペン）
    final homePitchingState = TeamPitchingState(
      currentPitcher: homeTeam.pitcher,
      condition: PitcherCondition.random(_random),
      bullpen: [...homeTeam.bullpen],
    );
    final awayPitchingState = TeamPitchingState(
      currentPitcher: awayTeam.pitcher,
      condition: PitcherCondition.random(_random),
      bullpen: [...awayTeam.bullpen],
    );

    // 各チームの野手運用状態（ラインナップ・守備配置・ベンチ）
    final homeFieldingState = TeamFieldingState.fromTeam(homeTeam);
    final awayFieldingState = TeamFieldingState.fromTeam(awayTeam);

    for (int inning = 1; inning <= maxInnings; inning++) {
      // 表（アウェイチームの攻撃、ホーム投手が投げる）
      final topResult = _simulateHalfInning(
        inning: inning,
        isTop: true,
        battingFieldingState: awayFieldingState,
        pitchingFieldingState: homeFieldingState,
        battingOrder: awayBattingOrder,
        pitchingState: homePitchingState,
        myTeamScore: homeScore,
        opponentScoreAtStart: awayScore,
        batterConditionModifiers: batterConditionModifiers,
      );
      halfInnings.add(topResult.halfInning);
      awayScore += topResult.halfInning.runs;
      awayBattingOrder = topResult.nextBattingOrder;

      // 9回以降の表終了時点で後攻が勝っていれば、裏はやらずに試合終了
      if (inning >= regulationInnings && homeScore > awayScore) {
        inningScores.add(InningScore(
          top: topResult.halfInning.runs,
          bottom: null,
        ));
        break;
      }

      // 裏（ホームチームの攻撃、アウェイ投手が投げる）
      final bottomResult = _simulateHalfInning(
        inning: inning,
        isTop: false,
        battingFieldingState: homeFieldingState,
        pitchingFieldingState: awayFieldingState,
        battingOrder: homeBattingOrder,
        pitchingState: awayPitchingState,
        myTeamScore: awayScore,
        opponentScoreAtStart: homeScore,
        batterConditionModifiers: batterConditionModifiers,
      );
      halfInnings.add(bottomResult.halfInning);
      homeScore += bottomResult.halfInning.runs;
      homeBattingOrder = bottomResult.nextBattingOrder;

      inningScores.add(InningScore(
        top: topResult.halfInning.runs,
        bottom: bottomResult.halfInning.runs,
      ));

      // 9回以降の裏終了時点で決着がついていれば試合終了
      // （同点なら次のイニングへ、ただし12回終了時は引き分けで終了）
      if (inning >= regulationInnings && homeScore != awayScore) {
        break;
      }
    }

    return GameResult(
      homeTeam: homeTeam,
      awayTeam: awayTeam,
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
    required TeamFieldingState battingFieldingState,
    required TeamFieldingState pitchingFieldingState,
    required int battingOrder,
    required TeamPitchingState pitchingState,
    required int myTeamScore, // 投手チームの現在得点
    required int opponentScoreAtStart, // 相手チームの現在得点（このハーフイニング開始時点）
    Map<String, int> batterConditionModifiers = const {},
  }) {
    final atBats = <AtBatResult>[];
    final stealEvents = <StealEvent>[];
    final pitcherChanges = <PitcherChangeEvent>[];
    final fielderChanges = <FielderChangeEvent>[];
    int outs = 0;
    int runs = 0;
    int stolenBases = 0;
    int caughtStealing = 0;
    BaseRunners runners = BaseRunners.empty;
    int currentBattingOrder = battingOrder;

    // 走者責任投手の追跡（player.id → 責任投手 player.id）
    // インヘリット走者（前任投手が出した走者）の失点を正しく前任投手に計上するため
    // ハーフイニング全体で管理する。
    final runnerResponsibility = <String, String>{};

    // 自責点判定用の状態
    // - runnerIsUnearned: そのランナーがエラー出塁等で塁に出ているかどうか
    // - errorOuts: このイニングで「エラーで取り損なったアウト」の数
    //   実アウト + errorOuts >= 3 になった以降の得点は不自責
    final runnerIsUnearned = <String, bool>{};
    int errorOuts = 0;

    // 守備側チーム（このハーフで守る側）のアライメントを確定させる
    // 前の攻撃ハーフでの代打・代走の結果をここで反映する
    final defensiveChangesAtStart =
        pitchingFieldingState.reconcileAlignmentBeforeDefense();

    while (outs < 3) {
      // 代打判断（打者前に評価）
      final currentBatterBeforePH =
          battingFieldingState.currentBatter(currentBattingOrder);
      final phContext = PinchHitContext(
        fieldingState: battingFieldingState,
        inning: inning,
        isTop: isTop,
        outs: outs,
        myTeamScore: opponentScoreAtStart + runs, // 攻撃側チームの現在得点
        opponentScore: myTeamScore, // 守備側チームの現在得点
        runners: runners,
        battingOrder: currentBattingOrder,
        currentBatter: currentBatterBeforePH,
        opposingPitcher: pitchingState.currentPitcher,
        random: _random,
      );
      final phDecision = _fielderChangeStrategy.decidePinchHit(phContext);
      if (phDecision != null) {
        battingFieldingState.applyPinchHit(
          outgoing: phDecision.outgoing,
          incoming: phDecision.hitter,
          battingOrder: phDecision.battingOrder,
        );
        fielderChanges.add(FielderChangeEvent(
          type: FielderChangeType.pinchHit,
          inning: inning,
          isTop: isTop,
          atBatIndex: atBats.length,
          outgoing: phDecision.outgoing,
          incoming: phDecision.hitter,
          battingOrder: phDecision.battingOrder,
          reason: phDecision.reason,
        ));
      }

      // 代走判断（塁上のランナーごとに評価）
      runners = _applyPinchRunDecisions(
        runners: runners,
        battingFieldingState: battingFieldingState,
        inning: inning,
        isTop: isTop,
        outs: outs,
        attackingScore: opponentScoreAtStart + runs,
        defendingScore: myTeamScore,
        fielderChanges: fielderChanges,
        atBatIndex: atBats.length,
        runnerResponsibility: runnerResponsibility,
        runnerIsUnearned: runnerIsUnearned,
      );

      final batter = battingFieldingState.currentBatter(currentBattingOrder);

      // 投手交代判断（打者ごとに評価）
      // 抑え投手は team.closer に指名されていて、まだ未登板（=ブルペンに残っている）
      // 場合のみ候補として渡す。コンディションの判定は SeasonController が
      // 既に bullpen を絞った上で渡しているので、ここでは在籍チェックのみ。
      final closerCandidate = pitchingFieldingState.originalTeam.closer;
      final isCloserAvailable = closerCandidate != null &&
          pitchingState.bullpen.any((p) => p.id == closerCandidate.id);
      final changeContext = PitcherChangeContext(
        pitchingState: pitchingState,
        inning: inning,
        isTop: isTop,
        outs: outs,
        myTeamScore: myTeamScore,
        opponentScore: opponentScoreAtStart + runs,
        runners: runners,
        closer: isCloserAvailable ? closerCandidate : null,
        batter: batter,
        random: _random,
      );
      final decision = _pitcherChangeStrategy.decide(changeContext);
      if (decision != null) {
        final oldPitcher = pitchingState.currentPitcher;
        // 旧投手の打順スロットを取得（setPitcher前にチェック）
        int pitcherSlot = 0;
        for (int i = 0; i < pitchingFieldingState.currentLineup.length; i++) {
          if (pitchingFieldingState.currentLineup[i].id == oldPitcher.id) {
            pitcherSlot = i;
            break;
          }
        }
        pitchingState.changePitcher(
          decision.newPitcher,
          PitcherCondition.random(_random),
        );
        // 守備配置の投手位置も同期（DH非採用なのでラインナップも更新される）
        pitchingFieldingState.setPitcher(decision.newPitcher);
        pitcherChanges.add(PitcherChangeEvent(
          oldPitcher: oldPitcher,
          newPitcher: decision.newPitcher,
          inning: inning,
          isTop: isTop,
          atBatIndex: atBats.length,
          battingOrder: pitcherSlot,
          reason: decision.reason,
        ));
      }

      final pitcher = pitchingState.currentPitcher;

      // 打席前の状態を保存
      final outsBefore = outs;
      final runnersBefore = runners;

      // 守備側のスナップショット（現在の守備配置を反映したTeam）
      final pitchingTeamSnapshot = pitchingFieldingState.asTeamSnapshot();

      // バント判定: 試行する状況なら simulateBuntAtBat を使う。
      // 次打者を渡して「次が強打者なら積極的にバント」を判定に反映する。
      final nextOrder = (currentBattingOrder + 1) % 9;
      final nextBatter =
          battingFieldingState.currentBatter(nextOrder);
      final buntCtx = BuntContext(
        batter: batter,
        nextBatter: nextBatter,
        runners: runners,
        outs: outs,
        inning: inning,
        myTeamScore: opponentScoreAtStart + runs,
        opponentScore: myTeamScore,
        random: _random,
      );
      final shouldBunt = _buntDecisionStrategy.shouldBunt(buntCtx);

      // 打席シミュレーション（バント時はバント専用ルート）
      final atBatResult = shouldBunt
          ? _atBatSimulator.simulateBuntAtBat(
              pitcher,
              batter,
              pitchingTeam: pitchingTeamSnapshot,
              runners: runners,
              outs: outs,
              stealSimulator: _stealSimulator,
              pitchCount: pitchingState.pitchCount,
              condition: pitchingState.condition,
              batterConditionModifier:
                  batterConditionModifiers[batter.id] ?? 0,
            )
          : _atBatSimulator.simulateAtBat(
              pitcher,
              batter,
              pitchingTeamSnapshot,
              runners: runners,
              outs: outs,
              stealSimulator: _stealSimulator,
              pitchCount: pitchingState.pitchCount,
              condition: pitchingState.condition,
              batterConditionModifier:
                  batterConditionModifiers[batter.id] ?? 0,
            );
      // 現投手の投球数を更新
      pitchingState.pitchCount += atBatResult.pitches.length;

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

        // 未完了の打席として記録（盗塁死でイニング終了）
        // resultはダミー、isIncomplete=trueで打席として数えない
        // 投手交代バナーの表示位置（atBatIndex）を正しく機能させるためにも必要
        atBats.add(AtBatResult(
          batter: batter,
          pitcher: pitcher,
          inning: inning,
          isTop: isTop,
          pitches: atBatResult.pitches,
          result: AtBatResultType.strikeout, // ダミー（isIncomplete=trueなので使われない）
          rbiCount: 0,
          outsBefore: outsBefore,
          runnersBefore: runnersBefore,
          isIncomplete: true,
        ));

        break;
      }

      // 失点の責任投手追跡用: 打席開始時点でのランナー責任マップをスナップショット
      // （バッテリーエラー・打席結果による生還で、生還した走者の責任投手を引く）
      final responsibilitySnapshot = Map<String, String>.from(runnerResponsibility);

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
          _shouldDoublePlay(batter, pitcher)) {
        resultType = AtBatResultType.doublePlay;
      }

      // ヒットの場合、打球方向を外野に調整（内野安打以外で内野方向は不自然なため）
      fieldPosition = _adjustFieldPositionForHit(fieldPosition, resultType);

      // バッテリーエラーによる得点を加算
      runs += atBatResult.batteryErrorRuns;

      // 走塁処理（打席結果による進塁、盗塁後のランナー状態を使用）
      final advanceResult = _advanceRunners(
        runners,
        resultType,
        batter,
        outs,
        fieldPosition: fieldPosition,
        pitchingTeam: pitchingTeamSnapshot,
      );

      // 犠飛: 外野フライ + 3塁走者がタッチアップ生還 → 結果を sacrificeFly に上書き。
      // 集計側で「打数に含めない、犠飛として記録」になる。
      if (resultType == AtBatResultType.flyOut &&
          advanceResult.wasSacrificeFly) {
        resultType = AtBatResultType.sacrificeFly;
      }

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

      // 失点の責任投手別配分を算出
      // 全ての生還した走者（バッテリーエラー + 打席結果）について、
      // 打席開始前のスナップショット responsibility から投手を引く。
      // 打者自身が生還（HR等）した場合は現在の投手の責任。
      //
      // 自責点判定:
      //   - 打席開始時点で「実アウト + errorOuts >= 3」なら、すでにイニングが
      //     終わっていたはずなので、この打席の全得点は不自責
      //   - 走者がエラー出塁で塁にいた場合、その走者の生還は不自責
      //   - パスボールで生還した走者は不自責（ワイルドピッチは自責）
      final runsByPitcher = <String, int>{};
      final earnedRunsByPitcher = <String, int>{};
      final inningWouldHaveEnded = outsBefore + errorOuts >= 3;

      for (final scoring in atBatResult.batteryErrorScorers) {
        final scorerId = scoring.runner.id;
        final responsibleId = responsibilitySnapshot[scorerId] ?? pitcher.id;
        runsByPitcher[responsibleId] = (runsByPitcher[responsibleId] ?? 0) + 1;
        // 自責判定: イニング延長後 or PB or その走者が不自責ランナーなら不自責
        final isUnearned = inningWouldHaveEnded ||
            scoring.type == BatteryErrorType.passedBall ||
            (runnerIsUnearned[scorerId] ?? false);
        if (!isUnearned) {
          earnedRunsByPitcher[responsibleId] =
              (earnedRunsByPitcher[responsibleId] ?? 0) + 1;
        }
      }
      for (final scorer in advanceResult.scoringRunners) {
        // 打者自身（HR）は現在の投手の責任
        // 走者の場合は responsibilitySnapshot から責任投手を引く
        final responsibleId = scorer.id == batter.id
            ? pitcher.id
            : (responsibilitySnapshot[scorer.id] ?? pitcher.id);
        runsByPitcher[responsibleId] = (runsByPitcher[responsibleId] ?? 0) + 1;
        // 自責判定:
        //   - イニングが既に終わっていたはずなら不自責
        //   - 打者自身がエラー絡み（= reachedOnError）の打者ではない限り、
        //     打者の得点は通常自責（HR）。
        //   - 走者がエラー出塁の走者なら不自責
        final isUnearnedRunner = scorer.id == batter.id
            ? false
            : (runnerIsUnearned[scorer.id] ?? false);
        final isUnearned = inningWouldHaveEnded || isUnearnedRunner;
        if (!isUnearned) {
          earnedRunsByPitcher[responsibleId] =
              (earnedRunsByPitcher[responsibleId] ?? 0) + 1;
        }
      }

      // 次打席のために責任投手マップを更新
      // 新しいランナー状態 (runners) に残っていない走者は除去（生還 or アウト）
      // 新たに塁上に出た打者（= 既存マップにいない player）は現在の投手の責任で記録
      final newRunnersIds = <String>{
        if (runners.first != null) runners.first!.id,
        if (runners.second != null) runners.second!.id,
        if (runners.third != null) runners.third!.id,
      };
      runnerResponsibility.removeWhere((id, _) => !newRunnersIds.contains(id));
      for (final id in newRunnersIds) {
        runnerResponsibility.putIfAbsent(id, () => pitcher.id);
      }

      // 自責点判定状態を次打席のために更新
      // - エラー出塁（reachedOnError）したらその走者を unearned としてマーク、
      //   かつ errorOuts を +1（取れていたはずのアウトを取り損なった）
      // - 走者状態に居なくなった選手（生還 or アウト）は unearned マップから除去
      runnerIsUnearned.removeWhere((id, _) => !newRunnersIds.contains(id));
      if (resultType == AtBatResultType.reachedOnError) {
        runnerIsUnearned[batter.id] = true;
        errorOuts++;
      }

      // 個人「得点」集計用に、本塁を踏んだ選手をすべて集める。
      // バッテリーエラー（WP/PB）由来 + 走塁由来（HR で打者自身を含む）。
      final allScorers = <Player>[
        for (final s in atBatResult.batteryErrorScorers) s.runner,
        ...advanceResult.scoringRunners,
      ];

      final completedAtBat = AtBatResult(
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
        tagUps: advanceResult.tagUps.isNotEmpty ? advanceResult.tagUps : null,
        fieldingError: atBatResult.fieldingError,
        isBunt: shouldBunt,
        runsByPitcher: runsByPitcher,
        earnedRunsByPitcher: earnedRunsByPitcher,
        scoringRunners: allScorers,
      );
      atBats.add(completedAtBat);

      // 現投手の交代判断用の指標を更新
      pitchingState.recordAtBat(
        completedAtBat,
        batteryErrorRuns: atBatResult.batteryErrorRuns,
      );

      currentBattingOrder = (currentBattingOrder + 1) % 9;

      // サヨナラ判定: 9回以降の裏で、攻撃側（ホーム）が勝ち越したら試合終了
      if (!isTop && inning >= regulationInnings) {
        final attackingScore = opponentScoreAtStart + runs;
        final defendingScore = myTeamScore;
        if (attackingScore > defendingScore) break;
      }
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
        pitcherChanges: pitcherChanges,
        fielderChanges: fielderChanges,
        defensiveChangesAtStart: defensiveChangesAtStart,
      ),
      nextBattingOrder: currentBattingOrder,
    );
  }

  /// 塁上のランナーごとに代走判定を行い、適用する
  /// 戻り値は更新後の BaseRunners
  BaseRunners _applyPinchRunDecisions({
    required BaseRunners runners,
    required TeamFieldingState battingFieldingState,
    required int inning,
    required bool isTop,
    required int outs,
    required int attackingScore,
    required int defendingScore,
    required List<FielderChangeEvent> fielderChanges,
    required int atBatIndex,
    required Map<String, String> runnerResponsibility,
    required Map<String, bool> runnerIsUnearned,
  }) {
    // 3塁 → 2塁 → 1塁 の順で評価（前のランナーから）
    final candidates = <(Base, Player)>[];
    if (runners.third != null) candidates.add((Base.third, runners.third!));
    if (runners.second != null) candidates.add((Base.second, runners.second!));
    if (runners.first != null) candidates.add((Base.first, runners.first!));

    var current = runners;
    for (final (base, runner) in candidates) {
      // ランナーの打順を特定
      final battingOrder = _findBattingOrder(battingFieldingState, runner);
      if (battingOrder == null) continue;

      final ctx = PinchRunContext(
        fieldingState: battingFieldingState,
        inning: inning,
        isTop: isTop,
        outs: outs,
        myTeamScore: attackingScore,
        opponentScore: defendingScore,
        base: base,
        runner: runner,
        battingOrder: battingOrder,
        random: _random,
      );
      final decision = _fielderChangeStrategy.decidePinchRun(ctx);
      if (decision == null) continue;

      // 代走を適用（ラインナップのみ更新）
      battingFieldingState.applyPinchRun(
        outgoing: decision.outgoing,
        incoming: decision.runner,
        battingOrder: decision.battingOrder,
      );
      // 塁上のランナーを入れ替え
      current = current.replaceRunner(base, decision.runner);
      // 責任投手・自責点フラグを引き継ぎ: 元の走者 → 代走者
      final originalResponsibility = runnerResponsibility.remove(runner.id);
      if (originalResponsibility != null) {
        runnerResponsibility[decision.runner.id] = originalResponsibility;
      }
      final wasUnearned = runnerIsUnearned.remove(runner.id);
      if (wasUnearned != null && wasUnearned) {
        runnerIsUnearned[decision.runner.id] = true;
      }

      fielderChanges.add(FielderChangeEvent(
        type: FielderChangeType.pinchRun,
        inning: inning,
        isTop: isTop,
        atBatIndex: atBatIndex,
        outgoing: decision.outgoing,
        incoming: decision.runner,
        battingOrder: decision.battingOrder,
        reason: decision.reason,
      ));
    }
    return current;
  }

  /// currentLineup の中から指定プレイヤーの打順を検索
  int? _findBattingOrder(TeamFieldingState state, Player player) {
    for (int i = 0; i < state.currentLineup.length; i++) {
      if (state.currentLineup[i].id == player.id) return i;
    }
    return null;
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

  /// 併殺成功率を計算（打者の走力と打席に基づく）
  /// 走力1: 94%, 走力5: 70%, 走力10: 40%
  /// 走力が高いほど併殺崩れが起きやすい
  /// 左打者は一塁に近い分、併殺率が下がる
  double _doublePlayProbability(int batterSpeed, {bool isLeftBatter = false}) {
    const baseRate = 0.70;
    final speedModifier = (batterSpeed - 5) * 0.06;
    final leftPenalty = isLeftBatter ? 0.05 : 0.0;
    return (baseRate - speedModifier - leftPenalty).clamp(0.30, 0.95);
  }

  /// 併殺が成立するかどうかを判定
  /// 条件: ランナー1塁がいる、アウト < 2、ゴロアウト
  /// 戻り値: true = 併殺成立、false = 併殺崩れ（通常のゴロアウト）
  bool _shouldDoublePlay(Player batter, Player pitcher) {
    final batterSpeed = batter.speed ?? 5;
    final batterSide = batter.effectiveBatsAgainst(pitcher);
    final isLeftBatter = batterSide == Handedness.left;
    return _random.nextDouble() <
        _doublePlayProbability(batterSpeed, isLeftBatter: isLeftBatter);
  }

  /// 併殺の条件を満たしているかチェック
  /// 条件: ランナー1塁がいる、アウト < 2
  bool _canAttemptDoublePlay(BaseRunners runners, int outs) {
    return runners.first != null && outs < 2;
  }

  /// 外野フライの「深さ」を内部抽選する。
  /// 浅い 30% / 中くらい 40% / 深い 30%。
  /// この深さによってタッチアップの試行確率・成功確率が大きく変わる。
  /// （現実: フライの深さで結果がほぼ決まり、走力・肩は微妙なライン (中) で効く）
  _FlyDepth _rollFlyDepth() {
    final r = _random.nextDouble();
    if (r < 0.30) return _FlyDepth.shallow;
    if (r < 0.70) return _FlyDepth.medium;
    return _FlyDepth.deep;
  }

  /// 深さ × 走力 × 肩 によるタッチアップ試行確率。
  /// 浅い: ほぼ試行しない (5%)、深い: ほぼ試行する (90%)、
  /// 中くらいのみ走力・肩で大きく揺れる。
  double _tagUpAttemptProb(_FlyDepth depth, int speed, int arm) {
    switch (depth) {
      case _FlyDepth.shallow:
        return 0.05;
      case _FlyDepth.deep:
        return 0.90;
      case _FlyDepth.medium:
        // 走力5・肩5 で 50%、走力10・肩1 で 86%、走力1・肩10 で 14%
        final p = 0.50 + (speed - 5) * 0.04 - (arm - 5) * 0.04;
        return p.clamp(0.05, 0.95);
    }
  }

  /// 深さ × 走力 × 肩 によるタッチアップ成功確率。
  /// 試行された時点で基本セーフ寄り。深いほど確実、浅いと無理して試行 → アウト寄り。
  double _tagUpSuccessProb(_FlyDepth depth, int speed, int arm) {
    switch (depth) {
      case _FlyDepth.shallow:
        return 0.50;
      case _FlyDepth.deep:
        return 0.95;
      case _FlyDepth.medium:
        // 走力5・肩5 で 85%、走力10・肩1 で 98%（clamp で 95）、走力1・肩10 で 71.5%
        final p = 0.85 + (speed - 5) * 0.015 - (arm - 5) * 0.015;
        return p.clamp(0.50, 0.95);
    }
  }

  /// タッチアップを試行するかどうかを判定（フライの深さを考慮）
  bool _shouldAttemptTagUp(Player runner, _FlyDepth depth, int arm) {
    final speed = runner.speed ?? 5;
    return _random.nextDouble() < _tagUpAttemptProb(depth, speed, arm);
  }

  /// タッチアップが成功するかどうかを判定（フライの深さ・外野手の肩を考慮）
  bool _isTagUpSuccessful(Player runner, _FlyDepth depth, int arm) {
    final speed = runner.speed ?? 5;
    return _random.nextDouble() < _tagUpSuccessProb(depth, speed, arm);
  }

  /// 2塁ランナーがタッチアップ可能な方向かチェック
  /// ライトフライとセンターフライのみ可能（レフトは3塁に近いので不可）
  bool _canSecondRunnerTagUp(FieldPosition? fieldPosition) {
    return fieldPosition == FieldPosition.right ||
        fieldPosition == FieldPosition.center;
  }

  // ============================================================
  // 走塁処理（打席結果タイプごとに分割）
  // ============================================================

  /// 走塁処理のメインメソッド
  _RunnerAdvanceResult _advanceRunners(
    BaseRunners runners,
    AtBatResultType result,
    Player batter,
    int outs, {
    FieldPosition? fieldPosition,
    Team? pitchingTeam,
  }) {
    switch (result) {
      case AtBatResultType.homeRun:
        return _advanceOnHomeRun(runners, batter);
      case AtBatResultType.triple:
        return _advanceOnTriple(runners, batter);
      case AtBatResultType.double_:
        return _advanceOnDouble(runners, batter);
      case AtBatResultType.single:
      case AtBatResultType.infieldHit:
        return _advanceOnSingle(runners, batter);
      case AtBatResultType.walk:
        return _advanceOnWalk(runners, batter);
      case AtBatResultType.groundOut:
        return _advanceOnGroundOut(runners, outs);
      case AtBatResultType.doublePlay:
        return _advanceOnDoublePlay(runners, outs);
      case AtBatResultType.flyOut:
        return _advanceOnFlyOut(runners, outs, fieldPosition, pitchingTeam);
      case AtBatResultType.lineOut:
      case AtBatResultType.strikeout:
        return _advanceOnNoChange(runners);
      case AtBatResultType.reachedOnError:
        return _advanceOnError(runners, batter);
      case AtBatResultType.sacrificeBunt:
        return _advanceOnSacrificeBunt(runners);
      case AtBatResultType.sacrificeFly:
        // 通常 _advanceRunners には flyOut が渡り、_processTagUp の結果から
        // 呼び出し側で sacrificeFly に書き換えられる。ここに到達することはない想定。
        return _advanceOnNoChange(runners);
      case AtBatResultType.fieldersChoice:
        return _advanceOnFieldersChoice(runners, batter);
    }
  }

  /// 送りバント成功時の走塁
  /// 打者は1塁でアウト。各走者が1塁ずつ進む。
  /// （簡易: 進塁先が空いている場合のみ進塁。詰まっていたら据え置き）
  _RunnerAdvanceResult _advanceOnSacrificeBunt(BaseRunners runners) {
    final scorers = <Player>[];
    Player? newSecond;
    Player? newThird;

    // 3塁ランナーは普通動かない（バント=ゴロは内野前なのでホーム生還は稀）
    newThird = runners.third;

    // 2塁ランナーは3塁が空いていれば3塁へ
    if (runners.second != null) {
      if (newThird == null) {
        newThird = runners.second;
      } else {
        // 3塁が詰まっていれば据え置き（実際には起こらない想定だが念のため）
        newThird = runners.second;
      }
    }

    // 1塁ランナーは2塁が空いていれば2塁へ
    if (runners.first != null) {
      newSecond = runners.first;
    }

    return _RunnerAdvanceResult(
      newRunners: BaseRunners(second: newSecond, third: newThird),
      scoringRunners: scorers,
    );
  }

  /// 野選（FC）時の走塁
  /// バント失敗で先頭走者がアウト。打者は1塁でセーフ。
  /// 1塁ランナーがいれば → 2塁で封殺、打者は1塁
  /// 2塁ランナーがいて1塁が空 → 3塁で封殺、打者は1塁
  /// 1,2塁の場合は2塁ランナー（先頭）がアウト、1塁ランナーは2塁、打者は1塁
  _RunnerAdvanceResult _advanceOnFieldersChoice(
    BaseRunners runners,
    Player batter,
  ) {
    Player? newFirst = batter;
    Player? newSecond;
    Player? newThird = runners.third;

    if (runners.first != null && runners.second != null) {
      // 1,2塁: 2塁ランナー（先頭）が3塁で封殺、1塁ランナー → 2塁、打者 → 1塁
      newSecond = runners.first;
    } else if (runners.second != null) {
      // 2塁のみ: 2塁ランナーが3塁で封殺、打者 → 1塁
    } else if (runners.first != null) {
      // 1塁のみ: 1塁ランナーが2塁で封殺、打者 → 1塁
    }

    // 先頭走者をアウトにする → 1アウト追加
    return _RunnerAdvanceResult(
      newRunners:
          BaseRunners(first: newFirst, second: newSecond, third: newThird),
      additionalOuts: 1,
      scoringRunners: const [],
    );
  }

  /// ホームラン時の走塁
  _RunnerAdvanceResult _advanceOnHomeRun(BaseRunners runners, Player batter) {
    final scorers = <Player>[];
    if (runners.third != null) scorers.add(runners.third!);
    if (runners.second != null) scorers.add(runners.second!);
    if (runners.first != null) scorers.add(runners.first!);
    scorers.add(batter); // 打者自身もホームイン
    return _RunnerAdvanceResult(
      newRunners: BaseRunners.empty,
      scoringRunners: scorers,
    );
  }

  /// 三塁打時の走塁
  _RunnerAdvanceResult _advanceOnTriple(BaseRunners runners, Player batter) {
    final scorers = <Player>[];
    if (runners.third != null) scorers.add(runners.third!);
    if (runners.second != null) scorers.add(runners.second!);
    if (runners.first != null) scorers.add(runners.first!);
    return _RunnerAdvanceResult(
      newRunners: BaseRunners(third: batter),
      scoringRunners: scorers,
    );
  }

  /// 二塁打時の走塁
  _RunnerAdvanceResult _advanceOnDouble(BaseRunners runners, Player batter) {
    final scorers = <Player>[];
    Player? newThird;

    // 3塁ランナー・2塁ランナーはホーム
    if (runners.third != null) scorers.add(runners.third!);
    if (runners.second != null) scorers.add(runners.second!);

    // 1塁ランナー: 基本3塁、走力次第でホーム
    if (runners.first != null) {
      if (_shouldExtraAdvance(runners.first!)) {
        scorers.add(runners.first!);
      } else {
        newThird = runners.first;
      }
    }

    return _RunnerAdvanceResult(
      newRunners: BaseRunners(second: batter, third: newThird),
      scoringRunners: scorers,
    );
  }

  /// 単打・内野安打時の走塁
  _RunnerAdvanceResult _advanceOnSingle(BaseRunners runners, Player batter) {
    final scorers = <Player>[];
    Player? newSecond;
    Player? newThird;

    // 3塁ランナーはホーム
    if (runners.third != null) scorers.add(runners.third!);

    // 2塁ランナー: 基本3塁、走力次第でホーム
    if (runners.second != null) {
      if (_shouldExtraAdvance(runners.second!)) {
        scorers.add(runners.second!);
      } else {
        newThird = runners.second;
      }
    }

    // 1塁ランナー: 基本2塁、走力次第で3塁（3塁が空いている場合のみ）
    if (runners.first != null) {
      if (newThird == null && _shouldExtraAdvance(runners.first!)) {
        newThird = runners.first;
      } else {
        newSecond = runners.first;
      }
    }

    return _RunnerAdvanceResult(
      newRunners: BaseRunners(first: batter, second: newSecond, third: newThird),
      scoringRunners: scorers,
    );
  }

  /// 四球時の走塁（押し出し判定含む）
  _RunnerAdvanceResult _advanceOnWalk(BaseRunners runners, Player batter) {
    final scorers = <Player>[];
    Player? newFirst = batter;
    Player? newSecond = runners.second;
    Player? newThird = runners.third;

    if (runners.isLoaded) {
      // 満塁: 押し出し（3塁ランナーが生還）
      scorers.add(runners.third!);
      newThird = runners.second;
      newSecond = runners.first;
    } else if (runners.first != null && runners.second != null) {
      // 1,2塁: 詰まって進塁
      newThird = runners.second;
      newSecond = runners.first;
    } else if (runners.first != null) {
      // 1塁のみ: 1塁ランナーが2塁へ
      newSecond = runners.first;
    }
    // それ以外は打者が1塁に出るだけ

    return _RunnerAdvanceResult(
      newRunners: BaseRunners(first: newFirst, second: newSecond, third: newThird),
      scoringRunners: scorers,
    );
  }

  /// ゴロアウト時の走塁
  _RunnerAdvanceResult _advanceOnGroundOut(BaseRunners runners, int outs) {
    // 2アウト時は3アウトチェンジ、走者進塁なし
    if (outs >= 2) {
      return const _RunnerAdvanceResult(newRunners: BaseRunners.empty);
    }

    // 0-1アウト: 走者進塁
    final scorers = <Player>[];
    if (runners.third != null) scorers.add(runners.third!);

    return _RunnerAdvanceResult(
      newRunners: BaseRunners(second: runners.first, third: runners.second),
      scoringRunners: scorers,
    );
  }

  /// 併殺打時の走塁
  _RunnerAdvanceResult _advanceOnDoublePlay(BaseRunners runners, int outs) {
    // 併殺で3アウトになるかどうか
    final willBeThreeOuts = outs == 1;
    final scorers = <Player>[];

    // 満塁の場合、3塁ランナーがホームへ（ただし3アウトにならない場合のみ）
    if (runners.isLoaded && !willBeThreeOuts) {
      scorers.add(runners.third!);
    }

    // 2塁ランナーは3塁へ、1塁・2塁は空く
    return _RunnerAdvanceResult(
      newRunners: BaseRunners(third: runners.second),
      scoringRunners: scorers,
    );
  }

  /// 外野フライ時の走塁（タッチアップ判定含む）
  _RunnerAdvanceResult _advanceOnFlyOut(
    BaseRunners runners,
    int outs,
    FieldPosition? fieldPosition,
    Team? pitchingTeam,
  ) {
    final isOutfield = fieldPosition?.isOutfield ?? false;

    // 内野フライ or 2アウト: 走者動かず
    if (!isOutfield || outs >= 2) {
      return _advanceOnNoChange(runners);
    }

    // タッチアップ判定
    return _processTagUp(runners, outs, fieldPosition!, pitchingTeam);
  }

  /// タッチアップ処理（外野フライ時）
  _RunnerAdvanceResult _processTagUp(
    BaseRunners runners,
    int outs,
    FieldPosition fieldPosition,
    Team? pitchingTeam,
  ) {
    final scorers = <Player>[];
    int tagUpOuts = 0;
    final tagUpAttempts = <TagUpAttempt>[];

    Player? newFirst = runners.first;
    Player? newSecond = runners.second;
    Player? newThird = runners.third;

    // 外野手の肩を取得
    final outfielder = pitchingTeam?.getFielder(fieldPosition);
    final outfielderArm = outfielder?.arm ?? 5;

    // フライの深さを内部抽選（浅い 30% / 中 40% / 深い 30%）。
    // この打席のタッチアップ判定（3塁・2塁の両方）に共通で適用する。
    final flyDepth = _rollFlyDepth();

    // 3塁ランナーのタッチアップ判定
    bool thirdRunnerTaggedUp = false;
    bool thirdRunnerScored = false;

    if (runners.third != null &&
        _shouldAttemptTagUp(runners.third!, flyDepth, outfielderArm)) {
      thirdRunnerTaggedUp = true;
      if (_isTagUpSuccessful(runners.third!, flyDepth, outfielderArm)) {
        thirdRunnerScored = true;
        scorers.add(runners.third!);
        newThird = null;
        tagUpAttempts.add(TagUpAttempt(
          runner: runners.third!,
          fromBase: Base.third,
          toBase: Base.home,
          success: true,
        ));
      } else {
        tagUpOuts++;
        newThird = null;
        tagUpAttempts.add(TagUpAttempt(
          runner: runners.third!,
          fromBase: Base.third,
          toBase: Base.home,
          success: false,
        ));
      }
    }

    // 3塁ランナーのタッチアップ失敗で既に3アウト目に達している場合、
    // 2塁ランナーのタッチアップは処理しない（プレイが死んでいるため）
    // outs(打席前) + 1(フライアウト) + tagUpOuts(3塁ランナー分) >= 3 ならイニング終了
    final inningAlreadyEnded = outs + 1 + tagUpOuts >= 3;

    // 2塁ランナーのタッチアップ判定
    //
    // 物理的整合性: 外野手は捕球後 1 つしか送球できないため、
    // 3塁走者がタッチアップ試行している場合は本塁送球になり、
    // 2塁走者の 3塁進塁を阻止することは時間的に不可能（→ 無条件成功）。
    // 3塁走者がいない場合のみ、外野手は 3塁送球を選び、走力 vs 肩で判定する。
    if (!inningAlreadyEnded &&
        runners.second != null &&
        _canSecondRunnerTagUp(fieldPosition) &&
        (thirdRunnerTaggedUp || runners.third == null)) {
      if (_shouldAttemptTagUp(runners.second!, flyDepth, outfielderArm)) {
        if (runners.third != null) {
          // 同時タッチアップ: 外野手は本塁送球。2塁→3塁は無条件成功。
          // 3塁走者が本塁でセーフでもアウトでも、2塁走者は 3塁を取れる。
          newThird = runners.second;
          newSecond = null;
          tagUpAttempts.add(TagUpAttempt(
            runner: runners.second!,
            fromBase: Base.second,
            toBase: Base.third,
            success: true,
          ));
        } else {
          // 単独タッチアップ: 外野手は 3塁送球。走力 vs 肩で判定。
          if (_isTagUpSuccessful(runners.second!, flyDepth, outfielderArm)) {
            newThird = runners.second;
            newSecond = null;
            tagUpAttempts.add(TagUpAttempt(
              runner: runners.second!,
              fromBase: Base.second,
              toBase: Base.third,
              success: true,
            ));
          } else {
            tagUpOuts++;
            newSecond = null;
            tagUpAttempts.add(TagUpAttempt(
              runner: runners.second!,
              fromBase: Base.second,
              toBase: Base.third,
              success: false,
            ));
          }
        }
      }
    }

    // タッチアップ失敗で3アウトになった場合、得点は無効
    final inningEnds = outs + 1 + tagUpOuts >= 3;
    final finalScorers = inningEnds ? <Player>[] : scorers;

    // 犠飛: 3塁走者がタッチアップで生還し、その得点が有効ならば true。
    // 集計上は「打数に含めない、出塁率の分母には入る、打点として記録」になる。
    final wasSacrificeFly = thirdRunnerScored && !inningEnds;

    return _RunnerAdvanceResult(
      newRunners: BaseRunners(first: newFirst, second: newSecond, third: newThird),
      additionalOuts: tagUpOuts,
      tagUps: tagUpAttempts,
      scoringRunners: finalScorers,
      wasSacrificeFly: wasSacrificeFly,
    );
  }

  /// ランナー変化なし（三振・ライナーアウト）
  _RunnerAdvanceResult _advanceOnNoChange(BaseRunners runners) {
    return _RunnerAdvanceResult(newRunners: runners);
  }

  /// エラー出塁時の走塁
  _RunnerAdvanceResult _advanceOnError(BaseRunners runners, Player batter) {
    final scorers = <Player>[];
    if (runners.third != null) scorers.add(runners.third!);

    return _RunnerAdvanceResult(
      newRunners: BaseRunners(
        first: batter,
        second: runners.first,
        third: runners.second,
      ),
      scoringRunners: scorers,
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
  final BaseRunners newRunners;
  final int additionalOuts; // タッチアップ失敗などによる追加アウト
  final List<TagUpAttempt> tagUps; // タッチアップの試み

  /// この走塁で生還した選手（責任投手の特定に使用）
  /// 打席結果による得点（HR で打者自身が含まれる場合もある）。
  final List<Player> scoringRunners;

  /// 外野フライ + 3塁走者がタッチアップで生還したケース。
  /// 呼び出し側で打席結果を flyOut → sacrificeFly に書き換えるためのフラグ。
  final bool wasSacrificeFly;

  const _RunnerAdvanceResult({
    required this.newRunners,
    this.additionalOuts = 0,
    this.tagUps = const [],
    this.scoringRunners = const [],
    this.wasSacrificeFly = false,
  });

  int get runsScored => scoringRunners.length;
}

/// 外野フライの深さ（_processTagUp 内部のみで使用、外には漏らさない）。
/// 浅い: タッチアップ不可寄り / 中くらい: 走力・肩で揺れる / 深い: 確実に走れる。
enum _FlyDepth { shallow, medium, deep }

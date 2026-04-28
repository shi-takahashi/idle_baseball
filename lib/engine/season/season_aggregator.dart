import '../models/models.dart';
import 'player_season_stats.dart';
import 'standings.dart';

/// シーズンを通して試合結果を集計するクラス
///
/// チーム生成時に `SeasonAggregator(teams)` で初期化し、試合ごとに `recordGame(game)` を呼ぶ。
/// 集計対象:
/// - チーム順位表（勝敗・得失点）
/// - 野手・投手のシーズン成績
/// - 勝ち投手・負け投手（ハーフイニング単位の簡易判定）
class SeasonAggregator {
  final Standings standings;
  final Map<String, BatterSeasonStats> batterStats;
  final Map<String, PitcherSeasonStats> pitcherStats;

  SeasonAggregator(List<Team> teams)
      : standings = Standings([for (final t in teams) TeamRecord(t)]),
        batterStats = {},
        pitcherStats = {} {
    for (final team in teams) {
      // チーム保有選手（players + 先発ローテ + 救援 + 控え）
      // 重複を避けるため id ベースで集約
      final all = <String, Player>{};
      for (final p in [
        ...team.players,
        ...team.startingRotation,
        ...team.bullpen,
        ...team.bench,
      ]) {
        all[p.id] = p;
      }
      for (final p in all.values) {
        if (p.isPitcher) {
          pitcherStats[p.id] = PitcherSeasonStats(player: p, team: team);
        } else {
          batterStats[p.id] = BatterSeasonStats(player: p, team: team);
        }
      }
    }
  }

  /// 1試合の結果を集計に反映
  void recordGame(GameResult game) {
    _updateTeamRecord(game);
    _collectPlayerStats(game);
    _updateWinLoss(game);
  }

  // ---- チーム勝敗 ----
  void _updateTeamRecord(GameResult game) {
    final homeRecord =
        standings.records.firstWhere((r) => r.team.id == game.homeTeam.id);
    final awayRecord =
        standings.records.firstWhere((r) => r.team.id == game.awayTeam.id);
    homeRecord.games++;
    awayRecord.games++;
    homeRecord.runsScored += game.homeScore;
    homeRecord.runsAllowed += game.awayScore;
    awayRecord.runsScored += game.awayScore;
    awayRecord.runsAllowed += game.homeScore;

    if (game.homeScore > game.awayScore) {
      homeRecord.wins++;
      awayRecord.losses++;
    } else if (game.awayScore > game.homeScore) {
      awayRecord.wins++;
      homeRecord.losses++;
    } else {
      homeRecord.ties++;
      awayRecord.ties++;
    }

    // 失策（フィールディングエラー）の集計
    // 守備側 = halfInning.isTop なら home（home が守る）/ そうでなければ away
    for (final half in game.halfInnings) {
      final fieldingRecord = half.isTop ? homeRecord : awayRecord;
      for (final ab in half.atBats) {
        if (ab.fieldingError != null) {
          fieldingRecord.errors++;
        }
      }
    }
  }

  // ---- 勝ち投手・負け投手・セーブ・ホールド ----
  void _updateWinLoss(GameResult game) {
    final decisive = _determineDecisivePitchers(game);
    final winnerId = decisive.$1?.id;
    final loserId = decisive.$2?.id;
    if (winnerId != null) pitcherStats[winnerId]?.wins++;
    if (loserId != null) pitcherStats[loserId]?.losses++;

    // 登板履歴をビルドして、save / hold の判定に使い回す
    final outings = _buildOutings(game);
    _updateSave(game, winnerId, outings.$1, outings.$2);
    _updateHolds(winnerId, outings.$1, outings.$2);
  }

  /// 各チームの登板履歴を時系列で組み立てる
  /// 各 `_PitcherOuting` には登板時のリード/走者数、登板中の最低リード、
  /// アウト数を記録する。save / hold 判定はこのデータをもとに行う。
  (List<_PitcherOuting>, List<_PitcherOuting>) _buildOutings(GameResult game) {
    final homeOutings = <_PitcherOuting>[
      _PitcherOuting(
          pitcher: game.homeTeam.pitcher, entryLead: 0, entryRunners: 0),
    ];
    final awayOutings = <_PitcherOuting>[
      _PitcherOuting(
          pitcher: game.awayTeam.pitcher, entryLead: 0, entryRunners: 0),
    ];

    int homeScore = 0;
    int awayScore = 0;

    for (final half in game.halfInnings) {
      final defenderIsHome = half.isTop;
      final defOutings = defenderIsHome ? homeOutings : awayOutings;

      // このハーフ内で発生する投手交代を atBatIndex でグルーピング
      final changesByIdx = <int, List<PitcherChangeEvent>>{};
      for (final ch in half.pitcherChanges) {
        changesByIdx.putIfAbsent(ch.atBatIndex, () => []).add(ch);
      }

      for (int i = 0; i < half.atBats.length; i++) {
        // この打席の前に発生する投手交代を反映
        final changes = changesByIdx[i];
        if (changes != null) {
          for (final ch in changes) {
            final defScore = defenderIsHome ? homeScore : awayScore;
            final batScore = defenderIsHome ? awayScore : homeScore;
            defOutings.add(_PitcherOuting(
              pitcher: ch.newPitcher,
              entryLead: defScore - batScore,
              entryRunners: half.atBats[i].runnersBefore.count,
            ));
          }
        }

        final ab = half.atBats[i];
        final outing = defOutings.last;
        outing.outsRecorded += _outsInAtBat(ab);

        int runsHere = ab.rbiCount;
        for (final pitch in ab.pitches) {
          if (pitch.batteryError != null) {
            runsHere += pitch.batteryError!.runsScored;
          }
        }
        if (defenderIsHome) {
          awayScore += runsHere;
        } else {
          homeScore += runsHere;
        }

        final defScore = defenderIsHome ? homeScore : awayScore;
        final batScore = defenderIsHome ? awayScore : homeScore;
        final currentLead = defScore - batScore;
        if (currentLead < outing.minLeadDuring) {
          outing.minLeadDuring = currentLead;
        }
      }
    }

    return (homeOutings, awayOutings);
  }

  /// セーブ機会の条件（save / hold 共通）
  ///   必須:
  ///     - 1/3 イニング以上
  ///     - 登板時にリードしていた
  ///     - 登板中に同点・逆転を許していない
  ///   かついずれか:
  ///     A. 3点差以内のリードで 1イニング以上投げる
  ///     B. リード ≤ 走者数 + 2（連続2HRで同点・逆転）
  ///     C. 3イニング以上投げる
  bool _meetsSaveSituation(_PitcherOuting outing) {
    if (outing.outsRecorded < 1) return false;
    if (outing.entryLead <= 0) return false;
    if (outing.minLeadDuring <= 0) return false;
    final entryLead = outing.entryLead;
    final entryRunners = outing.entryRunners;
    final outs = outing.outsRecorded;
    final condA = entryLead <= 3 && outs >= 3;
    final condB = entryLead <= entryRunners + 2;
    final condC = outs >= 9;
    return condA || condB || condC;
  }

  // ---- セーブ ----
  /// セーブの判定:
  ///   必須条件:
  ///     - 勝利投手でない
  ///     - 自チームが勝った試合の最後を投げ切った投手
  ///     - セーブ機会の条件を満たす
  void _updateSave(
    GameResult game,
    String? winnerPitcherId,
    List<_PitcherOuting> homeOutings,
    List<_PitcherOuting> awayOutings,
  ) {
    if (game.winner == null) return;
    final homeWon = game.winner == game.homeTeamName;
    final winningOutings = homeWon ? homeOutings : awayOutings;
    final finisher = winningOutings.last;

    if (winnerPitcherId != null && finisher.pitcher.id == winnerPitcherId) {
      return;
    }
    if (!_meetsSaveSituation(finisher)) return;

    pitcherStats[finisher.pitcher.id]?.saves++;
  }

  // ---- ホールド ----
  /// ホールドの判定（救援登板ごとに独立に評価）:
  ///   - 先発投手ではない（i > 0）
  ///   - 試合の最後を投げ切ったのではない（i < length - 1、後続投手にバトンタッチ）
  ///   - 勝利投手でない
  ///   - セーブ機会の条件を満たす
  ///
  /// 試合の勝敗は無関係（負け試合でもホールドはつく）。
  /// 1試合で複数の投手にホールドがつくことがある。
  void _updateHolds(
    String? winnerPitcherId,
    List<_PitcherOuting> homeOutings,
    List<_PitcherOuting> awayOutings,
  ) {
    for (final outings in [homeOutings, awayOutings]) {
      // i == 0 は先発、i == length-1 はそのチームの最終投手（フィニッシャー）
      for (int i = 1; i < outings.length - 1; i++) {
        final outing = outings[i];
        if (winnerPitcherId != null && outing.pitcher.id == winnerPitcherId) {
          continue;
        }
        if (!_meetsSaveSituation(outing)) continue;
        pitcherStats[outing.pitcher.id]?.holds++;
      }
    }
  }

  // ---- 選手成績 ----
  void _collectPlayerStats(GameResult game) {
    // 出場した選手（games カウント用）
    final batterAppeared = <String>{};
    final pitcherAppeared = <String>{};

    // スタメン野手は自動的に出場
    for (final p in game.homeTeam.players.skip(1)) {
      batterAppeared.add(p.id);
    }
    for (final p in game.awayTeam.players.skip(1)) {
      batterAppeared.add(p.id);
    }
    // 先発投手は自動的に出場
    pitcherAppeared.add(game.homeTeam.pitcher.id);
    pitcherAppeared.add(game.awayTeam.pitcher.id);

    for (final half in game.halfInnings) {
      // 投手交代で登板した投手を追加
      for (final change in half.pitcherChanges) {
        pitcherAppeared.add(change.newPitcher.id);
      }
      // 野手交代で出場した選手を追加
      for (final fc in half.fielderChanges) {
        batterAppeared.add(fc.incoming.id);
      }

      // 盗塁成績
      for (final se in half.stealEvents) {
        for (final att in se.attempts) {
          final stats = batterStats[att.runner.id];
          if (stats == null) continue;
          if (att.success) {
            stats.stolenBases++;
          } else if (att.isOut) {
            stats.caughtStealing++;
          }
        }
      }

      // 打席ごとの集計
      for (final ab in half.atBats) {
        // 投手のアウト集計（未完了打席を含めて全て）
        final pStats = pitcherStats[ab.pitcher.id];
        if (pStats != null) {
          pStats.outsRecorded += _outsInAtBat(ab);
        }

        if (ab.isIncomplete) continue;

        // 野手成績
        final bStats = batterStats[ab.batter.id];
        if (bStats != null) {
          bStats.plateAppearances++;
          final isSacFly =
              ab.result == AtBatResultType.flyOut && ab.rbiCount > 0;
          if (isSacFly) bStats.sacFlies++;
          // 打数: 打席 - 四球 - 犠飛
          if (ab.result != AtBatResultType.walk && !isSacFly) {
            bStats.atBats++;
          }
          if (ab.result == AtBatResultType.walk) bStats.walks++;
          if (ab.result == AtBatResultType.strikeout) bStats.strikeouts++;
          if (ab.result.isHit) bStats.hits++;
          if (ab.result == AtBatResultType.double_) bStats.doubles++;
          if (ab.result == AtBatResultType.triple) bStats.triples++;
          if (ab.result == AtBatResultType.homeRun) bStats.homeRuns++;
          bStats.rbi += ab.rbiCount;
        }

        // 投手成績（打席内のカウント系）
        if (pStats != null) {
          if (ab.result.isHit) pStats.hitsAllowed++;
          if (ab.result == AtBatResultType.homeRun) pStats.homeRunsAllowed++;
          if (ab.result == AtBatResultType.walk) pStats.walksAllowed++;
          if (ab.result == AtBatResultType.strikeout) {
            pStats.strikeoutsRecorded++;
          }
        }

        // 失点（runsByPitcher）: 打席で生還した走者の責任投手に分配済みのマップを使用
        // インヘリット走者（前任投手が出した走者）の生還は前任投手の失点になる
        for (final entry in ab.runsByPitcher.entries) {
          final responsibleStats = pitcherStats[entry.key];
          if (responsibleStats != null) {
            responsibleStats.runsAllowed += entry.value;
          }
        }
        // 自責点（earnedRunsByPitcher）: 失点のうち投手の責任分のみ
        for (final entry in ab.earnedRunsByPitcher.entries) {
          final responsibleStats = pitcherStats[entry.key];
          if (responsibleStats != null) {
            responsibleStats.earnedRuns += entry.value;
          }
        }
      }
    }

    // 出場カウント
    for (final id in batterAppeared) {
      batterStats[id]?.games++;
    }
    for (final id in pitcherAppeared) {
      pitcherStats[id]?.games++;
    }

    // 先発登板
    pitcherStats[game.homeTeam.pitcher.id]?.starts++;
    pitcherStats[game.awayTeam.pitcher.id]?.starts++;
  }

  /// この打席でピッチャーが記録したアウト数
  /// 打席結果によるアウト + タッチアップ失敗による追加アウト + 盗塁死
  int _outsInAtBat(AtBatResult ab) {
    int outs = 0;
    if (!ab.isIncomplete) {
      if (ab.result.isOut) {
        outs = ab.result.isDoublePlay ? 2 : 1;
      }
      if (ab.tagUps != null) {
        for (final tu in ab.tagUps!) {
          if (!tu.success) outs++;
        }
      }
    }
    // 盗塁死（未完了打席でも計上）
    for (final pitch in ab.pitches) {
      if (pitch.steals != null) {
        for (final att in pitch.steals!) {
          if (att.isOut) outs++;
        }
      }
    }
    return outs;
  }

  /// 勝利投手・敗戦投手を決定する（ハーフイニング単位の簡易版）
  ///
  /// 「勝ちチームがリードを取った最後のハーフイニング」で、その時の両チームの現役投手を採用する。
  /// - 勝ちチームの現役投手 = 勝利投手
  /// - 負けチームの現役投手 = 敗戦投手
  ///
  /// 引き分けの場合はどちらも null。
  /// 複数回リードが入れ替わった場合、最後の勝ち越しの瞬間を採用（再度追いつかれていないので）。
  (Player?, Player?) _determineDecisivePitchers(GameResult game) {
    if (game.winner == null) return (null, null);
    final homeWon = game.winner == game.homeTeamName;

    Player homePitcher = game.homeTeam.pitcher;
    Player awayPitcher = game.awayTeam.pitcher;
    int homeScore = 0;
    int awayScore = 0;
    Player? decisiveWinner;
    Player? decisiveLoser;

    for (final half in game.halfInnings) {
      final isAwayBatting = half.isTop;

      // このハーフでの投手交代を適用（守備側のみ）
      for (final change in half.pitcherChanges) {
        if (isAwayBatting) {
          homePitcher = change.newPitcher;
        } else {
          awayPitcher = change.newPitcher;
        }
      }

      // スコア更新
      final wasHomeLeading = homeScore > awayScore;
      final wasAwayLeading = awayScore > homeScore;
      if (isAwayBatting) {
        awayScore += half.runs;
      } else {
        homeScore += half.runs;
      }
      final isHomeLeading = homeScore > awayScore;
      final isAwayLeading = awayScore > homeScore;

      // 勝者側がこのハーフで「リードなし → リードあり」に変化したなら決定打
      if (homeWon && isHomeLeading && !wasHomeLeading) {
        decisiveWinner = homePitcher;
        decisiveLoser = awayPitcher;
      } else if (!homeWon && isAwayLeading && !wasAwayLeading) {
        decisiveWinner = awayPitcher;
        decisiveLoser = homePitcher;
      }
    }

    return (decisiveWinner, decisiveLoser);
  }
}

/// 1人の投手の登板（セーブ判定用）
class _PitcherOuting {
  final Player pitcher;
  final int entryLead; // 登板時のリード（守備チーム視点、正で勝っている）
  final int entryRunners; // 登板時の走者数
  int outsRecorded = 0; // この登板で取ったアウト
  int minLeadDuring; // 登板中の最低リード（≤0 になれば同点・逆転を許した）

  _PitcherOuting({
    required this.pitcher,
    required this.entryLead,
    required this.entryRunners,
  }) : minLeadDuring = entryLead;
}

import 'dart:math';

import '../models/models.dart';
import '../simulation/simulation.dart';
import 'player_season_stats.dart';
import 'schedule.dart';
import 'season_result.dart';
import 'standings.dart';

/// シーズン全試合をシミュレートし、順位表と個人成績を集計する
class SeasonSimulator {
  final GameSimulator _gameSimulator;

  SeasonSimulator({Random? random, GameSimulator? gameSimulator})
      : _gameSimulator = gameSimulator ?? GameSimulator(random: random);

  /// 指定チーム・日程でシーズン全試合をシミュレート
  SeasonResult simulate(List<Team> teams, Schedule schedule) {
    // ---- 初期化 ----
    final standings = Standings([for (final t in teams) TeamRecord(t)]);
    final batterStats = <String, BatterSeasonStats>{};
    final pitcherStats = <String, PitcherSeasonStats>{};
    for (final team in teams) {
      for (final p in [...team.players, ...team.bullpen, ...team.bench]) {
        if (p.isPitcher) {
          pitcherStats[p.id] = PitcherSeasonStats(player: p, team: team);
        } else {
          batterStats[p.id] = BatterSeasonStats(player: p, team: team);
        }
      }
    }

    // ---- 全試合を順次シミュレーション ----
    final results = <GameResult>[];
    for (final sg in schedule.games) {
      final result = _gameSimulator.simulate(sg.homeTeam, sg.awayTeam);
      results.add(result);
      _recordGame(result, standings, batterStats, pitcherStats);
    }

    return SeasonResult(
      schedule: schedule,
      games: results,
      standings: standings,
      batterStats: batterStats,
      pitcherStats: pitcherStats,
    );
  }

  /// 1試合の結果を集計に反映
  void _recordGame(
    GameResult game,
    Standings standings,
    Map<String, BatterSeasonStats> batterStats,
    Map<String, PitcherSeasonStats> pitcherStats,
  ) {
    // ---- チーム勝敗 ----
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

    // ---- 選手成績 ----
    _collectPlayerStats(game, batterStats, pitcherStats);

    // ---- 勝ち投手・負け投手 ----
    final decisive = _determineDecisivePitchers(game);
    final winnerId = decisive.$1?.id;
    final loserId = decisive.$2?.id;
    if (winnerId != null) pitcherStats[winnerId]?.wins++;
    if (loserId != null) pitcherStats[loserId]?.losses++;
  }

  /// 1試合の個人成績を集計
  void _collectPlayerStats(
    GameResult game,
    Map<String, BatterSeasonStats> batterStats,
    Map<String, PitcherSeasonStats> pitcherStats,
  ) {
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
          // 失点: 打点分 + バッテリーエラー得点分
          // （簡略化: この打席を投げた投手にそのまま計上。インヘリット走者の扱いは無視）
          pStats.runsAllowed += ab.rbiCount;
          for (final pitch in ab.pitches) {
            if (pitch.batteryError != null) {
              pStats.runsAllowed += pitch.batteryError!.runsScored;
            }
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

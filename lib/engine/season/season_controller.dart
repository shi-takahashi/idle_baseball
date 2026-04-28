import 'dart:math';

import '../generators/generators.dart';
import '../models/models.dart';
import '../simulation/simulation.dart';
import 'player_season_stats.dart';
import 'schedule.dart';
import 'schedule_generator.dart';
import 'scheduled_game.dart';
import 'season_aggregator.dart';
import 'standings.dart';

/// シーズン進行を管理するコントローラー（可変状態）
///
/// 1日ずつ試合を進めるための状態管理:
/// - `advanceDay()`: 次の日（3試合）をシミュレート
/// - `advanceAll()`: 残り全日を一括シミュレート（デバッグ用）
///
/// 進行状況:
/// - `currentDay == 0` → シーズン開始前（まだ1試合も消化していない）
/// - `currentDay == N (1〜totalDays)` → N日目まで消化済み
/// - `isSeasonOver == true` → 全日消化済み
///
/// engine 層を Flutter に依存させないため、独自の listener API を持つ:
/// - `addListener(void Function())`
/// - `removeListener(void Function())`
/// - 進行操作の度に登録済みリスナーが呼ばれる
///
/// UI 側は `Listenable` に変換するアダプタ（lib/screens/season_listenable.dart）を
/// 経由して `ListenableBuilder` で購読する。
class SeasonController {
  final List<Team> teams;
  final Schedule schedule;
  final String myTeamId;
  final SeasonAggregator _aggregator;
  final GameSimulator _gameSimulator;

  /// gameNumber → GameResult のマップ（未実行の試合はキーなし）
  final Map<int, GameResult> _results = {};

  int _currentDay = 0;

  /// 進行通知を受け取るリスナー
  final List<void Function()> _listeners = [];

  /// 進行通知のリスナー登録
  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  /// 進行通知のリスナー解除
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void _notify() {
    // リスナー内で removeListener が呼ばれても安全に走るようコピー
    for (final l in List<void Function()>.of(_listeners)) {
      l();
    }
  }

  // ---- 投手スタミナ（試合間） ----
  // 各先発投手のコンディション（0-100）。試合で消費・1日経過で回復する。
  // pitcher.id をキーに保持。
  final Map<String, int> _pitcherFreshness = {};

  // 各投手の最終登板日。中4日縛りの判定に使う。
  // 未登板は -100 とみなす（実装上は entry なしで処理）。
  final Map<String, int> _pitcherLastStartDay = {};

  // 完投 1試合 ≒ 120球で full depletion (-100)
  static const double _completeGamePitches = 120;
  // 中4日（5日空ける）以上空いていない投手は原則先発しない
  static const int _minDaysBetweenStarts = 5;
  // 先発として「フル回復」とみなす閾値
  // ここを 100 にすることで「完全回復するまで先発させない」運用にし、
  // 投球数（=消耗の重さ）次第で次の登板までの間隔が変わる → 各チームの
  // ローテ周期にズレが生じて、同じ投手の投げ合いが固定化しない。
  static const int _starterReadyThreshold = 100;

  // リリーフ投手は短い登板が多いので、コンディション 80 を「使用可能」とみなす。
  // - 1イニング登板（~15球）→ 翌日には 100 近くまで戻り、翌々日に出せる
  // - 2イニング登板（~30球）→ 1日休み必要
  // - 3イニング以上 → 2日以上休み必要
  static const int _relieverReadyThreshold = 80;

  /// 先発選出時のローテ揺らぎ用 RNG。
  /// 完全に決定論的に「最終登板日が古い順」で選ぶと 100% 中5日に固定されるため、
  /// 微小な揺らぎを与えて現実の中4日／中6日が混ざるようにする。
  final Random _rotationRandom;

  SeasonController({
    required this.teams,
    required this.schedule,
    required this.myTeamId,
    GameSimulator? gameSimulator,
    Random? random,
  })  : _aggregator = SeasonAggregator(teams),
        _gameSimulator = gameSimulator ?? GameSimulator(random: random),
        _rotationRandom = random ?? Random() {
    // 開幕時、SP・RP 全員フレッシュ（100）でスタート
    for (final team in teams) {
      for (final p in [...team.startingRotation, ...team.bullpen]) {
        _pitcherFreshness[p.id] = 100;
      }
    }
  }

  /// 6チームを自動生成して新しいシーズンを開始するファクトリ
  factory SeasonController.newSeason({
    Random? random,
    String myTeamId = 'team_phoenix',
  }) {
    final teams = TeamGenerator(random: random).generateLeague();
    final schedule = const ScheduleGenerator().generate(teams);
    return SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: myTeamId,
      random: random,
    );
  }

  // ---- 状態の参照 ----
  int get currentDay => _currentDay;
  int get totalDays => schedule.totalDays;
  bool get isSeasonOver => _currentDay >= schedule.totalDays;
  Team get myTeam => teams.firstWhere((t) => t.id == myTeamId);
  Standings get standings => _aggregator.standings;
  Map<String, BatterSeasonStats> get batterStats => _aggregator.batterStats;
  Map<String, PitcherSeasonStats> get pitcherStats => _aggregator.pitcherStats;

  /// 指定日の予定試合一覧
  List<ScheduledGame> scheduledGamesOnDay(int day) =>
      schedule.gamesOnDay(day);

  /// 指定 gameNumber の結果（未実行なら null）
  GameResult? resultFor(int gameNumber) => _results[gameNumber];

  /// 指定チームの打撃集計（順位表での 打率・本塁打・盗塁 用）
  ({int hits, int atBats, int homeRuns, int stolenBases}) teamBattingTotals(
      String teamId) {
    int hits = 0, atBats = 0, homeRuns = 0, stolenBases = 0;
    for (final s in _aggregator.batterStats.values) {
      if (s.team.id != teamId) continue;
      hits += s.hits;
      atBats += s.atBats;
      homeRuns += s.homeRuns;
      stolenBases += s.stolenBases;
    }
    return (
      hits: hits,
      atBats: atBats,
      homeRuns: homeRuns,
      stolenBases: stolenBases,
    );
  }

  /// 指定チームの投手集計（順位表での防御率用）
  /// outsRecorded: 投手が奪ったアウト合計（投球回 = outs / 3）
  /// runsAllowed: 投手が記録した失点合計
  ({int outsRecorded, int runsAllowed}) teamPitchingTotals(String teamId) {
    int outs = 0, runs = 0;
    for (final s in _aggregator.pitcherStats.values) {
      if (s.team.id != teamId) continue;
      outs += s.outsRecorded;
      runs += s.runsAllowed;
    }
    return (outsRecorded: outs, runsAllowed: runs);
  }

  // ---- 進行操作 ----

  /// 1日分（3試合）をシミュレート
  /// シーズン終了済みなら何もせず空リストを返す
  List<GameResult> advanceDay() {
    if (isSeasonOver) return const [];
    _currentDay++;

    // 1日経過分の回復（全 SP 対象）
    _recoverPitcherFreshness();

    final games = scheduledGamesOnDay(_currentDay);
    final results = <GameResult>[];
    for (final sg in games) {
      // 各チームの今日の先発を選出
      final homeSP = _selectStarter(sg.homeTeam);
      final awaySP = _selectStarter(sg.awayTeam);
      final homeForGame = _withGameLineup(sg.homeTeam, homeSP);
      final awayForGame = _withGameLineup(sg.awayTeam, awaySP);

      final result = _gameSimulator.simulate(homeForGame, awayForGame);
      _results[sg.gameNumber] = result;
      _aggregator.recordGame(result);

      // 球数に応じてコンディションを消費（先発・リリーフそれぞれ）
      _depleteStarterFreshness(result);
      _depleteRelieverFreshness(result);

      results.add(result);
    }
    _notify();
    return results;
  }

  /// 残り全日を一括シミュレート（デバッグ用）
  /// 内部で advanceDay を呼ぶたびに通知が走るため、ここでは追加通知しない
  void advanceAll() {
    while (!isSeasonOver) {
      advanceDay();
    }
  }

  // ---- 投手スタミナ管理 ----

  /// 1日分の回復を全投手（SP + RP）に適用
  /// 回復量は素 stamina パラメータで決まる:
  /// stamina 1 → 15/日, stamina 5 → 17/日, stamina 10 → 20/日
  void _recoverPitcherFreshness() {
    for (final team in teams) {
      for (final p in [...team.startingRotation, ...team.bullpen]) {
        final current = _pitcherFreshness[p.id] ?? 100;
        if (current >= 100) continue;
        final stamina = p.stamina ?? 5;
        final recovery = (14 + stamina * 0.6).round();
        _pitcherFreshness[p.id] = (current + recovery).clamp(0, 100);
      }
    }
  }

  /// 試合の先発投手から、球数に応じてコンディションを消費する
  void _depleteStarterFreshness(GameResult game) {
    for (final team in [game.homeTeam, game.awayTeam]) {
      final sp = team.pitcher;
      int pitches = 0;
      for (final half in game.halfInnings) {
        for (final ab in half.atBats) {
          if (ab.pitcher.id == sp.id) {
            pitches += ab.pitches.length;
          }
        }
      }
      final depletion = (pitches * 100 / _completeGamePitches).round();
      final current = _pitcherFreshness[sp.id] ?? 100;
      _pitcherFreshness[sp.id] = (current - depletion).clamp(0, 100);
      _pitcherLastStartDay[sp.id] = _currentDay;
    }
  }

  /// 試合のリリーフ投手から、球数に応じてコンディションを消費する
  /// 各 RP の試合内合計投球数を集計して、それぞれ深ぴ depletion を適用
  void _depleteRelieverFreshness(GameResult game) {
    for (final team in [game.homeTeam, game.awayTeam]) {
      final starterId = team.pitcher.id;
      // 各リリーフ投手の球数を集計
      final pitchesByReliever = <String, int>{};
      for (final half in game.halfInnings) {
        for (final ab in half.atBats) {
          final id = ab.pitcher.id;
          if (id == starterId) continue;
          pitchesByReliever[id] =
              (pitchesByReliever[id] ?? 0) + ab.pitches.length;
        }
      }
      for (final entry in pitchesByReliever.entries) {
        final pitches = entry.value;
        final depletion = (pitches * 100 / _completeGamePitches).round();
        final current = _pitcherFreshness[entry.key] ?? 100;
        _pitcherFreshness[entry.key] =
            (current - depletion).clamp(0, 100);
      }
    }
  }

  /// その日のブルペンを「使用可能な順」に並び替えて返す
  /// - コンディション 80 以上を「フレッシュな RP」として優先
  /// - その中でも残コンディションが高い順に並べる（フレッシュ順）
  /// - フレッシュな RP が 3 人未満なら、全員から残コンディション順で並べる
  List<Player> _availableBullpen(Team team) {
    final all = team.bullpen.toList();
    final fresh = all
        .where((p) =>
            (_pitcherFreshness[p.id] ?? 100) >= _relieverReadyThreshold)
        .toList();
    final pool = fresh.length >= 3 ? fresh : all;
    pool.sort((a, b) {
      final fa = _pitcherFreshness[a.id] ?? 100;
      final fb = _pitcherFreshness[b.id] ?? 100;
      return fb.compareTo(fa);
    });
    return pool;
  }

  /// 今日の先発を選出する
  /// 1. ローテが空なら従来通り players[0] を使用（後方互換）
  /// 2. 中4日以上空いている SP に絞る（hard min）
  /// 3. その中でコンディション 100 のフル回復 SP がいれば、登板から最も空いている者
  /// 4. フル回復者がいなければ、最も登板から空いている者（コンディションは二次基準）
  /// 5. 中4日縛りで誰もいなければ、最も登板から日数が空いている者にフォールバック
  ///
  /// タイブレーカーを「最終登板日が古い順」にすることで、ローテ全員が均等に
  /// 回るようになる。また閾値 100（フル回復必須）にしたことで、消耗の重い
  /// 試合の翌登板が遅れ、各チームのローテ周期が試合内容に応じて自然にズレる。
  Player _selectStarter(Team team) {
    final rotation = team.startingRotation;
    if (rotation.isEmpty) return team.pitcher;

    final restEligible = rotation.where((sp) {
      final last = _pitcherLastStartDay[sp.id];
      if (last == null) return true; // 未登板
      return (_currentDay - last) >= _minDaysBetweenStarts;
    }).toList();

    if (restEligible.isEmpty) {
      // 全員が中4日経っていない異常時 → 最も休んでいる SP
      final sorted = rotation.toList()..sort(_compareByJitteredLastStart());
      return sorted.first;
    }

    final fullyRecovered = restEligible
        .where((sp) =>
            (_pitcherFreshness[sp.id] ?? 100) >= _starterReadyThreshold)
        .toList();

    final pool =
        fullyRecovered.isNotEmpty ? fullyRecovered : restEligible;
    pool.sort(_compareByJitteredLastStart());
    return pool.first;
  }

  /// 先発スコアを最終登板日 + 能力ボーナス + ジッターで計算するコンパレータを返す。
  /// 値が小さい方が先頭に来る（より早く先発に立つ）。
  ///
  /// - 最終登板日: 大きいほど最近登板したので不利（順送り）
  /// - 能力ボーナス: 高エース（[0..1] スコア）ほど -1 までスコアを下げる → 優先
  /// - ジッター: [0, 2) の揺らぎでローテに自然なズレを発生させる
  ///
  /// 結果として：
  /// - 同じくらい休んでいる場合、能力が高い投手（エース）が選ばれやすい
  /// - 「エースは中4日でも投げる」「下位投手は中6日空ける」という現実の動きを再現
  /// - 大きく休養日が違う場合は揺らぎ無関係に休んでいる方が選ばれる（破綻しない）
  int Function(Player a, Player b) _compareByJitteredLastStart() {
    final scoreCache = <String, double>{};
    return (a, b) {
      final sa = _starterScore(a, scoreCache);
      final sb = _starterScore(b, scoreCache);
      final c = sa.compareTo(sb);
      if (c != 0) return c;
      final fa = _pitcherFreshness[a.id] ?? 100;
      final fb = _pitcherFreshness[b.id] ?? 100;
      return fb.compareTo(fa);
    };
  }

  double _starterScore(Player p, Map<String, double> cache) {
    return cache.putIfAbsent(p.id, () {
      final last = (_pitcherLastStartDay[p.id] ?? -1000).toDouble();
      final ace = _aceScore(p); // 0..1
      // ace ボーナスは [0, 1.5] のレンジで効かせる：
      // ジッター範囲 [0, 2) と組み合わさって、エース差が大きい場合は
      // 中4日や中6日の振り分けが「能力差」によりはっきり寄る。
      return last - ace * 1.5 + _rotationRandom.nextDouble() * 2;
    });
  }

  /// 先発候補の「エース度」を [0, 1] で返す。
  /// 球速・制球・ストレートの質・変化球の最高値の平均を使う簡易版。
  /// 既存の stamina パラメータは別途回復速度に使っているので、ここには含めない。
  double _aceScore(Player p) {
    final speed = ((p.averageSpeed ?? 145) - 130) / 25;
    final speedNorm = speed.clamp(0.0, 1.0);
    final controlNorm = (p.control ?? 5) / 10.0;
    final fastballNorm = (p.fastball ?? 5) / 10.0;
    final pitches = <int>[
      p.slider ?? 0,
      p.curve ?? 0,
      p.splitter ?? 0,
      p.changeup ?? 0,
    ];
    final bestPitch = pitches.reduce((a, b) => a > b ? a : b) / 10.0;
    return (speedNorm + controlNorm + fastballNorm + bestPitch) / 4.0;
  }

  /// 1試合分の Team を構築する：
  /// - players[0] を当日の先発 SP に差し替え
  /// - bullpen をフレッシュな RP 順に並び替え（疲労した RP は除外）
  ///
  /// ロール別の getter（team.closer / setupPitcher など）は bullpen 内を
  /// reliefRole で検索するため、疲労した投手はここで bullpen から外れることで
  /// 自動的に「当日不在」扱いになる（連投回避）。
  Team _withGameLineup(Team team, Player sp) {
    final newPlayers = team.players.isNotEmpty && team.players[0].id == sp.id
        ? team.players
        : [sp, ...team.players.skip(1)];
    return team.copyWith(
      players: newPlayers,
      bullpen: _availableBullpen(team),
    );
  }

  /// 投手のコンディション参照（UI 用）
  // pitcherLastStartDay は既存定義あり。pitcherFreshness は既存。
  // ここでは追加 API なし。

  /// 投手のコンディション参照（UI 用）
  int? pitcherFreshness(String pitcherId) => _pitcherFreshness[pitcherId];

  /// 投手の最終登板日参照（UI 用）
  int? pitcherLastStartDay(String pitcherId) =>
      _pitcherLastStartDay[pitcherId];
}

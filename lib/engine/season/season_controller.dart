import 'dart:math';

import '../generators/generators.dart';
import '../models/models.dart';
import '../offseason/offseason_plan.dart';
import '../offseason/player_aging.dart';
import '../offseason/team_rebuilder.dart';
import '../simulation/simulation.dart';
import 'batter_condition.dart';
import 'game_summary.dart';
import 'lineup_planner.dart';
import 'next_game_strategy.dart';
import 'player_season_stats.dart';
import 'recent_form.dart';
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
  Schedule _schedule;
  final String myTeamId;
  SeasonAggregator _aggregator;
  final GameSimulator _gameSimulator;

  /// 1チームあたりのシーズン試合数（30 / 90 / 150 を想定）。
  /// 開幕時に UI から選択され、`commitOffseason` で次シーズンへも明示的に
  /// 引き渡される（未指定の場合は前シーズンの値を継承）。
  int _gamesPerTeam;

  /// gameNumber → GameResult のマップ（未実行の試合はキーなし）
  final Map<int, GameResult> _results = {};

  int _currentDay = 0;

  /// シーズン番号（1-indexed）。新規シーズン作成で 1、`advanceToNextSeason` で +1。
  int _seasonYear = 1;

  /// Schedule を外部から参照する getter。シーズン跨ぎで差し替わるため非 final。
  Schedule get schedule => _schedule;

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

  /// 各打者の直近の打席結果。
  /// 当日のスタメン・打順決定で「調子」として参照する。
  /// 試合後に [_updateRecentForms] が更新する。
  final Map<String, RecentForm> _recentForms = {};

  /// 野手の調子（隠しパラメータ）。シミュレーションの能力に直接効く。
  /// 毎日朝に Markov 遷移で更新され、複数日にわたって持続する。
  /// シーズン跨ぎでリセットするので `late final` ではなく `late` にしてある。
  late BatterConditionTracker _batterConditions;

  /// 自チームの「次の試合」用の作戦。`null` ならオート編成。
  /// `advanceDay` で自チームが試合をした瞬間に消費（クリア）される。
  NextGameStrategy? _myStrategy;

  /// 新人選手生成用の長寿命ジェネレータ。シーズン跨ぎでも id・名前が衝突しないよう
  /// 各 Team 構築時に既存選手から復元される。
  late PlayerGenerator _playerGen;

  SeasonController({
    required this.teams,
    required Schedule schedule,
    required this.myTeamId,
    int gamesPerTeam = ScheduleGenerator.defaultGamesPerTeam,
    GameSimulator? gameSimulator,
    Random? random,
  })  : _schedule = schedule,
        _gamesPerTeam = gamesPerTeam,
        _aggregator = SeasonAggregator(teams),
        _gameSimulator = gameSimulator ?? GameSimulator(random: random),
        _rotationRandom = random ?? Random() {
    _batterConditions = BatterConditionTracker(random: random);
    _playerGen = _buildPlayerGen(teams, random);
    // 開幕時、SP・RP 全員フレッシュ（100）でスタート
    for (final team in teams) {
      for (final p in [...team.startingRotation, ...team.bullpen]) {
        _pitcherFreshness[p.id] = 100;
      }
    }
  }

  /// 既存選手の id 連番と名前セットから PlayerGenerator を再構築する。
  /// シーズン跨ぎで新人を追加する際に id・名前が重複しないようにするため。
  static PlayerGenerator _buildPlayerGen(
      List<Team> teams, Random? random) {
    final names = <String>{};
    int maxId = 0;
    for (final team in teams) {
      for (final p in [
        ...team.players,
        ...team.startingRotation,
        ...team.bullpen,
        ...team.bench,
      ]) {
        names.add(p.name);
        final id = p.id;
        if (id.startsWith('p_')) {
          final num = int.tryParse(id.substring(2));
          if (num != null && num > maxId) maxId = num;
        }
      }
    }
    return PlayerGenerator(
      random: random,
      idStart: maxId,
      usedNames: names,
    );
  }

  /// 6チームを自動生成して新しいシーズンを開始するファクトリ
  factory SeasonController.newSeason({
    Random? random,
    String myTeamId = 'team_phoenix',
    int gamesPerTeam = ScheduleGenerator.defaultGamesPerTeam,
  }) {
    final teams = TeamGenerator(random: random).generateLeague();
    final schedule = const ScheduleGenerator()
        .generateForGamesPerTeam(teams, gamesPerTeam);
    return SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: myTeamId,
      gamesPerTeam: gamesPerTeam,
      random: random,
    );
  }

  // ---- 状態の参照 ----
  int get currentDay => _currentDay;
  int get totalDays => schedule.totalDays;
  bool get isSeasonOver => _currentDay >= schedule.totalDays;
  int get seasonYear => _seasonYear;

  /// 1チームあたりの今シーズン試合数（30 / 90 / 150）。
  /// 翌シーズンの選択肢のデフォルト値や、UI 表示に使う。
  int get gamesPerTeam => _gamesPerTeam;
  Team get myTeam => teams.firstWhere((t) => t.id == myTeamId);
  Standings get standings => _aggregator.standings;
  Map<String, BatterSeasonStats> get batterStats => _aggregator.batterStats;
  Map<String, PitcherSeasonStats> get pitcherStats => _aggregator.pitcherStats;

  /// 次の試合用の自チーム作戦（null ならオート編成）
  NextGameStrategy? get myStrategy => _myStrategy;

  /// 次の試合用の作戦をセットする。
  /// 自動編成と異なるラインナップ・先発を使いたいときに UI から呼ぶ。
  /// 構築時に NextGameStrategy 自身がバリデーションする。
  void setMyStrategy(NextGameStrategy strategy) {
    _myStrategy = strategy;
    _notify();
  }

  /// 作戦をクリアしてオート編成に戻す。
  void clearMyStrategy() {
    if (_myStrategy == null) return;
    _myStrategy = null;
    _notify();
  }

  /// 自チームの「次の試合のオート編成」をシミュレートして返す（state は変えない）。
  /// 作戦画面の初期表示用。
  /// 投手はオートでは 9 番固定だが、ユーザーが作戦画面で他の打順に動かすことは可能
  /// （[NextGameStrategy] は投手位置を縛らない）。
  /// 投手は「コンディション高い順 → 背番号順」のシンプルなルールで選出する
  /// ([_pickFreshestStarter])。
  /// シーズン終了済み・自チームに試合がない日には null を返す。
  ({
    List<Player> lineup,
    Map<FieldPosition, Player> alignment,
  })? suggestedStrategyForMyTeam() {
    if (isSeasonOver) return null;
    final team = teams.firstWhere((t) => t.id == myTeamId);
    if (team.players.length < 9) return null;
    final sp = _pickFreshestStarter(team);
    final result = LineupPlanner(
      team: team,
      forms: _recentForms,
      todaysPitcher: sp,
    ).buildLineup();
    return (
      lineup: result.lineup,
      alignment: result.alignment,
    );
  }

  /// 自チームの次の予定試合（明日の試合）。シーズン終了時は null。
  ScheduledGame? get nextScheduledGameForMyTeam {
    if (isSeasonOver) return null;
    final nextDay = _currentDay + 1;
    for (final sg in schedule.gamesOnDay(nextDay)) {
      if (sg.homeTeam.id == myTeamId || sg.awayTeam.id == myTeamId) {
        return sg;
      }
    }
    return null;
  }

  /// id から最新の Player を引く。
  /// 編集後は teams 内の各リスト・統計に反映済みなので、まずは teams を見れば足りる。
  /// 過去の試合 (`GameResult`) に登場する Player 参照は古いままだが、
  /// 過去成績・過去試合は再シミュレートしないので問題にならない。
  Player? findPlayerById(String id) {
    for (final team in teams) {
      for (final p in [
        ...team.players,
        ...team.startingRotation,
        ...team.bullpen,
        ...team.bench,
      ]) {
        if (p.id == id) return p;
      }
    }
    return null;
  }

  /// 選手の能力を編集して全参照を差し替える（編集機能用）。
  /// 同 id の Player を:
  /// - 各 Team の `players` / `startingRotation` / `bullpen` / `bench` /
  ///   `defenseAlignment` 内で置換（**in-place** で書き換え）
  /// - `batterStats[id].player` / `pitcherStats[id].player` も更新
  /// - 累積成績カウンタは維持
  ///
  /// **なぜ in-place か:**
  /// `Schedule` / `ScheduledGame` はシーズン開始時に作られ、Team のオブジェクト
  /// 参照を保持している。Team を新しく作り直して `teams[i]` を差し替えると、
  /// `ScheduledGame.homeTeam` などは古い Team を指したままになり、
  /// 編集後の試合シミュレートに新しい能力値が反映されない。
  /// 各 Team の内部リストを in-place で書き換えれば、
  /// 同じ Team を参照しているスケジュール・統計・標準順位表すべてに
  /// 自動で反映される。
  ///
  /// 過去の `GameResult` 内の Player 参照は古いまま（履歴として保存）。
  void updatePlayer(Player updated) {
    for (final team in teams) {
      _replacePlayerInTeamInPlace(team, updated);
    }
    final bs = _aggregator.batterStats[updated.id];
    if (bs != null) bs.player = updated;
    final ps = _aggregator.pitcherStats[updated.id];
    if (ps != null) ps.player = updated;
    _notify();
  }

  /// チームの基本情報（名前 / 略称 / カラー）を編集する。
  /// Player 編集と同じ理由で **in-place** で書き換えるため、
  /// `ScheduledGame` や統計が保持している Team 参照すべてに反映される。
  /// `null` を渡したフィールドは変更しない。
  void updateTeam(
    String teamId, {
    String? name,
    String? shortName,
    int? primaryColorValue,
  }) {
    final t = teams.firstWhere((x) => x.id == teamId);
    if (name != null) t.name = name;
    if (shortName != null) t.shortName = shortName;
    if (primaryColorValue != null) t.primaryColorValue = primaryColorValue;
    _notify();
  }

  void _replacePlayerInTeamInPlace(Team t, Player updated) {
    void swap(List<Player> list) {
      for (int i = 0; i < list.length; i++) {
        if (list[i].id == updated.id) list[i] = updated;
      }
    }

    swap(t.players);
    swap(t.startingRotation);
    swap(t.bullpen);
    swap(t.bench);

    final align = t.defenseAlignment;
    if (align != null) {
      final keys = <FieldPosition>[];
      align.forEach((k, v) {
        if (v.id == updated.id) keys.add(k);
      });
      for (final k in keys) {
        align[k] = updated;
      }
    }
  }

  /// 指定日の予定試合一覧
  List<ScheduledGame> scheduledGamesOnDay(int day) =>
      schedule.gamesOnDay(day);

  /// 指定 gameNumber の結果（未実行なら null）
  GameResult? resultFor(int gameNumber) => _results[gameNumber];

  /// 指定 gameNumber のサマリー情報（勝利投手・敗戦投手・セーブ・本塁打通算番号）
  /// 各投手にはその試合終了時点での通算 W/L/S 成績が付く。
  /// スコアタブ等で表示する用途。試合が未実行なら GameSummary.empty。
  GameSummary gameSummaryFor(int gameNumber) {
    final game = _results[gameNumber];
    if (game == null) return GameSummary.empty;

    // 試合順序で:
    //   - 投手別の通算 W/L/S
    //   - 打者別の通算 HR 数
    // を累積し、対象試合の時点での値を取得する。
    final winsByPitcher = <String, int>{};
    final lossesByPitcher = <String, int>{};
    final savesByPitcher = <String, int>{};
    final hrCounts = <String, int>{};
    final homeRuns = <HomeRunRecord>[];

    ({Player? winningPitcher, Player? losingPitcher, Player? savingPitcher})?
        targetDecisions;

    for (final sg in schedule.games) {
      if (sg.gameNumber > gameNumber) break;
      final g = _results[sg.gameNumber];
      if (g == null) continue;

      // 決定投手を集計
      final d = _aggregator.resolveGameDecisions(g);
      if (d.winningPitcher != null) {
        winsByPitcher[d.winningPitcher!.id] =
            (winsByPitcher[d.winningPitcher!.id] ?? 0) + 1;
      }
      if (d.losingPitcher != null) {
        lossesByPitcher[d.losingPitcher!.id] =
            (lossesByPitcher[d.losingPitcher!.id] ?? 0) + 1;
      }
      if (d.savingPitcher != null) {
        savesByPitcher[d.savingPitcher!.id] =
            (savesByPitcher[d.savingPitcher!.id] ?? 0) + 1;
      }

      // 本塁打を集計（対象試合のみ HomeRunRecord に追加）
      for (final half in g.halfInnings) {
        for (final ab in half.atBats) {
          if (ab.result != AtBatResultType.homeRun) continue;
          if (ab.isIncomplete) continue;
          hrCounts[ab.batter.id] = (hrCounts[ab.batter.id] ?? 0) + 1;
          if (sg.gameNumber == gameNumber) {
            homeRuns.add(HomeRunRecord(
              batter: ab.batter,
              seasonNumber: hrCounts[ab.batter.id]!,
              isAway: ab.isTop,
              inning: ab.inning,
            ));
          }
        }
      }

      if (sg.gameNumber == gameNumber) targetDecisions = d;
    }

    PitcherDecisionRecord? recordFor(Player? p) {
      if (p == null) return null;
      return PitcherDecisionRecord(
        pitcher: p,
        wins: winsByPitcher[p.id] ?? 0,
        losses: lossesByPitcher[p.id] ?? 0,
        saves: savesByPitcher[p.id] ?? 0,
      );
    }

    return GameSummary(
      winning: recordFor(targetDecisions?.winningPitcher),
      losing: recordFor(targetDecisions?.losingPitcher),
      saving: recordFor(targetDecisions?.savingPitcher),
      homeRuns: homeRuns,
    );
  }

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

    // 全選手の野手調子を Markov 遷移で更新（試合前に確定）
    _advanceBatterConditions();

    final games = scheduledGamesOnDay(_currentDay);
    final results = <GameResult>[];
    for (final sg in games) {
      // 自チームの試合で strategy が指定されていれば、それを採用してオート編成を上書き。
      // strategy は **試合後も保持** し、次の試合でも同じ打順 + 守備配置を再利用する。
      final useStrategyForHome =
          sg.homeTeam.id == myTeamId && _myStrategy != null;
      final useStrategyForAway =
          sg.awayTeam.id == myTeamId && _myStrategy != null;

      final homeSP = useStrategyForHome
          ? _myStrategy!.startingPitcher
          : _selectStarter(sg.homeTeam);
      final awaySP = useStrategyForAway
          ? _myStrategy!.startingPitcher
          : _selectStarter(sg.awayTeam);

      final homeForGame = useStrategyForHome
          ? _applyMyStrategy(sg.homeTeam, _myStrategy!)
          : _withGameLineup(sg.homeTeam, homeSP);
      final awayForGame = useStrategyForAway
          ? _applyMyStrategy(sg.awayTeam, _myStrategy!)
          : _withGameLineup(sg.awayTeam, awaySP);

      final result = _gameSimulator.simulate(
        homeForGame,
        awayForGame,
        batterConditionModifiers:
            _conditionMapForGame(homeForGame, awayForGame),
      );
      _results[sg.gameNumber] = result;
      _aggregator.recordGame(result);

      // 球数に応じてコンディションを消費（先発・リリーフそれぞれ）
      _depleteStarterFreshness(result);
      _depleteRelieverFreshness(result);

      // 各打者の直近成績を更新（次試合の打順決定で使う）
      _updateRecentForms(result);

      results.add(result);
    }

    // 試合終了後、strategy が残っていれば「次の試合用」の SP に差し替えておく。
    // 今日の試合で使った SP は疲労しているので、明日のために自動で別の候補を入れておく
    // （これがないと、翌日の作戦画面で今日の疲労 SP がそのまま表示される）。
    // 自動選出ルール: 先発ローテの中で「疲労度が小さい（コンディション高い）順」、
    //                同値なら背番号順。シンプル・予測可能で連投も自然に回避できる。
    // ユーザーが明日の作戦画面で別 SP を選ぶことも自由にできる。
    if (_myStrategy != null && !isSeasonOver) {
      final myTeam = teams.firstWhere((t) => t.id == myTeamId);
      final tomorrowsSP = _pickFreshestStarter(myTeam);
      _myStrategy =
          _withSPReplacedInStrategy(_myStrategy!, tomorrowsSP);
    }

    _notify();
    return results;
  }

  /// 先発ローテの中で「コンディション高い順 → 背番号低い順」で先頭を返す。
  /// 自チームの作戦自動編成で使う。シーズン序盤は全員 100 で揃うので
  /// 背番号最小から順に登板し、その後はコンディション差で自然に回るようになる。
  Player _pickFreshestStarter(Team team) {
    final rotation = team.startingRotation;
    if (rotation.isEmpty) return team.pitcher;
    final sorted = rotation.toList()
      ..sort((a, b) {
        final fa = _pitcherFreshness[a.id] ?? 100;
        final fb = _pitcherFreshness[b.id] ?? 100;
        final c = fb.compareTo(fa); // freshness 高い順
        if (c != 0) return c;
        return a.number.compareTo(b.number); // 同値なら背番号低い順
      });
    return sorted.first;
  }

  /// strategy 内の SP を `newSP` に置き換えた新しい [NextGameStrategy] を返す。
  /// 既に同じ SP なら同じインスタンスを返す。
  /// `lineup` 内の旧 SP の位置（打順位置）はそのまま、新 SP に差し替える。
  NextGameStrategy _withSPReplacedInStrategy(
      NextGameStrategy old, Player newSP) {
    if (old.startingPitcher.id == newSP.id) return old;
    final newLineup =
        old.lineup.map((p) => p.isPitcher ? newSP : p).toList();
    final newAlignment = <FieldPosition, Player>{
      ...old.alignment,
      FieldPosition.pitcher: newSP,
    };
    return NextGameStrategy(lineup: newLineup, alignment: newAlignment);
  }

  /// 残り全日を一括シミュレート（デバッグ用）
  /// 内部で advanceDay を呼ぶたびに通知が走るため、ここでは追加通知しない
  void advanceAll() {
    while (!isSeasonOver) {
      advanceDay();
    }
  }

  /// 自チームのオフシーズン編成候補を生成する（チームの状態は変更しない）。
  ///
  /// シーズン終了後に UI から呼んで、ユーザーに引退候補・新人候補を提示するための
  /// データを取得する。`commitOffseason(selection)` を呼ぶまでチームは変更されない。
  ///
  /// 同じセッション中に複数回呼ぶと、その度に新しい新人候補が生成される
  /// （前回の候補は破棄される）。アプリ再起動後の再呼出も、別の新人が生成される
  /// （未確定の候補はディスクに保存しない）。
  OffseasonPlan prepareOffseason() {
    if (!isSeasonOver) {
      throw StateError('シーズン進行中は prepareOffseason を呼べません');
    }
    return TeamRebuilder(
      playerGen: _playerGen,
      previousBatterStats: _aggregator.batterStats,
      random: _rotationRandom,
    ).buildOffseasonPlan(myTeam);
  }

  /// シーズン終了状態から次シーズンへ進む（Day 0 / 新シーズンに準備）。
  ///
  /// オフシーズン処理の順序:
  ///   1. 全選手の `age + 1` と能力変動（[PlayerAging] による年齢曲線）
  ///   2. CPU チームの引退・新人加入・スタメン再編成・投手ロール再編
  ///   3. 自チーム: [selection] と [plan] が両方与えられた場合のみ、
  ///      ユーザー選択に従って引退・新人加入・スタメン再編成を実行
  ///      （未指定の場合は自チームは無編集で次シーズンへ）
  ///   4. シーズン番号 +1、Schedule・統計・順位表のリセット
  ///   5. _pitcherFreshness を全員 100 にリセット
  ///   6. _batterConditions も新規作成、_currentDay = 0
  ///
  /// [gamesPerTeam] を渡すとそのシーズンの試合数を更新する（30 / 90 / 150）。
  /// 省略時は前シーズンの値を継承する。
  ///
  /// 呼び出し条件: `isSeasonOver` が true。シーズン進行中に呼ぶと [StateError]。
  void commitOffseason({
    OffseasonPlan? plan,
    OffseasonSelection? selection,
    int? gamesPerTeam,
  }) {
    if (!isSeasonOver) {
      throw StateError('シーズン進行中は commitOffseason を呼べません');
    }
    if ((plan == null) != (selection == null)) {
      throw ArgumentError('plan と selection は両方指定するか、両方省略してください');
    }

    // 自チーム再編で参照する「前年スタメン」を加齢前にスナップショット。
    // 加齢で player object 自体は差し替わるが id は不変なので、id を保存しておけば
    // 加齢後も継続性ボーナスを正しく付与できる。
    final myTeamPreviousStarterIds = <String>{};
    if (selection != null) {
      myTeamPreviousStarterIds
          .addAll(myTeam.players.take(8).map((p) => p.id));
    }

    // 1. 加齢 + 能力変動。各 Team 内の players/rotation/bullpen/bench/alignment を
    //    in-place で書き換え（_replacePlayerInTeamInPlace 経由でスケジュール参照も追従）。
    //    ※ updatePlayer は notify を発火させるのでループ向きでない。直接 in-place 置換。
    final aging = PlayerAging(random: _rotationRandom);
    final seenIds = <String>{};
    for (final team in teams) {
      for (final p in [
        ...team.players,
        ...team.startingRotation,
        ...team.bullpen,
        ...team.bench,
      ]) {
        if (!seenIds.add(p.id)) continue;
        final updated = aging.ageOneYear(p);
        // 全 Team 横断で in-place 置換（同じ Player 参照を持つ場所すべてを更新）
        for (final t in teams) {
          _replacePlayerInTeamInPlace(t, updated);
        }
      }
    }

    // 2. CPU チームの引退・新人加入・スタメン再編成・投手ロール再編。
    //    再編成時に前シーズンの成績（OPS）をスコア要素として参照する。
    final rebuilder = TeamRebuilder(
      playerGen: _playerGen,
      previousBatterStats: _aggregator.batterStats,
      random: _rotationRandom,
    );
    rebuilder.rebuildCpuTeams(teams, myTeamId);

    // 3. 自チーム: ユーザー選択を反映（プランが渡されたときのみ）
    if (plan != null && selection != null) {
      rebuilder.applyUserSelection(
        myTeam,
        plan,
        selection,
        myTeamPreviousStarterIds,
      );
    }

    // 4〜6.
    _seasonYear++;
    if (gamesPerTeam != null) {
      _gamesPerTeam = gamesPerTeam;
    }
    _schedule = const ScheduleGenerator()
        .generateForGamesPerTeam(teams, _gamesPerTeam);
    _aggregator = SeasonAggregator(teams);
    _results.clear();
    _recentForms.clear();
    _myStrategy = null;
    _pitcherLastStartDay.clear();
    _pitcherFreshness.clear();
    for (final team in teams) {
      for (final p in [...team.startingRotation, ...team.bullpen]) {
        _pitcherFreshness[p.id] = 100;
      }
    }
    _batterConditions = BatterConditionTracker(random: _rotationRandom);
    _currentDay = 0;

    _notify();
  }

  /// 自チームの編成変更なしで次シーズンへ進む（後方互換用エイリアス）。
  /// テストや、UI で「自チームは無編集」を選んだケースから呼ぶ。
  void advanceToNextSeason() {
    commitOffseason();
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
  /// 1. ローテが空なら従来通り players[8] を使用（後方互換）
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
  /// - LineupPlanner で当日の打順 (1〜8番) と守備配置を決定
  /// - 9番は当日の先発 SP
  /// - bullpen をフレッシュな RP 順に並び替え（疲労した RP は除外）
  /// - スワップで控えに回ったスタメン野手は bench に移動
  ///
  /// ロール別の getter（team.closer / setupPitcher など）は bullpen 内を
  /// reliefRole で検索するため、疲労した投手はここで bullpen から外れることで
  /// 自動的に「当日不在」扱いになる（連投回避）。
  Team _withGameLineup(Team team, Player sp) {
    // 正規化チームの players[0..7] が崩れている場合（テストなど）は最低限の投手差し替えだけ行う
    if (team.players.length < 9) {
      final newPlayers = team.players.length >= 9 && team.players[8].id == sp.id
          ? team.players
          : [...team.players.take(8), sp];
      return team.copyWith(
        players: newPlayers,
        bullpen: _availableBullpen(team),
      );
    }

    final planner = LineupPlanner(
      team: team,
      forms: _recentForms,
      todaysPitcher: sp,
    );
    final result = planner.buildLineup();

    // 当日の bench を再構成: 元のベンチから「スタメン入りした選手」を除き、
    // 「スタメンから外された選手」を加える
    final lineupIds = result.lineup.map((p) => p.id).toSet();
    final newBench = <Player>[];
    for (final p in team.bench) {
      if (!lineupIds.contains(p.id)) newBench.add(p);
    }
    for (final p in team.players.take(8)) {
      if (!lineupIds.contains(p.id)) newBench.add(p);
    }

    return team.copyWith(
      players: result.lineup,
      defenseAlignment: result.alignment,
      bench: newBench,
      bullpen: _availableBullpen(team),
    );
  }

  /// ユーザーが指定した作戦（NextGameStrategy）から1試合分の Team を構築する。
  /// `_withGameLineup` のオート版とほぼ同じだが、打順・守備配置・先発はユーザー指定を採用。
  Team _applyMyStrategy(Team team, NextGameStrategy strategy) {
    final lineupIds = strategy.fullLineup.map((p) => p.id).toSet();
    final newBench = <Player>[];
    for (final p in team.bench) {
      if (!lineupIds.contains(p.id)) newBench.add(p);
    }
    for (final p in team.players.take(8)) {
      if (!lineupIds.contains(p.id)) newBench.add(p);
    }
    return team.copyWith(
      players: strategy.fullLineup,
      defenseAlignment: Map.of(strategy.alignment),
      bench: newBench,
      bullpen: _availableBullpen(team),
    );
  }

  /// 試合結果から各打者の直近打席を [_recentForms] に取り込む
  void _updateRecentForms(GameResult game) {
    for (final half in game.halfInnings) {
      for (final ab in half.atBats) {
        final form =
            _recentForms.putIfAbsent(ab.batter.id, () => RecentForm());
        form.recordAtBat(ab);
      }
    }
  }

  /// 全リーグの選手について野手調子を Markov 遷移で1日進める
  void _advanceBatterConditions() {
    final ids = <String>{};
    for (final team in teams) {
      for (final p in [...team.players, ...team.bench]) {
        ids.add(p.id);
      }
    }
    _batterConditions.advanceDay(ids);
  }

  /// 1試合用の player.id → 調子補正値マップを構築する
  Map<String, int> _conditionMapForGame(Team home, Team away) {
    final mods = <String, int>{};
    for (final p in [
      ...home.players,
      ...home.bench,
      ...away.players,
      ...away.bench,
    ]) {
      final m = _batterConditions.stateOf(p.id);
      if (m != 0) mods[p.id] = m;
    }
    return mods;
  }

  /// 指定選手の現在の野手調子（-1/0/+1）。UI からの参照用。
  int batterConditionState(String playerId) =>
      _batterConditions.stateOf(playerId);

  /// 投手のコンディション（0〜100、100 = 完全フレッシュ）。
  /// 試合の球数で消費し、1 日経過で `stamina` 依存の量だけ回復する。
  /// 作戦画面で「連投できそうか」の判断材料として表示する。
  /// 未登録の投手は 100 を返す（開幕直後の挙動と一致）。
  int pitcherFreshness(String pitcherId) =>
      _pitcherFreshness[pitcherId] ?? 100;

  /// 投手の最終登板日参照（UI 用）
  int? pitcherLastStartDay(String pitcherId) =>
      _pitcherLastStartDay[pitcherId];

  // ---- 永続化 ----
  // フォーマットバージョン。スキーマ変更時に古いセーブを弾くために使う。
  static const int saveFormatVersion = 1;

  /// 全状態を JSON-serializable な Map にまとめる。
  /// Player は teams 内に登場するすべての一意の選手を `players` セクションに集約し、
  /// 他の場所では id 参照のみ。
  Map<String, dynamic> toJson() {
    // 全 Player を id 単位で集約（teams から重複なく抽出）
    final allPlayers = <String, Player>{};
    for (final team in teams) {
      for (final p in [
        ...team.players,
        ...team.startingRotation,
        ...team.bullpen,
        ...team.bench,
      ]) {
        allPlayers[p.id] = p;
      }
    }

    return {
      'version': saveFormatVersion,
      'myTeamId': myTeamId,
      'seasonYear': _seasonYear,
      'gamesPerTeam': _gamesPerTeam,
      'currentDay': _currentDay,
      'players': {
        for (final entry in allPlayers.entries)
          entry.key: entry.value.toJson(),
      },
      'teams': [for (final t in teams) t.toJson()],
      'schedule': schedule.toJson(),
      'results': {
        for (final entry in _results.entries)
          entry.key.toString(): entry.value.toJson(),
      },
      'standings': _aggregator.standings.toJson(),
      'batterStats': {
        for (final entry in _aggregator.batterStats.entries)
          entry.key: entry.value.toJson(),
      },
      'pitcherStats': {
        for (final entry in _aggregator.pitcherStats.entries)
          entry.key: entry.value.toJson(),
      },
      'pitcherFreshness': _pitcherFreshness,
      'pitcherLastStartDay': _pitcherLastStartDay,
      'recentForms': {
        for (final entry in _recentForms.entries)
          entry.key: entry.value.toJson(),
      },
      'batterConditions': _batterConditions.exportStates(),
      if (_myStrategy != null) 'myStrategy': _myStrategy!.toJson(),
    };
  }

  /// JSON から SeasonController を復元する。
  /// バージョンが合わない場合は [FormatException] を投げる。
  factory SeasonController.fromJson(
    Map<String, dynamic> json, {
    Random? random,
  }) {
    final version = json['version'] as int? ?? 0;
    if (version != saveFormatVersion) {
      throw FormatException(
          '保存形式のバージョンが違います (期待: $saveFormatVersion, 実際: $version)');
    }

    // 1. Player registry
    final playerById = <String, Player>{};
    for (final entry in (json['players'] as Map).entries) {
      playerById[entry.key as String] =
          Player.fromJson(entry.value as Map<String, dynamic>);
    }

    // 2. Teams
    final teams = <Team>[
      for (final t in (json['teams'] as List))
        Team.fromJson(t as Map<String, dynamic>, playerById),
    ];
    final teamById = {for (final t in teams) t.id: t};

    // 3. Schedule
    final schedule = Schedule.fromJson(
        json['schedule'] as Map<String, dynamic>, teamById);

    // 4. Construct controller (aggregator は空で初期化される)
    // 旧フォーマット (v1 with gamesPerTeam 未保存) では 30 試合扱いで復元する。
    final gamesPerTeam = json['gamesPerTeam'] as int? ??
        ScheduleGenerator.defaultGamesPerTeam;
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: json['myTeamId'] as String,
      gamesPerTeam: gamesPerTeam,
      random: random,
    );

    // 5. 内部状態を直接復元
    controller._currentDay = json['currentDay'] as int? ?? 0;
    controller._seasonYear = json['seasonYear'] as int? ?? 1;

    // 5a. 試合結果
    controller._results.clear();
    final resultsJson = json['results'] as Map?;
    if (resultsJson != null) {
      for (final entry in resultsJson.entries) {
        final num = int.parse(entry.key as String);
        controller._results[num] = GameResult.fromJson(
            entry.value as Map<String, dynamic>, playerById);
      }
    }

    // 5b. Standings (aggregator のリストを書き換え)
    final st = controller._aggregator.standings;
    st.records.clear();
    for (final r in (json['standings']['records'] as List)) {
      st.records.add(
          TeamRecord.fromJson(r as Map<String, dynamic>, teamById));
    }

    // 5c. BatterStats / PitcherStats
    final bs = controller._aggregator.batterStats;
    bs.clear();
    for (final entry in (json['batterStats'] as Map).entries) {
      bs[entry.key as String] = BatterSeasonStats.fromJson(
          entry.value as Map<String, dynamic>, playerById, teamById);
    }
    final ps = controller._aggregator.pitcherStats;
    ps.clear();
    for (final entry in (json['pitcherStats'] as Map).entries) {
      ps[entry.key as String] = PitcherSeasonStats.fromJson(
          entry.value as Map<String, dynamic>, playerById, teamById);
    }

    // 5d. Pitcher freshness / last start day
    controller._pitcherFreshness.clear();
    for (final e in (json['pitcherFreshness'] as Map? ?? {}).entries) {
      controller._pitcherFreshness[e.key as String] = e.value as int;
    }
    controller._pitcherLastStartDay.clear();
    for (final e in (json['pitcherLastStartDay'] as Map? ?? {}).entries) {
      controller._pitcherLastStartDay[e.key as String] = e.value as int;
    }

    // 5e. RecentForms
    controller._recentForms.clear();
    for (final e in (json['recentForms'] as Map? ?? {}).entries) {
      controller._recentForms[e.key as String] =
          RecentForm.fromJson(e.value as Map<String, dynamic>);
    }

    // 5f. BatterConditions
    final bcJson = json['batterConditions'] as Map? ?? {};
    controller._batterConditions.importStates({
      for (final e in bcJson.entries) e.key as String: e.value as int,
    });

    // 5g. MyStrategy
    final ms = json['myStrategy'] as Map<String, dynamic>?;
    controller._myStrategy =
        ms == null ? null : NextGameStrategy.fromJson(ms, playerById);

    return controller;
  }
}

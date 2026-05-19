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

  /// オフシーズンの「時の流れ」を有効にするか（デフォルト true）。
  ///
  /// true: 次シーズン移行時に加齢・能力変動・引退・新人加入を実行（現状の挙動）
  /// false: 加齢も入替もスキップし、前シーズンと同じ選手・同じパラメータで開始
  ///        （手動編集による変更は従来通り反映される）
  bool _offseasonProgressionEnabled;

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

  // ---- 投手の登板疲労（試合間） ----
  // 各先発投手のコンディション（0-100）。試合で消費・1日経過で回復する。
  // pitcher.id をキーに保持。
  final Map<String, int> _pitcherFreshness = {};

  // 各投手の最終「先発」登板日。CPU のローテ周期判定（_selectStarter）に使う。
  // 未登板は entry なしで処理。
  final Map<String, int> _pitcherLastStartDay = {};

  // 各投手の最終「登板」日（先発・救援問わず）。先発指定の登板間隔ゲート
  // （canStartNextGame）に使う。救援で投げ続けている投手は間隔が空かず先発に
  // できない／ベンチ入りから外して休ませた投手は先発にできる、を成立させる。
  final Map<String, int> _pitcherLastAppearanceDay = {};

  // 完投 1試合 ≒ 120球で full depletion (-100)
  static const double _completeGamePitches = 120;
  // 中5日（6日空ける）以上空いていない投手は原則先発しない。
  // 先発6人ロスターを 6 日周期で回す前提（ROSTER_EXPANSION_PLAN.md）。
  static const int _minDaysBetweenStarts = 6;
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

  // ---- 当日ベンチ入り（40人ロスター → 26人）----
  // 各チームは 40 人ロスター（投手18 / 野手22）を持つが、1 試合に出られるのは
  // 当日ベンチ入りした 26 人だけ。内訳は 投手9（当日先発1 + 救援8）/ 野手17
  // （主力8 + 控え9）。主力野手8と先発ローテ6は常時候補で、ここで絞るのは
  // 控え野手と救援。
  static const int _activeBenchSize = 9; // 当日ベンチ入りする控え野手の人数
  static const int _activeBullpenSize = 8; // 当日ベンチ入りする救援投手の人数
  // CPU 運用の自然な揺らぎ: 控え野手・救援それぞれで、1 チーム 1 日あたり
  // 「能力下位アクティブ ↔ 非アクティブ」が 1 組入れ替わる確率。
  static const double _activeRosterSwapChance = 0.12;

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
    bool offseasonProgressionEnabled = true,
    GameSimulator? gameSimulator,
    Random? random,
  })  : _schedule = schedule,
        _gamesPerTeam = gamesPerTeam,
        _offseasonProgressionEnabled = offseasonProgressionEnabled,
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
    bool offseasonProgressionEnabled = true,
  }) {
    final teams = TeamGenerator(random: random).generateLeague();
    final schedule = const ScheduleGenerator()
        .generateForGamesPerTeam(teams, gamesPerTeam);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: myTeamId,
      gamesPerTeam: gamesPerTeam,
      offseasonProgressionEnabled: offseasonProgressionEnabled,
      random: random,
    );
    // 自チームの投手ロールは推測ゲームの一部としてユーザーが試合結果から決める。
    // 開幕時は能力で抑え等が割り当てられた状態にせず、中立な初期ロール
    // （生成時の先発6人→「先発」、救援12人→「中継ぎ」）で始める。
    // 先発/中継ぎの区分も以降ユーザーが自由に変えられる（先発・ベンチ入りとも
    // 全18投手から選択）。CPU 5 球団は TeamGenerator のロールのまま
    // （対戦相手の偵察は推測ゲームの一部）。
    final my = controller.myTeam;
    for (final p in [...my.startingRotation]) {
      if (p.pitcherRole != PitcherRole.starter) {
        controller.updatePlayer(p.withPitcherRole(PitcherRole.starter));
      }
    }
    for (final p in [...my.bullpen]) {
      if (p.pitcherRole != PitcherRole.middle) {
        controller.updatePlayer(p.withPitcherRole(PitcherRole.middle));
      }
    }
    return controller;
  }

  // ---- 状態の参照 ----
  int get currentDay => _currentDay;
  int get totalDays => schedule.totalDays;
  bool get isSeasonOver => _currentDay >= schedule.totalDays;
  int get seasonYear => _seasonYear;

  /// 1チームあたりの今シーズン試合数（30 / 90 / 150）。
  /// 翌シーズンの選択肢のデフォルト値や、UI 表示に使う。
  int get gamesPerTeam => _gamesPerTeam;

  /// オフシーズン進行（加齢・引退・新人加入）の ON/OFF。
  /// false の間に [commitOffseason] を呼ぶと、選手はそのままで翌シーズンへ進む。
  bool get offseasonProgressionEnabled => _offseasonProgressionEnabled;

  /// オフシーズン進行 ON/OFF を切り替える。
  /// 設定画面のトグルから呼び出す。AutoSaver が拾えるよう [_notify] を発火する。
  set offseasonProgressionEnabled(bool value) {
    if (_offseasonProgressionEnabled == value) return;
    _offseasonProgressionEnabled = value;
    _notify();
  }

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

  /// 自チームの「次の試合のオート編成」を [NextGameStrategy] として返す
  /// （state は変えない）。作戦画面の初期表示・編集の土台に使う。
  ///
  /// 打順・守備配置に加え、当日ベンチ入り（控え野手 [NextGameStrategy.activeBench] /
  /// 救援 [NextGameStrategy.activeBullpen]）も埋めた完全な編成を返す。
  /// すべて中立（能力序列を出さない）— 推測ゲームの最適解バレを避けるため
  /// （SPEC §コンセプト）。ユーザーが作戦画面で観察に基づき組み替える。
  ///
  /// - 先発: 全18投手から、登板間隔（中5日）の空いた最も背番号の若い投手
  /// - ベンチ入り救援: 先発を除く投手から背番号順で8人
  /// - 打順・守備: 背番号順の中立編成（[_withGameLineup] neutralOrder）
  ///
  /// シーズン終了済み・自チームの選手が9人未満の異常時には null を返す。
  NextGameStrategy? suggestedStrategyForMyTeam() {
    if (isSeasonOver) return null;
    final team = teams.firstWhere((t) => t.id == myTeamId);
    if (team.players.length < 9) return null;
    // 先発: 全18投手（先発ローテ + 救援）から、登板間隔の空いた背番号最小の投手。
    final allPitchers = <Player>[
      ...team.startingRotation,
      ...team.bullpen,
    ]..sort((a, b) => a.number.compareTo(b.number));
    final sp = allPitchers.firstWhere(
      (p) => canStartNextGame(p.id),
      orElse: () => allPitchers.first,
    );
    // ベンチ入り救援: 先発を除く投手から背番号順で8人。
    final activeBullpen = [
      for (final p in allPitchers)
        if (p.id != sp.id) p,
    ].take(_activeBullpenSize).toList();
    // 野手側は中立選定 + 中立打順。
    final active = _selectActiveRoster(team, neutral: true);
    final game = _withGameLineup(active, sp, neutralOrder: true);
    return NextGameStrategy(
      lineup: game.players,
      alignment: game.defenseAlignment!,
      activeBench: game.bench,
      activeBullpen: activeBullpen,
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
    // 保存済みの作戦（NextGameStrategy）内の Player 参照も差し替える。
    // strategy の lineup / alignment は Team とは別に Player を保持しており、
    // 自チームの試合は `_applyMyStrategy` が `strategy.fullLineup` から編成する。
    // ここを差し替えないと、編集した選手が自チームの試合で旧能力のまま
    // シミュレートされる（UI には新能力が出るのに成績に反映されない）。
    final strategy = _myStrategy;
    if (strategy != null) {
      _myStrategy = _replacePlayerInStrategy(strategy, updated);
    }
    _notify();
  }

  /// 救援投手のロールを変更する（永続）。作戦画面のベンチ入りタブから呼ぶ。
  ///
  /// 自チームの救援ロールは「試合結果から能力を推測して起用を決める」推測ゲームの
  /// 一部なので、エンジンは自動で割り当てない（開幕時は全員中継ぎ）。ユーザーが
  /// ここで決めたロールは書き換えるまで保持され、オフシーズンでも自動再編しない。
  void setPitcherRole(String pitcherId, PitcherRole role) {
    final p = findPlayerById(pitcherId);
    if (p == null || !p.isPitcher || p.pitcherRole == role) return;
    updatePlayer(p.withPitcherRole(role));
  }

  /// [strategy] 内の同 id の Player を [updated] に差し替えた新しい
  /// [NextGameStrategy] を返す。該当選手がいなければ [strategy] をそのまま返す。
  NextGameStrategy _replacePlayerInStrategy(
      NextGameStrategy strategy, Player updated) {
    Player swap(Player p) => p.id == updated.id ? updated : p;
    final inStrategy = strategy.lineup.any((p) => p.id == updated.id) ||
        strategy.activeBench.any((p) => p.id == updated.id) ||
        strategy.activeBullpen.any((p) => p.id == updated.id);
    if (!inStrategy) return strategy;
    return NextGameStrategy(
      lineup: [for (final p in strategy.lineup) swap(p)],
      alignment: {
        for (final e in strategy.alignment.entries) e.key: swap(e.value),
      },
      activeBench: [for (final p in strategy.activeBench) swap(p)],
      activeBullpen: [for (final p in strategy.activeBullpen) swap(p)],
    );
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

      // 自チームに作戦指定があればそれを採用（先発・ベンチ入りもユーザー指定）。
      // オートの場合は 40 人ロスター → 当日ベンチ入り 26 人に絞って自動編成。
      final homeForGame = useStrategyForHome
          ? _applyMyStrategy(sg.homeTeam, _myStrategy!)
          : _buildAutoGameTeam(sg.homeTeam);
      final awayForGame = useStrategyForAway
          ? _applyMyStrategy(sg.awayTeam, _myStrategy!)
          : _buildAutoGameTeam(sg.awayTeam);

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
    // ユーザーが明日の作戦画面で別 SP を選ぶことも自由にできる。
    if (_myStrategy != null && !isSeasonOver) {
      final myTeam = teams.firstWhere((t) => t.id == myTeamId);
      final tomorrowsSP = _pickNextStarter(myTeam, _myStrategy!);
      _myStrategy =
          _withSPReplacedInStrategy(_myStrategy!, tomorrowsSP);
    }

    _notify();
    return results;
  }

  /// 次の試合用の先発を中立に選ぶ（試合後の SP 自動差し替え用）。
  /// 全18投手のうち「ベンチ入り救援に入れておらず、登板間隔（中5日）の空いた
  /// 最も背番号の若い投手」。能力で選ばないので推測ゲームのヒントにならない。
  /// 該当者がいなければ登板間隔の空いた者、それも無ければ背番号最小にフォールバック。
  Player _pickNextStarter(Team team, NextGameStrategy current) {
    final benchedIds = current.activeBullpen.map((p) => p.id).toSet();
    final pitchers = <Player>[
      ...team.startingRotation,
      ...team.bullpen,
    ]..sort((a, b) => a.number.compareTo(b.number));
    if (pitchers.isEmpty) return team.pitcher;
    for (final p in pitchers) {
      if (benchedIds.contains(p.id)) continue;
      if (canStartNextGame(p.id)) return p;
    }
    for (final p in pitchers) {
      if (canStartNextGame(p.id)) return p;
    }
    return pitchers.first;
  }

  /// strategy 内の SP を `newSP` に置き換えた新しい [NextGameStrategy] を返す。
  /// 既に同じ SP なら同じインスタンスを返す。
  /// `lineup` 内の旧 SP の位置（打順位置）はそのまま、新 SP に差し替える。
  /// newSP が当日ベンチ入り救援に入っていた場合は、スタメンと重複しないよう
  /// activeBullpen から取り除く（先発と救援の二重登録を防ぐ）。
  NextGameStrategy _withSPReplacedInStrategy(
      NextGameStrategy old, Player newSP) {
    if (old.startingPitcher.id == newSP.id) return old;
    final newLineup =
        old.lineup.map((p) => p.isPitcher ? newSP : p).toList();
    final newAlignment = <FieldPosition, Player>{
      ...old.alignment,
      FieldPosition.pitcher: newSP,
    };
    return NextGameStrategy(
      lineup: newLineup,
      alignment: newAlignment,
      activeBench: old.activeBench,
      activeBullpen: [
        for (final p in old.activeBullpen)
          if (p.id != newSP.id) p,
      ],
    );
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
    if (!_offseasonProgressionEnabled) {
      throw StateError(
          'オフシーズン進行が OFF のとき prepareOffseason は呼べません');
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
    if (!_offseasonProgressionEnabled && plan != null) {
      throw ArgumentError(
          'オフシーズン進行が OFF のとき plan/selection は渡せません');
    }

    if (_offseasonProgressionEnabled) {
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
    }
    // OFF 時は加齢・rebuild をスキップし、選手・能力をそのまま次シーズンへ持ち越す。

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
    _pitcherLastAppearanceDay.clear();
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

  // ---- 投手の登板疲労管理 ----

  /// 1日分の回復を全投手（SP + RP）に適用。
  /// 回復量は全投手一律 17/日（スタミナを能力パラメータとして廃止したため）。
  static const int _freshnessRecoveryPerDay = 17;

  void _recoverPitcherFreshness() {
    for (final team in teams) {
      for (final p in [...team.startingRotation, ...team.bullpen]) {
        final current = _pitcherFreshness[p.id] ?? 100;
        if (current >= 100) continue;
        _pitcherFreshness[p.id] =
            (current + _freshnessRecoveryPerDay).clamp(0, 100);
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
      _pitcherLastAppearanceDay[sp.id] = _currentDay;
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
        _pitcherLastAppearanceDay[entry.key] = _currentDay;
      }
    }
  }

  /// 40 人ロスターから「当日ベンチ入り 26 人」に絞った試合用 Team を返す。
  ///
  /// - 主力野手 8（players[0..7]）と先発ローテ 6 はそのまま
  ///   （当日先発は後段の [_selectStarter] が 6 人から選ぶ）
  /// - 控え野手 14 → 9（控え捕手は希少なので最大 2 人を優先確保）
  /// - 救援 12 → 8（抑えは役割が固有なので 1 人を優先確保）
  ///
  /// [neutral] true（自チーム）: 残り枠を**背番号順**で埋める。エンジンが
  /// 能力上位を選ぶと「どれが上位選手か」のヒントになり推測ゲームが崩れるため
  /// （SPEC §コンセプト）。false（CPU）: 能力上位で埋め、たまにランダムで入替。
  /// 既に 26 人以下のロスター（旧データ・テスト用の小規模チーム）はそのまま返す。
  Team _selectActiveRoster(Team team, {bool neutral = false}) {
    // players が 9 人に正規化されていない異常系（テスト等）はそのまま返す
    if (team.players.length < 9) return team;
    final bench = _selectActiveBench(team.bench, neutral: neutral);
    final bullpen = _selectActiveBullpen(team.bullpen, neutral: neutral);
    if (identical(bench, team.bench) && identical(bullpen, team.bullpen)) {
      return team; // 絞り込み不要だった
    }
    return team.copyWith(bench: bench, bullpen: bullpen);
  }

  /// 控え野手 14 人から当日ベンチ入りの 9 人を選ぶ。
  /// 控え捕手は代打・守備交代で枯れると守備が回らなくなるため、最大 2 人を
  /// 必ずアクティブにする（守備適性ベースの確保で、能力リークではない）。
  List<Player> _selectActiveBench(List<Player> bench, {bool neutral = false}) {
    if (bench.length <= _activeBenchSize) return bench;
    final catchers = bench
        .where((p) => p.getFielding(DefensePosition.catcher) > 0)
        .toList()
      ..sort(_rosterRank(neutral));
    final guaranteed = catchers.take(2).toList();
    final pool =
        bench.where((p) => !guaranteed.contains(p)).toList();
    return [
      ...guaranteed,
      ..._pickActive(pool, _activeBenchSize - guaranteed.length,
          neutral: neutral),
    ];
  }

  /// 救援 12 人から当日ベンチ入りの 8 人を選ぶ。
  /// 抑えは終盤の役割が固有なので 1 人を必ずアクティブにする
  /// （自チームでロール指定された抑えを当日も使えるようにする意図。
  /// 自チームは開幕時全員中継ぎなので、その場合は closers が空になり素通し）。
  List<Player> _selectActiveBullpen(List<Player> bullpen,
      {bool neutral = false}) {
    if (bullpen.length <= _activeBullpenSize) return bullpen;
    final closers = bullpen
        .where((p) => p.pitcherRole == PitcherRole.closer)
        .toList()
      ..sort(_rosterRank(neutral));
    final guaranteed = closers.take(1).toList();
    final pool =
        bullpen.where((p) => !guaranteed.contains(p)).toList();
    return [
      ...guaranteed,
      ..._pickActive(pool, _activeBullpenSize - guaranteed.length,
          neutral: neutral),
    ];
  }

  /// [pool] から [count] 人を選ぶ。
  /// [neutral] true（自チーム）: 背番号順で先頭 [count] 人。能力序列を出さない。
  /// false（CPU）: 能力上位で選び、たまに「能力下位アクティブ ↔ 上位非アクティブ」を
  /// 1 組入れ替える（運用の自然な揺らぎ。当落線上の控えだけが churn）。
  List<Player> _pickActive(List<Player> pool, int count,
      {bool neutral = false}) {
    if (pool.length <= count) return pool.toList();
    final sorted = pool.toList()..sort(_rosterRank(neutral));
    if (neutral) return sorted.sublist(0, count);
    final active = sorted.sublist(0, count);
    final inactive = sorted.sublist(count);
    if (_rotationRandom.nextDouble() < _activeRosterSwapChance) {
      final outIdx = count - 1 - _rotationRandom.nextInt(min(3, count));
      final inIdx = _rotationRandom.nextInt(min(3, inactive.length));
      final swapped = active[outIdx];
      active[outIdx] = inactive[inIdx];
      inactive[inIdx] = swapped;
    }
    return active;
  }

  /// ロスター選定用のコンパレータ。
  /// [neutral] true: 背番号昇順（中立）。false: 能力スコア降順。
  int Function(Player, Player) _rosterRank(bool neutral) {
    if (neutral) return (a, b) => a.number.compareTo(b.number);
    return (a, b) => _rosterScore(b).compareTo(_rosterScore(a));
  }

  /// ロスター選定用の能力スコア。homogeneous なプール内での順位付け専用なので、
  /// 投手（[_aceScore] 0..1）と野手（打撃 5 項目平均 1..10）でスケールが
  /// 違っても問題ない（同種同士でしか比較しない）。
  double _rosterScore(Player p) {
    if (p.isPitcher) return _aceScore(p);
    return ((p.meet ?? 5) +
            (p.power ?? 5) +
            (p.eye ?? 5) +
            (p.speed ?? 5) +
            (p.arm ?? 5)) /
        5.0;
  }

  /// その日のブルペンを「使用可能な順」に並び替えて返す
  /// - コンディション 80 以上を「フレッシュな RP」として優先
  /// - その中でも残コンディションが高い順に並べる（フレッシュ順）
  /// - フレッシュな RP が 3 人未満なら、全員から残コンディション順で並べる
  List<Player> _availableBullpen(Team team) =>
      _availableBullpenFrom(team.bullpen);

  /// [_availableBullpen] のリスト版（当日ベンチ入り救援リストから直接並べる）。
  List<Player> _availableBullpenFrom(List<Player> bullpen) {
    final all = bullpen.toList();
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

    // 開幕戦: 全員未登板の場合はジッターを入れず、純粋にエース順で選ぶ。
    // 開幕投手は確定でエース、というのが NPB の標準的な運用。
    final noOneHasStarted =
        rotation.every((sp) => _pitcherLastStartDay[sp.id] == null);
    if (noOneHasStarted) {
      final sorted = rotation.toList()
        ..sort((a, b) => _aceScore(b).compareTo(_aceScore(a)));
      return sorted.first;
    }

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
      // ace ボーナスは [0, 4.0] のレンジで効かせる。ジッター [0, 2) を上回らせ、
      // 同じ休養日のコホート内では「能力高い投手が先に登板」が安定する。
      return last - ace * 4.0 + _rotationRandom.nextDouble() * 2;
    });
  }

  /// 先発候補の「エース度」を [0, 1] で返す。
  /// 球速・制球・ストレートの質・変化球の最高値の平均を使う簡易版。
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

  /// オート編成で1試合分の Team を構築する。
  /// 40 人ロスター → 当日ベンチ入り 26 人に絞り、先発選出・打順編成まで行う。
  ///
  /// 自チームは能力序列を出さない中立打順（背番号順）で組む。エンジンが能力順の
  /// 打順を提示すると推測ゲームの「最適解バレ」になるため（SPEC §コンセプト）。
  /// 通常はユーザーが作戦画面で打順を確定するのでこの経路は来ないが、
  /// 作戦未設定での進行・テスト時のフォールバックとして中立にしておく。
  Team _buildAutoGameTeam(Team season) {
    final isMyTeam = season.id == myTeamId;
    final active = _selectActiveRoster(season, neutral: isMyTeam);
    return _withGameLineup(
      active,
      _selectStarter(active),
      neutralOrder: isMyTeam,
    );
  }

  /// 1試合分の Team を構築する：
  /// - LineupPlanner で当日の打順 (1〜8番) と守備配置を決定
  /// - 9番は当日の先発 SP
  /// - bullpen をフレッシュな RP 順に並び替え（疲労した RP は除外）
  /// - スワップで控えに回ったスタメン野手は bench に移動
  ///
  /// ロール別の getter（team.closer / setupPitcher など）は bullpen 内を
  /// pitcherRole で検索するため、疲労した投手はここで bullpen から外れることで
  /// 自動的に「当日不在」扱いになる（連投回避）。
  /// [neutralOrder] true で打順を能力順でなく背番号順にする（自チーム用）。
  Team _withGameLineup(Team team, Player sp, {bool neutralOrder = false}) {
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
      neutralOrder: neutralOrder,
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
  ///
  /// 打順・守備配置・先発・当日ベンチ入り（控え野手・救援）すべてユーザー指定を採用。
  /// 引数 [team] は 40 人ロスターのシーズン保持 Team（オート版と違い
  /// `_selectActiveRoster` は通さない — ベンチ入りもユーザーが決めるため）。
  ///
  /// `strategy.activeBench` / `activeBullpen` が空（旧セーブ等）の場合のみ、
  /// エンジンの自動ベンチ入り選定にフォールバックする。
  Team _applyMyStrategy(Team team, NextGameStrategy strategy) {
    // 旧セーブ等で当日ベンチ入りが未指定のときのフォールバック。
    // _applyMyStrategy は自チーム専用なので中立選定（背番号順）にする。
    final bench = strategy.activeBench.isNotEmpty
        ? strategy.activeBench
        : _selectActiveBench(team.bench, neutral: true);
    final bullpen = strategy.activeBullpen.isNotEmpty
        ? strategy.activeBullpen
        : _selectActiveBullpen(team.bullpen, neutral: true);
    return team.copyWith(
      players: strategy.fullLineup,
      defenseAlignment: Map.of(strategy.alignment),
      bench: bench,
      bullpen: _availableBullpenFrom(bullpen),
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
  /// 試合の球数で消費し、1 日経過で全投手一律の量だけ回復する。
  /// 作戦画面で「連投できそうか」の判断材料として表示する。
  /// 未登録の投手は 100 を返す（開幕直後の挙動と一致）。
  int pitcherFreshness(String pitcherId) =>
      _pitcherFreshness[pitcherId] ?? 100;

  /// 投手の最終登板日参照（UI 用）
  int? pitcherLastStartDay(String pitcherId) =>
      _pitcherLastStartDay[pitcherId];

  /// 次の自チーム試合（currentDay+1）で、この投手が先発できるか。
  /// 中5日（_minDaysBetweenStarts 日空ける）の登板間隔を満たすことが条件。
  ///
  /// 判定は「最終**登板**日」（先発・救援問わず）ベース。これにより、
  /// ベンチ入りさせて救援で投げ続けている投手は間隔が空かず先発候補に挙がらず、
  /// ベンチ入りから外して休ませた投手は先発に指定できる。
  bool canStartNextGame(String pitcherId) {
    final last = _pitcherLastAppearanceDay[pitcherId];
    if (last == null) return true; // 未登板
    return ((_currentDay + 1) - last) >= _minDaysBetweenStarts;
  }

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
      'offseasonProgressionEnabled': _offseasonProgressionEnabled,
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
      'pitcherLastAppearanceDay': _pitcherLastAppearanceDay,
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
    // オフシーズン進行フラグ。旧セーブには存在しないので true（現状の挙動）扱い。
    final offseasonProgressionEnabled =
        json['offseasonProgressionEnabled'] as bool? ?? true;
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: json['myTeamId'] as String,
      gamesPerTeam: gamesPerTeam,
      offseasonProgressionEnabled: offseasonProgressionEnabled,
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
    controller._pitcherLastAppearanceDay.clear();
    for (final e
        in (json['pitcherLastAppearanceDay'] as Map? ?? {}).entries) {
      controller._pitcherLastAppearanceDay[e.key as String] = e.value as int;
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

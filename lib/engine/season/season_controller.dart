import 'dart:async';
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
import 'unlock_gate.dart';
import 'schedule_generator.dart';
import 'scheduled_game.dart';
import 'season_aggregator.dart';
import 'season_snapshot.dart';
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

  /// リーグで DH（指名打者）制を採用するか。
  ///
  /// シーズン開幕時に試合数と一緒に選び、そのシーズン中は固定（途中変更不可）。
  /// `commitOffseason` で次シーズンへ明示的に引き渡す（未指定なら前シーズンを継承）。
  ///
  /// true: 投手は打席に立たず、各チームは野手を DH として打たせる（権利なので
  ///       大谷型は投手を打順に入れることも可能 = チーム単位の選択）。
  /// false: 全チーム投手が打席に立つ（＝v1.0 までの挙動）。旧セーブの復元時は
  ///        互換のため false 扱い。
  bool _enableDH;

  /// 試合結果の解禁時刻（0-23 時、デフォルト 21）。1日1試合制約で使う。
  /// 詳細は docs/DAILY_GATE_PLAN.md / [UnlockGate] 参照。
  int _unlockHour;

  /// 直近の「解禁が発生した時刻」。null = onboarding 中 + onboarding 直後の最初の解禁前。
  /// 視聴で消費すると `markGameViewed` で「直近の解禁時刻ジャスト」が記録される。
  DateTime? _lastUnlockAt;

  /// 結果確認時刻にローカル通知を出すか（デフォルト true）。
  /// 設定画面の通知トグルから変更可能。OFF にすると `NotificationService` 側で
  /// 予約をキャンセル、ON で次回ぶんを 1 件予約する。
  bool _notificationsEnabled;

  /// onboarding 期間の閾値: 1シーズン目の自チーム消化試合数 < この値 なら onboarding 中。
  static const int onboardingGameCount = 10;

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

  // シーズン終了後の編成プラン（引退候補・新人候補）のキャッシュ。
  // 一度生成したら commitOffseason / newSeason まで保持し、再呼出でも同じ
  // 候補を返す。これでアプリ再起動 → オフシーズン編成画面を開いても同じ
  // 新人が表示され、リセマラ（再起動で新人ガチャを引き直す）を防ぐ。
  OffseasonPlan? _pendingOffseasonPlan;

  // 過去シーズンの集計スナップショット履歴。
  // commitOffseason で次シーズンに進む直前に現シーズンの成績を凍結して
  // ここに追加する。年度別成績画面・オフシーズン編成画面・作戦画面で
  // 「前年成績」「キャリア推移」を見るために使う。
  // 全シーズン保持しても 50 シーズンで 3.5MB 程度なので切り捨てなし。
  final List<SeasonSnapshot> _seasonHistory = [];

  /// 過去シーズンのスナップショット（古い順）。
  List<SeasonSnapshot> get seasonHistory =>
      List.unmodifiable(_seasonHistory);

  /// 指定選手の年度別成績（野手）を古い順で返す。出場が無いシーズンは含めない。
  List<({int year, BatterSeasonStats stats})> batterHistoryOf(
      String playerId) {
    return [
      for (final s in _seasonHistory)
        if (s.batterStats[playerId] != null &&
            s.batterStats[playerId]!.games > 0)
          (year: s.year, stats: s.batterStats[playerId]!),
    ];
  }

  /// 指定選手の年度別成績（投手）を古い順で返す。登板が無いシーズンは含めない。
  List<({int year, PitcherSeasonStats stats})> pitcherHistoryOf(
      String playerId) {
    return [
      for (final s in _seasonHistory)
        if (s.pitcherStats[playerId] != null &&
            s.pitcherStats[playerId]!.games > 0)
          (year: s.year, stats: s.pitcherStats[playerId]!),
    ];
  }

  /// 前年の野手成績（直近のシーズンスナップショットから引く）。
  /// 履歴が空（1 年目）なら null。
  BatterSeasonStats? previousBatterStatsOf(String playerId) {
    if (_seasonHistory.isEmpty) return null;
    return _seasonHistory.last.batterStats[playerId];
  }

  /// 前年の投手成績。同上。
  PitcherSeasonStats? previousPitcherStatsOf(String playerId) {
    if (_seasonHistory.isEmpty) return null;
    return _seasonHistory.last.pitcherStats[playerId];
  }

  // 完投 1試合 ≒ 120球で full depletion (-100)
  static const double _completeGamePitches = 120;
  // 中4日（5日空ける）以上空いていない投手は原則先発しない。
  // 中4日 + 体力100% の AND 条件で先発登板可。「中4日経過しても体力が戻らない」
  // 場合は先発できず、「中4日で体力100%に戻った（前回球数を抑えた）」場合は登板可。
  // これで前回球数の重さ次第でローテ周期が自然にズレ、同じ投手の対戦の固定化を防ぐ。
  // 完投 (~120球) すると 6日後（中5日）にようやく 100 復帰、~100球以下で降りれば
  // 中4日で 100 復帰、というメジャーリーグ寄りの運用になる。
  static const int _minDaysBetweenStarts = 5;
  // 先発として「フル回復」とみなす閾値。
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
  static const int _activeBenchSize = 8; // 当日ベンチ入りする控え野手の人数
  static const int _activeBullpenSize = 9; // 当日ベンチ入りする救援投手の人数
  // CPU 運用の自然な揺らぎ: 控え野手・救援それぞれで、1 チーム 1 日あたり
  // 「能力下位アクティブ ↔ 非アクティブ」が 1 組入れ替わる確率。
  static const double _activeRosterSwapChance = 0.12;

  /// 先発選出時のローテ揺らぎ用 RNG。
  /// 完全に決定論的に「最終登板日が古い順」で選ぶと 100% 中4日に固定されるため、
  /// 微小な揺らぎを与えて現実の中4日／中5日／中6日が混ざるようにする。
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

  /// 前シーズン最終試合での自チーム打順スナップショット（id ベース）。
  /// 次シーズン Day 1 の `suggestedStrategyForMyTeam` でこれを優先して復元するため、
  /// commitOffseason で _myStrategy をクリアする直前に保存する。
  /// 引退者・移籍者は復元時にスキップして、控えで穴埋めする。
  /// 投手スロットは中4日ゲートのため毎日選び直す必要があるので含めない（位置のみ記録）。
  List<_LineupSlotSnapshot>? _lastSeasonFinalLineup;

  /// 前シーズン最終スタメンが DH 制だったか。Day 1 復元の分岐に使う。
  bool _lastSeasonUseDH = false;

  /// 前シーズン最終スタメンが DH 制のときの先発投手 id（投手は打順に居ないため別保持）。
  /// 復元時は中4日ゲートで選び直すので参考値。非DHでは null。
  String? _lastSeasonStarterPitcherId;

  /// 前シーズン最終時点で当日ベンチ入りしていた控え野手の id リスト。
  /// ユーザーが手動でベンチ入りを選んでいた場合に翌年継承する。
  /// 引退者の枠は復元時に背番号順で穴埋め。
  List<String>? _lastSeasonActiveBenchIds;

  /// 前シーズン最終時点で当日ベンチ入りしていた救援投手の id リスト。
  /// 引退者の枠は背番号順で穴埋め。先発ロールの投手は穴埋め対象から除外する
  /// （中立提案と同じ「先発ロールはローテに残す」考え方）。
  List<String>? _lastSeasonActiveBullpenIds;

  /// 新人選手生成用の長寿命ジェネレータ。シーズン跨ぎでも id・名前が衝突しないよう
  /// 各 Team 構築時に既存選手から復元される。
  late PlayerGenerator _playerGen;

  SeasonController({
    required this.teams,
    required Schedule schedule,
    required this.myTeamId,
    int gamesPerTeam = ScheduleGenerator.defaultGamesPerTeam,
    bool offseasonProgressionEnabled = true,
    bool enableDH = false,
    int unlockHour = 21,
    DateTime? lastUnlockAt,
    bool notificationsEnabled = true,
    GameSimulator? gameSimulator,
    Random? random,
  })  : _schedule = schedule,
        _gamesPerTeam = gamesPerTeam,
        _offseasonProgressionEnabled = offseasonProgressionEnabled,
        _enableDH = enableDH,
        _unlockHour = unlockHour,
        _lastUnlockAt = lastUnlockAt,
        _notificationsEnabled = notificationsEnabled,
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
    bool enableDH = true,
    int unlockHour = 21,
    bool notificationsEnabled = true,
  }) {
    final teams = TeamGenerator(random: random).generateLeague();
    // 日程は 5 ラウンドのサークル法。random を渡すことでラウンド順をシャッフルし、
    // 毎シーズン開幕カードや 3 連戦の組み合わせが変わるようにする。
    final schedule = const ScheduleGenerator().generateForGamesPerTeam(
      teams,
      gamesPerTeam,
      random: random ?? Random(),
    );
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: myTeamId,
      gamesPerTeam: gamesPerTeam,
      offseasonProgressionEnabled: offseasonProgressionEnabled,
      enableDH: enableDH,
      unlockHour: unlockHour,
      notificationsEnabled: notificationsEnabled,
      random: random,
    );
    // 自チームの投手ロール・スタメン野手は推測ゲームの一部としてユーザーが
    // 試合結果から決める。開幕時はエンジンが能力で配置した状態にせず、背番号順の
    // 中立な初期配置で始める。CPU 5 球団は TeamGenerator の能力ベース配置のまま
    // （対戦相手の偵察は推測ゲームの一部）。
    // [feedback_no_ability_based_auto_assignment]
    final my = controller.myTeam;

    // ① 投手ロール: 全18投手を背番号順に並べ、若い6人→「先発」、残り12人→「中継ぎ」
    final pitchers = <Player>[...my.startingRotation, ...my.bullpen]
      ..sort((a, b) => a.number.compareTo(b.number));
    for (int i = 0; i < pitchers.length; i++) {
      final role = i < 6 ? PitcherRole.starter : PitcherRole.middle;
      if (pitchers[i].pitcherRole != role) {
        controller.updatePlayer(pitchers[i].withPitcherRole(role));
      }
    }

    // ② 野手スタメン: TeamGenerator が能力スコア順にポジション別スタメンを選んでいるが、
    // それを「背番号順にポジション別スタメンを選ぶ」中立な配置に上書きする。
    // 22 名（players[0..7] + bench、投手 players[8] を除く）を背番号順に並べ、
    // ポジションごとに「守れる選手の中で背番号最小」を順に拾う。
    const slotPositions = [
      DefensePosition.catcher,
      DefensePosition.first,
      DefensePosition.second,
      DefensePosition.third,
      DefensePosition.shortstop,
      DefensePosition.outfield,
      DefensePosition.outfield,
      DefensePosition.outfield,
    ];
    final fielderPool = <Player>[
      ...my.players.take(8),
      ...my.bench,
    ]..sort((a, b) => a.number.compareTo(b.number));
    final neutralStarters = <Player>[];
    final usedIds = <String>{};
    for (final pos in slotPositions) {
      Player? chosen;
      for (final p in fielderPool) {
        if (usedIds.contains(p.id)) continue;
        if (p.canPlay(pos)) {
          chosen = p;
          break;
        }
      }
      chosen ??= fielderPool.firstWhere((p) => !usedIds.contains(p.id));
      neutralStarters.add(chosen);
      usedIds.add(chosen.id);
    }
    // 投手スロット（players[8]）はそのまま維持。スタメン野手 8 と残り bench を再構成。
    final pitcherSlot = my.players[8];
    final newBench =
        fielderPool.where((p) => !usedIds.contains(p.id)).toList();
    my.players
      ..clear()
      ..addAll([...neutralStarters, pitcherSlot]);
    my.bench
      ..clear()
      ..addAll(newBench);

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

  /// 今シーズンが DH（指名打者）制を採用しているか。
  /// 開幕時に確定し、シーズン中は不変。UI 表示・編成判断に使う。
  bool get enableDH => _enableDH;

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

  // ---- 1日1試合制約（時間ゲート） ----
  // 詳細仕様は docs/DAILY_GATE_PLAN.md / [UnlockGate] 参照。

  /// 試合結果の解禁時刻（0-23 時）。設定画面から変更可能。
  int get unlockHour => _unlockHour;

  /// 直近の「解禁が発生した時刻」。null = onboarding 中 or 11試合目の初回解禁前。
  DateTime? get lastUnlockAt => _lastUnlockAt;

  /// 解禁時刻を変更する。`_lastUnlockAt` は触らないので、12h 制約は次の
  /// `nextUnlockAt` 計算で自然に効く（同日中の再解禁を抑止）。
  set unlockHour(int value) {
    final clamped = value.clamp(0, 23);
    if (_unlockHour == clamped) return;
    _unlockHour = clamped;
    _notify();
  }

  /// 結果確認時刻にローカル通知を出すか。デフォルト true。
  bool get notificationsEnabled => _notificationsEnabled;

  set notificationsEnabled(bool value) {
    if (_notificationsEnabled == value) return;
    _notificationsEnabled = value;
    _notify();
  }

  /// 自チームが今シーズン消化した試合数（GameResult ベースで数える）。
  int get selfTeamGamesPlayed {
    int count = 0;
    for (final result in _results.values) {
      if (result.homeTeam.id == myTeamId || result.awayTeam.id == myTeamId) {
        count++;
      }
    }
    return count;
  }

  /// onboarding 期間中か（1シーズン目 + 自チーム消化試合数 < 閾値）。
  /// 2 シーズン目以降は常に false（推測ゲームの足場作りはシーズン1だけで十分）。
  bool get isInOnboarding =>
      _seasonYear == 1 && selfTeamGamesPlayed < onboardingGameCount;

  /// 現在の状態から [UnlockGate] を構築する。
  /// [hasTimeSkipSub] は将来課金で実装、現状は常に false。
  UnlockGate unlockGate({bool hasTimeSkipSub = false}) {
    return UnlockGate(
      unlockHour: _unlockHour,
      lastUnlockAt: _lastUnlockAt,
      isInOnboarding: isInOnboarding,
      hasTimeSkipSub: hasTimeSkipSub,
    );
  }

  /// 試合結果を視聴したことを記録（解禁を消費）。
  /// UI 層（試合進行が完了して結果画面を表示するタイミング）から呼ぶ。
  ///
  /// onboarding 中は `_lastUnlockAt` を触らない。それ以降は「直近の解禁時刻ジャスト」
  /// （[now] 以前で最も近い設定時刻オカレンス）を記録する。
  void markGameViewed(DateTime now, {bool hasTimeSkipSub = false}) {
    final gate = unlockGate(hasTimeSkipSub: hasTimeSkipSub);
    final newValue = gate.newLastUnlockAtOnView(now);
    if (newValue == null) return; // onboarding 中など、更新不要
    if (_lastUnlockAt != null && _lastUnlockAt!.isAtSameMomentAs(newValue)) {
      return;
    }
    _lastUnlockAt = newValue;
    _notify();
  }

  Team get myTeam => teams.firstWhere((t) => t.id == myTeamId);
  Standings get standings => _aggregator.standings;
  Map<String, BatterSeasonStats> get batterStats => _aggregator.batterStats;
  Map<String, PitcherSeasonStats> get pitcherStats => _aggregator.pitcherStats;

  /// 次の試合用の自チーム作戦（null ならオート編成）
  NextGameStrategy? get myStrategy => _myStrategy;

  /// 前年最終スタメンの snapshot を作戦画面に公開する（Day 1 で構成継承するため）。
  /// 各要素は (playerId, position, isDH) のレコード。DH スロットは position=null,
  /// isDH=true。引退者は呼び出し側で playerId 解決時に null となり、空白スロット
  /// として扱われる。
  List<({String playerId, FieldPosition? position, bool isDH})>?
      get previousLineupSnapshot {
    final snap = _lastSeasonFinalLineup;
    if (snap == null) return null;
    return [
      for (final s in snap)
        (playerId: s.playerId, position: s.position, isDH: s.isDH),
    ];
  }

  /// 前年最終スタメンが DH 制だったか（Day 1 復元の分岐用）。
  bool get previousUseDH => _lastSeasonUseDH;

  /// 前年最終スタメンが DH 制のときの先発投手 id（参考値。中4日ゲートで選び直す）。
  String? get previousStarterPitcherId => _lastSeasonStarterPitcherId;

  /// 前年最終時点で当日ベンチ入りしていた控え野手の id リスト。
  /// 引退者はそのまま残るので、呼び出し側で findPlayerById で解決して除外する。
  List<String>? get previousActiveBenchIds =>
      _lastSeasonActiveBenchIds == null
          ? null
          : List.unmodifiable(_lastSeasonActiveBenchIds!);

  /// 前年最終時点で当日ベンチ入りしていた救援投手の id リスト。
  List<String>? get previousActiveBullpenIds =>
      _lastSeasonActiveBullpenIds == null
          ? null
          : List.unmodifiable(_lastSeasonActiveBullpenIds!);

  /// 自チームのデフォルト先発投手。**作戦画面の投手ピッカーと同じ並び**
  /// （ロール優先度: 先発 → ロング → … → 体力降順 → 背番号）で、登板条件
  /// （中4日 + 体力100%）を満たす最初の投手を返す。
  /// つまり「先発ロールで条件を満たす人がいればその先頭、いなければロング…」と
  /// 順に探した最初の該当者。作戦画面が表示中の SP を検証・差し替えるのに使う。
  /// [excludeIds]: 候補から外す投手 id（DH に起用中の投手など、打順に入っていて
  /// 先発にできない選手）。作戦画面から渡す。
  Player? defaultStarterForMyTeam({Set<String> excludeIds = const {}}) {
    final team = teams.firstWhere((t) => t.id == myTeamId);
    final pitchers = <Player>[
      ...team.startingRotation,
      ...team.bullpen,
    ]..sort((a, b) {
        final ra = pitcherRoleStarterPriority(a.pitcherRole);
        final rb = pitcherRoleStarterPriority(b.pitcherRole);
        if (ra != rb) return ra.compareTo(rb);
        final fa = pitcherFreshness(a.id);
        final fb = pitcherFreshness(b.id);
        if (fa != fb) return fb.compareTo(fa);
        return a.number.compareTo(b.number);
      });
    if (pitchers.isEmpty) return null;
    return _pickDefaultStarter(pitchers, exclude: excludeIds);
  }

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
  /// - 先発: 全18投手から、作戦画面の投手ピッカーと同じ並び
  ///   （ロール優先度→体力降順→背番号）で `canStartNextGame` な先頭の投手
  /// - ベンチ入り救援: 先発ロールの投手を除き、中継ぎ等のロールから背番号順で8人
  /// - 打順・守備: 背番号順の中立編成（[_withGameLineup] neutralOrder）
  ///
  /// シーズン終了済み・自チームの選手が9人未満の異常時には null を返す。
  NextGameStrategy? suggestedStrategyForMyTeam() {
    if (isSeasonOver) return null;
    final team = teams.firstWhere((t) => t.id == myTeamId);
    if (team.players.length < 9) return null;
    // 先発: 全18投手（先発ローテ + 救援）を作戦画面の投手ピッカーと同じ順で並べ、
    // 登板可能（中4日 + 体力100%）な先頭の投手を選ぶ。
    //   ロール優先度（先発 → ロング → 中継ぎ → …）→ 体力降順 → 背番号
    // ピッカー先頭がそのままデフォルト先発になるよう揃えてある（推測ゲームの中立性を
    // 保ちつつ、ピッカー上で「最も先発に近い」と提示している投手と一致させる狙い）。
    final allPitchers = <Player>[
      ...team.startingRotation,
      ...team.bullpen,
    ]..sort((a, b) {
        final ra = pitcherRoleStarterPriority(a.pitcherRole);
        final rb = pitcherRoleStarterPriority(b.pitcherRole);
        if (ra != rb) return ra.compareTo(rb);
        final fa = pitcherFreshness(a.id);
        final fb = pitcherFreshness(b.id);
        if (fa != fb) return fb.compareTo(fa);
        return a.number.compareTo(b.number);
      });
    // 体力のある（休養済み）投手の中からロール優先で選ぶ。前日登板など休養不足の
    // 投手は、他に休養できている投手がいる限りデフォルトにしない。
    final sp = _pickDefaultStarter(allPitchers);
    // ベンチ入り救援: 先発ロールの投手は初期提案から外す（ローテ予定の投手が
    // 救援要員に埋まるのを避ける）。中継ぎ等のロールから背番号順で8人。
    final activeBullpen = [
      for (final p in allPitchers)
        if (p.id != sp.id && p.pitcherRole != PitcherRole.starter) p,
    ].take(_activeBullpenSize).toList();
    // 野手側は中立選定 + 中立打順。
    // Day 1 の前年スタメン継承は `suggestedStrategy` ではなく作戦画面側で
    // [previousLineupSnapshot] / [previousActiveBenchIds] /
    // [previousActiveBullpenIds] を参照して構築する（引退者を「空白」として
    // 残したいため、Player? の許容が必要）。
    final active = _selectActiveRoster(team, neutral: true);
    // リーグ DH 採用時はデフォルトで DH を使う提案にする（投手は打席に立たず、
    // 控え野手から中立に DH を選ぶ）。ユーザーは作戦画面で大谷型（投手を打順に
    // 入れる）に変更できる。
    final game =
        _withGameLineup(active, sp, neutralOrder: true, useDH: _enableDH);

    return NextGameStrategy(
      lineup: game.players,
      alignment: game.defenseAlignment!,
      useDH: _enableDH,
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
      useDH: strategy.useDH,
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
        enableDH: _enableDH,
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
      final tomorrowsSP = _pickNextStarter(myTeam);
      _myStrategy =
          _withSPReplacedInStrategy(_myStrategy!, tomorrowsSP);
    }

    _notify();
    return results;
  }

  /// 次の試合用の先発を中立に選ぶ（試合後の SP 自動差し替え用）。
  /// 並び順は作戦画面の投手ピッカーと同じ:
  ///   ロール優先度（先発 → ロング → 中継ぎ → …）→ 体力降順 → 背番号。
  /// その並びで「登板間隔（中4日）+ 体力100%」を満たす最初の投手を選ぶ
  /// （[_pickDefaultStarter]）。能力で選ばないので推測ゲームのヒントにならない。
  Player _pickNextStarter(Team team) {
    final pitchers = <Player>[
      ...team.startingRotation,
      ...team.bullpen,
    ]..sort((a, b) {
        final ra = pitcherRoleStarterPriority(a.pitcherRole);
        final rb = pitcherRoleStarterPriority(b.pitcherRole);
        if (ra != rb) return ra.compareTo(rb);
        final fa = pitcherFreshness(a.id);
        final fb = pitcherFreshness(b.id);
        if (fa != fb) return fb.compareTo(fa);
        return a.number.compareTo(b.number);
      });
    if (pitchers.isEmpty) return team.pitcher;
    // DH に投手登板選手を起用している場合、その選手（打順に居る）は先発候補から除外。
    final exclude = _myStrategy == null
        ? const <String>{}
        : {for (final p in _myStrategy!.lineup) p.id};
    return _pickDefaultStarter(pitchers, exclude: exclude);
  }

  /// 次の試合の登板で中4日（[_minDaysBetweenStarts]）の登板間隔を満たさないか
  /// （= 直近に登板していて休養不足か）。前日登板の投手はここで true。
  bool _startsTooSoon(String pitcherId) {
    final last = _pitcherLastAppearanceDay[pitcherId];
    return last != null &&
        ((_currentDay + 1) - last) < _minDaysBetweenStarts;
  }

  /// デフォルト先発を選ぶ。**作戦画面の投手ピッカーと同じ並び順で、先発できる
  /// 条件（中4日 + 体力100%）を満たす最初の投手**を返す。これにより「ピッカーで
  /// デフォルト選択される投手」と一致する（前日登板など条件を満たさない投手は飛ばす）。
  ///
  /// [pitchers] はピッカーと同じ並び（ロール優先度→体力降順→背番号）で整列済みのこと。
  /// [exclude] は候補から外す投手 id（DH に起用中の投手登板選手など。同じ選手が
  /// DH で打席に立ちつつ先発もすることはありえないため除外する）。
  /// 万一どの投手も条件を満たさない場合のみ、休養を満たす最初の投手 →
  /// 最も体力のある投手、の順でフォールバックする（体力のない投手を選ばないため）。
  Player _pickDefaultStarter(List<Player> pitchers,
      {Set<String> exclude = const {}}) {
    // 本命: 並び順で「中4日 + 体力100%」を満たす最初の投手。
    for (final p in pitchers) {
      if (exclude.contains(p.id)) continue;
      if (canStartNextGame(p.id)) return p;
    }
    // フォールバック1: 中4日（休養間隔）だけは満たす最初の投手。
    for (final p in pitchers) {
      if (exclude.contains(p.id)) continue;
      if (!_startsTooSoon(p.id)) return p;
    }
    // フォールバック2: 全員が直近登板。せめて最も体力のある投手。
    final pool = [for (final p in pitchers) if (!exclude.contains(p.id)) p]
      ..sort((a, b) => pitcherFreshness(b.id).compareTo(pitcherFreshness(a.id)));
    if (pool.isNotEmpty) return pool.first;
    return pitchers.first; // 全員除外の異常系
  }

  /// strategy 内の SP を `newSP` に置き換えた新しい [NextGameStrategy] を返す。
  /// 既に同じ SP なら同じインスタンスを返す。
  /// `lineup` 内の旧 SP の位置（打順位置）はそのまま、新 SP に差し替える。
  /// newSP が当日ベンチ入り救援に入っていた場合は、スタメンと重複しないよう
  /// activeBullpen から取り除く（先発と救援の二重登録を防ぐ）。
  NextGameStrategy _withSPReplacedInStrategy(
      NextGameStrategy old, Player newSP) {
    if (old.startingPitcher.id == newSP.id) return old;
    // DH採用時、先発投手は打順に居ない。打順内の選手（DH に起用した投手登録選手を
    // 含む）を別途の先発投手にはできないので、その場合は差し替えない。
    if (old.useDH && old.lineup.any((p) => p.id == newSP.id)) return old;
    // 非DHでは投手は打順に居るので打順内の投手を差し替える。
    // DH採用時は投手が打順に居ない（DH の投手登録選手は別人）ので打順は不変、
    // 守備配置の投手だけ差し替える。
    final newLineup = old.useDH
        ? old.lineup
        : old.lineup.map((p) => p.isPitcher ? newSP : p).toList();
    final newAlignment = <FieldPosition, Player>{
      ...old.alignment,
      FieldPosition.pitcher: newSP,
    };
    return NextGameStrategy(
      lineup: newLineup,
      alignment: newAlignment,
      useDH: old.useDH,
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
  /// **冪等**: 同じシーズン終了状態で複数回呼んでも常に同じ候補（同じ Player・
  /// 同じ id）を返す。初回呼出時に候補を生成して `_pendingOffseasonPlan` に
  /// キャッシュし、以降の呼出はキャッシュを返す。アプリ再起動を挟んでも、
  /// セーブに含まれる pendingOffseasonPlan から復元されるので結果は変わらない。
  /// これによりリセマラ（アプリ再起動で新人ガチャを引き直す）を防ぐ。
  /// キャッシュは `commitOffseason` 内で次シーズンに進む際にクリアされる。
  OffseasonPlan prepareOffseason() {
    if (!isSeasonOver) {
      throw StateError('シーズン進行中は prepareOffseason を呼べません');
    }
    if (!_offseasonProgressionEnabled) {
      throw StateError(
          'オフシーズン進行が OFF のとき prepareOffseason は呼べません');
    }
    final cached = _pendingOffseasonPlan;
    if (cached != null) return cached;
    final plan = TeamRebuilder(
      playerGen: _playerGen,
      previousBatterStats: _aggregator.batterStats,
      random: _rotationRandom,
    ).buildOffseasonPlan(myTeam);
    _pendingOffseasonPlan = plan;
    // セーブを誘発するため notify は必要だが、本メソッドは UI の initState
    // から呼ばれることがあり、その場合は「ビルド中の setState」エラーになる。
    // 次のマイクロタスクで notify を発火し、ビルド完了後に listener が走るようにする。
    scheduleMicrotask(_notify);
    return plan;
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
    bool? enableDH,
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
      //    外国人の強制離脱・補充も CPU の rebuildCpuTeams 内で実行される。
      final rebuilder = TeamRebuilder(
        playerGen: _playerGen,
        previousBatterStats: _aggregator.batterStats,
        random: _rotationRandom,
      );
      rebuilder.rebuildCpuTeams(teams, myTeamId);

      // 3. 自チーム: ユーザー選択を反映（プランが渡されたときのみ）。
      //    外国人の強制離脱判定と新候補生成は prepareOffseason 内で済んでおり、
      //    plan.foreignDepartures / plan.foreignCandidates + ユーザー選択を
      //    applyUserSelection が一括で適用する。プラン無しケース（offseason 自動
      //    進行で UI を経由しない）では外国人入替は発生しない（既存挙動と同じく
      //    現状維持）。
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

    // 次シーズンに進む前に現シーズンの集計結果をスナップショット化して履歴に追加。
    // 加齢で Player インスタンス自体は差し替わるが、stats は id 参照ベースで
    // 復元できる（fromJson の playerById で解決）ので、加齢後でも参照が壊れない。
    // BatterSeasonStats / PitcherSeasonStats は加齢前の Player 参照を保持しているが、
    // toJson で id だけ保存されるため永続化往復後は新しい Player に解決される。
    _seasonHistory.add(SeasonSnapshot(
      year: _seasonYear,
      batterStats: Map.of(_aggregator.batterStats),
      pitcherStats: Map.of(_aggregator.pitcherStats),
      standings: _aggregator.standings,
    ));

    // 4〜6.
    _seasonYear++;
    if (gamesPerTeam != null) {
      _gamesPerTeam = gamesPerTeam;
    }
    // DH 採用可否も次シーズン開幕時に選び直せる（未指定なら前シーズンを継承）。
    if (enableDH != null) {
      _enableDH = enableDH;
    }
    // 前シーズン最終スタメン・ベンチ入りのスナップショットを取る
    // （次シーズン Day 1 で作戦画面が復元するため）。
    // _myStrategy は試合後の SP 自動差し替えで最終試合のあと「次の試合用」に
    // 更新されているが、野手の打順・守備位置・ベンチ入りは試合中の代打・代走では
    // 書き換えず、翌試合用の初期構成を維持しているため、ここから取ればシーズン
    // 終了時点のユーザー編集を反映できる。
    final lastStrategy = _myStrategy;
    if (lastStrategy != null) {
      // DH採用時、DH の打順スロットは守備配置に居ないので isDH=true で記録し、
      // 投手は打順に居ないので別フィールドに保存する。
      final dhId =
          lastStrategy.useDH ? lastStrategy.designatedHitter?.id : null;
      _lastSeasonFinalLineup = [
        for (final p in lastStrategy.lineup)
          if (p.id == dhId)
            _LineupSlotSnapshot(p.id, null, isDH: true)
          else
            _LineupSlotSnapshot(
              p.id,
              lastStrategy.alignment.entries
                  .firstWhere((e) => e.value.id == p.id)
                  .key,
            ),
      ];
      _lastSeasonUseDH = lastStrategy.useDH;
      _lastSeasonStarterPitcherId =
          lastStrategy.useDH ? lastStrategy.startingPitcher.id : null;
      _lastSeasonActiveBenchIds = [
        for (final p in lastStrategy.activeBench) p.id,
      ];
      _lastSeasonActiveBullpenIds = [
        for (final p in lastStrategy.activeBullpen) p.id,
      ];
    } else {
      // オート編成のままシーズンを終えた場合は前年継続の意味が薄いのでクリア。
      // 次シーズンも中立提案にフォールバックする。
      _lastSeasonFinalLineup = null;
      _lastSeasonUseDH = false;
      _lastSeasonStarterPitcherId = null;
      _lastSeasonActiveBenchIds = null;
      _lastSeasonActiveBullpenIds = null;
    }

    // 次シーズンの日程もラウンド順をシャッフルする（_rotationRandom を使い回し）。
    _schedule = const ScheduleGenerator().generateForGamesPerTeam(
      teams,
      _gamesPerTeam,
      random: _rotationRandom,
    );
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
    // 次シーズンに入ったので、保留中の編成プランは消費済み。次のシーズン終了で
    // 再度生成する。
    _pendingOffseasonPlan = null;

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
  /// 内訳: スタメン野手 8 + 控え野手 8 + 先発 1 + 救援 9 = 26
  /// - 主力野手 8（players[0..7]）と先発ローテ 6 はそのまま
  ///   （当日先発は後段の [_selectStarter] が 6 人から選ぶ）
  /// - 控え野手 12 → 8（各ポジション 2 人以上守れるよう確保、外野は 5 人以上）
  /// - 救援 14 → 9（抑えは役割が固有なので 1 人を優先確保）
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

  /// 控え野手 12 人から当日ベンチ入りの 8 人を選ぶ。
  ///
  /// **ポジション充足の制約**: スタメン 8 (捕1+内野4+外野3) に控えを加えた合計で、
  /// 各ポジション 2 人以上、外野 5 人以上守れるよう確保する。
  /// これは「代打・守備交代で枯れない」現実的な編成（守備適性ベース、能力リーク
  /// ではない）。スタメンが各ポジ 1 人ずつなので、控えは:
  ///   捕手 ≥ 1 / 一塁 ≥ 1 / 二塁 ≥ 1 / 三塁 ≥ 1 / 遊撃 ≥ 1 / 外野 ≥ 2
  /// を確保。兼任選手 1 名で複数ポジションをカバーするケースも含む。
  List<Player> _selectActiveBench(List<Player> bench, {bool neutral = false}) {
    if (bench.length <= _activeBenchSize) return bench;

    const benchMinByPosition = <DefensePosition, int>{
      DefensePosition.catcher: 1,
      DefensePosition.first: 1,
      DefensePosition.second: 1,
      DefensePosition.third: 1,
      DefensePosition.shortstop: 1,
      DefensePosition.outfield: 2,
    };

    final selected = <Player>[];
    for (final entry in benchMinByPosition.entries) {
      final pos = entry.key;
      final needed = entry.value;
      final alreadyCovers =
          selected.where((p) => p.canPlay(pos)).length;
      if (alreadyCovers >= needed) continue;
      final candidates = bench
          .where((p) => !selected.contains(p) && p.canPlay(pos))
          .toList()
        ..sort(_rosterRank(neutral));
      selected.addAll(candidates.take(needed - alreadyCovers));
    }

    final remainingCount = _activeBenchSize - selected.length;
    if (remainingCount <= 0) return selected.take(_activeBenchSize).toList();
    final pool = bench.where((p) => !selected.contains(p)).toList();
    return [
      ...selected,
      ..._pickActive(pool, remainingCount, neutral: neutral),
    ];
  }

  /// 救援 14 人から当日ベンチ入りの 9 人を選ぶ。
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
      // リーグ DH 採用時、オート編成（CPU 全チーム + 作戦未設定の自チーム）は
      // 常に DH を使う（自動生成の投手は打力が低く、現実通り DH を使うのが妥当）。
      useDH: _enableDH,
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
  /// [useDH] true で投手を打順に入れず DH を立てる（リーグ DH 採用時）。
  Team _withGameLineup(
    Team team,
    Player sp, {
    bool neutralOrder = false,
    bool useDH = false,
  }) {
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
    final result = planner.buildLineup(useDH: useDH);

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
      // DH 採用かつ DH 編成が成立した（投手が打順に居ない）ときだけ DH 試合扱い。
      usesDH: useDH && !result.lineup.any((p) => p.isPitcher),
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
      usesDH: strategy.useDH,
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
  ///
  /// **作戦画面表示用に、保存値ではなく「次の試合での体力」を返す。**
  /// 内部状態 `_pitcherFreshness` は「直近の試合実施後」の値だが、advanceDay の
  /// 冒頭で +`_freshnessRecoveryPerDay` 回復してから試合が始まるため、ユーザーが
  /// 作戦画面で見るべき値は「保存値 + 1日分の回復」になる。これを足さないと
  /// 「Day N に登板 → Day N+1 の作戦画面で 0 と表示 → でも実際は 17 で投げる」
  /// という表示と挙動の食い違いが起きる。エンジン内部のロジック（先発候補選定など）
  /// は `_pitcherFreshness` を直接読むのでこの補正は無関係。
  int pitcherFreshness(String pitcherId) {
    final saved = _pitcherFreshness[pitcherId] ?? 100;
    return (saved + _freshnessRecoveryPerDay).clamp(0, 100);
  }

  /// 投手の最終登板日参照（UI 用）
  int? pitcherLastStartDay(String pitcherId) =>
      _pitcherLastStartDay[pitcherId];

  /// 次の自チーム試合（currentDay+1）で、この投手が先発できるか。
  /// 次の自チーム試合（currentDay+1）で、この投手が先発できるか。
  ///
  /// 条件は AND:
  ///   1. 中4日（[_minDaysBetweenStarts] 日空ける）の登板間隔を満たす
  ///   2. 次の試合の登板時に体力が [_starterReadyThreshold] (= 100%) ある
  ///
  /// 判定は「最終**登板**日」（先発・救援問わず）ベース。これにより、
  /// ベンチ入りさせて救援で投げ続けている投手は間隔が空かず先発候補に挙がらず、
  /// ベンチ入りから外して休ませた投手は先発に指定できる。
  ///
  /// 体力条件は「次の試合での体力 = 保存値 + 1 日分の回復」で判定する
  /// （advanceDay が +[_freshnessRecoveryPerDay] してから試合を実行するため）。
  /// 中4日経過しても体力 100% に届かない（前回球数が多すぎた）場合は不可、
  /// 中4日で 100% に届く（前回球数を抑えた）場合は可になる。
  bool canStartNextGame(String pitcherId) {
    return starterDisabledReason(pitcherId) == null;
  }

  /// 次の試合でこの投手が先発できない理由を短い日本語で返す。
  /// 先発可能なら null。UI のピッカーで「なぜ選べないか」を表示するのに使う。
  String? starterDisabledReason(String pitcherId) {
    final saved = _pitcherFreshness[pitcherId] ?? 100;
    final nextGameFreshness =
        (saved + _freshnessRecoveryPerDay).clamp(0, 100);
    final tired = nextGameFreshness < _starterReadyThreshold;
    final tooSoon = _startsTooSoon(pitcherId);
    if (tired && tooSoon) return '登板間隔・体力 不足';
    if (tired) return '体力 不足';
    if (tooSoon) return '登板間隔 不足';
    return null;
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
      'enableDH': _enableDH,
      'unlockHour': _unlockHour,
      if (_lastUnlockAt != null)
        'lastUnlockAt': _lastUnlockAt!.toIso8601String(),
      'notificationsEnabled': _notificationsEnabled,
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
      // 前年最終スタメン・ベンチ入りの snapshot（次年 Day 1 で構成継承するため）。
      if (_lastSeasonFinalLineup != null)
        'lastSeasonFinalLineup': [
          for (final s in _lastSeasonFinalLineup!) s.toJson(),
        ],
      'lastSeasonUseDH': _lastSeasonUseDH,
      if (_lastSeasonStarterPitcherId != null)
        'lastSeasonStarterPitcherId': _lastSeasonStarterPitcherId,
      if (_lastSeasonActiveBenchIds != null)
        'lastSeasonActiveBenchIds': _lastSeasonActiveBenchIds,
      if (_lastSeasonActiveBullpenIds != null)
        'lastSeasonActiveBullpenIds': _lastSeasonActiveBullpenIds,
      // シーズン終了 → 編成画面確定 の間でアプリ再起動しても同じ候補が表示される
      // ように、保留中の編成プランを永続化（リセマラ防止）。
      if (_pendingOffseasonPlan != null)
        'pendingOffseasonPlan': _pendingOffseasonPlan!.toJson(),
      // 過去シーズンの年度別成績（古い順）。
      'seasonHistory': [for (final s in _seasonHistory) s.toJson()],
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
    // DH 採用可否。旧セーブ（v1.0、DH 概念なし＝投手が打つ）には存在しないので
    // 互換のため false 扱い。
    final enableDH = json['enableDH'] as bool? ?? false;
    // 1日1試合制約。旧セーブには存在しないので unlockHour=21 / lastUnlockAt=null 扱い。
    final unlockHour = json['unlockHour'] as int? ?? 21;
    final lastUnlockAtStr = json['lastUnlockAt'] as String?;
    final lastUnlockAt =
        lastUnlockAtStr == null ? null : DateTime.parse(lastUnlockAtStr);
    // 通知 ON/OFF。旧セーブには存在しないので true（デフォルト）扱い。
    final notificationsEnabled =
        json['notificationsEnabled'] as bool? ?? true;
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: json['myTeamId'] as String,
      gamesPerTeam: gamesPerTeam,
      offseasonProgressionEnabled: offseasonProgressionEnabled,
      enableDH: enableDH,
      unlockHour: unlockHour,
      lastUnlockAt: lastUnlockAt,
      notificationsEnabled: notificationsEnabled,
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

    // 5g'. 前年最終スタメン・ベンチ入り snapshot
    final lastLineup = json['lastSeasonFinalLineup'] as List?;
    controller._lastSeasonFinalLineup = lastLineup == null
        ? null
        : [
            for (final s in lastLineup)
              _LineupSlotSnapshot.fromJson(s as Map<String, dynamic>),
          ];
    controller._lastSeasonUseDH = json['lastSeasonUseDH'] as bool? ?? false;
    controller._lastSeasonStarterPitcherId =
        json['lastSeasonStarterPitcherId'] as String?;
    final lastBench = json['lastSeasonActiveBenchIds'] as List?;
    controller._lastSeasonActiveBenchIds = lastBench == null
        ? null
        : [for (final id in lastBench) id as String];
    final lastBullpen = json['lastSeasonActiveBullpenIds'] as List?;
    controller._lastSeasonActiveBullpenIds = lastBullpen == null
        ? null
        : [for (final id in lastBullpen) id as String];

    // 5h. 保留中の編成プラン（リセマラ防止用キャッシュ）
    final planJson = json['pendingOffseasonPlan'] as Map<String, dynamic>?;
    controller._pendingOffseasonPlan = planJson == null
        ? null
        : OffseasonPlan.fromJson(planJson, playerById);

    // 5i. 過去シーズンのスナップショット履歴
    final history = json['seasonHistory'] as List?;
    if (history != null) {
      for (final s in history) {
        controller._seasonHistory.add(SeasonSnapshot.fromJson(
          s as Map<String, dynamic>,
          playerById,
          teamById,
        ));
      }
    }

    return controller;
  }
}

/// 前シーズン最終スタメンの 1 打順スロットを保持する軽量レコード。
///
/// 守備位置 [position] を持つ通常スロットと、守備に就かない DH スロット
/// （[isDH] = true, [position] = null）の 2 種類。DH採用時、投手は打順に居ない
/// ので別途 [SeasonController._lastSeasonStarterPitcherId] に保存する。
class _LineupSlotSnapshot {
  final String playerId;
  final FieldPosition? position;
  final bool isDH;
  const _LineupSlotSnapshot(this.playerId, this.position, {this.isDH = false});

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        if (position != null) 'position': position!.index,
        if (isDH) 'isDH': true,
      };

  factory _LineupSlotSnapshot.fromJson(Map<String, dynamic> json) =>
      _LineupSlotSnapshot(
        json['playerId'] as String,
        json['position'] == null
            ? null
            : FieldPosition.values[json['position'] as int],
        isDH: json['isDH'] as bool? ?? false,
      );
}

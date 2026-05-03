import 'dart:math';

import '../generators/player_generator.dart';
import '../models/models.dart';
import '../season/player_season_stats.dart';
import 'offseason_plan.dart';

/// オフシーズンの CPU チーム再構築。
///
/// 1チームあたり野手 2 名 + 投手 2 名を引退させ、同数の新人を加入させる。
/// 引退判定は **年齢 25 歳超 + 能力低下** をスコア化し、高スコア順に選ぶ。
/// 野手は「各守備位置を最低 2 人が守れる」制約を満たす範囲で引退者を決める。
/// 投手は引退後にブルペンのロール（抑え/セットアッパー/中継ぎ等）を能力順に再アサインする。
///
/// 自チームについては UI 経由でユーザーが選択するため、別 API を用意:
///   - [buildOffseasonPlan]: 候補一覧を生成
///   - [applyUserSelection]: 選択結果をチームに反映 + スタメン再編成
class TeamRebuilder {
  static const int retireFieldersPerTeam = 2;
  static const int retirePitchersPerTeam = 2;
  static const int minPlayersPerPosition = 2;

  /// 引退候補に入る最低年齢（これ未満は能力が低くても引退しない）
  static const int minRetirementAge = 26;

  final PlayerGenerator playerGen;

  /// 前シーズンの野手成績。スタメン選定で OPS ボーナスとして参照する。null なら成績考慮なし。
  final Map<String, BatterSeasonStats>? previousBatterStats;

  /// 新人タイプの抽選などに使う乱数。playerGen と独立に持たせるのは、
  /// 「生成順を変えても抽選結果がブレない」ようにするため。
  final Random _random;

  TeamRebuilder({
    required this.playerGen,
    this.previousBatterStats,
    Random? random,
  }) : _random = random ?? Random();

  /// CPU 新人のタイプ重み: 大卒 40% / 高卒 30% / 社会人 30%。
  /// リーグ内に 3 タイプが混ざるよう適度に分散させる。
  RookieType _pickCpuRookieType() {
    final r = _random.nextDouble();
    if (r < 0.4) return RookieType.college;
    if (r < 0.7) return RookieType.highSchool;
    return RookieType.corporate;
  }

  /// `team.players[0..7]` の既定守備位置（catcher / first / .. / outfield × 3）。
  /// オフシーズンのスタメン再編成や試合時の LineupPlanner と共通の構造。
  static const List<DefensePosition> _starterDefaultPositions = [
    DefensePosition.catcher,
    DefensePosition.first,
    DefensePosition.second,
    DefensePosition.third,
    DefensePosition.shortstop,
    DefensePosition.outfield,
    DefensePosition.outfield,
    DefensePosition.outfield,
  ];

  /// CPU チーム全員の引退・新人加入・スタメン再編成・投手ロール再編を実行。
  /// 自チーム ([myTeamId]) は対象外。
  /// 引退選手の id リストを返す（呼び出し側で statistics 参照のクリーン用に使える）
  List<String> rebuildCpuTeams(List<Team> teams, String myTeamId) {
    final retired = <String>[];
    for (final team in teams) {
      if (team.id == myTeamId) continue;
      // 前年スタメンの id を「再編前」のスナップショットとして保存
      // （引退・加入で team.players が変わる前に取得して、再編成時の継続性ボーナスに使う）
      final previousStarterIds =
          team.players.take(8).map((p) => p.id).toSet();

      retired.addAll(_retireAndReplaceFielders(team));
      retired.addAll(_retireAndReplacePitchers(team));
      _rebalanceStarters(team, previousStarterIds);
      _reorganizeBullpenRoles(team);
    }
    return retired;
  }

  /// 引退・加入が終わったチームの野手プール（`players[0..7]` + `bench`）から、
  /// 各ポジションのスタメンを改めて選び直す。
  ///
  /// スコア = 打撃力 + 守備力 + 前年スタメン継続性 + 前年 OPS ボーナス
  /// - 守備位置を守れない選手はそのスロットの候補にならない（最終フォールバックを除く）
  /// - 前年スタメンは「継続性ボーナス」で同条件なら維持されやすい
  /// - 前年 OPS が高い選手は打撃ボーナスが乗る
  ///
  /// 結果: 上位 8 人がスタメン (`players[0..7]`)、残りはベンチ。
  /// 投手スロット (`players[8]`) は触らない。
  void _rebalanceStarters(Team team, Set<String> previousStarterIds) {
    if (team.players.length < 9) return;

    // 投手スロットを退避
    final pitcherSlot = team.players[8];

    // 全野手プール
    final pool = <Player>[
      ...team.players.take(8),
      ...team.bench,
    ];

    final newStarters = <Player?>[for (int i = 0; i < 8; i++) null];
    final used = <String>{};

    // 「希少なポジションから先に決める」ことで、限られた候補を取り合わずに済む。
    // 通常 catcher / shortstop が候補数の少ない順なので先に処理する。
    final slotOrder = List<int>.generate(8, (i) => i)
      ..sort((a, b) {
        int countCandidates(int slot) {
          final pos = _starterDefaultPositions[slot];
          return pool.where((p) => p.canPlay(pos)).length;
        }

        return countCandidates(a).compareTo(countCandidates(b));
      });

    for (final i in slotOrder) {
      final pos = _starterDefaultPositions[i];
      Player? best;
      double bestScore = -double.infinity;
      for (final p in pool) {
        if (used.contains(p.id)) continue;
        if (!p.canPlay(pos)) continue;
        final score = _starterScore(p, pos, previousStarterIds);
        if (score > bestScore) {
          bestScore = score;
          best = p;
        }
      }
      if (best == null) {
        // フォールバック: 守れる選手がいない異常系。守れない選手から最良を選ぶ
        for (final p in pool) {
          if (used.contains(p.id)) continue;
          final score = _starterScore(p, pos, previousStarterIds);
          if (score > bestScore) {
            bestScore = score;
            best = p;
          }
        }
      }
      if (best != null) {
        newStarters[i] = best;
        used.add(best.id);
      }
    }

    final benchPlayers =
        pool.where((p) => !used.contains(p.id)).toList();

    // team.players と team.bench を in-place で書き換え
    // （Schedule など外部から保持されている list 参照を保つため）
    team.players
      ..clear()
      ..addAll(newStarters.cast<Player>())
      ..add(pitcherSlot);
    team.bench
      ..clear()
      ..addAll(benchPlayers);

    // 既存の defenseAlignment があれば、新スタメンに合わせてリフレッシュする
    // （古いマップの値が新スタメンに含まれていない場合を防ぐ）
    final align = team.defenseAlignment;
    if (align != null) {
      align.clear();
      for (int i = 0; i < 8; i++) {
        align[_slotFieldPositions[i]] = newStarters[i]!;
      }
      align[FieldPosition.pitcher] = pitcherSlot;
    }
  }

  /// `team.players[i]` のスロットに対応する具体的な [FieldPosition]。
  /// 外野は左 / 中 / 右の 3 枠に展開される。
  static const List<FieldPosition> _slotFieldPositions = [
    FieldPosition.catcher,
    FieldPosition.first,
    FieldPosition.second,
    FieldPosition.third,
    FieldPosition.shortstop,
    FieldPosition.left,
    FieldPosition.center,
    FieldPosition.right,
  ];

  /// 指定ポジションのスタメンスコア。値が大きいほどスタメンに選ばれやすい。
  /// 構成:
  ///   - 打撃力（meet + power*0.8 + eye*0.4）
  ///   - 守備力（fielding[pos] * 0.6）
  ///   - 前年スタメン継続性ボーナス: +1.5
  ///   - 前年 OPS ボーナス: (OPS - .700) * 8、最低 30 打席必要
  double _starterScore(
    Player p,
    DefensePosition pos,
    Set<String> previousStarterIds,
  ) {
    final meet = (p.meet ?? 5).toDouble();
    final power = (p.power ?? 5).toDouble();
    final eye = (p.eye ?? 5).toDouble();
    final batting = meet + power * 0.8 + eye * 0.4;

    final fielding = p.fielding?[pos] ?? 0;
    final defense = fielding * 0.6;

    final continuity = previousStarterIds.contains(p.id) ? 1.5 : 0.0;

    double formBonus = 0.0;
    final stats = previousBatterStats?[p.id];
    if (stats != null && stats.atBats >= 30) {
      formBonus = (stats.ops - 0.700) * 8.0;
    }

    return batting + defense + continuity + formBonus;
  }

  // ---------------------------------------------------
  // 野手の引退・新人加入
  // ---------------------------------------------------

  List<String> _retireAndReplaceFielders(Team team) {
    final fielders = <Player>[
      ...team.players.where((p) => !p.isPitcher),
      ...team.bench,
    ];
    // 引退スコア順に並べる（高スコア = 引退候補）
    fielders.sort(
        (a, b) => _retirementScore(b).compareTo(_retirementScore(a)));

    // 各 DefensePosition について「守れる野手数」を集計
    final canPlayCount = <DefensePosition, int>{
      for (final pos in DefensePosition.values) pos: 0,
    };
    for (final p in fielders) {
      for (final pos in DefensePosition.values) {
        if (p.canPlay(pos)) canPlayCount[pos] = canPlayCount[pos]! + 1;
      }
    }

    final retiredIds = <String>[];
    final retiredPlayers = <Player>[];
    for (final candidate in fielders) {
      if (retiredPlayers.length >= retireFieldersPerTeam) break;
      if (_retirementScore(candidate) <= 0) break; // スコアが 0 以下 = 引退対象外
      // 引退してもポジション制約を満たすか
      bool wouldBreakConstraint = false;
      for (final pos in DefensePosition.values) {
        if (candidate.canPlay(pos)) {
          if (canPlayCount[pos]! - 1 < minPlayersPerPosition) {
            wouldBreakConstraint = true;
            break;
          }
        }
      }
      if (wouldBreakConstraint) continue;
      // 引退確定
      retiredPlayers.add(candidate);
      retiredIds.add(candidate.id);
      for (final pos in DefensePosition.values) {
        if (candidate.canPlay(pos)) {
          canPlayCount[pos] = canPlayCount[pos]! - 1;
        }
      }
    }

    // 引退者を新人野手と入れ替え。新人は自分独自の守備プロファイルを持つ
    // （引退者のポジションは継承しない＝個性が出る）。
    // スロット位置との整合性は LineupPlanner が吸収する：
    // 守れない選手がスタメンスロットにいれば、ベンチから守れる選手が
    // 自動的に昇格して新人がベンチに回る。
    for (final retiredPlayer in retiredPlayers) {
      final rookie = playerGen.generateRookieFielder(
        number: retiredPlayer.number,
        type: _pickCpuRookieType(),
      );
      _replacePlayerInTeam(team, retiredPlayer, rookie);
    }

    return retiredIds;
  }

  // ---------------------------------------------------
  // 投手の引退・新人加入
  // ---------------------------------------------------

  List<String> _retireAndReplacePitchers(Team team) {
    final pitchers = <Player>[
      ...team.startingRotation,
      ...team.bullpen,
    ];
    pitchers.sort(
        (a, b) => _retirementScore(b).compareTo(_retirementScore(a)));

    final retiredIds = <String>[];
    final retiredPlayers = <Player>[];
    for (final candidate in pitchers) {
      if (retiredPlayers.length >= retirePitchersPerTeam) break;
      if (_retirementScore(candidate) <= 0) break;
      retiredPlayers.add(candidate);
      retiredIds.add(candidate.id);
    }

    for (final retiredPlayer in retiredPlayers) {
      final wasStarter = team.startingRotation
          .any((p) => p.id == retiredPlayer.id);
      final rookie = playerGen.generateRookiePitcher(
        number: retiredPlayer.number,
        isStarter: wasStarter,
        reliefRole: wasStarter ? null : retiredPlayer.reliefRole,
        type: _pickCpuRookieType(),
      );
      _replacePlayerInTeam(team, retiredPlayer, rookie);
    }

    return retiredIds;
  }

  // ---------------------------------------------------
  // 投手ロール再編（ブルペン内で能力順に再アサイン）
  // ---------------------------------------------------

  /// ブルペン投手を能力スコア順にソートし、ロールを再アサインする。
  /// ロール構成は維持: closer 1 / setup 1 / middle 2 / situational 1 / long 1 / mopUp 2
  /// situational（ワンポイント）は左投手を優先、いなければスキップして他のロールに回す。
  /// long（ロング）は stamina の高い投手を優先。
  void _reorganizeBullpenRoles(Team team) {
    if (team.bullpen.length < 2) return;

    final pitchers = [...team.bullpen];
    pitchers.sort((a, b) => _abilityScore(b).compareTo(_abilityScore(a)));

    // ロールの新規割り当てをコンピュート
    final assignments = <Player, ReliefRole>{};
    final remaining = [...pitchers];

    // 能力 1位 = 抑え
    if (remaining.isNotEmpty) {
      final p = remaining.removeAt(0);
      assignments[p] = ReliefRole.closer;
    }
    // 2位 = セットアッパー
    if (remaining.isNotEmpty) {
      final p = remaining.removeAt(0);
      assignments[p] = ReliefRole.setup;
    }
    // ロング: 残りのうち stamina 最高（10 以下なら採用、極端に低い者がいない時のフォールバック）
    Player? longCandidate;
    int longIdx = -1;
    int bestStamina = -1;
    for (int i = 0; i < remaining.length; i++) {
      final s = remaining[i].stamina ?? 5;
      if (s > bestStamina) {
        bestStamina = s;
        longCandidate = remaining[i];
        longIdx = i;
      }
    }
    if (longCandidate != null && bestStamina >= 6) {
      assignments[longCandidate] = ReliefRole.long;
      remaining.removeAt(longIdx);
    }
    // ワンポイント: 残りの左投手を優先
    Player? situational;
    int sitIdx = -1;
    for (int i = 0; i < remaining.length; i++) {
      if (remaining[i].effectiveThrows == Handedness.left) {
        situational = remaining[i];
        sitIdx = i;
        break;
      }
    }
    if (situational != null) {
      assignments[situational] = ReliefRole.situational;
      remaining.removeAt(sitIdx);
    }
    // 中継ぎを 2 人（残りの上位）
    int middleAssigned = 0;
    while (remaining.isNotEmpty && middleAssigned < 2) {
      final p = remaining.removeAt(0);
      assignments[p] = ReliefRole.middle;
      middleAssigned++;
    }
    // 残り全員 = 敗戦処理
    for (final p in remaining) {
      assignments[p] = ReliefRole.mopUp;
    }

    // ロール変更が発生する場合のみ Player を差し替え（id 維持、reliefRole のみ変える）
    for (final entry in assignments.entries) {
      final p = entry.key;
      final newRole = entry.value;
      if (p.reliefRole == newRole) continue;
      final updated = _withReliefRole(p, newRole);
      _replacePlayerInTeam(team, p, updated);
    }
  }

  /// 同一 id・同一能力で reliefRole だけを差し替えた Player を返す。
  Player _withReliefRole(Player p, ReliefRole role) {
    return Player(
      id: p.id,
      name: p.name,
      number: p.number,
      age: p.age,
      averageSpeed: p.averageSpeed,
      fastball: p.fastball,
      control: p.control,
      stamina: p.stamina,
      slider: p.slider,
      curve: p.curve,
      splitter: p.splitter,
      changeup: p.changeup,
      meet: p.meet,
      power: p.power,
      speed: p.speed,
      eye: p.eye,
      arm: p.arm,
      lead: p.lead,
      fielding: p.fielding,
      throws: p.throws,
      bats: p.bats,
      reliefRole: role,
    );
  }

  // ---------------------------------------------------
  // 共通ヘルパ
  // ---------------------------------------------------

  /// 引退スコア。高いほど引退候補（年齢が高く能力が低い）。
  /// 25 歳以下は -1（引退対象外）を返す。
  double _retirementScore(Player p) {
    if (p.age < minRetirementAge) return -1;
    final ability = _abilityScore(p);
    return (p.age - 25) * 1.0 + (10 - ability) * 1.5;
  }

  /// 1〜10 スケールの能力スコア。野手は打撃 + 走塁系の平均、投手は球速 + 制球 + 球質 + 球種の平均。
  double _abilityScore(Player p) {
    if (p.isPitcher) {
      final values = <double>[
        _speedToScale(p.averageSpeed),
        (p.fastball ?? 5).toDouble(),
        (p.control ?? 5).toDouble(),
        (p.stamina ?? 5).toDouble(),
      ];
      final pitches = <int>[
        if (p.slider != null) p.slider!,
        if (p.curve != null) p.curve!,
        if (p.splitter != null) p.splitter!,
        if (p.changeup != null) p.changeup!,
      ];
      if (pitches.isNotEmpty) {
        values.add(
            pitches.reduce((a, b) => a > b ? a : b).toDouble());
      }
      return values.reduce((a, b) => a + b) / values.length;
    } else {
      final values = <double>[
        (p.meet ?? 5).toDouble(),
        (p.power ?? 5).toDouble(),
        (p.speed ?? 5).toDouble(),
        (p.eye ?? 5).toDouble(),
        (p.arm ?? 5).toDouble(),
      ];
      return values.reduce((a, b) => a + b) / values.length;
    }
  }

  /// 球速 (km/h) を 1〜10 のスケールに変換
  double _speedToScale(int? kmh) {
    if (kmh == null) return 5;
    return ((kmh - 130) / 30.0 * 10).clamp(1.0, 10.0);
  }

  /// チーム内の retired Player を replacement に in-place で置換する。
  /// players / startingRotation / bullpen / bench / defenseAlignment 全てが対象。
  void _replacePlayerInTeam(Team team, Player retired, Player replacement) {
    void swap(List<Player> list) {
      for (int i = 0; i < list.length; i++) {
        if (list[i].id == retired.id) list[i] = replacement;
      }
    }

    swap(team.players);
    swap(team.startingRotation);
    swap(team.bullpen);
    swap(team.bench);

    final align = team.defenseAlignment;
    if (align != null) {
      final keys = <FieldPosition>[];
      align.forEach((k, v) {
        if (v.id == retired.id) keys.add(k);
      });
      for (final k in keys) {
        align[k] = replacement;
      }
    }
  }

  // ---------------------------------------------------
  // 自チーム向け API
  // ---------------------------------------------------

  /// 自チームの引退候補・新人候補リストを生成する。
  /// チームの状態は変更しない。
  ///
  /// 引退候補は野手・投手それぞれ全選手をスコア降順で含み、UI 側で表示する。
  /// 推奨選択は CPU と同じ条件: 26 歳以上 + スコア > 0 の上位最大 [retireFieldersPerTeam] 名。
  ///
  /// 新人候補は野手・投手それぞれ [rookieCandidatesPerType] × 3 タイプ = 6 名生成する
  /// （高卒 / 大卒 / 社会人 を各 [rookieCandidatesPerType] 名）。
  /// 推奨は能力スコア上位を選ぶ（基本的には大卒・社会人寄りに偏るが、
  /// まれな高卒の即戦力もここで拾える）。
  OffseasonPlan buildOffseasonPlan(
    Team team, {
    int rookieCandidatesPerType = 2,
  }) {
    final fielders = <Player>[
      ...team.players.where((p) => !p.isPitcher),
      ...team.bench,
    ]..sort(
        (a, b) => _retirementScore(b).compareTo(_retirementScore(a)),
      );

    final pitchers = <Player>[
      ...team.startingRotation,
      ...team.bullpen,
    ]..sort(
        (a, b) => _retirementScore(b).compareTo(_retirementScore(a)),
      );

    final recommendedRetireFielders = _recommendedRetirements(
      fielders,
      retireFieldersPerTeam,
    );
    final recommendedRetirePitchers = _recommendedRetirements(
      pitchers,
      retirePitchersPerTeam,
    );

    // 新人は背番号未確定のままプール生成（commit 時に引退者の番号を引き継ぐ）。
    // 先発寄り（reliefRole = null）に生成し、救援に振られる場合は
    // [applyUserSelection] で reliefRole を上書きする。
    final rookieFielders = <RookieCandidate>[
      for (final type in RookieType.values)
        for (int i = 0; i < rookieCandidatesPerType; i++)
          RookieCandidate(
            player:
                playerGen.generateRookieFielder(number: 0, type: type),
            type: type,
          ),
    ];
    final rookiePitchers = <RookieCandidate>[
      for (final type in RookieType.values)
        for (int i = 0; i < rookieCandidatesPerType; i++)
          RookieCandidate(
            player:
                playerGen.generateRookiePitcher(number: 0, type: type),
            type: type,
          ),
    ];

    // 推奨新人: 引退人数に合わせて、能力スコア降順で上位を選ぶ。
    // _abilityScore は野手・投手両方に対応しているのでそのまま使える。
    List<RookieCandidate> topByAbility(
        List<RookieCandidate> pool, int count) {
      final sorted = [...pool]..sort((a, b) =>
          _abilityScore(b.player).compareTo(_abilityScore(a.player)));
      return sorted.take(count).toList();
    }

    return OffseasonPlan(
      retireCandidateFielders: fielders,
      retireCandidatePitchers: pitchers,
      rookieFielderCandidates: rookieFielders,
      rookiePitcherCandidates: rookiePitchers,
      recommendedRetireFielderIds:
          recommendedRetireFielders.map((p) => p.id).toList(),
      recommendedRetirePitcherIds:
          recommendedRetirePitchers.map((p) => p.id).toList(),
      recommendedTakeFielderIds: topByAbility(
              rookieFielders, recommendedRetireFielders.length)
          .map((c) => c.id)
          .toList(),
      recommendedTakePitcherIds: topByAbility(
              rookiePitchers, recommendedRetirePitchers.length)
          .map((c) => c.id)
          .toList(),
    );
  }

  /// CPU と同じ「26 歳以上 + スコア > 0 の上位 [count] 名」を返す。
  /// ただしポジション制約（最低 2 人/位置）は守らない（UI 側でユーザーが調整できるため）。
  List<Player> _recommendedRetirements(List<Player> sorted, int count) {
    final picks = <Player>[];
    for (final p in sorted) {
      if (picks.length >= count) break;
      if (_retirementScore(p) <= 0) break;
      picks.add(p);
    }
    return picks;
  }

  /// ユーザー選択をチームに反映する。
  ///
  /// [previousStarterIds] は再編成時の前年スタメン継続性ボーナスに使う
  /// （`SeasonController` 側で commit 直前にスナップショットを取る）。
  ///
  /// 引退・新人のペアリングは順序ベース:
  /// `selection.retireFielderIds[i]` を引退させ、`selection.takeFielderIds[i]` を加入させる。
  /// 新人は引退者の背番号と先発／救援ロールを引き継ぐ。
  void applyUserSelection(
    Team team,
    OffseasonPlan plan,
    OffseasonSelection selection,
    Set<String> previousStarterIds,
  ) {
    if (!selection.isValid) {
      throw ArgumentError(
        '引退と新人の人数が一致していません: '
        'fielder ${selection.retireFielderIds.length} retire / '
        '${selection.takeFielderIds.length} take, '
        'pitcher ${selection.retirePitcherIds.length} retire / '
        '${selection.takePitcherIds.length} take',
      );
    }

    Player findFielderRetiree(String id) =>
        plan.retireCandidateFielders.firstWhere(
          (p) => p.id == id,
          orElse: () =>
              throw ArgumentError('引退候補に存在しない野手 id: $id'),
        );
    Player findPitcherRetiree(String id) =>
        plan.retireCandidatePitchers.firstWhere(
          (p) => p.id == id,
          orElse: () =>
              throw ArgumentError('引退候補に存在しない投手 id: $id'),
        );
    Player findRookieFielder(String id) =>
        plan.rookieFielderCandidates
            .firstWhere(
              (c) => c.id == id,
              orElse: () =>
                  throw ArgumentError('新人候補に存在しない野手 id: $id'),
            )
            .player;
    Player findRookiePitcher(String id) =>
        plan.rookiePitcherCandidates
            .firstWhere(
              (c) => c.id == id,
              orElse: () =>
                  throw ArgumentError('新人候補に存在しない投手 id: $id'),
            )
            .player;

    for (int i = 0; i < selection.retireFielderIds.length; i++) {
      final retired = findFielderRetiree(selection.retireFielderIds[i]);
      final rookie = findRookieFielder(selection.takeFielderIds[i]);
      final replacement = _withNumber(rookie, retired.number);
      _replacePlayerInTeam(team, retired, replacement);
    }

    for (int i = 0; i < selection.retirePitcherIds.length; i++) {
      final retired = findPitcherRetiree(selection.retirePitcherIds[i]);
      final rookie = findRookiePitcher(selection.takePitcherIds[i]);
      final wasStarter =
          team.startingRotation.any((p) => p.id == retired.id);
      Player replacement = _withNumberAndRole(
        rookie,
        retired.number,
        wasStarter ? null : (retired.reliefRole ?? ReliefRole.middle),
      );
      _replacePlayerInTeam(team, retired, replacement);
    }

    _rebalanceStarters(team, previousStarterIds);
    _reorganizeBullpenRoles(team);
  }

  /// id・能力はそのまま、背番号だけを差し替えた Player を返す。
  Player _withNumber(Player p, int number) {
    return _withNumberAndRole(p, number, p.reliefRole);
  }

  /// id・能力はそのまま、背番号とリリーフロールを差し替えた Player を返す。
  Player _withNumberAndRole(Player p, int number, ReliefRole? role) {
    return Player(
      id: p.id,
      name: p.name,
      number: number,
      age: p.age,
      averageSpeed: p.averageSpeed,
      fastball: p.fastball,
      control: p.control,
      stamina: p.stamina,
      slider: p.slider,
      curve: p.curve,
      splitter: p.splitter,
      changeup: p.changeup,
      meet: p.meet,
      power: p.power,
      speed: p.speed,
      eye: p.eye,
      arm: p.arm,
      lead: p.lead,
      fielding: p.fielding,
      throws: p.throws,
      bats: p.bats,
      reliefRole: role,
    );
  }
}

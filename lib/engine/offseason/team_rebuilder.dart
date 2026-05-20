import 'dart:math';

import '../generators/player_generator.dart';
import '../models/models.dart';
import '../season/player_season_stats.dart';
import 'offseason_plan.dart';

/// オフシーズンの CPU チーム再構築。
///
/// 1チームあたり野手 3 名 + 投手 3 名を引退させ、同数の新人を加入させる
/// （40 人ロスター化に合わせ 2/2 → 3/3。ROSTER_EXPANSION_PLAN.md フェーズC）。
/// 引退判定は **年齢 25 歳超 + 能力低下** をスコア化し、高スコア順に選ぶ。
/// 野手は「各守備位置を最低 2 人が守れる」制約を満たす範囲で引退者を決める。
/// 投手は引退後にブルペンのロール（抑え/セットアッパー/中継ぎ等）を能力順に再アサインする。
///
/// 自チームについては UI 経由でユーザーが選択するため、別 API を用意:
///   - [buildOffseasonPlan]: 候補一覧を生成
///   - [applyUserSelection]: 選択結果をチームに反映 + スタメン再編成
class TeamRebuilder {
  static const int retireFieldersPerTeam = 3;
  static const int retirePitchersPerTeam = 3;

  /// 外国人選手の強制離脱率（シーズン終了時、各外国人について独立判定）。
  /// 1/5 = キャリア平均 5 年で離脱する目安。優秀な選手も含めて確率は一律。
  static const double foreignDepartureChance = 0.20;

  /// 引退候補に入る最低年齢（これ未満は能力が低くても引退しない）
  static const int minRetirementAge = 26;

  /// 各ポジションで最低限守れる選手数（CPU 自動再編で必ず維持される）。
  /// 外野は試合中 3 人配置するため厚めに必要。
  /// この水準を割らないよう引退判定をブロックし、新人加入で不足ポジションを補う。
  static int minPlayersForPosition(DefensePosition pos) =>
      pos == DefensePosition.outfield ? 5 : 2;

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

      retired.addAll(_handleForeignDepartures(team));
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
  // 外国人選手の強制離脱と新外国人での補充
  // ---------------------------------------------------

  /// 各シーズン終了時、チーム内の外国人選手を 1/5 の確率で独立に強制離脱させる。
  /// 離脱した枠は同じ守備位置タイプ（野手 or 投手）の新外国人で即補充する。
  /// 補充選手は能力フラット分布で当たり外れ、ユーザーから見ると賭け。
  /// 戻り値: 離脱した外国人選手の id リスト。
  List<String> _handleForeignDepartures(Team team) {
    final retiredIds = <String>[];
    // チーム内の外国人選手を一意収集（id ベース）
    final seen = <String>{};
    final foreigners = <Player>[];
    for (final p in [
      ...team.players,
      ...team.startingRotation,
      ...team.bullpen,
      ...team.bench,
    ]) {
      if (!p.isForeign) continue;
      if (!seen.add(p.id)) continue;
      foreigners.add(p);
    }

    for (final f in foreigners) {
      if (_random.nextDouble() >= foreignDepartureChance) continue;
      // 離脱 → 新外国人で同じ枠を補充
      final newForeign = f.isPitcher
          ? playerGen.generateForeignPitcher(
              number: f.number,
              pitcherRole: f.pitcherRole ?? PitcherRole.starter,
            )
          : playerGen.generateForeignFielder(number: f.number);
      _replacePlayerInTeam(team, f, newForeign);
      retiredIds.add(f.id);
    }
    return retiredIds;
  }

  // ---------------------------------------------------
  // 野手の引退・新人加入
  // ---------------------------------------------------

  List<String> _retireAndReplaceFielders(Team team) {
    // 外国人選手は別ロジック（_handleForeignDepartures）で離脱処理されているので、
    // 日本人選手の引退枠からは除外する。混ぜると外国人が日本人新人で置き換わって
    // 外国人枠が消失してしまう。
    final fielders = <Player>[
      ...team.players.where((p) => !p.isPitcher && !p.isForeign),
      ...team.bench.where((p) => !p.isForeign),
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
          if (canPlayCount[pos]! - 1 < minPlayersForPosition(pos)) {
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

    // 引退者を新人野手と入れ替え。各引退で減ったポジションが最低ラインを
    // 下回るなら、新人はそのポジションを守れる選手として生成（補充重視）。
    // それ以外の引退はランダム守備プロファイル（新人の個性を尊重）。
    for (final retiredPlayer in retiredPlayers) {
      final shortage = _shortagePositionForRetiree(canPlayCount, retiredPlayer);
      final rookie = playerGen.generateRookieFielder(
        number: retiredPlayer.number,
        type: _pickCpuRookieType(),
        forcedPositions: shortage == null ? null : [shortage],
      );
      // 新人が守れる位置を canPlayCount に加算（次の新人選択の参照用）
      for (final pos in DefensePosition.values) {
        if (rookie.canPlay(pos)) canPlayCount[pos] = canPlayCount[pos]! + 1;
      }
      _replacePlayerInTeam(team, retiredPlayer, rookie);
    }

    return retiredIds;
  }

  /// 引退者が守っていたポジションで、引退後に最低ラインを下回るものを返す。
  /// 複数あれば外野を優先（最も枯渇しやすいため）、なければ null。
  DefensePosition? _shortagePositionForRetiree(
    Map<DefensePosition, int> currentCount,
    Player retiredPlayer,
  ) {
    DefensePosition? best;
    int bestDeficit = 0;
    for (final pos in DefensePosition.values) {
      if (!retiredPlayer.canPlay(pos)) continue;
      final deficit = minPlayersForPosition(pos) - currentCount[pos]!;
      if (deficit <= 0) continue;
      // 外野不足を優先（試合中 3 人配置が必要なため）
      final priority =
          deficit * 10 + (pos == DefensePosition.outfield ? 1 : 0);
      if (priority > bestDeficit) {
        bestDeficit = priority;
        best = pos;
      }
    }
    return best;
  }

  // ---------------------------------------------------
  // 投手の引退・新人加入
  // ---------------------------------------------------

  List<String> _retireAndReplacePitchers(Team team) {
    // 外国人投手は別ロジックで離脱処理済み。日本人引退枠からは除外する。
    final pitchers = <Player>[
      ...team.startingRotation.where((p) => !p.isForeign),
      ...team.bullpen.where((p) => !p.isForeign),
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
        pitcherRole: wasStarter ? null : retiredPlayer.pitcherRole,
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
  /// 12 人ブルペンのロール構成: closer 1 / setup 2 / long 2 / situational 1 /
  /// middle 4 / mopUp 残り（標準12人なら2）。TeamGenerator の生成構成に揃える。
  /// situational（ワンポイント）は左投手を優先、いなければスキップして他のロールに回す。
  /// 能力上位から closer → setup → long の順に充て、中継ぎは残りの上位から埋める。
  /// ブルペンが12人未満（旧データ・テスト）の場合は枠が埋まらないだけで破綻しない。
  void _reorganizeBullpenRoles(Team team) {
    if (team.bullpen.length < 2) return;

    final remaining = [...team.bullpen]
      ..sort((a, b) => _abilityScore(b).compareTo(_abilityScore(a)));
    final assignments = <Player, PitcherRole>{};

    // 能力上位から quota 人ぶん role を割り当てるヘルパ。
    void assignTop(PitcherRole role, int quota) {
      for (int i = 0; i < quota && remaining.isNotEmpty; i++) {
        assignments[remaining.removeAt(0)] = role;
      }
    }

    assignTop(PitcherRole.closer, 1); // 1位 = 抑え
    assignTop(PitcherRole.setup, 2); // 2〜3位 = セットアッパー
    assignTop(PitcherRole.long, 2); // 次点2人 = ロング
    // ワンポイント: 残りの左投手を優先（いなければ枠を空けたまま中継ぎに回す）
    final sitIdx =
        remaining.indexWhere((p) => p.effectiveThrows == Handedness.left);
    if (sitIdx >= 0) {
      assignments[remaining.removeAt(sitIdx)] = PitcherRole.situational;
    }
    assignTop(PitcherRole.middle, 4); // 中継ぎ4人（残りの上位）
    // 残り全員 = 敗戦処理
    for (final p in remaining) {
      assignments[p] = PitcherRole.mopUp;
    }

    // ロール変更が発生する場合のみ Player を差し替え（id 維持、pitcherRole のみ変える）
    for (final entry in assignments.entries) {
      final p = entry.key;
      final newRole = entry.value;
      if (p.pitcherRole == newRole) continue;
      _replacePlayerInTeam(team, p, p.withPitcherRole(newRole));
    }
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
    // 外国人選手は自動離脱ロジック（commitOffseason 内の
    // applyForeignDeparturesToMyTeam）で別途処理されるので、引退候補リストには
    // 含めない。混ぜると日本人新人で置き換わって外国人枠が消失してしまう。
    final fielders = <Player>[
      ...team.players.where((p) => !p.isPitcher && !p.isForeign),
      ...team.bench.where((p) => !p.isForeign),
    ]..sort(
        (a, b) => _retirementScore(b).compareTo(_retirementScore(a)),
      );

    final pitchers = <Player>[
      ...team.startingRotation.where((p) => !p.isForeign),
      ...team.bullpen.where((p) => !p.isForeign),
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
    // 先発寄り（pitcherRole = null）に生成し、救援に振られる場合は
    // [applyUserSelection] で pitcherRole を上書きする。
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
  /// 自チームに対して外国人選手の強制離脱と新外国人での補充を実行する。
  /// CPU と同じロジック（[_handleForeignDepartures]）を public 露出したもの。
  /// 戻り値は離脱した外国人選手の id リスト（UI で「離脱: ○○」と通知する用）。
  List<String> applyForeignDeparturesToMyTeam(Team team) {
    return _handleForeignDepartures(team);
  }

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
      // 自チームの投手ロールはユーザーが推測ゲームの中で決めるもの。
      // 引退者のロールを新人に継承させると「引退した抑えの後継＝抑え」と
      // 能力に頼らず役割が決まってしまうので、新人は中立なロール（先発枠の
      // 後継＝先発、救援枠の後継＝中継ぎ）で加入する。既存投手のロールも
      // ここでは触らない（_reorganizeBullpenRoles は呼ばない）。
      Player replacement = _withNumberAndRole(
        rookie,
        retired.number,
        wasStarter ? PitcherRole.starter : PitcherRole.middle,
      );
      _replacePlayerInTeam(team, retired, replacement);
    }

    // スタメン野手は再編するが、救援ロールはユーザー設定を維持するため
    // _reorganizeBullpenRoles は呼ばない（CPU チームのみ rebuildCpuTeams で再編）。
    _rebalanceStarters(team, previousStarterIds);
  }

  /// id・能力はそのまま、背番号だけを差し替えた Player を返す。
  Player _withNumber(Player p, int number) {
    return _withNumberAndRole(p, number, p.pitcherRole);
  }

  /// id・能力はそのまま、背番号とリリーフロールを差し替えた Player を返す。
  /// 球種（shoot/cutter/sinker 含む全種）・ポテンシャルもすべて維持する。
  Player _withNumberAndRole(Player p, int number, PitcherRole? role) {
    return Player(
      id: p.id,
      name: p.name,
      number: number,
      age: p.age,
      averageSpeed: p.averageSpeed,
      fastball: p.fastball,
      control: p.control,
      slider: p.slider,
      curve: p.curve,
      splitter: p.splitter,
      changeup: p.changeup,
      shoot: p.shoot,
      cutter: p.cutter,
      sinker: p.sinker,
      meet: p.meet,
      power: p.power,
      speed: p.speed,
      eye: p.eye,
      arm: p.arm,
      fielding: p.fielding,
      throws: p.throws,
      bats: p.bats,
      pitcherRole: role,
      potentials: p.potentials,
      potentialFielding: p.potentialFielding,
      potentialAverageSpeed: p.potentialAverageSpeed,
      isForeign: p.isForeign,
    );
  }
}

import 'dart:math';

import '../generators/player_generator.dart';
import '../generators/team_generator.dart';
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

  /// 1 チームに常時配置する外国人選手の理想枠（SPEC §4.1）。
  /// 投手 2（先発ローテ）+ 野手 2（控え）= 計 4 名。NPB の通常運用に近づける。
  /// `_applyForeignChanges` で「現状 - 離脱 + 獲得 = この枠数」を満たす整合性を要求する。
  static const int targetForeignPitchers = 2;
  static const int targetForeignFielders = 2;

  /// 引退候補に入る最低年齢（これ未満は能力が低くても引退しない）
  static const int minRetirementAge = 26;

  /// 各ポジションで最低限守れる選手数（CPU 自動再編で必ず維持される）。
  /// 内野・捕手は 3 人、外野は試合中 3 人配置するため 8 人を要求する。
  /// この水準を割らないよう引退判定をブロックし、新人加入で不足ポジションを補う。
  ///
  /// 20 名ロスター (日本人 18 + 外国人 2) で守備人数は概ね:
  ///   捕手 3 / 一塁 5-6 / 二塁 3 / 三塁 4 / 遊撃 3 / 外野 8-9
  /// と初期生成時点で制約をぎりぎり満たす。経年で薄くなったら新人で補強する。
  static int minPlayersForPosition(DefensePosition pos) =>
      pos == DefensePosition.outfield ? 8 : 3;

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
      _reassignPitcherRoles(team);
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
      if (_random.nextDouble() >= _cpuForeignReleaseChance(f)) continue;
      // 離脱 → 新外国人で同じ枠を補充。
      // 残るチーム内外国人と同苗字にならないよう、現役外国人の苗字を渡す。
      final remainingSurnames = <String>{
        for (final other in foreigners)
          if (other.id != f.id && !retiredIds.contains(other.id))
            foreignSurnameOf(other.name),
      };
      // 新外国人はロール未割り当てで生成。後の `_reassignPitcherRoles` で
      // 18 名全体を能力スコア順にロール再評価するため、ここではロールを固定しない。
      final newForeign = f.isPitcher
          ? playerGen.generateForeignPitcher(
              number: f.number,
              pitcherRole: null,
              teamSurnames: remainingSurnames,
            )
          : playerGen.generateForeignFielder(
              number: f.number,
              teamSurnames: remainingSurnames,
            );
      _replacePlayerInTeam(team, f, newForeign);
      retiredIds.add(f.id);
    }
    return retiredIds;
  }

  /// CPU チームでの外国人離脱判定確率（強制離脱 + チーム契約解除の合算）。
  ///
  /// 旧版は一律 [foreignDepartureChance] = 20% の強制離脱のみで、CPU 球団でも
  /// 平均 5 年在籍になっていた。NPB の現実は外国人在籍 1〜2 年が中心で、
  /// 「CPU 球団が成績の出ない外国人を契約解除する」ケースが多い。これを再現するため:
  ///
  /// - 強制離脱（怪我・帰国・引退）: [foreignDepartureChance] = 20%（自チームと共通）
  /// - チーム契約解除（CPU 都合、能力ベース）: ハズレ外国人ほど高確率で解除
  ///   - 能力スコア 4.5 未満（ハズレ）: 70%
  ///   - 4.5〜5.5: 45%
  ///   - 5.5〜6.5: 20%
  ///   - 6.5〜7.5: 5%
  ///   - 7.5+（エース級）: 2%
  ///
  /// 合算離脱率は独立試行モデル: 1 - (1-強制) × (1-解除)。
  /// 平均能力 5.3 程度のリーグ全体で約 50% 離脱率 ≒ 平均在籍 2 年。
  ///
  /// 自チームでは [prepareOffseason] が `foreignDepartureChance` のみで「強制離脱」
  /// を表示し、契約解除はユーザー自身が UI で選ぶ（CPU 自動判定とは経路が違う）。
  double _cpuForeignReleaseChance(Player p) {
    final score = _abilityScore(p);
    final double releaseChance;
    if (score < 4.5) {
      releaseChance = 0.70;
    } else if (score < 5.5) {
      releaseChance = 0.45;
    } else if (score < 6.5) {
      releaseChance = 0.20;
    } else if (score < 7.5) {
      releaseChance = 0.05;
    } else {
      releaseChance = 0.02;
    }
    return 1.0 - (1.0 - foreignDepartureChance) * (1.0 - releaseChance);
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

    // 各 DefensePosition の「守れる野手数」は **チーム全体（外国人込み）** で
    // 集計する。ユーザー方針: 各ポジ 3 / 外野 8 はチーム全体での充足を意味する。
    // 引退判定でも新人補強でもこの全体カウントを使う。
    final allFielders = <Player>[
      ...team.players.where((p) => !p.isPitcher),
      ...team.bench,
    ];
    final canPlayCount = <DefensePosition, int>{
      for (final pos in DefensePosition.values) pos: 0,
    };
    for (final p in allFielders) {
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

    // 引退者を新人野手と入れ替え。チーム全体で最低ラインを下回るポジションが
    // あれば、新人はそのポジションを守れる選手として生成（補充重視、引退者の
    // 守備位置とは無関係に「最も不足しているポジション」を優先）。
    // すべての制約を満たしていれば、新人はランダム守備プロファイル（個性を尊重）。
    for (final retiredPlayer in retiredPlayers) {
      final shortage = _mostNeededShortagePosition(canPlayCount);
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

  /// チーム全体で「最低ラインを下回るポジション」のうち、最も不足が大きいものを返す。
  /// 同率なら外野を優先（試合中 3 人配置が必要なため枯渇インパクトが大きい）。
  /// すべて充足していれば null。
  DefensePosition? _mostNeededShortagePosition(
    Map<DefensePosition, int> currentCount,
  ) {
    DefensePosition? best;
    int bestPriority = 0;
    for (final pos in DefensePosition.values) {
      final deficit = minPlayersForPosition(pos) - currentCount[pos]!;
      if (deficit <= 0) continue;
      final priority =
          deficit * 10 + (pos == DefensePosition.outfield ? 1 : 0);
      if (priority > bestPriority) {
        bestPriority = priority;
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

    // 新人投手は **ロール未割り当て** で生成する（旧版は引退者の wasStarter/role を
     // 継承していたため、能力に関係なく役割が固定されていた）。
     // この後の `_reassignPitcherRoles` で 18 名全体を能力スコア順に再評価し、
     // 新人でも能力が高ければ先発・抑えに上がる、衰えた既存先発は救援に落ちる、
     // という流動が起きる。
    for (final retiredPlayer in retiredPlayers) {
      final rookie = playerGen.generateRookiePitcher(
        number: retiredPlayer.number,
        isStarter: false, // 役割なしフラット生成
        pitcherRole: null,
        type: _pickCpuRookieType(),
      );
      _replacePlayerInTeam(team, retiredPlayer, rookie);
    }

    return retiredIds;
  }

  // ---------------------------------------------------
  // 投手ロール再評価（18 名全体を能力スコア順に再アサイン）
  // ---------------------------------------------------

  /// 投手 18 名（先発ローテ 6 + ブルペン 12）を **全体で** 能力スコア順にロール
  /// 再アサインする。`TeamGenerator.assignPitcherRoles` と同じロジックを使い、
  /// 初期生成・オフシーズン再評価で配置基準を統一する。
  ///
  /// 旧版 `_reorganizeBullpenRoles` はブルペン 12 人内でしか再評価せず、衰えた
  /// 先発エースは先発のまま、強い新人救援は救援のまま、と能力との乖離が
  /// 蓄積する構造だった。新版は先発↔救援の入れ替えも発生し、毎オフシーズン
  /// 「最強 6 名が先発、次点が抑え/セットアッパー、能力低位が敗戦処理」
  /// という配置が再構築される。
  ///
  /// 自チームは `rebuildCpuTeams` の対象外なので、ユーザーが手動でロールを
  /// 維持できる。
  void _reassignPitcherRoles(Team team) {
    final allPitchers = <Player>[
      ...team.startingRotation,
      ...team.bullpen,
    ];
    if (allPitchers.length < 6) return;

    // assignPitcherRoles は入力リストの要素を新インスタンス（pitcherRole 更新済み）
    // で差し替える破壊的更新。終了後、allPitchers が最新インスタンスを保持。
    TeamGenerator.assignPitcherRoles(allPitchers);

    // チームの players / startingRotation / bullpen / bench を全て更新（id 一致で置換）
    final updatedById = <String, Player>{
      for (final p in allPitchers) p.id: p,
    };
    // role 変更が起きた選手だけ team 全体に in-place で差し替え
    for (final original in [
      ...team.startingRotation,
      ...team.bullpen,
      ...team.players,
    ]) {
      final updated = updatedById[original.id];
      if (updated == null) continue;
      if (identical(updated, original)) continue;
      _replacePlayerInTeam(team, original, updated);
    }

    // 新ロールに基づいて rotation / bullpen を再構成
    // （先発 → 救援に降格した選手、救援 → 先発に昇格した選手が混じるため）
    final newRotation = allPitchers
        .where((p) => p.pitcherRole == PitcherRole.starter)
        .toList()
      ..shuffle(_random);
    final newBullpen = allPitchers
        .where((p) => p.pitcherRole != PitcherRole.starter)
        .toList();
    team.startingRotation
      ..clear()
      ..addAll(newRotation);
    team.bullpen
      ..clear()
      ..addAll(newBullpen);

    // 投手スロット（players[8]）が現在の rotation に含まれていなければ
    // rotation の先頭で置き換える（救援に降格した投手は試合先発しない）
    if (team.players.length >= 9) {
      final players8 = team.players[8];
      if (!newRotation.any((p) => p.id == players8.id) &&
          newRotation.isNotEmpty) {
        team.players[8] = newRotation.first;
      }
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
  /// 新人候補は野手・投手それぞれ [rookieCandidatesPerType] × 3 タイプ = 9 名生成する
  /// （高卒 / 大卒 / 社会人 を各 [rookieCandidatesPerType] 名）。
  /// 推奨は能力スコア上位を選ぶ（基本的には大卒・社会人寄りに偏るが、
  /// まれな高卒の即戦力もここで拾える）。
  ///
  /// **数値の根拠**: 候補が少ないと「衰えた捕手を引退させたいが、新人候補に
  /// 捕手がいない」状況に陥りやすい。各タイプ 3 名（合計 9 名）にすることで、
  /// ランダム抽選でも 2-3 年以内に望むポジションが候補に出る確率を確保する。
  OffseasonPlan buildOffseasonPlan(
    Team team, {
    int rookieCandidatesPerType = 3,
  }) {
    // 外国人選手は別ロジック（prepareForeignChangesForMyTeam で生成・
    // applyUserSelection 内の _applyForeignChanges で適用）で処理されるので、
    // 引退候補リストには含めない。混ぜると日本人新人で置き換わって外国人枠が
    // 消失してしまう。
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

    final recommendedRetireFielders = _recommendedFielderRetirements(
      team,
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

    // 自チームの外国人入替の候補生成（強制離脱判定 + 投手2+野手2 の新候補）。
    // 結果は plan に格納して、commitOffseason で applyUserSelection が適用する。
    final foreignChanges = prepareForeignChangesForMyTeam(team);

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
      foreignDepartures: foreignChanges.departures,
      foreignCandidates: foreignChanges.candidates,
    );
  }

  /// CPU と同じ「26 歳以上 + スコア > 0 の上位 [count] 名」を返す（投手用）。
  /// ポジション制約は適用しない（投手にはポジション概念なし）。
  List<Player> _recommendedRetirements(List<Player> sorted, int count) {
    final picks = <Player>[];
    for (final p in sorted) {
      if (picks.length >= count) break;
      if (_retirementScore(p) <= 0) break;
      picks.add(p);
    }
    return picks;
  }

  /// 野手用の推奨引退。スコア順に候補を見つつ、引退でポジション制約
  /// （各ポジ [minPlayersForPosition]）を破る選手はスキップする。
  /// [team] はチーム全体のポジション充足判定に使う（外国人込みで集計）。
  List<Player> _recommendedFielderRetirements(
    Team team,
    List<Player> sortedFielders,
    int count,
  ) {
    final allFielders = <Player>[
      ...team.players.where((p) => !p.isPitcher),
      ...team.bench,
    ];
    final canPlayCount = <DefensePosition, int>{
      for (final pos in DefensePosition.values) pos: 0,
    };
    for (final p in allFielders) {
      for (final pos in DefensePosition.values) {
        if (p.canPlay(pos)) canPlayCount[pos] = canPlayCount[pos]! + 1;
      }
    }

    final picks = <Player>[];
    for (final p in sortedFielders) {
      if (picks.length >= count) break;
      if (_retirementScore(p) <= 0) break;
      bool wouldBreakConstraint = false;
      for (final pos in DefensePosition.values) {
        if (p.canPlay(pos) &&
            canPlayCount[pos]! - 1 < minPlayersForPosition(pos)) {
          wouldBreakConstraint = true;
          break;
        }
      }
      if (wouldBreakConstraint) continue;
      picks.add(p);
      for (final pos in DefensePosition.values) {
        if (p.canPlay(pos)) canPlayCount[pos] = canPlayCount[pos]! - 1;
      }
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
  /// 自チームの外国人入替の **候補生成のみ** を行う（チームには触らない）。
  /// オフシーズン開始時に [SeasonController.prepareOffseason] から呼ばれて、
  /// 強制離脱判定と新候補（投手 2 + 野手 2）を OffseasonPlan に格納する。
  ///
  /// 実際の入替は [applyUserSelection] で plan + selection を見て [_applyForeignChanges]
  /// が行う。CPU は依然として [_handleForeignDepartures] で即時自動補充。
  ({List<Player> departures, List<Player> candidates})
      prepareForeignChangesForMyTeam(Team team) {
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

    final departures = <Player>[
      for (final f in foreigners)
        if (_random.nextDouble() < foreignDepartureChance) f,
    ];

    // チームに残る現役外国人と同苗字にならないよう除外して候補を生成。
    // 候補同士も同苗字にならないよう、生成済み候補の苗字を追加していく。
    final remainingSurnames = <String>{
      for (final f in foreigners)
        if (!departures.contains(f)) foreignSurnameOf(f.name),
    };
    final candidates = <Player>[];
    Set<String> currentSurnames() => {
          ...remainingSurnames,
          for (final c in candidates) foreignSurnameOf(c.name),
        };
    // 投手 3 + 野手 3。想定枠 2+2 を満たすぶんに加えて、ユーザーが選択する
    // 余地として 1 名ずつ余裕を持たせる。
    for (int i = 0; i < 3; i++) {
      candidates.add(playerGen.generateForeignPitcher(
        number: 0,
        pitcherRole: PitcherRole.starter,
        teamSurnames: currentSurnames(),
      ));
    }
    for (int i = 0; i < 3; i++) {
      candidates.add(playerGen.generateForeignFielder(
        number: 0,
        teamSurnames: currentSurnames(),
      ));
    }
    return (departures: departures, candidates: candidates);
  }

  /// 強制離脱 + ユーザー任意カット + 候補から獲得 を team に in-place 適用。
  /// 投手枠と野手枠で順序ペアリングし、離脱者の背番号・ロールを新候補が引き継ぐ。
  void _applyForeignChanges(
    Team team,
    OffseasonPlan plan,
    OffseasonSelection selection,
  ) {
    // 1. team から外す対象（強制離脱 + ユーザー任意カット）を集める
    final removeTargets = <Player>[
      ...plan.foreignDepartures,
    ];
    for (final id in selection.foreignReleaseIds) {
      // 強制離脱と重複しても加算しない
      if (removeTargets.any((p) => p.id == id)) continue;
      final p = _findForeignInTeam(team, id);
      if (p != null) removeTargets.add(p);
    }
    final removePitchers = removeTargets.where((p) => p.isPitcher).toList();
    final removeFielders = removeTargets.where((p) => !p.isPitcher).toList();

    // 2. 獲得候補を投手・野手で分ける
    final acquirePitchers = <Player>[];
    final acquireFielders = <Player>[];
    for (final id in selection.foreignAcquireIds) {
      final c = plan.foreignCandidates.firstWhere(
        (p) => p.id == id,
        orElse: () =>
            throw ArgumentError('外国人候補に存在しない id: $id'),
      );
      if (c.isPitcher) {
        acquirePitchers.add(c);
      } else {
        acquireFielders.add(c);
      }
    }

    // 3. 投手枠 / 野手枠が想定枠数（[targetForeignPitchers] / [targetForeignFielders]）
    //    を満たしているか（現状 - 離脱 + 獲得 = 想定）。離脱より獲得が多いケース
    //    （= チームに既に空席があって新規追加でそれを埋める）も許容する。
    // 重複排除: players[8] と startingRotation[0] が同じ投手を参照する作りに
    // なっているので、id で一意化してから数える。
    final seenForeignIds = <String>{};
    final currentForeigners = <Player>[];
    for (final p in [
      ...team.players,
      ...team.startingRotation,
      ...team.bullpen,
      ...team.bench,
    ]) {
      if (!p.isForeign) continue;
      if (!seenForeignIds.add(p.id)) continue;
      currentForeigners.add(p);
    }
    final currentPitchers =
        currentForeigners.where((p) => p.isPitcher).length;
    final currentFielders =
        currentForeigners.where((p) => !p.isPitcher).length;
    final newPitchers =
        currentPitchers - removePitchers.length + acquirePitchers.length;
    final newFielders =
        currentFielders - removeFielders.length + acquireFielders.length;
    if (newPitchers != targetForeignPitchers) {
      throw ArgumentError(
        '外国人投手の枠が合いません: '
        '現状$currentPitchers - 離脱${removePitchers.length} '
        '+ 獲得${acquirePitchers.length} = $newPitchers ≠ $targetForeignPitchers',
      );
    }
    if (newFielders != targetForeignFielders) {
      throw ArgumentError(
        '外国人野手の枠が合いません: '
        '現状$currentFielders - 離脱${removeFielders.length} '
        '+ 獲得${acquireFielders.length} = $newFielders ≠ $targetForeignFielders',
      );
    }

    // 4. ペアできるぶん（離脱と獲得が揃っているぶん）は in-place 置換で背番号と
    //    ロールを引き継ぐ。ペアできない獲得（離脱より獲得が多い）はチームの
    //    該当リストに新規追加して空席を埋める。
    final usedNumbers = <int>{
      for (final p in [
        ...team.players,
        ...team.startingRotation,
        ...team.bullpen,
        ...team.bench,
      ])
        p.number,
    };
    int allocateNumber() {
      for (int n = 1; n <= 40; n++) {
        if (!usedNumbers.contains(n)) {
          usedNumbers.add(n);
          return n;
        }
      }
      int n = 41;
      while (usedNumbers.contains(n)) {
        n++;
      }
      usedNumbers.add(n);
      return n;
    }

    for (int i = 0; i < acquirePitchers.length; i++) {
      if (i < removePitchers.length) {
        final old = removePitchers[i];
        final newP = _withNumberAndRole(
          acquirePitchers[i],
          old.number,
          old.pitcherRole ?? PitcherRole.starter,
        );
        _replacePlayerInTeam(team, old, newP);
      } else {
        // 空席に新規追加（先発ローテに加える）
        final newP = _withNumberAndRole(
          acquirePitchers[i],
          allocateNumber(),
          PitcherRole.starter,
        );
        team.startingRotation.add(newP);
      }
    }
    for (int i = 0; i < acquireFielders.length; i++) {
      if (i < removeFielders.length) {
        final old = removeFielders[i];
        final newP = _withNumber(acquireFielders[i], old.number);
        _replacePlayerInTeam(team, old, newP);
      } else {
        // 空席に新規追加（ベンチに加える）
        final newP = _withNumber(acquireFielders[i], allocateNumber());
        team.bench.add(newP);
      }
    }
  }

  /// チーム内（players/rotation/bullpen/bench）から id で外国人を探す。見つからなければ null。
  Player? _findForeignInTeam(Team team, String id) {
    for (final p in [
      ...team.players,
      ...team.startingRotation,
      ...team.bullpen,
      ...team.bench,
    ]) {
      if (p.id == id) return p;
    }
    return null;
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
    final foreignError = selection.validateForeign(plan);
    if (foreignError != null) {
      throw ArgumentError(foreignError);
    }

    // 外国人入替を先に処理する（引退・新人の処理に影響しないよう独立で実行）。
    // 強制離脱 + ユーザー任意カット で対象選手を抽出し、投手枠・野手枠ごとに
    // 獲得候補とペアリングしてチーム内で in-place 置換する。
    _applyForeignChanges(team, plan, selection);

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

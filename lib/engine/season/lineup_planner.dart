import '../models/enums.dart';
import '../models/player.dart';
import '../models/team.dart';
import 'recent_form.dart';

/// 1試合分の打順 + 守備配置を計算する。
///
/// 入力は「正規化されたチーム」（[Team.players] が `[捕,一,二,三,遊,左,中,右,投]`
/// の順に並んでいる）と、当日の先発投手、各選手の直近成績。
///
/// アルゴリズム:
///   1. ベンチからの入れ替え判断（最大 [maxSwapsPerGame] 件）
///      不調の野手と、同ポジションを守れるベンチの好調選手を比較し、
///      閾値を超えたら入れ替える。中心選手（能力上位）は閾値を高くする。
///   2. 確定した8野手を打順1〜8番に割り当てる（伝統的日本式）
///        4番→3番→1番→2番→5番 の順に最適な選手を当て、
///        残りを打力順で 6→7→8 番に並べる。
///   3. 9番は当日の先発投手で固定。
///
/// [neutralOrder] が true のときは「能力で並べない」中立モードになる:
///   - 打順は背番号順（8野手）+ 投手9番。能力序列を UI に出さない。
///   - 能力差によるベンチ入れ替え（Phase 2）は行わない。
///   - 守れないポジションの強制スワップ（Phase 1）は中立モードでも行う。
/// 自チームの初期提案で使う。パラメータ非表示の方針上、エンジンが能力順の
/// 打順を提示すると「最適解を無料で渡す」ことになり推測ゲームが成立しないため
/// （SPEC §コンセプト）。CPU チームは従来どおり能力ベース（neutralOrder=false）。
class LineupPlanner {
  /// 正規化チームの `players[0..7]` のデフォルトポジション対応
  /// （TeamGenerator が生成する順序に対応）
  static const List<FieldPosition> _defaultPositions = [
    FieldPosition.catcher,
    FieldPosition.first,
    FieldPosition.second,
    FieldPosition.third,
    FieldPosition.shortstop,
    FieldPosition.left,
    FieldPosition.center,
    FieldPosition.right,
  ];

  /// 1試合での最大ベンチ入れ替え数
  static const int maxSwapsPerGame = 2;

  /// OPS の中立基準（リーグ平均 ~ .700 を想定）
  static const double opsBaseline = 0.700;

  final Team team;
  final Map<String, RecentForm> forms;
  final Player todaysPitcher;

  /// true なら能力で並べず背番号順にする（自チームの初期提案用）。
  final bool neutralOrder;

  LineupPlanner({
    required this.team,
    required this.forms,
    required this.todaysPitcher,
    this.neutralOrder = false,
  });

  /// 当日の打順 + 守備配置を返す。
  ///
  /// [useDH] が true のとき（リーグ DH 採用）は投手を打順に入れず、代わりに
  /// 控え野手から DH を選んで 9 人の打順（8 野手 + DH）を組む。投手は
  /// `alignment[pitcher]` にのみ入り、打席には立たない。
  /// DH 候補が居ない異常系では非DH（投手が打つ）にフォールバックする。
  ({List<Player> lineup, Map<FieldPosition, Player> alignment}) buildLineup({
    bool useDH = false,
  }) {
    final fielders = _selectFielders();

    final alignment = <FieldPosition, Player>{};
    for (int i = 0; i < fielders.length && i < _defaultPositions.length; i++) {
      alignment[_defaultPositions[i]] = fielders[i];
    }
    alignment[FieldPosition.pitcher] = todaysPitcher;

    if (useDH && fielders.length == 8) {
      final dh = _selectDH(fielders);
      if (dh != null) {
        final order = _assignBattingOrder([...fielders, dh]);
        return (lineup: order, alignment: alignment);
      }
    }

    final order = _assignBattingOrder(fielders);
    return (
      lineup: [...order, todaysPitcher],
      alignment: alignment,
    );
  }

  /// DH を選ぶ。スタメン8野手にも投手にもなっていない野手から、
  /// 能力モードでは最も打てる選手、中立モードでは背番号の若い選手を選ぶ。
  /// 候補がいなければ null（非DHにフォールバック）。
  Player? _selectDH(List<Player> fielders) {
    final usedIds = fielders.map((p) => p.id).toSet();
    final pool = <Player>[
      for (final p in [...team.players.take(8), ...team.bench])
        if (!p.isPitcher && !usedIds.contains(p.id)) p,
    ];
    if (pool.isEmpty) return null;
    if (neutralOrder) {
      pool.sort((a, b) => a.number.compareTo(b.number));
      return pool.first;
    }
    pool.sort((a, b) =>
        _formAdjustedAbility(b).compareTo(_formAdjustedAbility(a)));
    return pool.first;
  }

  // ---------------------------------------------------
  // ベンチからの入れ替え判断
  // ---------------------------------------------------

  /// `team.players[0..7]` を起点に、必要に応じてベンチ選手と入れ替える。
  /// ポジションは index に対応するデフォルト位置を維持する（位置を保ったままスワップ）。
  ///
  /// 2 段構え:
  ///   Phase 1 = 強制スワップ。スタメン枠の選手がそのポジションを守れない場合
  ///             （オフシーズンで守備プロファイルが合わない新人が入った等）、
  ///             ベンチから守れる選手を必ず昇格させる。回数制限なし。
  ///   Phase 2 = 通常スワップ。調子・能力差で最大 [maxSwapsPerGame] 件入れ替え。
  List<Player> _selectFielders() {
    // 中立モード（自チーム）: スタメン枠（players[0..7]）に頼らず、野手全体から
    // 「各守備位置を守れる最も背番号の若い選手」を選ぶ。能力で誰が主力かを
    // エンジンが提示しないため（SPEC §コンセプト）。
    if (neutralOrder) return _selectFieldersNeutral();

    final canonical = team.players.take(8).toList();
    if (canonical.length < 8) return canonical;

    final result = List.of(canonical);
    final usedReplacements = <String>{};

    // ---- Phase 1: 守れない選手を強制スワップ ----
    for (int i = 0; i < 8; i++) {
      final starter = result[i];
      final pos = _defaultPositions[i].defensePosition;
      if (pos == null) continue;
      if (starter.canPlay(pos)) continue;

      Player? best;
      double bestScore = -double.infinity;
      for (final benchPlayer in team.bench) {
        if (usedReplacements.contains(benchPlayer.id)) continue;
        if (!benchPlayer.canPlay(pos)) continue;
        final score = _formAdjustedAbility(benchPlayer);
        if (score > bestScore) {
          bestScore = score;
          best = benchPlayer;
        }
      }
      if (best != null) {
        result[i] = best;
        usedReplacements.add(best.id);
      }
      // ベンチに守れる選手がいなければ仕方なく canPlay=false の選手を起用。
      // ここまで来たらチーム編成自体に問題があるので最終フォールバックとして許容。
    }

    // ---- Phase 2: 調子・能力で通常スワップ（最大 maxSwapsPerGame 件） ----
    final candidates = <_SwapCandidate>[];
    for (int i = 0; i < 8; i++) {
      final starter = result[i];
      // Phase 1 で既に交代済みの枠は対象外
      if (usedReplacements.contains(starter.id)) continue;
      final pos = _defaultPositions[i].defensePosition;
      if (pos == null) continue;

      final starterScore = _formAdjustedAbility(starter);

      Player? best;
      double bestScore = starterScore;
      for (final benchPlayer in team.bench) {
        if (usedReplacements.contains(benchPlayer.id)) continue;
        if (!benchPlayer.canPlay(pos)) continue;
        final score = _formAdjustedAbility(benchPlayer);
        if (score > bestScore) {
          bestScore = score;
          best = benchPlayer;
        }
      }
      if (best == null) continue;

      // 中心選手は閾値を高くして外れにくくする
      final threshold = _swapThreshold(starter);
      if (bestScore > starterScore * threshold) {
        candidates.add(_SwapCandidate(
          slot: i,
          starter: starter,
          replacement: best,
          improvement: bestScore - starterScore,
        ));
      }
    }

    candidates.sort((a, b) => b.improvement.compareTo(a.improvement));
    int swapped = 0;
    for (final c in candidates) {
      if (swapped >= maxSwapsPerGame) break;
      if (usedReplacements.contains(c.replacement.id)) continue;
      result[c.slot] = c.replacement;
      usedReplacements.add(c.replacement.id);
      swapped++;
    }
    return result;
  }

  /// 中立モードのスタメン野手選定。
  ///
  /// 野手全体（[Team.players] の先頭8人 + [Team.bench]）から、各守備位置
  /// （捕一二三遊左中右）を守れる「最も背番号の若い選手」を割り当てる。
  /// 守れる選手が少ない位置（捕手など）から先に埋め、枯渇したら背番号順で補充。
  /// 能力には一切触れないので、誰が主力かのヒントを出さない。
  List<Player> _selectFieldersNeutral() {
    final pool = <Player>[
      for (final p in [...team.players.take(8), ...team.bench])
        if (!p.isPitcher) p,
    ]..sort((a, b) => a.number.compareTo(b.number));

    // 各スロットを守れるプール人数（希少な位置を先に埋めるための順序付け）。
    int eligibleCount(int slot) {
      final dp = _defaultPositions[slot].defensePosition;
      if (dp == null) return 0;
      return pool.where((p) => p.canPlay(dp)).length;
    }

    final slotOrder = List.generate(8, (i) => i)
      ..sort((a, b) => eligibleCount(a).compareTo(eligibleCount(b)));

    final result = List<Player?>.filled(8, null);
    final used = <String>{};
    for (final slot in slotOrder) {
      final dp = _defaultPositions[slot].defensePosition;
      if (dp == null) continue;
      for (final p in pool) {
        if (used.contains(p.id)) continue;
        if (!p.canPlay(dp)) continue;
        result[slot] = p;
        used.add(p.id);
        break;
      }
    }
    // 守れる選手が枯渇したスロットは背番号順で補充（異常系のフォールバック）。
    for (int i = 0; i < 8; i++) {
      if (result[i] != null) continue;
      for (final p in pool) {
        if (used.contains(p.id)) continue;
        result[i] = p;
        used.add(p.id);
        break;
      }
    }
    return [for (final p in result) if (p != null) p];
  }

  /// 中心選手（素能力上位）はスワップ閾値を高くする。
  /// 戻り値は「ベンチ選手スコア / スタメンスコア」がこの値を超えたら入れ替え対象。
  double _swapThreshold(Player starter) {
    final ability = _pureAbility(starter);
    if (ability >= 14) return 1.40; // 主軸級: 大きく上回らないと外さない
    if (ability >= 12) return 1.25;
    if (ability >= 10) return 1.15;
    return 1.08; // 平均以下: 軽い差でも入れ替え
  }

  // ---------------------------------------------------
  // 打順割り当て（伝統的日本式）
  // ---------------------------------------------------

  /// 打者を打順に割り当てる。[hitters] は 8 人（非DH。投手は buildLineup 側で
  /// 9番に付け足す）または 9 人（DH採用。8野手 + DH をすべて打順に並べる）。
  ///
  /// 確定順:
  ///   1. 4番（チームの主砲、最強長打）
  ///   2. 3番・5番（クリーンナップ）
  ///   3. 1番・2番（リードオフと繋ぎ）
  ///   4. 6番以降（残りを打力順）
  List<Player> _assignBattingOrder(List<Player> hitters) {
    // 中立モード: 能力で並べず背番号順。投手(非DH)は buildLineup 側で9番固定。
    if (neutralOrder) {
      return [...hitters]..sort((a, b) => a.number.compareTo(b.number));
    }

    final n = hitters.length;
    final available = List.of(hitters);
    final result = List<Player?>.filled(n, null);

    void assign(int slot) {
      final pick = _pickBest(available, slot: slot);
      result[slot] = pick;
      available.remove(pick);
    }

    assign(3); // 4番（主砲）
    assign(2); // 3番
    assign(4); // 5番
    assign(0); // 1番
    assign(1); // 2番

    // 残りを打力順に 6番以降へ
    available.sort(
        (a, b) => _scoreForSlot(b, 5).compareTo(_scoreForSlot(a, 5)));
    for (int i = 0; i + 5 < n; i++) {
      result[5 + i] = available[i];
    }

    return result.cast<Player>();
  }

  Player _pickBest(List<Player> available, {required int slot}) {
    Player best = available.first;
    double bestScore = _scoreForSlot(best, slot);
    for (final p in available.skip(1)) {
      final s = _scoreForSlot(p, slot);
      if (s > bestScore) {
        bestScore = s;
        best = p;
      }
    }
    return best;
  }

  /// 指定打順スロットに対する適正スコア（調子で補正済み）
  double _scoreForSlot(Player p, int slot) {
    final meet = (p.meet ?? 5).toDouble();
    final power = (p.power ?? 5).toDouble();
    final speed = (p.speed ?? 5).toDouble();
    final eye = (p.eye ?? 5).toDouble();

    double base;
    switch (slot) {
      case 0: // 1番: 走力 + ミート + 選球眼
        base = speed * 2.5 + meet * 1.5 + eye * 0.7;
        break;
      case 1: // 2番: ミート + 走力（繋ぐ）
        base = meet * 2.0 + speed * 1.5 + eye * 0.5;
        break;
      case 2: // 3番: 打率 + 長打
        base = meet * 2.0 + power * 1.5 + eye * 0.3;
        break;
      case 3: // 4番: 長打最強
        base = power * 3.0 + meet * 1.0;
        break;
      case 4: // 5番: 長打
        base = power * 2.0 + meet * 1.2;
        break;
      default: // 6〜8番: 打力順
        base = meet * 1.2 + power * 1.0 + eye * 0.3;
    }
    return base * _formMultiplier(p);
  }

  // ---------------------------------------------------
  // スコア・調子の補助
  // ---------------------------------------------------

  /// 素能力スコア（ミート + 長打 + 走力 + 選球眼 を重み付け）
  double _pureAbility(Player p) {
    final meet = (p.meet ?? 5).toDouble();
    final power = (p.power ?? 5).toDouble();
    final speed = (p.speed ?? 5).toDouble();
    final eye = (p.eye ?? 5).toDouble();
    return meet + power + speed * 0.5 + eye * 0.3;
  }

  /// 調子の倍率。サンプル不足は 1.0（中立）。
  /// 直近 OPS が baseline を上回れば +、下回れば - 方向にスコアを補正。
  /// 過剰なブレを抑えるため [0.7, 1.3] にクランプ。
  double _formMultiplier(Player p) {
    final form = forms[p.id];
    if (form == null || form.sampleSize < RecentForm.minSampleForOPS) {
      return 1.0;
    }
    final delta = form.recentOPS - opsBaseline;
    return (1.0 + delta * 0.4).clamp(0.7, 1.3);
  }

  double _formAdjustedAbility(Player p) {
    return _pureAbility(p) * _formMultiplier(p);
  }
}

class _SwapCandidate {
  final int slot;
  final Player starter;
  final Player replacement;
  final double improvement;

  const _SwapCandidate({
    required this.slot,
    required this.starter,
    required this.replacement,
    required this.improvement,
  });
}

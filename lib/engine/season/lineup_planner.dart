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

  LineupPlanner({
    required this.team,
    required this.forms,
    required this.todaysPitcher,
  });

  /// 当日の打順 + 守備配置を返す
  ({List<Player> lineup, Map<FieldPosition, Player> alignment}) buildLineup() {
    final fielders = _selectFielders();

    final alignment = <FieldPosition, Player>{};
    for (int i = 0; i < fielders.length && i < _defaultPositions.length; i++) {
      alignment[_defaultPositions[i]] = fielders[i];
    }
    alignment[FieldPosition.pitcher] = todaysPitcher;

    final order = _assignBattingOrder(fielders);
    return (
      lineup: [...order, todaysPitcher],
      alignment: alignment,
    );
  }

  // ---------------------------------------------------
  // ベンチからの入れ替え判断
  // ---------------------------------------------------

  /// `team.players[0..7]` を起点に、必要に応じてベンチ選手と入れ替える。
  /// ポジションは index に対応するデフォルト位置を維持する（位置を保ったままスワップ）。
  List<Player> _selectFielders() {
    final canonical = team.players.take(8).toList();
    if (canonical.length < 8) return canonical;

    // 各スタメン枠でのスワップ候補を列挙
    final candidates = <_SwapCandidate>[];
    for (int i = 0; i < 8; i++) {
      final starter = canonical[i];
      final pos = _defaultPositions[i].defensePosition;
      if (pos == null) continue;

      final starterScore = _formAdjustedAbility(starter);

      Player? best;
      double bestScore = starterScore;
      for (final benchPlayer in team.bench) {
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

    // 入れ替えメリットが大きい順に最大 maxSwapsPerGame 件適用
    candidates.sort((a, b) => b.improvement.compareTo(a.improvement));
    final usedReplacements = <String>{};
    final result = List.of(canonical);
    int swapped = 0;
    for (final c in candidates) {
      if (swapped >= maxSwapsPerGame) break;
      // 同じベンチ選手を複数枠に当てない
      if (usedReplacements.contains(c.replacement.id)) continue;
      result[c.slot] = c.replacement;
      usedReplacements.add(c.replacement.id);
      swapped++;
    }
    return result;
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

  /// 8人の野手を打順 1〜8番（index 0..7）に割り当てる
  ///
  /// 確定順:
  ///   1. 4番（チームの主砲、最強長打）
  ///   2. 3番・5番（クリーンナップ）
  ///   3. 1番・2番（リードオフと繋ぎ）
  ///   4. 6〜8番（残りを打力順）
  List<Player> _assignBattingOrder(List<Player> fielders) {
    final available = List.of(fielders);
    final result = List<Player?>.filled(8, null);

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

    // 残り3人を打力順に 6→7→8番
    available.sort(
        (a, b) => _scoreForSlot(b, 5).compareTo(_scoreForSlot(a, 5)));
    for (int i = 0; i < 3; i++) {
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

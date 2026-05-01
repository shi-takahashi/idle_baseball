import 'dart:math';

/// 野手の調子（複数日に渡って持続するバイオリズム）。
///
/// 試合中の能力に直接効く隠しパラメータで、見た目には反映されない。
/// Markov 連鎖で日々遷移し、好調・不調が数日続くようなプロファイルになる。
///
/// 状態:
///   * +1: 好調（meet/power/speed/eye が +1）
///   *  0: 普通（補正なし）
///   * -1: 不調（meet/power/speed/eye が -1）
///
/// 補正幅は意図的に控えめ。RecentForm（直近成績）と二重補正にならないよう、
/// こちらは「シミュレーションの能力に効く」、RecentForm は「打順決定に効く」という
/// 役割分担にしている。
class BatterConditionTracker {
  static const int minState = -1;
  static const int maxState = 1;

  final Random _random;
  final Map<String, int> _states = {};

  BatterConditionTracker({Random? random}) : _random = random ?? Random();

  /// 指定選手の現在の状態（-1, 0, +1）
  int stateOf(String playerId) => _states[playerId] ?? 0;

  /// 1日経過: 列挙した全選手について Markov 遷移で状態を更新
  void advanceDay(Iterable<String> playerIds) {
    for (final id in playerIds) {
      _states[id] = _transition(stateOf(id));
    }
  }

  /// テストや UI 用に状態を直接設定
  void setState(String playerId, int state) {
    _states[playerId] = state.clamp(minState, maxState);
  }

  /// 永続化用: 全状態を Map で取り出す
  Map<String, int> exportStates() => Map<String, int>.from(_states);

  /// 永続化用: 全状態を一括復元（既存値は上書き）
  void importStates(Map<String, int> states) {
    _states
      ..clear()
      ..addAll(states);
  }

  /// Markov 遷移
  ///   普通 → 80% 普通 / 10% 好調 / 10% 不調
  ///   好調 → 60% 好調 / 35% 普通 / 5% 不調
  ///   不調 → 60% 不調 / 35% 普通 / 5% 好調
  /// 平均で「普通」は ~5日、「好調・不調」は ~2.5日続く想定。
  int _transition(int current) {
    final r = _random.nextDouble();
    switch (current) {
      case 1:
        if (r < 0.60) return 1;
        if (r < 0.95) return 0;
        return -1;
      case -1:
        if (r < 0.60) return -1;
        if (r < 0.95) return 0;
        return 1;
      default:
        if (r < 0.80) return 0;
        if (r < 0.90) return 1;
        return -1;
    }
  }
}

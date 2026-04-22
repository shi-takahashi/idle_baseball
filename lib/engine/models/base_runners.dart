import 'enums.dart';
import 'player.dart';

/// 盗塁の試み
class StealAttempt {
  final Player runner;
  final Base fromBase; // 元の塁
  final Base toBase; // 目標の塁
  final bool success; // 盗塁成功として記録
  final bool isOut; // アウトかどうか（ダブルスチール失敗時、1塁ランナーはアウトにならず進塁）

  const StealAttempt({
    required this.runner,
    required this.fromBase,
    required this.toBase,
    required this.success,
    this.isOut = false,
  });

  @override
  String toString() {
    final result = success ? '成功' : '失敗';
    return '${runner.name} ${fromBase.name}→${toBase.name} $result';
  }
}

/// タッチアップの試み
class TagUpAttempt {
  final Player runner;
  final Base fromBase; // 元の塁（second または third）
  final Base toBase; // 目標の塁（third または home）
  final bool success; // 成功したかどうか

  const TagUpAttempt({
    required this.runner,
    required this.fromBase,
    required this.toBase,
    required this.success,
  });

  @override
  String toString() {
    final result = success ? '成功' : '失敗';
    final target = toBase == Base.home ? 'ホーム' : '3塁';
    return '${runner.name} タッチアップ$target $result';
  }
}

/// 盗塁イベント（イニング内で発生した盗塁）
class StealEvent {
  final List<StealAttempt> attempts;
  final int beforeAtBatIndex; // この打席の前に発生

  const StealEvent({
    required this.attempts,
    required this.beforeAtBatIndex,
  });
}

/// 走者の状態
class BaseRunners {
  final Player? first;
  final Player? second;
  final Player? third;

  const BaseRunners({
    this.first,
    this.second,
    this.third,
  });

  /// 空の状態
  static const empty = BaseRunners();

  /// 走者がいるかどうか
  bool get hasRunners => first != null || second != null || third != null;

  /// 満塁かどうか
  bool get isLoaded => first != null && second != null && third != null;

  /// 走者の数
  int get count {
    int c = 0;
    if (first != null) c++;
    if (second != null) c++;
    if (third != null) c++;
    return c;
  }

  @override
  String toString() {
    final runners = <String>[];
    if (first != null) runners.add('1塁:${first!.name}');
    if (second != null) runners.add('2塁:${second!.name}');
    if (third != null) runners.add('3塁:${third!.name}');
    return runners.isEmpty ? '走者なし' : runners.join(', ');
  }

  /// 盗塁可能かどうか（少なくとも1人が盗塁可能な状態か）
  bool get canSteal {
    // 1塁ランナーが2塁へ盗塁可能: 2塁が空いている
    if (first != null && second == null) return true;
    // 2塁ランナーが3塁へ盗塁可能: 3塁が空いている
    if (second != null && third == null) return true;
    // ダブルスチール: 1,2塁で3塁が空いている
    if (first != null && second != null && third == null) return true;
    // その他は盗塁不可
    return false;
  }

  /// 盗塁可能なランナーのリストを取得
  /// 戻り値: [(ランナー, 元の塁, 目標の塁)]
  List<(Player, Base, Base)> getStealCandidates() {
    final candidates = <(Player, Base, Base)>[];

    // 2塁ランナーが3塁へ盗塁可能（先に判定、ダブルスチール時は2塁が先に走る）
    if (second != null && third == null) {
      candidates.add((second!, Base.second, Base.third));
    }

    // 1塁ランナーが2塁へ盗塁可能
    // 条件: 2塁が空いている、または2塁ランナーも同時に盗塁（ダブルスチール）
    if (first != null && (second == null || (second != null && third == null))) {
      candidates.add((first!, Base.first, Base.second));
    }

    return candidates;
  }

  /// 盗塁成功後のランナー状況を取得
  BaseRunners afterSuccessfulSteal(List<(Player, Base, Base)> steals) {
    Player? newFirst = first;
    Player? newSecond = second;
    Player? newThird = third;

    for (final (runner, from, to) in steals) {
      // 元の塁を空ける
      switch (from) {
        case Base.first:
          newFirst = null;
          break;
        case Base.second:
          newSecond = null;
          break;
        case Base.third:
          newThird = null;
          break;
        case Base.home:
          break;
      }
      // 目標の塁に移動
      switch (to) {
        case Base.first:
          newFirst = runner;
          break;
        case Base.second:
          newSecond = runner;
          break;
        case Base.third:
          newThird = runner;
          break;
        case Base.home:
          // ホームスチールは実装しない
          break;
      }
    }

    return BaseRunners(first: newFirst, second: newSecond, third: newThird);
  }

  /// 盗塁失敗後のランナー状況を取得（失敗したランナーを除去）
  BaseRunners afterFailedSteal(Player failedRunner, Base fromBase) {
    Player? newFirst = first;
    Player? newSecond = second;
    Player? newThird = third;

    // 失敗したランナーを除去
    switch (fromBase) {
      case Base.first:
        if (first == failedRunner) newFirst = null;
        break;
      case Base.second:
        if (second == failedRunner) newSecond = null;
        break;
      case Base.third:
        if (third == failedRunner) newThird = null;
        break;
      case Base.home:
        break;
    }

    return BaseRunners(first: newFirst, second: newSecond, third: newThird);
  }
}

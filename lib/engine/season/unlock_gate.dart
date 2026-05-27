/// 試合結果の閲覧解禁判定（1日1試合制約）。
///
/// 詳細は docs/DAILY_GATE_PLAN.md 参照。
///
/// 状態は 4 入力で決まる純関数の集合:
/// - [unlockHour]: ユーザー設定の解禁時刻（0-23 時、デフォルト 21）
/// - [lastUnlockAt]: 直近の「解禁が発生した時刻」。null は「まだ解禁イベントが
///   起きていない」状態（onboarding 中 + onboarding 直後の最初の 1 試合分まで）
/// - [isInOnboarding]: 自チーム消化試合数 < 10（シーズン1のみ）なら true
/// - [hasTimeSkipSub]: 時間スキップサブスク購入済みなら true（将来課金）
///
/// 「視聴で消費」の概念はここには持たず、`SeasonController` 側で
/// `markGameViewed(now)` が呼ばれた時に [lastUnlockAt] が更新される。
class UnlockGate {
  final int unlockHour;
  final DateTime? lastUnlockAt;
  final bool isInOnboarding;
  final bool hasTimeSkipSub;

  const UnlockGate({
    required this.unlockHour,
    required this.lastUnlockAt,
    required this.isInOnboarding,
    required this.hasTimeSkipSub,
  });

  /// 現在時刻 [now] で結果が閲覧可能か。
  bool isViewable(DateTime now) {
    if (isInOnboarding) return true;
    if (hasTimeSkipSub) return true;
    if (lastUnlockAt == null) return true; // 未ブートストラップ（onboarding 直後など）
    final next = nextUnlockAt(now);
    // now == next の瞬間でも解禁とみなす（境界含む）
    return !now.isBefore(next);
  }

  /// 次に解禁される時刻。
  ///
  /// - onboarding / サブスク中 / [lastUnlockAt] が null（未ブートストラップ）: [now] を
  ///   返す（実質的に「今すぐ」）
  /// - 通常: [lastUnlockAt] + 12h 以降で最初の設定時刻オカレンス
  DateTime nextUnlockAt(DateTime now) {
    if (isInOnboarding || hasTimeSkipSub) return now;
    if (lastUnlockAt == null) return now;
    return _afterLastUnlock(lastUnlockAt!, unlockHour);
  }

  /// 視聴が発生した時に新しい [lastUnlockAt] として記録すべき値。
  ///
  /// 「実際に視聴した時刻」ではなく「**直近の解禁時刻ジャスト**」を記録するのが
  /// 仕様（DAILY_GATE_PLAN.md）。
  ///
  /// - onboarding 中: null を返す（lastUnlockAt は更新しない）
  /// - その他: [now] 以前で最も近い設定時刻オカレンス
  ///   - 例: 設定 21:00、now = 2026-05-28 22:30 → 2026-05-28 21:00
  ///   - 例: 設定 21:00、now = 2026-05-28 14:00 → 2026-05-27 21:00（前日 21:00）
  ///
  /// onboarding 終了直後の 11 試合目視聴も `mostRecentUnlockHour` を採用する。
  /// 直前の解禁時刻が「今日の 21:00（設定時刻）」と一致するため自然な値になる。
  DateTime? newLastUnlockAtOnView(DateTime now) {
    if (isInOnboarding) return null;
    return mostRecentUnlockHour(now, unlockHour);
  }

  /// [now] 以降で最初の `HH:00` オカレンス（HH=[unlockHour]）。
  /// now が `HH:00` ぴったりならその瞬間を返す。
  static DateTime nextUnlockHourOccurrence(DateTime now, int unlockHour) {
    var candidate = DateTime(now.year, now.month, now.day, unlockHour);
    if (candidate.isBefore(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  /// [t] 以前で最も近い `HH:00` オカレンス。`HH:00` ぴったりならその瞬間を返す。
  static DateTime mostRecentUnlockHour(DateTime t, int unlockHour) {
    var candidate = DateTime(t.year, t.month, t.day, unlockHour);
    if (candidate.isAfter(t)) {
      candidate = candidate.subtract(const Duration(days: 1));
    }
    return candidate;
  }

  /// 直近の解禁から 12h 以降で最初に来る設定時刻オカレンス。
  static DateTime _afterLastUnlock(DateTime lastUnlockAt, int unlockHour) {
    final minNext = lastUnlockAt.add(const Duration(hours: 12));
    var candidate =
        DateTime(minNext.year, minNext.month, minNext.day, unlockHour);
    if (candidate.isBefore(minNext)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }
}

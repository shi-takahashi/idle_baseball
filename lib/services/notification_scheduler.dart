import '../engine/engine.dart';
import 'notification_service.dart';

/// `SeasonController` の状態から「通知を予約すべきか / キャンセルすべきか」を
/// 判定して `NotificationService` を叩く薄いオーケストレータ。
///
/// 呼び出し側はトリガーごとに [reevaluate] を呼べばよい:
/// - アプリ起動時 (`SeasonController` ロード後)
/// - 試合視聴後 (`markGameViewed` の後)
/// - 設定画面で `unlockHour` / `notificationsEnabled` を変更した後
/// - シーズン終了・新シーズン開始時
///
/// 同じ通知 ID (`_gameUnlockNotificationId`) を使い回すので、何度呼んでも
/// 「最新の判定に基づく 1 件」に集約される（べき等）。
class NotificationScheduler {
  NotificationScheduler._();

  /// 現状の `SeasonController` に基づいて通知を再評価する。
  ///
  /// 以下の場合はキャンセル:
  /// - 通知 OFF
  /// - シーズン終了（オフシーズン中は試合がないので通知不要）
  /// - 既に解禁済み（ユーザーは今すぐ見れる状態。通知の意味なし）
  ///
  /// それ以外は `unlockGate.nextUnlockAt(now)` の時刻に予約する。
  static Future<void> reevaluate(
    SeasonController controller, {
    DateTime? now,
  }) async {
    if (!controller.notificationsEnabled) {
      await NotificationService.cancelScheduled();
      return;
    }
    if (controller.isSeasonOver) {
      await NotificationService.cancelScheduled();
      return;
    }
    final n = now ?? DateTime.now();
    final gate = controller.unlockGate();
    if (gate.isViewable(n)) {
      // もう見れる状態。通知してもユーザー視点で「もう知ってる」なので不要。
      await NotificationService.cancelScheduled();
      return;
    }
    final next = gate.nextUnlockAt(n);
    await NotificationService.scheduleNextUnlock(next);
  }
}

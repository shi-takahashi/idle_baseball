import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// ローカルプッシュ通知の管理。
///
/// 用途は 1 つだけ: **「次に試合結果が解禁される時刻」に通知を 1 件予約**。
/// 通知を視聴後 / 解禁時刻変更時 / 通知 ON/OFF 切替時に再予約・キャンセルする。
///
/// 仕様詳細は SPEC.md §1.1 / docs/DAILY_GATE_PLAN.md。
///
/// プラットフォーム:
/// - Android のみ対応（iOS は後フェーズ）
/// - Web は no-op
class NotificationService {
  NotificationService._();

  static const int _gameUnlockNotificationId = 1;
  static const String _channelId = 'game_unlock';
  static const String _channelName = '試合結果の通知';
  static const String _channelDescription = '結果確認時刻に試合結果の解禁をお知らせします';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// デバッグ表示用: 最後に予約した発火予定時刻。`scheduleNextUnlock` が成功した
  /// 時にセット、`cancelScheduled` で null。プラグイン API では時刻が取れないため
  /// 自前で保持する。アプリ再起動でリセットされる点に注意。
  static DateTime? _lastScheduledFor;
  static DateTime? get lastScheduledFor => _lastScheduledFor;

  /// プラグインの初期化 + タイムゾーンデータベースのロード。
  /// アプリ起動時に 1 回だけ呼ぶ。
  static Future<void> initialize() async {
    if (_initialized) return;
    if (kIsWeb) {
      _initialized = true;
      return;
    }

    tzdata.initializeTimeZones();
    try {
      final localTzName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTzName));
    } catch (e) {
      debugPrint('NotificationService: failed to load local timezone: $e');
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);
    _initialized = true;
  }

  /// 通知権限を要求（Android 13+ で必要）。
  /// 結果は bool で返す（true = 許可、false = 拒否 / 取得失敗）。
  /// 既に許可済みなら ture を返してダイアログは出ない。
  static Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    final granted = await android.requestNotificationsPermission();
    return granted ?? false;
  }

  /// 「次の解禁時刻」に通知を 1 件予約する。
  /// 既存予約があれば置き換える（同 ID なので自動的に上書き）。
  ///
  /// [unlockAt] が過去 / 現在以下なら何もしない（解禁済みのため通知不要）。
  static Future<void> scheduleNextUnlock(DateTime unlockAt) async {
    if (kIsWeb) return;
    if (!_initialized) await initialize();

    final now = DateTime.now();
    if (!unlockAt.isAfter(now)) {
      // 既に解禁時刻を過ぎている。通知は不要、既存予約だけ消す。
      await cancelScheduled();
      return;
    }

    _lastScheduledFor = unlockAt;

    final scheduled = tz.TZDateTime.from(unlockAt, tz.local);

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);

    try {
      await _plugin.zonedSchedule(
        _gameUnlockNotificationId,
        '本日の試合結果が出ました',
        '結果を確認しましょう',
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        // iOS 用パラメータ。Android 専用運用でも non-null が必須なので
        // absoluteTime を渡しておく（iOS 対応時に挙動を再確認する）。
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('NotificationService: schedule failed: $e');
    }
  }

  /// 予約済み通知をキャンセル（OFF 切替・シーズン終了等）。
  static Future<void> cancelScheduled() async {
    if (kIsWeb) return;
    if (!_initialized) await initialize();
    await _plugin.cancel(_gameUnlockNotificationId);
    _lastScheduledFor = null;
  }

  /// 現在 OS に予約されている通知の一覧（デバッグ確認用）。
  /// `PendingNotificationRequest` は時刻を持たないので、別途 [lastScheduledFor]
  /// と合わせて表示する。
  static Future<List<PendingNotificationRequest>> pendingRequests() async {
    if (kIsWeb) return const [];
    if (!_initialized) await initialize();
    return _plugin.pendingNotificationRequests();
  }
}

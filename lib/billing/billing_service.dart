import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'entitlements.dart';

/// RevenueCat の初期化・購入・復元をまとめる薄い層。
/// 取得した権利状態は [Entitlements] に流し込む（下流はそちらを読む）。
class BillingService {
  BillingService._();

  /// Android 用の公開 SDK キー（`goog_` 始まりの公開鍵なのでコード同梱・git 管理 OK）。
  /// Secret key (`sk_`) はサーバー用でアプリには絶対に入れない。
  static const String _androidApiKey = 'goog_nLTktLlkztwXRpguZSSUMLDCsri';

  static bool _configured = false;
  static bool get isConfigured => _configured;

  /// 起動時に一度だけ呼ぶ。設定 → リスナー登録 → 初期 customerInfo 取得。
  /// 失敗してもアプリ起動は止めない（課金は遊びの必須要件ではない）。
  static Future<void> configure() async {
    if (_configured) return;
    try {
      if (kDebugMode) {
        await Purchases.setLogLevel(LogLevel.debug);
      }
      await Purchases.configure(PurchasesConfiguration(_androidApiKey));
      _configured = true;

      // 以後の購入・解約・更新はこのリスナーで [Entitlements] に反映される。
      Purchases.addCustomerInfoUpdateListener(
        Entitlements.instance.applyCustomerInfo,
      );

      // 起動時点の権利状態を一度取り込む（既購入者・復元済み端末向け）。
      final info = await Purchases.getCustomerInfo();
      Entitlements.instance.applyCustomerInfo(info);
    } catch (e) {
      debugPrint('BillingService.configure failed: $e');
    }
  }

  /// 現在の Offering を取得（ショップ画面のカード生成用）。
  /// 未設定・取得失敗時は null。
  static Future<Offering?> currentOffering() async {
    if (!_configured) return null;
    try {
      final offerings = await Purchases.getOfferings();
      return offerings.current;
    } catch (e) {
      debugPrint('BillingService.currentOffering failed: $e');
      return null;
    }
  }

  /// パッケージを購入する。
  /// 成功で true、ユーザーがキャンセルした場合は false を返す。
  /// それ以外のエラーは rethrow（呼び出し側で表示する）。
  static Future<bool> purchase(Package package) async {
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      Entitlements.instance.applyCustomerInfo(result.customerInfo);
      return true;
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return false;
      }
      rethrow;
    }
  }

  /// 購入を復元する（再インストール・機種変更対応。ストア審査でも実質必須）。
  static Future<void> restore() async {
    final info = await Purchases.restorePurchases();
    Entitlements.instance.applyCustomerInfo(info);
  }
}

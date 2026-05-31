import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../dev/debug_flags.dart';

/// アプリ全体が参照する「権利（サブスク購入状態）」の単一の供給源。
///
/// 各フラグは **RevenueCat の実購入** と **[DebugFlags] のデバッグ上書き** の OR で決まる:
/// - 本番ビルド: デバッグメニューが非表示で [DebugFlags] は常に false のため、
///   実質的に RevenueCat の実購入だけが効く。
/// - デバッグビルド: デバッグメニューのトグルで擬似的に購入済みにできる。
///
/// 下流（`unlock_gate` / 広告判定 / 能力開示）はすべてこのクラスを読む。
/// RevenueCat の customerInfo 更新は [applyCustomerInfo] で流し込む（[BillingService] が配線）。
class Entitlements extends ChangeNotifier {
  Entitlements._() {
    // デバッグメニューでフラグが変わったら、このクラスの購読者にも伝播させる
    // （combined getter が [DebugFlags] を OR しているため）。
    DebugFlags.instance.addListener(notifyListeners);
  }

  /// プロセス内のシングルトン。
  static final Entitlements instance = Entitlements._();

  /// RevenueCat ダッシュボードで作成した Entitlement ID と一致させる。
  /// （広告非表示は Play 商品 ID が `sub_ad_hidden` だが Entitlement ID は `ad_removal`）
  static const String timeSkipId = 'time_skip';
  static const String adRemovalId = 'ad_removal';
  static const String abilityDisclosureId = 'ability_disclosure';

  bool _timeSkip = false;
  bool _adRemoval = false;
  bool _abilityDisclosure = false;

  /// 時間スキップ: 1日1試合の時間ゲートをバイパス。
  bool get hasTimeSkipSub => _timeSkip || DebugFlags.instance.hasTimeSkipSub;

  /// 広告非表示: 試合結果前の全画面広告を出さない。
  bool get hasAdRemovalSub => _adRemoval || DebugFlags.instance.hasAdRemovalSub;

  /// 能力開示＆編集: 選手の能力値・球種の表示と編集を解放。
  bool get hasAbilityDisclosureSub =>
      _abilityDisclosure || DebugFlags.instance.hasAbilityDisclosureSub;

  /// RevenueCat から取得した [CustomerInfo] の active entitlements を反映する。
  void applyCustomerInfo(CustomerInfo info) {
    final active = info.entitlements.active;
    final t = active.containsKey(timeSkipId);
    final a = active.containsKey(adRemovalId);
    final d = active.containsKey(abilityDisclosureId);
    if (t == _timeSkip && a == _adRemoval && d == _abilityDisclosure) return;
    _timeSkip = t;
    _adRemoval = a;
    _abilityDisclosure = d;
    notifyListeners();
  }
}

import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../billing/billing_service.dart';
import '../billing/entitlements.dart';
import 'help_screen.dart';

/// ショップ画面。3 種類のサブスクリプションを並べる。
///
/// 価格・購入は RevenueCat の Offering から取得する（[BillingService]）。
/// 購入済み状態は [Entitlements]（実購入 OR デバッグ上書き）を購読して表示する。
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

/// 1 カードぶんの静的な表示情報。価格は Offering の StoreProduct から動的に取得する。
class _ShopItem {
  /// RevenueCat の Offering に登録した package identifier。
  final String packageId;
  final String title;
  final String description;

  /// 購入済みか（[Entitlements] のどのフラグを見るか）。
  final bool Function(Entitlements e) isPurchased;

  const _ShopItem({required this.packageId, required this.title, required this.description, required this.isPurchased});
}

const List<_ShopItem> _items = [
  _ShopItem(packageId: Entitlements.timeSkipId, title: '時間スキップ', description: '毎日の決まった時間を待たずに、何度でも続けて試合結果を確認できます。', isPurchased: _isTimeSkip),
  _ShopItem(packageId: Entitlements.adRemovalId, title: '広告非表示', description: '試合結果の前に流れる広告を非表示にします。', isPurchased: _isAdRemoval),
  _ShopItem(
    packageId: Entitlements.abilityDisclosureId,
    title: '能力開示＆編集',
    description: '全チーム全選手の能力を表示し、名前も含めた全ての項目を自由に編集できます。',
    isPurchased: _isAbilityDisclosure,
  ),
];

// const コンテキストで使えるよう、getter 参照をトップレベル関数に切り出す。
bool _isTimeSkip(Entitlements e) => e.hasTimeSkipSub;
bool _isAdRemoval(Entitlements e) => e.hasAdRemovalSub;
bool _isAbilityDisclosure(Entitlements e) => e.hasAbilityDisclosureSub;

class _ShopScreenState extends State<ShopScreen> {
  Offering? _offering;
  bool _loading = true;

  /// 現在購入処理中の package identifier（多重タップ防止 + スピナー表示用）。
  String? _purchasingId;

  /// サブスク管理・解約画面の URL（アクティブなサブスクがある時のみ非 null）。
  String? _manageUrl;

  @override
  void initState() {
    super.initState();
    _loadOffering();
    _refreshManageUrl();
    // 購入・復元・解約で権利が変われば管理 URL の有無も変わるので追従する。
    Entitlements.instance.addListener(_onEntitlementsChanged);
  }

  @override
  void dispose() {
    Entitlements.instance.removeListener(_onEntitlementsChanged);
    super.dispose();
  }

  void _onEntitlementsChanged() {
    if (mounted) _refreshManageUrl();
  }

  Future<void> _loadOffering() async {
    setState(() => _loading = true);
    final offering = await BillingService.currentOffering();
    if (!mounted) return;
    setState(() {
      _offering = offering;
      _loading = false;
    });
  }

  Future<void> _refreshManageUrl() async {
    final url = await BillingService.managementUrl();
    if (!mounted) return;
    setState(() => _manageUrl = url);
  }

  Future<void> _purchase(Package package) async {
    setState(() => _purchasingId = package.identifier);
    try {
      final success = await BillingService.purchase(package);
      if (!mounted) return;
      if (success) {
        _showSnack('購入が完了しました。ありがとうございます。');
      }
      // キャンセル時 (success == false) は何も出さない。
    } catch (e) {
      if (!mounted) return;
      _showSnack('購入を完了できませんでした。時間をおいて再度お試しください。');
    } finally {
      if (mounted) setState(() => _purchasingId = null);
    }
  }

  Future<void> _restore() async {
    try {
      await BillingService.restore();
      if (!mounted) return;
      _showSnack('購入情報を復元しました。');
    } catch (e) {
      if (!mounted) return;
      _showSnack('復元できませんでした。時間をおいて再度お試しください。');
    }
  }

  Future<void> _openManage() async {
    final url = _manageUrl;
    if (url == null) return;
    // アプリ内から直接解約はできない（ストア仕様）ので、Play の定期購入画面を外部で開く。
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      _showSnack('管理画面を開けませんでした。');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ショップ'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        automaticallyImplyLeading: false,
        actions: [HelpScreen.appBarAction(context)],
      ),
      body: ListenableBuilder(
        listenable: Entitlements.instance,
        builder: (context, _) {
          final ent = Entitlements.instance;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 8, 4, 16),
                child: Text('お好きなものを選んでお楽しみください。', style: TextStyle(fontSize: 13)),
              ),
              for (final item in _items)
                _SubscriptionCard(
                  title: item.title,
                  description: item.description,
                  price: _priceFor(item.packageId),
                  isPurchased: item.isPurchased(ent),
                  isPurchasing: _purchasingId == item.packageId,
                  // 他カードの購入処理中・読み込み中はボタンを無効化する。
                  enabled: !_loading && _purchasingId == null,
                  onPurchase: () => _onPurchasePressed(item.packageId),
                ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(onPressed: _purchasingId == null ? _restore : null, child: const Text('購入を復元')),
              ),
              if (_manageUrl != null)
                Center(
                  child: TextButton(onPressed: _openManage, child: const Text('サブスクを管理・解約')),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Offering から該当パッケージの表示価格を引く。取得できなければ固定文言。
  String _priceFor(String packageId) {
    if (_loading) return '…';
    final pkg = _offering?.getPackage(packageId);
    if (pkg == null) return '月額 100 円';
    return '月額 ${pkg.storeProduct.priceString}';
  }

  void _onPurchasePressed(String packageId) {
    final pkg = _offering?.getPackage(packageId);
    if (pkg == null) {
      _showSnack('現在購入できません。時間をおいて再度お試しください。');
      _loadOffering();
      return;
    }
    _purchase(pkg);
  }
}

class _SubscriptionCard extends StatelessWidget {
  final String title;
  final String description;
  final String price;
  final bool isPurchased;
  final bool isPurchasing;
  final bool enabled;
  final VoidCallback onPurchase;

  const _SubscriptionCard({
    required this.title,
    required this.description,
    required this.price,
    required this.isPurchased,
    required this.isPurchasing,
    required this.enabled,
    required this.onPurchase,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(description, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  price,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                ),
                if (isPurchased)
                  const Chip(label: Text('購入済み'), backgroundColor: Color(0xFFE0F2E9))
                else if (isPurchasing)
                  const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  FilledButton(onPressed: enabled ? onPurchase : null, child: const Text('購入する')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

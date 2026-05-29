import 'package:flutter/material.dart';

import '../dev/debug_flags.dart';

/// ショップ画面。3 種類のサブスクリプションを並べる。
///
/// 現状はカードの UI 骨組みのみ。購入ボタンは SnackBar で「準備中」を出すだけ。
/// RevenueCat 連携が入ったら、`onPressed` を実購入処理に差し替える。
///
/// 購入済み状態は [DebugFlags] を購読しており、デバッグメニューでトグルすると
/// このカード表示も「購入済み」に切り替わる。
class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ショップ'), backgroundColor: Theme.of(context).colorScheme.inversePrimary, automaticallyImplyLeading: false),
      body: ListenableBuilder(
        listenable: DebugFlags.instance,
        builder: (context, _) {
          final flags = DebugFlags.instance;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 8, 4, 16),
                child: Text('お好きなものを選んでお楽しみください。', style: TextStyle(fontSize: 13)),
              ),
              _SubscriptionCard(title: '時間スキップ', description: '毎日の決まった時間を待たずに、何度でも続けて試合結果を確認できます。', price: '月額 100 円', isPurchased: flags.hasTimeSkipSub),
              _SubscriptionCard(title: '広告を消す', description: '試合結果の前に流れる広告を非表示にします。', price: '月額 100 円', isPurchased: flags.hasAdRemovalSub),
              _SubscriptionCard(
                title: '能力の表示と編集',
                description: '全チーム全選手の能力を表示し、名前も含めた全ての項目を自由に編集できます。',
                price: '月額 100 円',
                isPurchased: flags.hasAbilityDisclosureSub,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  final String title;
  final String description;
  final String price;
  final bool isPurchased;

  const _SubscriptionCard({required this.title, required this.description, required this.price, required this.isPurchased});

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
                else
                  FilledButton(onPressed: () => _onPurchasePressed(context), child: const Text('購入する')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _onPurchasePressed(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ストアでの購入は近日対応予定です。'), duration: Duration(seconds: 2)));
  }
}

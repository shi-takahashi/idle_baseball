import 'dart:async';

import 'package:flutter/material.dart';
import 'billing/billing_service.dart';
import 'screens/home_screen.dart';
import 'services/ad_service.dart';
import 'services/notification_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 起動直後に AdMob を初期化し、最初のインタースティシャル広告を先読み開始。
  // 失敗してもアプリ起動は継続させる（広告は試合フローの必須要件ではない）。
  unawaited(AdService.initialize());
  // ローカル通知プラグインを初期化（タイムゾーン読み込みも含む）。実際の予約は
  // `SeasonController` がロードされたあと `NotificationScheduler.reevaluate` で行う。
  unawaited(NotificationService.initialize());
  // RevenueCat を初期化し、購入済みのサブスク権利を `Entitlements` に取り込む。
  // 失敗してもアプリ起動は継続させる（課金は遊びの必須要件ではない）。
  unawaited(BillingService.configure());
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '眼力ベースボール',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

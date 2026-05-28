import 'dart:async';

import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/ad_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 起動直後に AdMob を初期化し、最初のインタースティシャル広告を先読み開始。
  // 失敗してもアプリ起動は継続させる（広告は試合フローの必須要件ではない）。
  unawaited(AdService.initialize());
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '放置系プロ野球',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

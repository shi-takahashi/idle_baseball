import 'package:flutter/material.dart';

import '../engine/engine.dart';

/// 個人成績画面（Step 4d 時点ではスタブ）
///
/// TODO(Step 4e): 打撃/投手ランキングを実装
class IndividualStatsScreen extends StatelessWidget {
  final SeasonController controller;

  const IndividualStatsScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('個人成績'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '個人成績ランキング\n(Step 4e で実装予定)',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      ),
    );
  }
}

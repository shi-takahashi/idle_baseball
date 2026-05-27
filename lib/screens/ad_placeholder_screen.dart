import 'dart:async';

import 'package:flutter/material.dart';

/// 試合結果確認前の全画面広告のスタブ。
///
/// 実際の広告 SDK 連携（AdMob 等）が入る前のプレースホルダー。3 秒間「広告（仮）」を
/// 表示してから自動で pop し、呼び出し元に制御を戻す。
///
/// 表示中はシステム戻るボタンで離脱できない（[PopScope] で canPop: false）。
/// 広告消しサブスクや onboarding 中は呼び出し側でこの画面自体を push しない。
///
/// 仕様詳細は docs/DAILY_GATE_PLAN.md「チャンク 5」を参照。
class AdPlaceholderScreen extends StatefulWidget {
  /// 表示秒数。
  final int durationSeconds;

  const AdPlaceholderScreen({super.key, this.durationSeconds = 3});

  @override
  State<AdPlaceholderScreen> createState() => _AdPlaceholderScreenState();
}

class _AdPlaceholderScreenState extends State<AdPlaceholderScreen> {
  late int _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.durationSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), _tick);
  }

  void _tick(Timer t) {
    if (!mounted) return;
    setState(() => _remaining--);
    if (_remaining <= 0) {
      t.cancel();
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  '広告（仮）',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '$_remaining 秒後に試合結果へ',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 48),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    '広告消しサブスクを購入すると、この画面が非表示になります',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

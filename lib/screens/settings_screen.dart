import 'package:flutter/material.dart';

import '../engine/engine.dart';

/// 設定画面
///
/// 現状はオフシーズン進行 ON/OFF のみ。今後の設定項目はここに追加していく。
class SettingsScreen extends StatelessWidget {
  final SeasonController controller;
  final Listenable listenable;

  const SettingsScreen({
    super.key,
    required this.controller,
    required this.listenable,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('設定'),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            automaticallyImplyLeading: false,
          ),
          body: ListView(
            children: [
              const _SectionHeader(title: 'シーズン進行'),
              SwitchListTile(
                title: const Text('オフシーズン進行'),
                subtitle: const Text(
                  'ON: 次シーズン移行時に選手が歳を取り、引退・新人加入が発生します（デフォルト）。\n'
                  'OFF: 加齢・引退・新人加入をスキップし、前シーズンと同じ選手・パラメータで開始します。\n'
                  '※ 手動での選手・チーム編集は ON/OFF どちらでも可能です。',
                ),
                value: controller.offseasonProgressionEnabled,
                onChanged: (v) =>
                    controller.offseasonProgressionEnabled = v,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

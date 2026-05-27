import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../dev/debug_flags.dart';
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
              const _SectionHeader(title: '試合結果の公開'),
              ListTile(
                title: const Text('結果確認時刻'),
                subtitle: const Text(
                  '毎日この時刻に試合結果が公開され、確認できるようになります。\n'
                  '前回の解禁から最低 12 時間空ける制約があるため、時刻を早めても同日中の再解禁は発生しません。',
                ),
                trailing: DropdownButton<int>(
                  value: controller.unlockHour,
                  items: [
                    for (int h = 0; h < 24; h++)
                      DropdownMenuItem(
                        value: h,
                        child: Text('${h.toString().padLeft(2, '0')}:00'),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) controller.unlockHour = v;
                  },
                ),
              ),
              const Divider(),
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
              if (kDebugMode) const _DebugSection(),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color? color;
  const _SectionHeader({required this.title, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color ?? Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// 開発時のみ表示されるデバッグメニュー。
/// 状態は [DebugFlags] のシングルトンに保持。永続化されず再起動でリセット。
class _DebugSection extends StatelessWidget {
  const _DebugSection();

  @override
  Widget build(BuildContext context) {
    final flags = DebugFlags.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 32),
        _SectionHeader(
          title: '開発者メニュー (debug build only)',
          color: Colors.orange.shade800,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            '※ いずれもセッション限定。再起動でリセットされます。本番ビルドでは表示されません。',
            style: TextStyle(
              fontSize: 11,
              color: Colors.orange.shade700,
            ),
          ),
        ),
        ListenableBuilder(
          listenable: flags,
          builder: (context, _) {
            return Column(
              children: [
                SwitchListTile(
                  title: const Text('時間スキップサブスク（仮）'),
                  subtitle: const Text(
                    'ON で 1日1試合制約を無視し、何度でも結果を確認できる扱いにする。',
                  ),
                  value: flags.hasTimeSkipSub,
                  onChanged: (v) => flags.hasTimeSkipSub = v,
                ),
                SwitchListTile(
                  title: const Text('広告消しサブスク（仮）'),
                  subtitle: const Text(
                    'ON で結果確認前の全画面広告が非表示になる扱いにする。',
                  ),
                  value: flags.hasAdRemovalSub,
                  onChanged: (v) => flags.hasAdRemovalSub = v,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

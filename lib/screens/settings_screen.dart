import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../dev/debug_flags.dart';
import '../engine/engine.dart';
import '../services/notification_scheduler.dart';
import '../services/notification_service.dart';

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
                subtitle: const Text('毎日この時刻に試合結果が公開されます。'),
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
                    if (v != null) {
                      controller.unlockHour = v;
                      // 解禁時刻が変わったら通知も新時刻で予約し直す。
                      NotificationScheduler.reevaluate(
                        controller,
                        hasTimeSkipSub: DebugFlags.instance.hasTimeSkipSub,
                      );
                    }
                  },
                ),
              ),
              SwitchListTile(
                title: const Text('結果公開時に通知する'),
                subtitle: const Text('結果が公開されたらお知らせします。'),
                value: controller.notificationsEnabled,
                onChanged: (v) async {
                  controller.notificationsEnabled = v;
                  if (v) {
                    // Android 13+ は OFF → ON の瞬間に権限要求ダイアログを出す。
                    // 拒否されても予約は試みる（次回起動時に再評価される）。
                    await NotificationService.requestPermission();
                  }
                  await NotificationScheduler.reevaluate(
                    controller,
                    hasTimeSkipSub: DebugFlags.instance.hasTimeSkipSub,
                  );
                },
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
              if (kDebugMode) _DebugSection(controller: controller),
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
  final SeasonController controller;

  const _DebugSection({required this.controller});

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
                  onChanged: (v) {
                    flags.hasTimeSkipSub = v;
                    // 時間スキップ ON で「常に解禁中」になるため予約通知は不要、
                    // OFF に戻したら次回解禁ぶんを予約し直す。
                    NotificationScheduler.reevaluate(
                      controller,
                      hasTimeSkipSub: v,
                    );
                  },
                ),
                SwitchListTile(
                  title: const Text('広告消しサブスク（仮）'),
                  subtitle: const Text(
                    'ON で結果確認前の全画面広告が非表示になる扱いにする。',
                  ),
                  value: flags.hasAdRemovalSub,
                  onChanged: (v) => flags.hasAdRemovalSub = v,
                ),
                SwitchListTile(
                  title: const Text('能力開示＆編集サブスク（仮）'),
                  subtitle: const Text(
                    'ON で選手の 1-10 能力値・球速・球種が表示され、能力編集も可能になる扱いにする。',
                  ),
                  value: flags.hasAbilityDisclosureSub,
                  onChanged: (v) => flags.hasAbilityDisclosureSub = v,
                ),
                ListTile(
                  title: const Text('通知の予約状況を確認'),
                  subtitle: const Text(
                    'OS に登録されている予約通知を一覧表示。Day10 視聴後に Day11 用の'
                    '予約が入っているかの切り分けに使う。',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showPendingNotifications(context),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _showPendingNotifications(BuildContext context) async {
    final pending = await NotificationService.pendingRequests();
    final lastScheduled = NotificationService.lastScheduledFor;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('予約通知の状況'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'OS への予約件数: ${pending.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '最後に scheduleNextUnlock した時刻: '
                  '${lastScheduled?.toString() ?? "(まだ予約していない / 再起動でリセット済み)"}',
                  style: const TextStyle(fontSize: 12),
                ),
                const Divider(height: 24),
                if (pending.isEmpty)
                  const Text(
                    '予約はありません。\n'
                    '- 通知 OFF\n'
                    '- onboarding 中（Day10 未満）\n'
                    '- 既に解禁済み（gate.isViewable == true）\n'
                    '- シーズン終了中\n'
                    'のいずれかに該当している可能性があります。',
                    style: TextStyle(fontSize: 12),
                  )
                else
                  ...pending.map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('id=${p.id}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold)),
                            Text('title: ${p.title ?? "(null)"}',
                                style: const TextStyle(fontSize: 12)),
                            Text('body: ${p.body ?? "(null)"}',
                                style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    );
  }
}

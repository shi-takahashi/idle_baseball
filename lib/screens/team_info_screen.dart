import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'team_edit_screen.dart';

/// チームの基本情報（名前・略称・カラー）の表示画面
///
/// チーム一覧の「基本情報」リンクから push される。
/// AppBar の編集ボタンから [TeamEditScreen] に遷移して編集できる。
/// `listenable` を購読しているので編集後はそのまま再描画される。
class TeamInfoScreen extends StatelessWidget {
  final SeasonController controller;
  final Listenable listenable;
  final String teamId;

  const TeamInfoScreen({
    super.key,
    required this.controller,
    required this.listenable,
    required this.teamId,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final team = controller.teams.firstWhere((t) => t.id == teamId);
        final primary = Color(team.primaryColorValue);
        return Scaffold(
          appBar: AppBar(
            title: const Text('チーム基本情報'),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            flexibleSpace: Align(
              alignment: Alignment.bottomCenter,
              child: Container(height: 3, color: primary),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: '編集',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TeamEditScreen(
                        controller: controller,
                        teamId: teamId,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _InfoRow(label: 'チーム名', value: team.name),
                    const Divider(height: 24),
                    _InfoRow(
                      label: '略称',
                      // 略称はスコアボードで使う英字1〜2文字
                      value: team.shortName.isEmpty ? '(未設定)' : team.shortName,
                    ),
                    const Divider(height: 24),
                    Row(
                      children: [
                        const SizedBox(
                          width: 96,
                          child: Text('チームカラー',
                              style: TextStyle(
                                  fontSize: 14, color: Colors.grey)),
                        ),
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: primary,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Colors.grey.shade300, width: 1),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '#${team.primaryColorValue.toRadixString(16).toUpperCase().padLeft(8, '0').substring(2)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(label,
              style: const TextStyle(fontSize: 14, color: Colors.grey)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 16)),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/engine.dart';

/// チーム基本情報の編集画面
///
/// チーム名・略称・チームカラーを変更できる。
/// 「保存」を押すと [SeasonController.updateTeam] で in-place 更新され、
/// 順位表・スコアボード・各種画面すべてに新しい値が反映される。
class TeamEditScreen extends StatefulWidget {
  final SeasonController controller;
  final String teamId;

  const TeamEditScreen({
    super.key,
    required this.controller,
    required this.teamId,
  });

  @override
  State<TeamEditScreen> createState() => _TeamEditScreenState();
}

class _TeamEditScreenState extends State<TeamEditScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _shortCtrl;
  late int _color;

  // 略称の最大文字数。スコアボードで2文字想定なので2に制限。
  static const int _shortNameMaxLen = 2;

  // 選択肢として並べる主要カラー。最後の行はバリエーション。
  // ARGB int 値（0xFFRRGGBB）。
  static const List<int> _palette = [
    0xFFE53935, // 赤
    0xFFD81B60, // ピンク
    0xFF8E24AA, // 紫
    0xFF5E35B1, // 深紫
    0xFF3949AB, // 紺
    0xFF1E88E5, // 青
    0xFF039BE5, // 水色
    0xFF00ACC1, // ターコイズ
    0xFF00897B, // 青緑
    0xFF43A047, // 緑
    0xFF7CB342, // 黄緑
    0xFFFBC02D, // 黄
    0xFFFB8C00, // 橙
    0xFFEF6C00, // 濃橙
    0xFF6D4C41, // 茶
    0xFF455A64, // 灰青
    0xFF000000, // 黒
    0xFFFFFFFF, // 白
  ];

  @override
  void initState() {
    super.initState();
    final t = widget.controller.teams.firstWhere((x) => x.id == widget.teamId);
    _nameCtrl = TextEditingController(text: t.name);
    _shortCtrl = TextEditingController(text: t.shortName);
    _color = t.primaryColorValue;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _shortCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('チーム編集'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存'),
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
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'チーム名',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _shortCtrl,
                  maxLength: _shortNameMaxLen,
                  inputFormatters: [
                    // スコアボードで使うので英数字に制限
                    FilteringTextInputFormatter.allow(
                        RegExp(r'[A-Za-z0-9]')),
                    UpperCaseTextFormatter(),
                  ],
                  decoration: const InputDecoration(
                    labelText: '略称（英数字 1〜2 文字）',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),
                const Text('チームカラー',
                    style: TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final c in _palette) _ColorChip(
                      color: c,
                      selected: c == _color,
                      onTap: () => setState(() => _color = c),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // プレビュー
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color:
                        Color.lerp(Colors.white, Color(_color), 0.18),
                    border: Border(
                      left: BorderSide(color: Color(_color), width: 4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _nameCtrl.text.isEmpty ? '(チーム名)' : _nameCtrl.text,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color.lerp(
                                Colors.black, Color(_color), 0.7),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Color(_color),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _shortCtrl.text.isEmpty ? '?' : _shortCtrl.text,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    final shortName = _shortCtrl.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('チーム名を入力してください')),
      );
      return;
    }
    if (shortName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('略称を入力してください')),
      );
      return;
    }

    widget.controller.updateTeam(
      widget.teamId,
      name: name,
      shortName: shortName,
      primaryColorValue: _color,
    );
    Navigator.of(context).pop();
  }
}

/// 略称用に常時大文字化する formatter
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class _ColorChip extends StatelessWidget {
  final int color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorChip({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Color(color),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.black : Colors.grey.shade300,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, size: 18, color: Colors.white)
            : null,
      ),
    );
  }
}

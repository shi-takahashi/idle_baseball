import 'package:flutter/material.dart';

import '../engine/engine.dart';
import '../persistence/save_service.dart';
import 'main_season_screen.dart';

/// ホーム画面
///
/// 既存セーブがあれば「続きから」+「新規シーズン」、無ければ「シーズン開始」のみ表示。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _saveService = SaveService();
  bool _checking = true;
  bool _hasSave = false;

  @override
  void initState() {
    super.initState();
    _refreshSaveState();
  }

  Future<void> _refreshSaveState() async {
    final has = await _saveService.hasSave();
    if (!mounted) return;
    setState(() {
      _hasSave = has;
      _checking = false;
    });
  }

  Future<void> _continueSeason() async {
    setState(() => _checking = true);
    SeasonController? controller;
    try {
      controller = await _saveService.load();
    } catch (e) {
      // 破損や互換性違いの場合は削除して新規へ誘導
      await _saveService.delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text('セーブデータを読み込めませんでした: $e'),
        ),
      );
      await _refreshSaveState();
      return;
    }
    if (!mounted) return;
    if (controller == null) {
      await _refreshSaveState();
      return;
    }
    await _enterSeason(controller);
  }

  Future<void> _newSeason() async {
    // 試合数セレクタ + 既存セーブ上書き警告を1つのダイアログにまとめる
    final gamesPerTeam = await showDialog<int>(
      context: context,
      builder: (ctx) => _NewSeasonDialog(
        showOverwriteWarning: _hasSave,
        initialGamesPerTeam: ScheduleGenerator.defaultGamesPerTeam,
      ),
    );
    if (gamesPerTeam == null || !mounted) return;

    final controller =
        SeasonController.newSeason(gamesPerTeam: gamesPerTeam);
    // 新規シーズン開始時に即座に保存して、古いセーブを上書きする
    await _saveService.save(controller);
    if (!mounted) return;
    await _enterSeason(controller);
  }

  Future<void> _enterSeason(SeasonController controller) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MainSeasonScreen(controller: controller),
      ),
    );
    if (!mounted) return;
    await _refreshSaveState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('放置系プロ野球'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: _checking
            ? const CircularProgressIndicator()
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '放置系プロ野球\nGMになろう！',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  if (_hasSave) ...[
                    ElevatedButton(
                      onPressed: _continueSeason,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 48, vertical: 16),
                      ),
                      child: const Text(
                        '続きから',
                        style: TextStyle(fontSize: 20),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _newSeason,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 48, vertical: 16),
                      ),
                      child: const Text(
                        '新規シーズン',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ] else
                    ElevatedButton(
                      onPressed: _newSeason,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 48, vertical: 16),
                      ),
                      child: const Text(
                        'シーズン開始',
                        style: TextStyle(fontSize: 20),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// 新規シーズン開始時のダイアログ（試合数選択 + 既存セーブ上書き警告）。
///
/// 戻り値: 選択された 1 チームあたり試合数 (30/90/150)、キャンセル時は null。
class _NewSeasonDialog extends StatefulWidget {
  final bool showOverwriteWarning;
  final int initialGamesPerTeam;

  const _NewSeasonDialog({
    required this.showOverwriteWarning,
    required this.initialGamesPerTeam,
  });

  @override
  State<_NewSeasonDialog> createState() => _NewSeasonDialogState();
}

class _NewSeasonDialogState extends State<_NewSeasonDialog> {
  late int _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialGamesPerTeam;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新規シーズン開始'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showOverwriteWarning) ...[
            const Text('現在のセーブデータは上書きされます。'),
            const SizedBox(height: 12),
          ],
          const Text('1シーズンの試合数:'),
          const SizedBox(height: 8),
          SeasonLengthSelector(
            value: _selected,
            onChanged: (v) => setState(() => _selected = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('キャンセル'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('開始'),
        ),
      ],
    );
  }
}

/// 30 / 90 / 150 試合のセグメントセレクタ。
/// HomeScreen と OffseasonScreen で共通利用する。
class SeasonLengthSelector extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const SeasonLengthSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      segments: [
        for (final n in ScheduleGenerator.allowedGamesPerTeam)
          ButtonSegment<int>(
            value: n,
            label: Text('$n試合'),
          ),
      ],
      selected: {value},
      onSelectionChanged: (s) {
        if (s.isNotEmpty) onChanged(s.first);
      },
      showSelectedIcon: false,
    );
  }
}

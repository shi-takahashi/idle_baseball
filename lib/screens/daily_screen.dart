import 'package:flutter/material.dart';

import '../engine/engine.dart';

/// 1日の試合結果画面（Step 4a: 最小シェル）
///
/// - 日付と自チーム名を表示
/// - [翌日へ] ボタンで次の日をシミュレート
/// - AppBar の早送りアイコンで残り全日を一括シミュレート（デバッグ用）
///
/// TODO(Step 4b): 自チームスコアボード表示、他2試合のサマリー表示
class DailyScreen extends StatefulWidget {
  final SeasonController controller;

  const DailyScreen({super.key, required this.controller});

  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends State<DailyScreen> {
  @override
  void initState() {
    super.initState();
    // シーズン開始直後なら自動的に Day 1 をシミュレート
    if (widget.controller.currentDay == 0) {
      widget.controller.advanceDay();
    }
  }

  void _advanceDay() {
    setState(() {
      widget.controller.advanceDay();
    });
  }

  void _advanceAll() {
    setState(() {
      widget.controller.advanceAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final ended = c.isSeasonOver;
    return Scaffold(
      appBar: AppBar(
        title: Text('Day ${c.currentDay} / ${c.totalDays}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.fast_forward),
            tooltip: '残り全日を一括シミュレート（デバッグ）',
            onPressed: ended ? null : _advanceAll,
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              ended ? 'シーズン終了' : 'Day ${c.currentDay}',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text('自チーム: ${c.myTeam.name}'),
            const SizedBox(height: 8),
            // 現時点での自チーム戦績（簡易）
            Builder(builder: (_) {
              final rec = c.standings.records
                  .firstWhere((r) => r.team.id == c.myTeamId);
              return Text(
                '${rec.wins}勝 ${rec.losses}敗 ${rec.ties}分  '
                '(${rec.winningPct.toStringAsFixed(3)})',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              );
            }),
            const SizedBox(height: 48),
            ElevatedButton(
              onPressed: ended ? null : _advanceDay,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 48, vertical: 16),
              ),
              child: Text(
                ended ? 'シーズン終了' : '翌日へ',
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

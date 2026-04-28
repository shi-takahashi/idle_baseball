import 'package:flutter/material.dart';

import '../engine/engine.dart';
import '../widgets/batting_stats.dart';
import '../widgets/game_summary_view.dart';
import '../widgets/pitching_stats.dart';
import '../widgets/score_board.dart';

/// 1試合の詳細結果画面
///
/// 指定された [gameResult] をスコア・打撃・投手の3タブで表示する。
/// [summary] が渡されればスコアボード下に勝敗投手・本塁打を表示する。
class GameResultScreen extends StatefulWidget {
  final GameResult gameResult;
  final GameSummary? summary;

  const GameResultScreen({
    super.key,
    required this.gameResult,
    this.summary,
  });

  @override
  State<GameResultScreen> createState() => _GameResultScreenState();
}

class _GameResultScreenState extends State<GameResultScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.gameResult;
    return Scaffold(
      appBar: AppBar(
        title: Text('${result.awayTeamName} @ ${result.homeTeamName}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'スコア'),
            Tab(text: '打撃成績'),
            Tab(text: '投手成績'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        // 横スワイプでタブ切り替えを起こさないようにする。
        // スコアボード側の横スクロール（延長戦）と干渉するため、
        // タブ切り替えは上部の TabBar タップに統一する。
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // スコアボードタブ
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ScoreBoard(gameResult: result),
                const SizedBox(height: 16),
                Text(
                  result.winner != null ? '勝者: ${result.winner}' : '引き分け',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                if (widget.summary != null)
                  GameSummaryView(
                    gameResult: result,
                    summary: widget.summary!,
                  ),
              ],
            ),
          ),
          // 打撃成績タブ
          Padding(
            padding: const EdgeInsets.all(8),
            child: BattingStats(gameResult: result),
          ),
          // 投手成績タブ
          Padding(
            padding: const EdgeInsets.all(8),
            child: PitchingStats(gameResult: result),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../engine/engine.dart';
import '../widgets/batting_stats.dart';
import '../widgets/pitching_stats.dart';
import '../widgets/score_board.dart';
import 'game_result_screen.dart';

/// 1日の試合結果画面
///
/// - メイン: 自チームの試合（スコアボード/打撃/投手 の3タブ）
/// - 下部: 他2試合のサマリー（カードタップで詳細画面に遷移）
///
/// 「翌日へ」「早送り」など進行系操作は親の [MainSeasonScreen] に移譲。
/// controller の更新通知に追従して再ビルドするため、build を [ListenableBuilder]
/// でラップしている。
class DailyScreen extends StatefulWidget {
  final SeasonController controller;

  const DailyScreen({super.key, required this.controller});

  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends State<DailyScreen>
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

  /// 現在の日の自チーム試合結果
  GameResult? _myGameResult() {
    final c = widget.controller;
    if (c.currentDay == 0) return null;
    final games = c.scheduledGamesOnDay(c.currentDay);
    final myGame = games.firstWhere(
      (g) => g.homeTeam.id == c.myTeamId || g.awayTeam.id == c.myTeamId,
      orElse: () => throw StateError('自チームの試合が見つかりません'),
    );
    return c.resultFor(myGame.gameNumber);
  }

  /// 現在の日の他2試合の結果
  List<GameResult> _otherGameResults() {
    final c = widget.controller;
    if (c.currentDay == 0) return const [];
    final games = c.scheduledGamesOnDay(c.currentDay);
    final others = games.where(
      (g) => g.homeTeam.id != c.myTeamId && g.awayTeam.id != c.myTeamId,
    );
    return others
        .map((sg) => c.resultFor(sg.gameNumber))
        .whereType<GameResult>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final myGame = _myGameResult();
        final otherGames = _otherGameResults();

        return Scaffold(
          appBar: AppBar(
            title: Text('Day ${c.currentDay} / ${c.totalDays}'),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            // 戻るボタンは親の MainSeasonScreen が PopScope で扱う想定なので
            // ここは明示的に無効化する（IndexedStack の各タブでルートのため）
            automaticallyImplyLeading: false,
            bottom: myGame == null
                ? null
                : TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(text: 'スコア'),
                      Tab(text: '打撃成績'),
                      Tab(text: '投手成績'),
                    ],
                  ),
          ),
          body: myGame == null
              ? const Center(child: Text('試合がありません'))
              : TabBarView(
                  controller: _tabController,
                  // 横スワイプでタブ切り替えを起こさないようにする。
                  // スコアボード側の横スクロール（延長戦）と干渉するため、
                  // タブ切り替えは上部の TabBar タップに統一する。
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildScoreTab(myGame, otherGames),
                    _buildBattingTab(myGame),
                    _buildPitchingTab(myGame),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildScoreTab(GameResult myGame, List<GameResult> otherGames) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 自チーム試合のヘッダ
          Text(
            '${myGame.awayTeamName} @ ${myGame.homeTeamName}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          ScoreBoard(gameResult: myGame),
          const SizedBox(height: 12),
          Text(
            myGame.winner != null ? '勝者: ${myGame.winner}' : '引き分け',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          const Text(
            '他の試合',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          for (final g in otherGames) _buildOtherGameCard(g),
        ],
      ),
    );
  }

  Widget _buildOtherGameCard(GameResult result) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => GameResultScreen(gameResult: result),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  result.awayTeamName,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '${result.awayScore} - ${result.homeScore}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: Text(
                  result.homeTeamName,
                  textAlign: TextAlign.left,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade500),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBattingTab(GameResult myGame) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: BattingStats(gameResult: myGame),
    );
  }

  Widget _buildPitchingTab(GameResult myGame) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: PitchingStats(gameResult: myGame),
    );
  }
}

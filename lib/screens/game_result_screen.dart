import 'package:flutter/material.dart';
import '../engine/engine.dart';
import '../widgets/score_board.dart';
import '../widgets/batting_stats.dart';
import '../widgets/pitching_stats.dart';

/// 試合結果画面
class GameResultScreen extends StatefulWidget {
  const GameResultScreen({super.key});

  @override
  State<GameResultScreen> createState() => _GameResultScreenState();
}

class _GameResultScreenState extends State<GameResultScreen>
    with SingleTickerProviderStateMixin {
  GameResult? _gameResult;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _simulateGame();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _simulateGame() {
    // タイガース: 速球派投手 + 強打者ライナップ
    final teamA = Team(
      id: 'team_a',
      name: 'タイガース',
      players: [
        const Player(id: 'a_0', name: '剛速球太郎', number: 18, averageSpeed: 155, control: 4),
        const Player(id: 'a_1', name: '首位打者', number: 1, meet: 8),
        const Player(id: 'a_2', name: '巧打者', number: 2, meet: 7),
        const Player(id: 'a_3', name: '強打者', number: 3, meet: 6),
        const Player(id: 'a_4', name: '四番打者', number: 4, meet: 7),
        const Player(id: 'a_5', name: '中堅打者', number: 5, meet: 6),
        const Player(id: 'a_6', name: '堅実打者', number: 6, meet: 6),
        const Player(id: 'a_7', name: '下位打者', number: 7, meet: 5),
        const Player(id: 'a_8', name: '守備職人', number: 8, meet: 4),
      ],
    );

    // ジャイアンツ: 技巧派投手 + 平均的ライナップ
    final teamB = Team(
      id: 'team_b',
      name: 'ジャイアンツ',
      players: [
        const Player(id: 'b_0', name: '技巧派次郎', number: 11, averageSpeed: 138, control: 8),
        const Player(id: 'b_1', name: '一番打者', number: 1, meet: 6),
        const Player(id: 'b_2', name: '二番打者', number: 2, meet: 5),
        const Player(id: 'b_3', name: '三番打者', number: 3, meet: 6),
        const Player(id: 'b_4', name: '四番打者', number: 4, meet: 5),
        const Player(id: 'b_5', name: '五番打者', number: 5, meet: 5),
        const Player(id: 'b_6', name: '六番打者', number: 6, meet: 4),
        const Player(id: 'b_7', name: '七番打者', number: 7, meet: 4),
        const Player(id: 'b_8', name: '八番打者', number: 8, meet: 3),
      ],
    );

    final simulator = GameSimulator();
    setState(() {
      _gameResult = simulator.simulate(teamB, teamA);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('試合結果'),
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
      body: _gameResult == null
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // スコアボードタブ
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ScoreBoard(gameResult: _gameResult!),
                      const SizedBox(height: 24),
                      Text(
                        _gameResult!.winner != null
                            ? '勝者: ${_gameResult!.winner}'
                            : '引き分け',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                // 打撃成績タブ
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: BattingStats(gameResult: _gameResult!),
                ),
                // 投手成績タブ
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: PitchingStats(gameResult: _gameResult!),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _simulateGame,
        tooltip: '再試合',
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

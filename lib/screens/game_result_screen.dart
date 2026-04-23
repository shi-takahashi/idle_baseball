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
    // タイガース: 速球派投手 + 強打者ライナップ（足速いチーム）
    final teamA = Team(
      id: 'team_a',
      name: 'タイガース',
      players: [
        const Player(
          id: 'a_0',
          name: '剛速球太郎',
          number: 18,
          averageSpeed: 155,
          fastball: 8,  // キレのあるストレート
          control: 4,
          stamina: 6,
          slider: 6,    // スライダーも投げる
          splitter: 7,  // 決め球のスプリット
          speed: 4,
          throws: Handedness.right,
        ),
        const Player(id: 'a_1', name: '首位打者', number: 1, meet: 8, power: 5, speed: 9, bats: Handedness.left),  // 左の俊足巧打
        const Player(id: 'a_2', name: '巧打者', number: 2, meet: 7, power: 4, speed: 8, bats: Handedness.both),    // スイッチヒッター
        const Player(id: 'a_3', name: '強打者', number: 3, meet: 6, power: 8, speed: 5, bats: Handedness.right),   // 右のパワー
        const Player(id: 'a_4', name: '四番打者', number: 4, meet: 7, power: 9, speed: 4, bats: Handedness.left),  // 左の主砲
        const Player(id: 'a_5', name: '中堅打者', number: 5, meet: 6, power: 6, speed: 7, bats: Handedness.right),
        const Player(id: 'a_6', name: '堅実打者', number: 6, meet: 6, power: 5, speed: 6, bats: Handedness.right),
        const Player(id: 'a_7', name: '下位打者', number: 7, meet: 5, power: 4, speed: 8, bats: Handedness.left),
        const Player(id: 'a_8', name: '守備職人', number: 8, meet: 4, power: 3, speed: 7, bats: Handedness.right),
      ],
      bench: [
        // 外野専任の強打代打候補
        const Player(
          id: 'a_ph1',
          name: '代打切り札',
          number: 35,
          meet: 7,
          power: 8,
          speed: 3,
          bats: Handedness.left,
          fielding: {
            DefensePosition.outfield: 5,
            DefensePosition.first: 4,
          },
        ),
        // バランス型代打
        const Player(
          id: 'a_ph2',
          name: '代打の神様',
          number: 36,
          meet: 8,
          power: 6,
          speed: 5,
          bats: Handedness.right,
          fielding: {
            DefensePosition.first: 5,
            DefensePosition.third: 5,
            DefensePosition.outfield: 4,
          },
        ),
        // 足のスペシャリスト（代走・守備要員）
        const Player(
          id: 'a_pr1',
          name: '韋駄天',
          number: 37,
          meet: 4,
          power: 2,
          speed: 10,
          bats: Handedness.right,
          fielding: {
            DefensePosition.outfield: 6,
            DefensePosition.second: 5,
          },
        ),
      ],
      bullpen: [
        const Player(
          id: 'a_rp1',
          name: '中継ぎA',
          number: 21,
          averageSpeed: 148,
          fastball: 6,
          control: 6,
          stamina: 4, // 中継ぎ型
          slider: 7,
          throws: Handedness.left, // 左の中継ぎ
        ),
        const Player(
          id: 'a_rp2',
          name: '中継ぎB',
          number: 22,
          averageSpeed: 143,
          fastball: 4,
          control: 7,
          stamina: 3,
          changeup: 7,
          throws: Handedness.right,
        ),
        const Player(
          id: 'a_cp',
          name: '守護神',
          number: 47,
          averageSpeed: 152,
          fastball: 8,
          control: 7,
          stamina: 3, // クローザー型
          splitter: 8,
          throws: Handedness.right,
        ),
      ],
    );

    // ジャイアンツ: 技巧派投手 + 平均的ライナップ（足普通チーム）
    final teamB = Team(
      id: 'team_b',
      name: 'ジャイアンツ',
      players: [
        const Player(
          id: 'b_0',
          name: '技巧派次郎',
          number: 11,
          averageSpeed: 138,
          fastball: 5,   // 普通のストレート
          control: 8,
          stamina: 7,
          curve: 8,      // 得意のカーブ
          slider: 5,     // スライダーも
          changeup: 7,   // チェンジアップで緩急
          speed: 3,
          throws: Handedness.left, // 技巧派左腕
        ),
        const Player(id: 'b_1', name: '一番打者', number: 1, meet: 6, power: 4, speed: 7, bats: Handedness.left),
        const Player(id: 'b_2', name: '二番打者', number: 2, meet: 5, power: 3, speed: 6, bats: Handedness.both),
        const Player(id: 'b_3', name: '三番打者', number: 3, meet: 6, power: 6, speed: 5, bats: Handedness.right),
        const Player(id: 'b_4', name: '四番打者', number: 4, meet: 5, power: 7, speed: 3, bats: Handedness.right),
        const Player(id: 'b_5', name: '五番打者', number: 5, meet: 5, power: 5, speed: 4, bats: Handedness.left),
        const Player(id: 'b_6', name: '六番打者', number: 6, meet: 4, power: 4, speed: 5, bats: Handedness.right),
        const Player(id: 'b_7', name: '七番打者', number: 7, meet: 4, power: 3, speed: 5, bats: Handedness.right),
        const Player(id: 'b_8', name: '八番打者', number: 8, meet: 3, power: 2, speed: 4, bats: Handedness.left),
      ],
      bench: [
        const Player(
          id: 'b_ph1',
          name: '強打代打',
          number: 38,
          meet: 7,
          power: 9,
          speed: 2,
          bats: Handedness.right,
          fielding: {
            DefensePosition.first: 5,
            DefensePosition.outfield: 3,
          },
        ),
        const Player(
          id: 'b_ph2',
          name: '万能控え',
          number: 39,
          meet: 6,
          power: 5,
          speed: 6,
          bats: Handedness.both,
          // 内外野どこでも守れる万能型
          fielding: {
            DefensePosition.second: 6,
            DefensePosition.third: 6,
            DefensePosition.shortstop: 5,
            DefensePosition.outfield: 5,
          },
        ),
        // 代走要員（足のスペシャリスト）
        const Player(
          id: 'b_pr1',
          name: '快足',
          number: 40,
          meet: 4,
          power: 2,
          speed: 9,
          bats: Handedness.left,
          fielding: {
            DefensePosition.outfield: 5,
            DefensePosition.second: 4,
          },
        ),
      ],
      bullpen: [
        const Player(
          id: 'b_rp1',
          name: '敗戦処理',
          number: 31,
          averageSpeed: 140,
          fastball: 4,
          control: 5,
          stamina: 6,
          curve: 5,
          throws: Handedness.right,
        ),
        const Player(
          id: 'b_rp2',
          name: 'セットアッパー',
          number: 32,
          averageSpeed: 146,
          fastball: 6,
          control: 7,
          stamina: 3,
          slider: 8,
          throws: Handedness.right,
        ),
        const Player(
          id: 'b_cp',
          name: '絶対的守護神',
          number: 54,
          averageSpeed: 150,
          fastball: 7,
          control: 8,
          stamina: 3,
          splitter: 9,
          throws: Handedness.right,
        ),
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

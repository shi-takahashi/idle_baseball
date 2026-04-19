import 'package:flutter/material.dart';
import 'engine/engine.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '放置系プロ野球',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  GameResult? _gameResult;

  @override
  void initState() {
    super.initState();
    _simulateGame();
  }

  void _simulateGame() {
    // タイガースの投手は速球派（平均155km）
    final teamA = Team(
      id: 'team_a',
      name: 'タイガース',
      players: [
        const Player(id: 'a_0', name: '剛速球太郎', number: 18, averageSpeed: 155),
        ...List.generate(
          8,
          (i) => Player(id: 'a_${i + 1}', name: '選手A${i + 2}', number: i + 2),
        ),
      ],
    );

    // ジャイアンツの投手は技巧派（平均138km）
    final teamB = Team(
      id: 'team_b',
      name: 'ジャイアンツ',
      players: [
        const Player(id: 'b_0', name: '技巧派次郎', number: 11, averageSpeed: 138),
        ...List.generate(
          8,
          (i) => Player(id: 'b_${i + 1}', name: '選手B${i + 2}', number: i + 2),
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
      ),
      body: _gameResult == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
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
      floatingActionButton: FloatingActionButton(
        onPressed: _simulateGame,
        tooltip: '再試合',
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

/// スコアボードウィジェット
class ScoreBoard extends StatelessWidget {
  final GameResult gameResult;

  const ScoreBoard({super.key, required this.gameResult});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Table(
          border: TableBorder.all(color: Colors.grey.shade300),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: {
            0: const FixedColumnWidth(80), // チーム名
            for (int i = 1; i <= 9; i++) i: const FixedColumnWidth(32), // 各イニング
            10: const FixedColumnWidth(40), // 計
          },
          children: [
            // ヘッダー行
            TableRow(
              decoration: BoxDecoration(color: Colors.grey.shade200),
              children: [
                _cell(context, '', null),
                for (int i = 1; i <= 9; i++) _cell(context, '$i', null),
                _cell(context, '計', null),
              ],
            ),
            // アウェイチーム（先攻）
            TableRow(
              children: [
                _cell(context, gameResult.awayTeamName, null, isTeamName: true),
                for (int i = 0; i < gameResult.inningScores.length; i++)
                  _cell(
                    context,
                    '${gameResult.inningScores[i].top ?? "-"}',
                    _getHalfInning(i + 1, true),
                    isClickable: true,
                  ),
                _cell(context, '${gameResult.awayScore}', null, isBold: true),
              ],
            ),
            // ホームチーム（後攻）
            TableRow(
              children: [
                _cell(context, gameResult.homeTeamName, null, isTeamName: true),
                for (int i = 0; i < gameResult.inningScores.length; i++)
                  _cell(
                    context,
                    gameResult.inningScores[i].bottom != null
                        ? '${gameResult.inningScores[i].bottom}'
                        : 'X',
                    _getHalfInning(i + 1, false),
                    isClickable: gameResult.inningScores[i].bottom != null,
                  ),
                _cell(context, '${gameResult.homeScore}', null, isBold: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  HalfInningResult? _getHalfInning(int inning, bool isTop) {
    try {
      return gameResult.halfInnings.firstWhere(
        (h) => h.inning == inning && h.isTop == isTop,
      );
    } catch (_) {
      return null;
    }
  }

  Widget _cell(
    BuildContext context,
    String text,
    HalfInningResult? halfInning, {
    bool isTeamName = false,
    bool isBold = false,
    bool isClickable = false,
  }) {
    final widget = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Text(
        text,
        textAlign: isTeamName ? TextAlign.left : TextAlign.center,
        style: TextStyle(
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          fontSize: isTeamName ? 12 : 14,
          color: isClickable ? Colors.blue.shade700 : null,
          decoration: isClickable ? TextDecoration.underline : null,
        ),
      ),
    );

    if (isClickable && halfInning != null) {
      return GestureDetector(
        onTap: () => _showInningDetail(context, halfInning),
        child: widget,
      );
    }
    return widget;
  }

  void _showInningDetail(BuildContext context, HalfInningResult halfInning) {
    final topBottom = halfInning.isTop ? '表' : '裏';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${halfInning.inning}回$topBottom (${halfInning.runs}点)'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: halfInning.atBats.length,
            itemBuilder: (context, index) {
              final atBat = halfInning.atBats[index];
              return _buildAtBatRow(index, atBat);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  Widget _buildAtBatRow(int index, AtBatResult atBat) {
    // 投球経過を文字列に（球速付き）
    final pitchLog = atBat.pitches.map((p) {
      final speedStr = '${p.speed}km';
      switch (p.type) {
        case PitchResultType.ball:
          return 'B($speedStr)';
        case PitchResultType.strikeLooking:
          return 'S見($speedStr)';
        case PitchResultType.strikeSwinging:
          return 'S空($speedStr)';
        case PitchResultType.foul:
          return 'F($speedStr)';
        case PitchResultType.inPlay:
          return '打($speedStr)';
      }
    }).join(' → ');

    // ランナー状況を文字列に
    final runners = atBat.runnersBefore;
    String runnerStatus;
    if (!runners.hasRunners) {
      runnerStatus = 'ランナーなし';
    } else {
      final bases = <String>[];
      if (runners.first != null) bases.add('一塁');
      if (runners.second != null) bases.add('二塁');
      if (runners.third != null) bases.add('三塁');
      runnerStatus = bases.join('・');
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${index + 1}. ${atBat.batter.name}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: atBat.result.isHit
                        ? Colors.green.shade100
                        : atBat.result == AtBatResultType.walk
                            ? Colors.blue.shade100
                            : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    atBat.result.displayName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: atBat.result.isHit
                          ? Colors.green.shade800
                          : atBat.result == AtBatResultType.walk
                              ? Colors.blue.shade800
                              : Colors.grey.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // アウトカウントとランナー状況
            Text(
              '${atBat.outsBefore}アウト $runnerStatus',
              style: TextStyle(
                fontSize: 12,
                color: Colors.brown.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '投球: $pitchLog',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            if (atBat.rbiCount > 0)
              Text(
                '打点: ${atBat.rbiCount}',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
              ),
          ],
        ),
      ),
    );
  }
}

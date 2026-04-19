import 'package:flutter/material.dart';
import '../engine/engine.dart';
import '../widgets/score_board.dart';

/// 試合結果画面
class GameResultScreen extends StatefulWidget {
  const GameResultScreen({super.key});

  @override
  State<GameResultScreen> createState() => _GameResultScreenState();
}

class _GameResultScreenState extends State<GameResultScreen> {
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

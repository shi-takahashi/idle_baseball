import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'game_result_screen.dart';

/// 指定チーム視点のシーズン日程・結果画面
///
/// チーム一覧の「日程・結果」リンクから push される。
/// シーズンの全試合を時系列に並べ、未消化試合は対戦予定、
/// 消化済みはスコアと勝敗を表示する。
/// 消化済みの行をタップすると [GameResultScreen] に遷移して試合詳細を確認できる。
class TeamScheduleScreen extends StatelessWidget {
  final SeasonController controller;
  final Listenable listenable;
  final String teamId;

  const TeamScheduleScreen({
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

        // このチームが絡む試合のみ抽出して日順に並べる
        final games = controller.schedule.games
            .where((g) =>
                g.homeTeam.id == teamId || g.awayTeam.id == teamId)
            .toList()
          ..sort((a, b) {
            final c = a.day.compareTo(b.day);
            if (c != 0) return c;
            return a.gameNumber.compareTo(b.gameNumber);
          });

        // チーム単位の通算成績を上部にサマリ表示
        int wins = 0, losses = 0, draws = 0, runsFor = 0, runsAgainst = 0;
        for (final sg in games) {
          final r = controller.resultFor(sg.gameNumber);
          if (r == null) continue;
          final isHome = sg.homeTeam.id == teamId;
          final my = isHome ? r.homeScore : r.awayScore;
          final op = isHome ? r.awayScore : r.homeScore;
          runsFor += my;
          runsAgainst += op;
          if (my > op) {
            wins++;
          } else if (my < op) {
            losses++;
          } else {
            draws++;
          }
        }

        return Scaffold(
          appBar: AppBar(
            title: Text('${team.name}　日程・結果'),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            flexibleSpace: Align(
              alignment: Alignment.bottomCenter,
              child: Container(height: 3, color: primary),
            ),
          ),
          body: Column(
            children: [
              _SummaryBar(
                wins: wins,
                losses: losses,
                draws: draws,
                runsFor: runsFor,
                runsAgainst: runsAgainst,
              ),
              const _HeaderRow(),
              Expanded(
                child: ListView.separated(
                  itemCount: games.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: Colors.grey.shade200,
                  ),
                  itemBuilder: (context, i) {
                    final sg = games[i];
                    final result = controller.resultFor(sg.gameNumber);
                    final summary = result == null
                        ? null
                        : controller.gameSummaryFor(sg.gameNumber);
                    return _GameRow(
                      scheduled: sg,
                      result: result,
                      teamId: teamId,
                      onTap: result == null
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => GameResultScreen(
                                    gameResult: result,
                                    summary: summary,
                                  ),
                                ),
                              );
                            },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 上部の戦績サマリ（消化分のみ）
class _SummaryBar extends StatelessWidget {
  final int wins;
  final int losses;
  final int draws;
  final int runsFor;
  final int runsAgainst;

  const _SummaryBar({
    required this.wins,
    required this.losses,
    required this.draws,
    required this.runsFor,
    required this.runsAgainst,
  });

  @override
  Widget build(BuildContext context) {
    final played = wins + losses + draws;
    final pct = (wins + losses) == 0
        ? null
        : (wins / (wins + losses)).toStringAsFixed(3);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.grey.shade100,
      child: Row(
        children: [
          Text(
            '$played 試合消化',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(width: 12),
          Text(
            '$wins 勝 $losses 敗 $draws 分',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold),
          ),
          if (pct != null) ...[
            const SizedBox(width: 8),
            Text('(.${pct.substring(2)})',
                style: const TextStyle(fontSize: 12)),
          ],
          const Spacer(),
          Text(
            '$runsFor - $runsAgainst',
            style: const TextStyle(
                fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

/// 列ヘッダー
class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.grey.shade200,
      child: const Row(
        children: [
          SizedBox(width: 32, child: _Hd('日')),
          SizedBox(width: 24, child: _Hd('H/A')),
          Expanded(child: _Hd('対戦')),
          SizedBox(width: 56, child: _Hd('スコア', center: true)),
          SizedBox(width: 24, child: _Hd('結', center: true)),
        ],
      ),
    );
  }
}

class _Hd extends StatelessWidget {
  final String label;
  final bool center;

  const _Hd(this.label, {this.center = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textAlign: center ? TextAlign.center : TextAlign.left,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
    );
  }
}

/// 1 試合の行
class _GameRow extends StatelessWidget {
  final ScheduledGame scheduled;
  final GameResult? result;
  final String teamId;
  final VoidCallback? onTap;

  const _GameRow({
    required this.scheduled,
    required this.result,
    required this.teamId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isHome = scheduled.homeTeam.id == teamId;
    final opponent = isHome ? scheduled.awayTeam : scheduled.homeTeam;
    final opColor = Color(opponent.primaryColorValue);

    String scoreText = '-';
    String resultMark = '-';
    Color resultColor = Colors.grey;
    if (result != null) {
      final my = isHome ? result!.homeScore : result!.awayScore;
      final op = isHome ? result!.awayScore : result!.homeScore;
      scoreText = '$my - $op';
      if (my > op) {
        resultMark = '○';
        resultColor = Colors.red.shade700;
      } else if (my < op) {
        resultMark = '●';
        resultColor = Colors.blue.shade700;
      } else {
        resultMark = '△';
        resultColor = Colors.grey.shade700;
      }
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                '${scheduled.day}',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
            SizedBox(
              width: 24,
              child: Text(
                isHome ? 'H' : 'A',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isHome ? Colors.deepOrange : Colors.indigo,
                ),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  // 相手チームカラーの小バッジ
                  Container(
                    width: 18,
                    height: 18,
                    margin: const EdgeInsets.only(right: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: opColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      opponent.shortName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      opponent.name,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 56,
              child: Text(
                scoreText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: result == null ? Colors.grey : null,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            SizedBox(
              width: 24,
              child: Text(
                resultMark,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: resultColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

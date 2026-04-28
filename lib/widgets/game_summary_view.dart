import 'package:flutter/material.dart';

import '../engine/engine.dart';

/// スコアボード下に表示する試合サマリー
/// 勝利投手 / 敗戦投手 / セーブ投手 / 本塁打打者を表示する。
class GameSummaryView extends StatelessWidget {
  final GameResult gameResult;
  final GameSummary summary;

  const GameSummaryView({
    super.key,
    required this.gameResult,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final hasDecisions = summary.winning != null ||
        summary.losing != null ||
        summary.saving != null;
    final hasHomeRuns = summary.homeRuns.isNotEmpty;
    if (!hasDecisions && !hasHomeRuns) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasDecisions) _buildDecisionsRow(context),
            if (hasDecisions && hasHomeRuns)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1),
              ),
            if (hasHomeRuns) _buildHomeRunsRow(context),
          ],
        ),
      ),
    );
  }

  Widget _buildDecisionsRow(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summary.winning != null)
          _buildLine(
            label: '勝利',
            record: summary.winning!,
            color: Colors.red.shade700,
          ),
        if (summary.losing != null)
          _buildLine(
            label: '敗戦',
            record: summary.losing!,
            color: Colors.blue.shade700,
          ),
        if (summary.saving != null)
          _buildLine(
            label: 'セーブ',
            record: summary.saving!,
            color: Colors.green.shade700,
          ),
      ],
    );
  }

  Widget _buildHomeRunsRow(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: Text(
            '本塁打',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ),
        ...summary.homeRuns.map(_buildHomeRunRow),
      ],
    );
  }

  Widget _buildHomeRunRow(HomeRunRecord hr) {
    final team = hr.isAway ? gameResult.awayTeam : gameResult.homeTeam;
    final teamColor = Color(team.primaryColorValue);
    final accentText = Color.lerp(Colors.black, teamColor, 0.7)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          // チームカラーの小さなマーカー
          Container(
            width: 4,
            height: 14,
            color: teamColor,
            margin: const EdgeInsets.only(right: 8),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 13),
                children: [
                  TextSpan(
                    text: hr.batter.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: accentText,
                    ),
                  ),
                  TextSpan(
                    text:
                        '  第${hr.seasonNumber}号  ${hr.inning}回${hr.isAway ? "表" : "裏"}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLine({
    required String label,
    required PitcherDecisionRecord record,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              border: Border.all(color: color, width: 1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            record.pitcher.name,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 6),
          Text(
            '(${record.wins}勝${record.losses}敗${record.saves}S)',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}

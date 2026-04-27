import 'package:flutter/material.dart';

import '../engine/engine.dart';

/// 順位表画面
///
/// 現時点の6チームの順位を表示。自チームは太字＋青色ハイライト。
/// 左：順位 + チーム名（固定） / 右：戦績・打率・本塁打・盗塁・防御率・失策（横スクロール）
class StandingsScreen extends StatelessWidget {
  final SeasonController controller;
  final Listenable listenable;

  const StandingsScreen({
    super.key,
    required this.controller,
    required this.listenable,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final sorted = controller.standings.sorted;
        final leader = sorted.isEmpty ? null : sorted.first;
        final rows = <_StandingsRow>[
          for (int i = 0; i < sorted.length; i++)
            _buildRowData(i + 1, sorted[i], leader),
        ];

        return Scaffold(
          appBar: AppBar(
            title: const Text('順位表'),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            automaticallyImplyLeading: false,
          ),
          body: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Day ${controller.currentDay} / ${controller.totalDays} 終了時点',
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFixedTable(rows),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: _buildScrollTable(rows),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 固定列：順位 + チーム名
  Widget _buildFixedTable(List<_StandingsRow> rows) {
    return DataTable(
      columnSpacing: 8,
      horizontalMargin: 8,
      headingRowHeight: 36,
      dataRowMinHeight: 36,
      dataRowMaxHeight: 36,
      columns: const [
        DataColumn(label: Text('順位', style: TextStyle(fontSize: 12))),
        DataColumn(label: Text('チーム', style: TextStyle(fontSize: 12))),
      ],
      rows: rows
          .map((r) => DataRow(cells: [
                DataCell(Text('${r.rank}', style: r.style)),
                DataCell(Text(r.teamName, style: r.style)),
              ]))
          .toList(),
    );
  }

  /// スクロール列：戦績 + チーム指標
  Widget _buildScrollTable(List<_StandingsRow> rows) {
    return DataTable(
      columnSpacing: 12,
      horizontalMargin: 8,
      headingRowHeight: 36,
      dataRowMinHeight: 36,
      dataRowMaxHeight: 36,
      columns: const [
        DataColumn(label: Text('試', style: TextStyle(fontSize: 12))),
        DataColumn(label: Text('勝', style: TextStyle(fontSize: 12))),
        DataColumn(label: Text('負', style: TextStyle(fontSize: 12))),
        DataColumn(label: Text('分', style: TextStyle(fontSize: 12))),
        DataColumn(label: Text('勝率', style: TextStyle(fontSize: 12))),
        DataColumn(label: Text('差', style: TextStyle(fontSize: 12))),
        DataColumn(label: Text('得', style: TextStyle(fontSize: 12))),
        DataColumn(label: Text('失', style: TextStyle(fontSize: 12))),
        DataColumn(label: Text('本塁打', style: TextStyle(fontSize: 12))),
        DataColumn(label: Text('盗塁', style: TextStyle(fontSize: 12))),
        DataColumn(label: Text('打率', style: TextStyle(fontSize: 12))),
        DataColumn(label: Text('防御率', style: TextStyle(fontSize: 12))),
        DataColumn(label: Text('失策', style: TextStyle(fontSize: 12))),
      ],
      rows: rows
          .map((r) => DataRow(cells: [
                DataCell(Text('${r.games}', style: r.style)),
                DataCell(Text('${r.wins}', style: r.style)),
                DataCell(Text('${r.losses}', style: r.style)),
                DataCell(Text('${r.ties}', style: r.style)),
                DataCell(Text(r.winningPct, style: r.style)),
                DataCell(Text(r.gb, style: r.style)),
                DataCell(Text('${r.runsScored}', style: r.style)),
                DataCell(Text('${r.runsAllowed}', style: r.style)),
                DataCell(Text('${r.homeRuns}', style: r.style)),
                DataCell(Text('${r.stolenBases}', style: r.style)),
                DataCell(Text(r.battingAvg, style: r.style)),
                DataCell(Text(r.era, style: r.style)),
                DataCell(Text('${r.errors}', style: r.style)),
              ]))
          .toList(),
    );
  }

  _StandingsRow _buildRowData(int rank, TeamRecord r, TeamRecord? leader) {
    final gb = leader == null || rank == 1
        ? '-'
        : controller.standings.gamesBehind(r, leader).toStringAsFixed(1);
    final isMyTeam = r.team.id == controller.myTeamId;
    final style = TextStyle(
      fontSize: 12,
      fontWeight: isMyTeam ? FontWeight.bold : FontWeight.normal,
      color: isMyTeam ? Colors.blue.shade800 : null,
    );

    final batting = controller.teamBattingTotals(r.team.id);
    final pitching = controller.teamPitchingTotals(r.team.id);
    final battingAvg = batting.atBats == 0
        ? '.000'
        : (batting.hits / batting.atBats).toStringAsFixed(3).substring(1);
    final era = pitching.outsRecorded == 0
        ? '-.--'
        : (pitching.runsAllowed * 27 / pitching.outsRecorded)
            .toStringAsFixed(2);

    return _StandingsRow(
      rank: rank,
      teamName: r.team.name,
      games: r.games,
      wins: r.wins,
      losses: r.losses,
      ties: r.ties,
      winningPct: r.winningPct.toStringAsFixed(3),
      gb: gb,
      runsScored: r.runsScored,
      runsAllowed: r.runsAllowed,
      battingAvg: battingAvg,
      homeRuns: batting.homeRuns,
      stolenBases: batting.stolenBases,
      era: era,
      errors: r.errors,
      style: style,
    );
  }
}

/// 順位表の1行分のデータ（固定列とスクロール列で共通利用）
class _StandingsRow {
  final int rank;
  final String teamName;
  final int games;
  final int wins;
  final int losses;
  final int ties;
  final String winningPct;
  final String gb;
  final int runsScored;
  final int runsAllowed;
  final String battingAvg;
  final int homeRuns;
  final int stolenBases;
  final String era;
  final int errors;
  final TextStyle style;

  const _StandingsRow({
    required this.rank,
    required this.teamName,
    required this.games,
    required this.wins,
    required this.losses,
    required this.ties,
    required this.winningPct,
    required this.gb,
    required this.runsScored,
    required this.runsAllowed,
    required this.battingAvg,
    required this.homeRuns,
    required this.stolenBases,
    required this.era,
    required this.errors,
    required this.style,
  });
}

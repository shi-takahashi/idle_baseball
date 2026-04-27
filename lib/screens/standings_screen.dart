import 'package:flutter/material.dart';

import '../engine/engine.dart';

/// 順位表画面
///
/// 現時点の6チームの順位を表示。自チームは太字ハイライト。
class StandingsScreen extends StatelessWidget {
  final SeasonController controller;

  const StandingsScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final sorted = controller.standings.sorted;
        final leader = sorted.isEmpty ? null : sorted.first;

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
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: _buildTable(context, sorted, leader),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTable(
      BuildContext context, List<TeamRecord> sorted, TeamRecord? leader) {
    return DataTable(
      columnSpacing: 12,
      headingRowHeight: 36,
      dataRowMinHeight: 36,
      dataRowMaxHeight: 36,
      columns: const [
        DataColumn(label: Text('順位', style: TextStyle(fontSize: 12))),
        DataColumn(label: Text('チーム', style: TextStyle(fontSize: 12))),
        DataColumn(label: Text('試', style: TextStyle(fontSize: 12))),
        DataColumn(label: Text('勝', style: TextStyle(fontSize: 12))),
        DataColumn(label: Text('負', style: TextStyle(fontSize: 12))),
        DataColumn(label: Text('分', style: TextStyle(fontSize: 12))),
        DataColumn(label: Text('勝率', style: TextStyle(fontSize: 12))),
        DataColumn(label: Text('差', style: TextStyle(fontSize: 12))),
        DataColumn(label: Text('得', style: TextStyle(fontSize: 12))),
        DataColumn(label: Text('失', style: TextStyle(fontSize: 12))),
        DataColumn(label: Text('得失', style: TextStyle(fontSize: 12))),
      ],
      rows: [
        for (int i = 0; i < sorted.length; i++)
          _buildRow(i + 1, sorted[i], leader),
      ],
    );
  }

  DataRow _buildRow(int rank, TeamRecord r, TeamRecord? leader) {
    final gb = leader == null || rank == 1
        ? '-'
        : controller.standings.gamesBehind(r, leader).toStringAsFixed(1);

    final isMyTeam = r.team.id == controller.myTeamId;
    final style = TextStyle(
      fontSize: 12,
      fontWeight: isMyTeam ? FontWeight.bold : FontWeight.normal,
      color: isMyTeam ? Colors.blue.shade800 : null,
    );

    final diffStr =
        '${r.runDifferential >= 0 ? '+' : ''}${r.runDifferential}';

    return DataRow(
      cells: [
        DataCell(Text('$rank', style: style)),
        DataCell(Text(r.team.name, style: style)),
        DataCell(Text('${r.games}', style: style)),
        DataCell(Text('${r.wins}', style: style)),
        DataCell(Text('${r.losses}', style: style)),
        DataCell(Text('${r.ties}', style: style)),
        DataCell(Text(r.winningPct.toStringAsFixed(3), style: style)),
        DataCell(Text(gb, style: style)),
        DataCell(Text('${r.runsScored}', style: style)),
        DataCell(Text('${r.runsAllowed}', style: style)),
        DataCell(Text(diffStr, style: style)),
      ],
    );
  }

}

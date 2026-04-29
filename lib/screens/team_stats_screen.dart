import 'package:flutter/material.dart';

import '../engine/engine.dart';

/// 単一チームの全選手シーズン成績画面
///
/// [TeamListScreen] のチームカードから「打撃成績」「投手成績」リンクを
/// 押すことで遷移してくる。push 時に [initialTabIndex] でどちらのタブを
/// 初期表示するかを指定する（0=打撃 / 1=投手）。
///
/// 「選手」列を左に固定し、右側を横スクロールするのは
/// 既存の BattingStats / PitchingStats と同じパターン。
class TeamStatsScreen extends StatefulWidget {
  final SeasonController controller;
  final Listenable listenable;
  final Team team;
  final int initialTabIndex;

  const TeamStatsScreen({
    super.key,
    required this.controller,
    required this.listenable,
    required this.team,
    this.initialTabIndex = 0,
  });

  @override
  State<TeamStatsScreen> createState() => _TeamStatsScreenState();
}

class _TeamStatsScreenState extends State<TeamStatsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Color(widget.team.primaryColorValue);
    return ListenableBuilder(
      listenable: widget.listenable,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.team.name),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            // チームカラーの帯を上部に
            flexibleSpace: Align(
              alignment: Alignment.bottomCenter,
              child: Container(height: 3, color: primary),
            ),
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: '打撃'),
                Tab(text: '投手'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            // 横スクロールしてもタブが切り替わらないようにする
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildBattingTab(),
              _buildPitchingTab(),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------
  // 打撃タブ
  // ---------------------------------------------------
  Widget _buildBattingTab() {
    final stats = widget.controller.batterStats.values
        .where((b) => b.team.id == widget.team.id)
        .toList()
      ..sort((a, b) {
        final c = b.plateAppearances.compareTo(a.plateAppearances);
        if (c != 0) return c;
        return b.atBats.compareTo(a.atBats);
      });
    if (stats.isEmpty) {
      return const Center(
        child: Text('データなし', style: TextStyle(color: Colors.grey)),
      );
    }
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Card(
          margin: EdgeInsets.zero,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBatterNameColumn(stats),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _buildBatterStatsTable(stats),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBatterNameColumn(List<BatterSeasonStats> stats) {
    return DataTable(
      columnSpacing: 8,
      horizontalMargin: 10,
      headingRowHeight: 32,
      dataRowMinHeight: 28,
      dataRowMaxHeight: 28,
      columns: const [
        DataColumn(
          label: Text('選手',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      ],
      rows: [
        for (final b in stats)
          DataRow(cells: [
            DataCell(_playerNameText(b.player)),
          ]),
      ],
    );
  }

  Widget _buildBatterStatsTable(List<BatterSeasonStats> stats) {
    return DataTable(
      columnSpacing: 12,
      horizontalMargin: 8,
      headingRowHeight: 32,
      dataRowMinHeight: 28,
      dataRowMaxHeight: 28,
      columns: const [
        DataColumn(label: _Hd('試')),
        DataColumn(label: _Hd('打席')),
        DataColumn(label: _Hd('打数')),
        DataColumn(label: _Hd('安')),
        DataColumn(label: _Hd('二')),
        DataColumn(label: _Hd('三')),
        DataColumn(label: _Hd('本')),
        DataColumn(label: _Hd('点')),
        DataColumn(label: _Hd('盗')),
        DataColumn(label: _Hd('四球')),
        DataColumn(label: _Hd('三振')),
        DataColumn(label: _Hd('打率')),
        DataColumn(label: _Hd('出塁')),
        DataColumn(label: _Hd('長打')),
        DataColumn(label: _Hd('OPS')),
      ],
      rows: [
        for (final b in stats)
          DataRow(cells: [
            _Cell.num(b.games),
            _Cell.num(b.plateAppearances),
            _Cell.num(b.atBats),
            _Cell.num(b.hits),
            _Cell.num(b.doubles),
            _Cell.num(b.triples),
            _Cell.num(b.homeRuns),
            _Cell.num(b.rbi),
            _Cell.num(b.stolenBases),
            _Cell.num(b.walks),
            _Cell.num(b.strikeouts),
            _Cell.rate(b.battingAverage),
            _Cell.rate(b.onBasePct),
            _Cell.rate(b.sluggingPct),
            _Cell.rate(b.ops),
          ]),
      ],
    );
  }

  // ---------------------------------------------------
  // 投手タブ
  // ---------------------------------------------------
  Widget _buildPitchingTab() {
    final stats = widget.controller.pitcherStats.values
        .where((p) => p.team.id == widget.team.id)
        .toList()
      ..sort((a, b) {
        // 先発登板数 → 投球回 → 登板数 の優先で降順
        final c1 = b.starts.compareTo(a.starts);
        if (c1 != 0) return c1;
        final c2 = b.outsRecorded.compareTo(a.outsRecorded);
        if (c2 != 0) return c2;
        return b.games.compareTo(a.games);
      });
    if (stats.isEmpty) {
      return const Center(
        child: Text('データなし', style: TextStyle(color: Colors.grey)),
      );
    }
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Card(
          margin: EdgeInsets.zero,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPitcherNameColumn(stats),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _buildPitcherStatsTable(stats),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPitcherNameColumn(List<PitcherSeasonStats> stats) {
    return DataTable(
      columnSpacing: 8,
      horizontalMargin: 10,
      headingRowHeight: 32,
      dataRowMinHeight: 28,
      dataRowMaxHeight: 28,
      columns: const [
        DataColumn(
          label: Text('選手',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      ],
      rows: [
        for (final p in stats)
          DataRow(cells: [
            DataCell(_playerNameText(p.player)),
          ]),
      ],
    );
  }

  Widget _buildPitcherStatsTable(List<PitcherSeasonStats> stats) {
    return DataTable(
      columnSpacing: 12,
      horizontalMargin: 8,
      headingRowHeight: 32,
      dataRowMinHeight: 28,
      dataRowMaxHeight: 28,
      columns: const [
        DataColumn(label: _Hd('登板')),
        DataColumn(label: _Hd('先発')),
        DataColumn(label: _Hd('勝')),
        DataColumn(label: _Hd('敗')),
        DataColumn(label: _Hd('S')),
        DataColumn(label: _Hd('H')),
        DataColumn(label: _Hd('回')),
        DataColumn(label: _Hd('被安')),
        DataColumn(label: _Hd('被本')),
        DataColumn(label: _Hd('与四')),
        DataColumn(label: _Hd('奪三')),
        DataColumn(label: _Hd('失')),
        DataColumn(label: _Hd('自責')),
        DataColumn(label: _Hd('防御率')),
        DataColumn(label: _Hd('WHIP')),
      ],
      rows: [
        for (final p in stats)
          DataRow(cells: [
            _Cell.num(p.games),
            _Cell.num(p.starts),
            _Cell.num(p.wins),
            _Cell.num(p.losses),
            _Cell.num(p.saves),
            _Cell.num(p.holds),
            _Cell.text(p.inningsPitchedDisplay),
            _Cell.num(p.hitsAllowed),
            _Cell.num(p.homeRunsAllowed),
            _Cell.num(p.walksAllowed),
            _Cell.num(p.strikeoutsRecorded),
            _Cell.num(p.runsAllowed),
            _Cell.num(p.earnedRuns),
            _Cell.text(p.outsRecorded == 0
                ? '-'
                : p.era.toStringAsFixed(2)),
            _Cell.text(p.outsRecorded == 0
                ? '-'
                : p.whip.toStringAsFixed(2)),
          ]),
      ],
    );
  }

  Widget _playerNameText(Player p) {
    return Text(
      p.name,
      style: const TextStyle(fontSize: 12),
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _Cell {
  static DataCell num(int v) => DataCell(
        Text('$v', style: const TextStyle(fontSize: 12)),
      );
  static DataCell rate(double v) => DataCell(
        Text(v.toStringAsFixed(3), style: const TextStyle(fontSize: 12)),
      );
  static DataCell text(String v) => DataCell(
        Text(v, style: const TextStyle(fontSize: 12)),
      );
}

class _Hd extends StatelessWidget {
  final String label;
  const _Hd(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
    );
  }
}

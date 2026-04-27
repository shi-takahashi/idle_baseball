import 'package:flutter/material.dart';

import '../engine/engine.dart';

/// 個人成績画面
///
/// タブ:
/// - 打撃: 首位打者(打率) / 本塁打王 / 打点王 / 盗塁王 / OPS
/// - 投手: 最優秀防御率 / 最多勝 / 最多奪三振 / WHIP
///
/// 自チームの選手は青色太字でハイライト。
class IndividualStatsScreen extends StatefulWidget {
  final SeasonController controller;

  const IndividualStatsScreen({super.key, required this.controller});

  @override
  State<IndividualStatsScreen> createState() =>
      _IndividualStatsScreenState();
}

class _IndividualStatsScreenState extends State<IndividualStatsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('個人成績'),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            automaticallyImplyLeading: false,
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
            children: [
              _buildBattingTab(),
              _buildPitchingTab(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBattingTab() {
    final c = widget.controller;
    final all = c.batterStats.values.toList();
    // 規定打席: シーズン試合数 × 3.1（現時点まで消化した試合数をベース）
    final qualifiedPA = (c.currentDay * 3.1).ceil();
    final qualified =
        all.where((b) => b.plateAppearances >= qualifiedPA).toList();

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        _buildHeader('Day ${c.currentDay}/${c.totalDays}   '
            '規定打席: $qualifiedPA'),
        _buildBatterRanking(
          '首位打者 (打率)',
          qualified,
          (b) => b.battingAverage,
          (v) => v.toStringAsFixed(3),
        ),
        _buildBatterRanking(
          '本塁打王',
          all,
          (b) => b.homeRuns.toDouble(),
          (v) => v.toInt().toString(),
          min: 1,
        ),
        _buildBatterRanking(
          '打点王',
          all,
          (b) => b.rbi.toDouble(),
          (v) => v.toInt().toString(),
          min: 1,
        ),
        _buildBatterRanking(
          '盗塁王',
          all,
          (b) => b.stolenBases.toDouble(),
          (v) => v.toInt().toString(),
          min: 1,
        ),
        _buildBatterRanking(
          'OPS',
          qualified,
          (b) => b.ops,
          (v) => v.toStringAsFixed(3),
        ),
      ],
    );
  }

  Widget _buildPitchingTab() {
    final c = widget.controller;
    final all = c.pitcherStats.values.toList();
    // 規定投球回: シーズン試合数 × 1.0
    final qualifiedIP = c.currentDay.toDouble();
    final qualified =
        all.where((p) => p.inningsPitched >= qualifiedIP).toList();

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        _buildHeader('Day ${c.currentDay}/${c.totalDays}   '
            '規定投球回: ${qualifiedIP.toInt()}'),
        _buildPitcherRanking(
          '最優秀防御率',
          qualified,
          (p) => p.era,
          (v) => v.toStringAsFixed(2),
          ascending: true,
        ),
        _buildPitcherRanking(
          '最多勝',
          all,
          (p) => p.wins.toDouble(),
          (v) => v.toInt().toString(),
          min: 1,
        ),
        _buildPitcherRanking(
          '最多奪三振',
          all,
          (p) => p.strikeoutsRecorded.toDouble(),
          (v) => v.toInt().toString(),
          min: 1,
        ),
        _buildPitcherRanking(
          'WHIP',
          qualified,
          (p) => p.whip,
          (v) => v.toStringAsFixed(2),
          ascending: true,
        ),
      ],
    );
  }

  Widget _buildHeader(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
      ),
    );
  }

  // ---------------------------------------------------
  // 打撃ランキング
  // ---------------------------------------------------
  Widget _buildBatterRanking(
    String title,
    List<BatterSeasonStats> batters,
    double Function(BatterSeasonStats) getValue,
    String Function(double) format, {
    int topN = 5,
    double min = 0,
    bool ascending = false,
  }) {
    final filtered = batters.where((b) => getValue(b) >= min).toList();
    filtered.sort((a, b) => ascending
        ? getValue(a).compareTo(getValue(b))
        : getValue(b).compareTo(getValue(a)));
    final top = filtered.take(topN).toList();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            if (top.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('該当選手なし',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              )
            else
              for (int i = 0; i < top.length; i++)
                _buildBatterRow(i + 1, top[i], getValue, format),
          ],
        ),
      ),
    );
  }

  Widget _buildBatterRow(
    int rank,
    BatterSeasonStats b,
    double Function(BatterSeasonStats) getValue,
    String Function(double) format,
  ) {
    final isMyTeam = b.team.id == widget.controller.myTeamId;
    final mainStyle = TextStyle(
      fontSize: 13,
      fontWeight: isMyTeam ? FontWeight.bold : FontWeight.normal,
      color: isMyTeam ? Colors.blue.shade800 : null,
    );
    final subStyle = TextStyle(
      fontSize: 10,
      color: isMyTeam ? Colors.blue.shade700 : Colors.grey.shade600,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 24, child: Text('$rank.', style: mainStyle)),
          SizedBox(
              width: 56,
              child: Text(format(getValue(b)),
                  style: mainStyle.copyWith(fontWeight: FontWeight.bold))),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${b.player.name}  (${b.team.name})',
                  style: mainStyle,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${b.atBats}打数${b.hits}安打  '
                  '${b.homeRuns}本${b.rbi}点  '
                  '盗${b.stolenBases}  四球${b.walks}  三振${b.strikeouts}',
                  style: subStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------
  // 投手ランキング
  // ---------------------------------------------------
  Widget _buildPitcherRanking(
    String title,
    List<PitcherSeasonStats> pitchers,
    double Function(PitcherSeasonStats) getValue,
    String Function(double) format, {
    int topN = 5,
    double min = 0,
    bool ascending = false,
  }) {
    final filtered = pitchers.where((p) => getValue(p) >= min).toList();
    filtered.sort((a, b) => ascending
        ? getValue(a).compareTo(getValue(b))
        : getValue(b).compareTo(getValue(a)));
    final top = filtered.take(topN).toList();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            if (top.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('該当選手なし',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              )
            else
              for (int i = 0; i < top.length; i++)
                _buildPitcherRow(i + 1, top[i], getValue, format),
          ],
        ),
      ),
    );
  }

  Widget _buildPitcherRow(
    int rank,
    PitcherSeasonStats p,
    double Function(PitcherSeasonStats) getValue,
    String Function(double) format,
  ) {
    final isMyTeam = p.team.id == widget.controller.myTeamId;
    final mainStyle = TextStyle(
      fontSize: 13,
      fontWeight: isMyTeam ? FontWeight.bold : FontWeight.normal,
      color: isMyTeam ? Colors.blue.shade800 : null,
    );
    final subStyle = TextStyle(
      fontSize: 10,
      color: isMyTeam ? Colors.blue.shade700 : Colors.grey.shade600,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 24, child: Text('$rank.', style: mainStyle)),
          SizedBox(
              width: 56,
              child: Text(format(getValue(p)),
                  style: mainStyle.copyWith(fontWeight: FontWeight.bold))),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${p.player.name}  (${p.team.name})',
                  style: mainStyle,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${p.inningsPitchedDisplay}回  '
                  '${p.wins}勝${p.losses}敗  '
                  '${p.strikeoutsRecorded}K  '
                  '${p.walksAllowed}四  '
                  '被${p.hitsAllowed}安  失${p.runsAllowed}',
                  style: subStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

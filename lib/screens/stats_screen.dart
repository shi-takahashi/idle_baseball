import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'help_screen.dart';
import 'individual_stats_screen.dart';
import 'standings_screen.dart';

/// 成績タブの親画面。3 タブ構成:
///   - 順位表: チーム順位とチーム指標
///   - 打撃: 個人打撃ランキング
///   - 投手: 個人投手ランキング
///
/// 旧 `StandingsScreen` と `IndividualStatsScreen` の表示を 1 タブに集約。
/// 中身は `StandingsView` / `BatterRankingView` / `PitcherRankingView` に分離して再利用。
class StatsScreen extends StatefulWidget {
  final SeasonController controller;
  final Listenable listenable;

  const StatsScreen({
    super.key,
    required this.controller,
    required this.listenable,
  });

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.listenable,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('成績'),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            automaticallyImplyLeading: false,
            actions: [HelpScreen.appBarAction(context)],
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: '順位表'),
                Tab(text: '打撃'),
                Tab(text: '投手'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              StandingsView(controller: widget.controller),
              BatterRankingView(controller: widget.controller),
              PitcherRankingView(controller: widget.controller),
            ],
          ),
        );
      },
    );
  }
}

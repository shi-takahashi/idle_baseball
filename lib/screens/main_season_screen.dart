import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'daily_screen.dart';
import 'individual_stats_screen.dart';
import 'season_listenable.dart';
import 'standings_screen.dart';
import 'team_list_screen.dart';

/// シーズン中の主画面
///
/// 下部 [NavigationBar] で「試合」「順位表」「個人成績」を切り替える。
/// 各タブは独立した [Navigator] を持つので、他試合の詳細を push しても
/// 下部のナビゲーションバーや「翌日へ」バーは画面に残る。
///
/// 「翌日へ」バー（自チーム戦績 + 翌日へ + 早送り）は MainSeasonScreen に常駐させ、
/// `SeasonController`（ChangeNotifier）の通知で内容を更新する。
class MainSeasonScreen extends StatefulWidget {
  final SeasonController controller;

  const MainSeasonScreen({super.key, required this.controller});

  @override
  State<MainSeasonScreen> createState() => _MainSeasonScreenState();
}

class _MainSeasonScreenState extends State<MainSeasonScreen> {
  int _selectedIndex = 0;

  /// 各タブの Navigator キー
  /// - タブ切替時に既存ルートを保持
  /// - WillPopScope などで個別に pop も可能
  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];

  /// SeasonController の通知を Listenable に変換するアダプタ
  /// 子画面・ListenableBuilder で共有する
  late final SeasonListenable _listenable;

  @override
  void initState() {
    super.initState();
    _listenable = SeasonListenable(widget.controller);
    // シーズン開始直後なら自動的に Day 1 をシミュレート
    if (widget.controller.currentDay == 0) {
      widget.controller.advanceDay();
    }
  }

  @override
  void dispose() {
    _listenable.dispose();
    super.dispose();
  }

  void _onSelect(int index) {
    if (index == _selectedIndex) {
      // 同じタブを再タップした場合はそのタブの先頭ルートに戻る
      _navigatorKeys[index]
          .currentState
          ?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() => _selectedIndex = index);
  }

  void _advanceDay() {
    if (widget.controller.isSeasonOver) return;
    widget.controller.advanceDay();
    // 進行後は前日の試合詳細などが残っていると紛らわしいので、
    // 現在のタブを最初のルート（DailyScreen 等）まで戻す
    _navigatorKeys[_selectedIndex]
        .currentState
        ?.popUntil((route) => route.isFirst);
  }

  void _advanceAll() {
    if (widget.controller.isSeasonOver) return;
    widget.controller.advanceAll();
    _navigatorKeys[_selectedIndex]
        .currentState
        ?.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // システムの戻るボタン: 現在のタブで pop できるなら pop、それ以外はホームへ戻る
        final navigator = _navigatorKeys[_selectedIndex].currentState;
        if (navigator != null && navigator.canPop()) {
          navigator.pop();
        } else if (mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _selectedIndex,
          children: [
            _buildTabNavigator(
              0,
              DailyScreen(
                controller: widget.controller,
                listenable: _listenable,
              ),
            ),
            _buildTabNavigator(
              1,
              StandingsScreen(
                controller: widget.controller,
                listenable: _listenable,
              ),
            ),
            _buildTabNavigator(
              2,
              IndividualStatsScreen(
                controller: widget.controller,
                listenable: _listenable,
              ),
            ),
            _buildTabNavigator(
              3,
              TeamListScreen(
                controller: widget.controller,
                listenable: _listenable,
              ),
            ),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 自チーム戦績 + 翌日へ + 早送り
            // controller の通知で再ビルドする
            ListenableBuilder(
              listenable: _listenable,
              builder: (context, _) => _buildAdvanceBar(),
            ),
            NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onSelect,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.sports_baseball),
                  label: '試合',
                ),
                NavigationDestination(
                  icon: Icon(Icons.leaderboard),
                  label: '順位表',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bar_chart),
                  label: '個人成績',
                ),
                NavigationDestination(
                  icon: Icon(Icons.groups_2),
                  label: 'チーム',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabNavigator(int index, Widget rootScreen) {
    return Navigator(
      key: _navigatorKeys[index],
      onGenerateRoute: (settings) =>
          MaterialPageRoute(builder: (_) => rootScreen),
    );
  }

  Widget _buildAdvanceBar() {
    final c = widget.controller;
    final ended = c.isSeasonOver;
    final rec = c.standings.records.firstWhere((r) => r.team.id == c.myTeamId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Day ${c.currentDay} / ${c.totalDays} ${c.myTeam.name}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '${rec.wins}勝 ${rec.losses}敗 ${rec.ties}分 '
                  '(${rec.winningPct.toStringAsFixed(3)})',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.fast_forward),
            tooltip: '残り全日を一括シミュレート（デバッグ）',
            onPressed: ended ? null : _advanceAll,
          ),
          ElevatedButton(
            onPressed: ended ? null : _advanceDay,
            style: ElevatedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text(
              ended ? 'シーズン終了' : '翌日へ',
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

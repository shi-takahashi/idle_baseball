import 'package:flutter/material.dart';

import '../engine/engine.dart';
import '../persistence/auto_saver.dart';
import '../persistence/save_service.dart';
import 'daily_screen.dart';
import 'individual_stats_screen.dart';
import 'offseason_screen.dart';
import 'season_listenable.dart';
import 'standings_screen.dart';
import 'strategy_screen.dart';
import 'team_list_screen.dart';

/// シーズン中の主画面
///
/// メイン（タブ0）は **作戦画面** = 次の試合のラインナップ調整。
/// 試合の時間が来るまではこの作戦画面が「ホーム」として表示され、
/// 「次の試合へ」を押すと:
///   1. シミュレートを実行 (`advanceDay`)
///   2. その日の試合結果（自チーム + 他2試合）を [DailyScreen] で push
///   3. 戻るボタンで作戦画面に戻り、翌日の作戦を組み直せる
/// シーズン終了までこのループ。
///
/// 順位表 / 個人成績 / チーム は補助的なタブ。
class MainSeasonScreen extends StatefulWidget {
  final SeasonController controller;

  const MainSeasonScreen({super.key, required this.controller});

  @override
  State<MainSeasonScreen> createState() => _MainSeasonScreenState();
}

class _MainSeasonScreenState extends State<MainSeasonScreen> {
  int _selectedIndex = 0;

  /// 各タブの Navigator キー
  /// 順序: 作戦 / 順位表 / 個人成績 / チーム
  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];

  /// 作戦画面への参照。早送り時にも作戦画面側のフォームを確定する必要があるため、
  /// 親（このクラス）から `tryCommit()` を呼べるようにキーで保持する。
  final GlobalKey<StrategyScreenState> _strategyKey =
      GlobalKey<StrategyScreenState>();

  /// SeasonController の通知を Listenable に変換するアダプタ
  late final SeasonListenable _listenable;

  /// SeasonController の通知に応じてセーブデータを自動更新するヘルパ
  late final AutoSaver _autoSaver;

  @override
  void initState() {
    super.initState();
    _listenable = SeasonListenable(widget.controller);
    _autoSaver = AutoSaver(widget.controller, SaveService());
    // シーズン開始直後は作戦画面で待機させたいので、Day 1 を自動消化はしない。
    // ユーザーが「次の試合へ」を押した時点で Day 1 が走り、結果が表示される。
  }

  @override
  void dispose() {
    // 画面を離れる前に未書き込みの編集を確実にディスクへ書き出す
    _autoSaver.flush();
    _autoSaver.dispose();
    _listenable.dispose();
    super.dispose();
  }

  void _onSelect(int index) {
    if (index == _selectedIndex) {
      _navigatorKeys[index]
          .currentState
          ?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() => _selectedIndex = index);
  }

  /// 「次の試合へ」: 試合は進めず、作戦タブに戻るだけ。
  ///
  /// 試合の実進行は作戦画面内の「試合開始」ボタンが担う。
  /// 将来 real-time 化したら「試合時間を過ぎてたら結果へ、まだなら作戦へ」の
  /// 分岐をここに入れる予定。
  void _goToStrategy() {
    if (_selectedIndex != 0) {
      setState(() => _selectedIndex = 0);
    }
    _navigatorKeys[0].currentState?.popUntil((route) => route.isFirst);
  }

  /// 作戦画面の「試合開始」ボタンから呼ぶ:
  /// 1日進めて、当日の結果画面 [DailyScreen] を作戦タブの上に push する。
  /// 戻るで作戦画面に復帰 → 翌日の作戦が表示される。
  void _runNextGame() {
    if (widget.controller.isSeasonOver) return;
    widget.controller.advanceDay();
    if (_selectedIndex != 0) {
      setState(() => _selectedIndex = 0);
    }
    final navigator = _navigatorKeys[0].currentState;
    if (navigator == null) return;
    navigator.popUntil((route) => route.isFirst);
    navigator.push(MaterialPageRoute(
      builder: (_) => DailyScreen(
        controller: widget.controller,
        listenable: _listenable,
      ),
    ));
  }

  void _advanceAll() {
    if (widget.controller.isSeasonOver) return;
    // 作戦画面のフォームに編集が残っていれば、ここで確定して反映してから進める。
    // 不整合があれば SnackBar が出て進行をキャンセル（`tryCommit` が false 返す）。
    final ok = _strategyKey.currentState?.tryCommit() ?? true;
    if (!ok) return;

    widget.controller.advanceAll();
    if (_selectedIndex != 0) {
      setState(() => _selectedIndex = 0);
    }
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
              StrategyScreen(
                key: _strategyKey,
                controller: widget.controller,
                listenable: _listenable,
                onStartGame: _runNextGame,
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
            ListenableBuilder(
              listenable: _listenable,
              builder: (context, _) => _buildAdvanceBar(),
            ),
            NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onSelect,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.assignment),
                  label: '作戦',
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

  /// シーズン終了状態から次シーズンへ進む。
  /// [OffseasonScreen] を push して、ユーザーに引退者・新人の選択をさせる。
  /// 確定で commit が走った後にここに戻り、作戦タブをルートに戻して
  /// 新シーズン Day 0 の作戦画面を表示する。
  Future<void> _advanceToNextSeason() async {
    final c = widget.controller;
    if (!c.isSeasonOver) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OffseasonScreen(controller: c),
      ),
    );
    if (!mounted) return;
    if (_selectedIndex != 0) {
      setState(() => _selectedIndex = 0);
    }
    _navigatorKeys[_selectedIndex]
        .currentState
        ?.popUntil((route) => route.isFirst);
  }

  Widget _buildAdvanceBar() {
    final c = widget.controller;
    final ended = c.isSeasonOver;
    final rec =
        c.standings.records.firstWhere((r) => r.team.id == c.myTeamId);
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
                  '${c.seasonYear}年目 Day ${c.currentDay} / ${c.totalDays} '
                  '${c.myTeam.name}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '${rec.wins}勝 ${rec.losses}敗 ${rec.ties}分 '
                  '(${rec.winningPct.toStringAsFixed(3)})',
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey.shade700),
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
            onPressed: ended ? _advanceToNextSeason : _goToStrategy,
            style: ElevatedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text(
              ended ? '次シーズンへ' : '次の試合へ',
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

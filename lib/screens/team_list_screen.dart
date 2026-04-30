import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'player_list_screen.dart';
import 'team_info_screen.dart';
import 'team_stats_screen.dart';

/// チーム一覧画面（下部ナビ「チーム」タブのルート）
///
/// 6チームをカード形式で並べ、各カードに「打撃成績」「投手成績」「選手一覧」
/// などのリンクを並べる。タップで該当チームの詳細画面に push する。
///
/// 「日程・結果」「対戦成績」は将来の拡張用に
/// 表示だけしておき、現状は無効リンクとして薄くグレーアウトしている。
class TeamListScreen extends StatelessWidget {
  final SeasonController controller;
  final Listenable listenable;

  const TeamListScreen({
    super.key,
    required this.controller,
    required this.listenable,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('チーム'),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            automaticallyImplyLeading: false,
          ),
          body: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: controller.teams.length,
            itemBuilder: (context, i) =>
                _TeamCard(
              team: controller.teams[i],
              isMyTeam: controller.teams[i].id == controller.myTeamId,
              onTapBatting: () =>
                  _openStats(context, controller.teams[i], 0),
              onTapPitching: () =>
                  _openStats(context, controller.teams[i], 1),
              onTapRoster: () => _openRoster(context, controller.teams[i]),
              onTapInfo: () => _openInfo(context, controller.teams[i]),
            ),
          ),
        );
      },
    );
  }

  void _openInfo(BuildContext context, Team team) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeamInfoScreen(
          controller: controller,
          listenable: listenable,
          teamId: team.id,
        ),
      ),
    );
  }

  void _openStats(BuildContext context, Team team, int initialTabIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeamStatsScreen(
          controller: controller,
          listenable: listenable,
          team: team,
          initialTabIndex: initialTabIndex,
        ),
      ),
    );
  }

  void _openRoster(BuildContext context, Team team) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerListScreen(
          controller: controller,
          listenable: listenable,
          teamId: team.id,
        ),
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  final Team team;
  final bool isMyTeam;
  final VoidCallback onTapBatting;
  final VoidCallback onTapPitching;
  final VoidCallback onTapRoster;
  final VoidCallback onTapInfo;

  const _TeamCard({
    required this.team,
    required this.isMyTeam,
    required this.onTapBatting,
    required this.onTapPitching,
    required this.onTapRoster,
    required this.onTapInfo,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Color(team.primaryColorValue);
    final bannerBg = Color.lerp(Colors.white, primary, 0.18)!;
    final accentText = Color.lerp(Colors.black, primary, 0.7)!;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // チーム名ヘッダー
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bannerBg,
              border: Border(left: BorderSide(color: primary, width: 4)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    team.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: accentText,
                    ),
                  ),
                ),
                if (isMyTeam)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      '自チーム',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // リンクの 2 列 × 2 行グリッド + 1 行（選手一覧）
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(child: _LinkText('日程・結果', null)),
                    const Expanded(child: _LinkText('対戦成績', null)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _LinkText('打撃成績', onTapBatting),
                    ),
                    Expanded(
                      child: _LinkText('投手成績', onTapPitching),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _LinkText('選手一覧', onTapRoster),
                    ),
                    Expanded(
                      child: _LinkText('基本情報', onTapInfo),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// テキストリンク。`onTap == null` のときは無効リンクとしてグレー表示。
class _LinkText extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _LinkText(this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = enabled
        ? Theme.of(context).colorScheme.primary
        : Colors.grey.shade400;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: color,
            decoration: enabled ? TextDecoration.underline : null,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'player_detail_screen.dart';

/// チーム所属選手の一覧画面
///
/// チーム一覧の「選手一覧」リンクから push される。
/// 「投手」「野手」の 2 タブで切り替え、各タブ内は背番号順に並べる
/// （ロスター40人化でスクロールが長くなるためタブ分割）。
/// 各行をタップすると [PlayerDetailScreen] に遷移して能力詳細を表示する。
///
/// `listenable` を購読しており、選手編集後に新しい能力で再描画される。
class PlayerListScreen extends StatelessWidget {
  final SeasonController controller;
  final Listenable listenable;
  final String teamId;

  const PlayerListScreen({
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

        // 投手（先発ローテ + 救援）/ 野手（主力 + 控え）を背番号順に。
        final pitchers = <Player>[
          ...team.startingRotation,
          ...team.bullpen,
        ]..sort((a, b) => a.number.compareTo(b.number));
        final fielders = <Player>[
          ...team.players.take(8),
          ...team.bench,
        ]..sort((a, b) => a.number.compareTo(b.number));

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text('${team.name}　選手一覧'),
              backgroundColor: Theme.of(context).colorScheme.inversePrimary,
              bottom: TabBar(
                indicatorColor: primary,
                tabs: [
                  Tab(text: '野手 (${fielders.length})'),
                  Tab(text: '投手 (${pitchers.length})'),
                ],
              ),
            ),
            // 左タブ＝野手（デフォルト表示）、右タブ＝投手。
            body: TabBarView(
              children: [
                _PlayerList(
                  players: fielders,
                  controller: controller,
                  listenable: listenable,
                ),
                _PlayerList(
                  players: pitchers,
                  controller: controller,
                  listenable: listenable,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 1 タブ分の選手リスト（背番号順に渡された [players] をそのまま並べる）。
class _PlayerList extends StatelessWidget {
  final List<Player> players;
  final SeasonController controller;
  final Listenable listenable;

  const _PlayerList({
    required this.players,
    required this.controller,
    required this.listenable,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final p in players)
          _PlayerRow(
            player: p,
            subtitle: _roleLabel(p),
            controller: controller,
            listenable: listenable,
          ),
      ],
    );
  }

  /// 行に出す肩書き。投手は先発/救援ロール、野手は守れる守備位置。
  /// 守備位置は **enum 順（捕→一→二→三→遊→外）** で並べ、選手ごとの順序揺らぎを
  /// 排除する（Map の挿入順だと生成時のサブポジ追加順に依存して安定しない）。
  static String _roleLabel(Player p) {
    if (p.isPitcher) {
      return p.pitcherRole?.displayName ?? '先発';
    }
    final map = p.fielding;
    if (map == null || map.isEmpty) return '—';
    final positions = [
      for (final dp in DefensePosition.values)
        if ((map[dp] ?? 0) > 0) dp.shortName,
    ];
    return positions.isEmpty ? '—' : positions.join('/');
  }
}

class _PlayerRow extends StatelessWidget {
  final Player player;
  final String subtitle;
  final SeasonController controller;
  final Listenable listenable;

  const _PlayerRow({
    required this.player,
    required this.subtitle,
    required this.controller,
    required this.listenable,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PlayerDetailScreen(
              controller: controller,
              listenable: listenable,
              playerId: player.id,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // 背番号
            SizedBox(
              width: 36,
              child: Text(
                '#${player.number}',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
            // 名前（背番号のすぐ右）+ 外国人タグ（カタカナ識別だけでは日本人で
            // カタカナ名(イチロー等、手動編集で起こり得る)と区別できないため復活）
            Text(
              player.name,
              style: const TextStyle(fontSize: 14),
            ),
            if (player.isForeign) ...[
              const SizedBox(width: 4),
              _foreignTag(),
            ],
            const SizedBox(width: 12),
            // ポジション / 役割（名前のすぐ右に続けて表示）
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            // 余白は右側に寄せ、利き手・矢印は右端に
            const Spacer(),
            Text(
              _handednessLabel(player),
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  String _handednessLabel(Player p) {
    if (p.isPitcher) {
      return '${p.effectiveThrows.displayName}投';
    }
    return '${p.effectiveBatsBase.displayName}打';
  }

  Widget _foreignTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.deepOrange.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.deepOrange.shade300, width: 0.5),
      ),
      child: Text(
        '外',
        style: TextStyle(
          fontSize: 10,
          color: Colors.deepOrange.shade700,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

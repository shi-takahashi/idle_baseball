import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'player_detail_screen.dart';

/// チーム所属選手の一覧画面
///
/// チーム一覧の「選手一覧」リンクから push される。
/// 投手（先発・救援）と野手（スタメン・控え）をセクションに分けて並べる。
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

        // 先発ローテ（6人）
        final starters = team.startingRotation;
        // 救援投手（ロール順に並べ替え）
        final relievers = [...team.bullpen]..sort((a, b) {
            final ra = a.reliefRole?.index ?? 999;
            final rb = b.reliefRole?.index ?? 999;
            return ra.compareTo(rb);
          });
        // スタメン野手（players[0..7]）
        final fielders = team.players.sublist(0, 8);
        // 控え野手
        final bench = team.bench;

        return Scaffold(
          appBar: AppBar(
            title: Text('${team.name}　選手一覧'),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            flexibleSpace: Align(
              alignment: Alignment.bottomCenter,
              child: Container(height: 3, color: primary),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _SectionHeader(label: '先発ローテーション (${starters.length})'),
              for (final p in starters)
                _PlayerRow(
                  player: p,
                  subtitle: '先発',
                  controller: controller,
                  listenable: listenable,
                ),
              _SectionHeader(label: '救援投手 (${relievers.length})'),
              for (final p in relievers)
                _PlayerRow(
                  player: p,
                  subtitle: p.reliefRole?.displayName ?? '救援',
                  controller: controller,
                  listenable: listenable,
                ),
              _SectionHeader(label: 'スタメン野手 (${fielders.length})'),
              for (int i = 0; i < fielders.length; i++)
                _PlayerRow(
                  player: fielders[i],
                  subtitle: _starterPositionLabel(i),
                  controller: controller,
                  listenable: listenable,
                ),
              _SectionHeader(label: '控え野手 (${bench.length})'),
              for (final p in bench)
                _PlayerRow(
                  player: p,
                  subtitle: _benchPositionLabel(p),
                  controller: controller,
                  listenable: listenable,
                ),
            ],
          ),
        );
      },
    );
  }

  // players[0..7] のデフォルト守備配置
  static const _starterPositions = [
    '捕',
    '一',
    '二',
    '三',
    '遊',
    '左',
    '中',
    '右',
  ];

  String _starterPositionLabel(int index) {
    return _starterPositions[index];
  }

  String _benchPositionLabel(Player p) {
    final map = p.fielding;
    if (map == null || map.isEmpty) return '控え';
    final positions = map.entries
        .where((e) => e.value > 0)
        .map((e) => e.key.shortName)
        .toList();
    return positions.isEmpty ? '控え' : positions.join('/');
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.grey.shade200,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
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
            // ポジション
            SizedBox(
              width: 56,
              child: Text(
                subtitle,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            // 名前
            Expanded(
              child: Text(
                player.name,
                style: const TextStyle(fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 利き
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
}

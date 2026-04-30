import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'player_edit_screen.dart';

/// 選手1人の能力パラメータ詳細画面
///
/// 1〜10 評価のパラメータは横長のメーターで可視化する。
/// 投手と野手で表示するパラメータが異なるため `_buildPitcherBody` /
/// `_buildFielderBody` に分岐させる。
///
/// AppBar の編集ボタンから [PlayerEditScreen] に遷移し、保存すると
/// `controller.updatePlayer` で値が反映される。本画面は `listenable`
/// を購読しているので、編集後にそのまま新しい値で再描画される。
class PlayerDetailScreen extends StatelessWidget {
  final SeasonController controller;
  final Listenable listenable;
  final String playerId;

  const PlayerDetailScreen({
    super.key,
    required this.controller,
    required this.listenable,
    required this.playerId,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final player = controller.findPlayerById(playerId);
        if (player == null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('選手'),
              backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            ),
            body: const Center(child: Text('選手が見つかりません')),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(player.name),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: '編集',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlayerEditScreen(
                        controller: controller,
                        initial: player,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context, player),
                const SizedBox(height: 12),
                if (player.isPitcher)
                  _buildPitcherBody(player)
                else
                  _buildFielderBody(player),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------
  // ヘッダー（名前・背番号・利き腕・打席・ロール）
  // ---------------------------------------------------
  Widget _buildHeader(BuildContext context, Player player) {
    final tags = <String>[];
    if (player.isPitcher) {
      tags.add(player.reliefRole == null ? '先発' : '救援');
      if (player.reliefRole != null) {
        tags.add(player.reliefRole!.displayName);
      }
      tags.add('${player.effectiveThrows.displayName}投');
      tags.add('${player.effectiveBatsBase.displayName}打');
    } else {
      tags.add('野手');
      tags.add('${player.effectiveBatsBase.displayName}打');
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(
                '#${player.number}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final t in tags) _Chip(label: t),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // 投手向け
  // ---------------------------------------------------
  Widget _buildPitcherBody(Player player) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title: '基本能力',
          children: [
            _SpeedRow(label: '球速', kmh: player.averageSpeed ?? 0),
            _RatingRow(label: '制球', value: player.control),
            _RatingRow(label: 'ストレートの質', value: player.fastball),
            _RatingRow(label: 'スタミナ', value: player.stamina),
          ],
        ),
        const SizedBox(height: 8),
        _SectionCard(
          title: '球種',
          children: [
            _PitchRow(label: 'スライダー', value: player.slider),
            _PitchRow(label: 'カーブ', value: player.curve),
            _PitchRow(label: 'スプリット', value: player.splitter),
            _PitchRow(label: 'チェンジアップ', value: player.changeup),
          ],
        ),
        const SizedBox(height: 8),
        // 投手も打席に立つので簡易表示
        _SectionCard(
          title: '打撃（参考）',
          children: [
            _RatingRow(label: 'ミート', value: player.meet),
            _RatingRow(label: '長打', value: player.power),
            _RatingRow(label: '選球眼', value: player.eye),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------
  // 野手向け
  // ---------------------------------------------------
  Widget _buildFielderBody(Player player) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title: '打撃',
          children: [
            _RatingRow(label: 'ミート', value: player.meet),
            _RatingRow(label: '長打', value: player.power),
            _RatingRow(label: '選球眼', value: player.eye),
          ],
        ),
        const SizedBox(height: 8),
        _SectionCard(
          title: '走塁・守備',
          children: [
            _RatingRow(label: '走力', value: player.speed),
            _RatingRow(label: '肩', value: player.arm),
            if (player.lead != null)
              _RatingRow(label: 'リード', value: player.lead),
          ],
        ),
        const SizedBox(height: 8),
        _SectionCard(
          title: '守備力（ポジション別）',
          children: _buildFieldingRows(player),
        ),
      ],
    );
  }

  List<Widget> _buildFieldingRows(Player player) {
    final map = player.fielding;
    if (map == null) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text(
            '全ポジション可（基準値5）',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      ];
    }
    // すべてのポジションを並べ、守れないものはダッシュ表示
    return [
      for (final pos in DefensePosition.values)
        _FieldingRow(
          label: pos.displayName,
          value: map[pos],
        ),
    ];
  }
}

// =====================================================
// パーツ
// =====================================================

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// 1〜10 のレーティングを横メーターで表示。null は「-」。
class _RatingRow extends StatelessWidget {
  final String label;
  final int? value;

  const _RatingRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
          Expanded(child: _RatingMeter(value: value)),
          const SizedBox(width: 8),
          SizedBox(
            width: 28,
            child: Text(
              value == null ? '-' : '$value',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 球種行。null は「投げない」とグレー表示。
class _PitchRow extends StatelessWidget {
  final String label;
  final int? value;

  const _PitchRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final disabled = value == null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: disabled ? Colors.grey : null,
              ),
            ),
          ),
          Expanded(
            child: disabled
                ? Text(
                    '投げない',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  )
                : _RatingMeter(value: value),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 28,
            child: Text(
              disabled ? '-' : '$value',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                color: disabled ? Colors.grey : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 守備力行。値 null（マップに無い）or 0 は「×」表示。
class _FieldingRow extends StatelessWidget {
  final String label;
  final int? value;

  const _FieldingRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final canPlay = value != null && value! > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: canPlay ? null : Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: canPlay
                ? _RatingMeter(value: value)
                : Text(
                    '守れない',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 28,
            child: Text(
              canPlay ? '$value' : '-',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                color: canPlay ? null : Colors.grey,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 球速の行（数値 + 単位）
class _SpeedRow extends StatelessWidget {
  final String label;
  final int kmh;

  const _SpeedRow({required this.label, required this.kmh});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
          Expanded(child: _SpeedMeter(kmh: kmh)),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: Text(
              '$kmh km/h',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 1〜10 のレーティングを横棒で表示。
/// 値が高いほど青→緑、低いほど赤に寄せる。
class _RatingMeter extends StatelessWidget {
  final int? value;

  const _RatingMeter({required this.value});

  @override
  Widget build(BuildContext context) {
    final v = value ?? 0;
    final ratio = v.clamp(0, 10) / 10.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Stack(
        children: [
          Container(height: 8, color: Colors.grey.shade200),
          FractionallySizedBox(
            widthFactor: ratio,
            child: Container(
              height: 8,
              color: _colorFor(v),
            ),
          ),
        ],
      ),
    );
  }

  Color _colorFor(int v) {
    if (v >= 8) return Colors.green.shade600;
    if (v >= 6) return Colors.lightGreen.shade600;
    if (v >= 4) return Colors.amber.shade600;
    if (v >= 2) return Colors.orange.shade600;
    return Colors.red.shade400;
  }
}

/// 球速メーター（130〜160 を 0〜100% にマッピング）
class _SpeedMeter extends StatelessWidget {
  final int kmh;

  const _SpeedMeter({required this.kmh});

  @override
  Widget build(BuildContext context) {
    const minKmh = 130;
    const maxKmh = 160;
    final ratio =
        ((kmh - minKmh) / (maxKmh - minKmh)).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Stack(
        children: [
          Container(height: 8, color: Colors.grey.shade200),
          FractionallySizedBox(
            widthFactor: ratio,
            child: Container(
              height: 8,
              color: _colorFor(kmh),
            ),
          ),
        ],
      ),
    );
  }

  Color _colorFor(int kmh) {
    if (kmh >= 152) return Colors.green.shade600;
    if (kmh >= 145) return Colors.lightGreen.shade600;
    if (kmh >= 140) return Colors.amber.shade600;
    return Colors.orange.shade600;
  }
}

class _Chip extends StatelessWidget {
  final String label;

  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11),
      ),
    );
  }
}

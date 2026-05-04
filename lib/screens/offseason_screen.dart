import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'home_screen.dart' show SeasonLengthSelector;

/// オフシーズン編成画面（自チーム用）。
///
/// シーズン終了時に [MainSeasonScreen] から push される。
/// `SeasonController.prepareOffseason()` で生成した候補一覧を表示し、
/// ユーザーが引退者と新人を選択 → 「次シーズン開始」で
/// `SeasonController.commitOffseason(...)` に流す。
///
/// 戻るで離脱した場合は何も変更せずに終了（シーズン終了状態のまま）。
/// 再度 push されたら新しい新人候補が生成される。
class OffseasonScreen extends StatefulWidget {
  final SeasonController controller;

  const OffseasonScreen({super.key, required this.controller});

  @override
  State<OffseasonScreen> createState() => _OffseasonScreenState();
}

class _OffseasonScreenState extends State<OffseasonScreen> {
  late final OffseasonPlan _plan;

  /// 各候補の選択状態（id → 選択中か）
  final _retireFielderSelected = <String>{};
  final _retirePitcherSelected = <String>{};
  final _takeFielderSelected = <String>{};
  final _takePitcherSelected = <String>{};

  /// 次シーズンの試合数（30 / 90 / 150）。デフォルトは前シーズンの試合数。
  late int _nextGamesPerTeam;

  @override
  void initState() {
    super.initState();
    _plan = widget.controller.prepareOffseason();
    _nextGamesPerTeam = widget.controller.gamesPerTeam;
    _applyRecommended();
  }

  void _applyRecommended() {
    setState(() {
      _retireFielderSelected
        ..clear()
        ..addAll(_plan.recommendedRetireFielderIds);
      _retirePitcherSelected
        ..clear()
        ..addAll(_plan.recommendedRetirePitcherIds);
      _takeFielderSelected
        ..clear()
        ..addAll(_plan.recommendedTakeFielderIds);
      _takePitcherSelected
        ..clear()
        ..addAll(_plan.recommendedTakePitcherIds);
    });
  }

  void _clearAll() {
    setState(() {
      _retireFielderSelected.clear();
      _retirePitcherSelected.clear();
      _takeFielderSelected.clear();
      _takePitcherSelected.clear();
    });
  }

  /// 引退と新人の数が両方とも揃っていれば true。
  /// 0+0 でも valid（自チーム無編集で次シーズンへ）。
  bool get _isValid =>
      _retireFielderSelected.length == _takeFielderSelected.length &&
      _retirePitcherSelected.length == _takePitcherSelected.length;

  /// 「○ 名引退 / ○ 名加入」の説明テキスト
  String get _summaryText {
    final rf = _retireFielderSelected.length;
    final rp = _retirePitcherSelected.length;
    final tf = _takeFielderSelected.length;
    final tp = _takePitcherSelected.length;
    return '引退: 野手 $rf 名 / 投手 $rp 名   '
        '加入: 野手 $tf 名 / 投手 $tp 名';
  }

  Future<void> _confirmAndCommit() async {
    if (!_isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('引退と新人の人数が揃っていません ($_summaryText)')),
      );
      return;
    }

    // 確認ダイアログ
    final c = widget.controller;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('次のシーズンへ'),
        content: Text(
          '${c.seasonYear}シーズン目を終了して、'
          '${c.seasonYear + 1}シーズン目を開始します。\n\n'
          '次シーズンの試合数: $_nextGamesPerTeam試合\n'
          '$_summaryText\n\n'
          '前シーズンの個人成績・順位は引き継がれません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('開始'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    // 選択を順序付きリストに変換（id の入った順 = チェックを入れた順ではないが、
    // 個別ペアリングは順序ベースなので同じ並びで OK）。
    final selection = OffseasonSelection(
      retireFielderIds: _retireFielderSelected.toList(),
      retirePitcherIds: _retirePitcherSelected.toList(),
      takeFielderIds: _takeFielderSelected.toList(),
      takePitcherIds: _takePitcherSelected.toList(),
    );

    // 引退・新人どちらも 0 件なら selection を渡さない（自チーム無編集）。
    if (selection.retireFielderIds.isEmpty &&
        selection.retirePitcherIds.isEmpty) {
      c.commitOffseason(gamesPerTeam: _nextGamesPerTeam);
    } else {
      c.commitOffseason(
        plan: _plan,
        selection: selection,
        gamesPerTeam: _nextGamesPerTeam,
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('オフシーズン編成'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          TextButton(
            onPressed: _applyRecommended,
            child: const Text('自動推奨'),
          ),
          TextButton(
            onPressed: _clearAll,
            child: const Text('全解除'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _buildIntro(),
          const SizedBox(height: 16),
          _SectionHeader(
            title: '引退する野手',
            subtitle:
                '上位ほど引退推奨（高齢 + 能力低下）。引退人数 = 加入人数になるよう選択してください。',
          ),
          ..._plan.retireCandidateFielders.map((p) => _RetireFielderTile(
                player: p,
                selected: _retireFielderSelected.contains(p.id),
                onToggle: () {
                  setState(() {
                    if (_retireFielderSelected.contains(p.id)) {
                      _retireFielderSelected.remove(p.id);
                    } else {
                      if (_retireFielderSelected.length >= 4) return;
                      _retireFielderSelected.add(p.id);
                    }
                  });
                },
              )),
          const SizedBox(height: 16),
          _SectionHeader(
            title: '引退する投手',
            subtitle: '同上。先発・救援どちらも候補に含まれます。',
          ),
          ..._plan.retireCandidatePitchers.map((p) => _RetirePitcherTile(
                player: p,
                isStarter: widget.controller.myTeam.startingRotation
                    .any((sp) => sp.id == p.id),
                selected: _retirePitcherSelected.contains(p.id),
                onToggle: () {
                  setState(() {
                    if (_retirePitcherSelected.contains(p.id)) {
                      _retirePitcherSelected.remove(p.id);
                    } else {
                      if (_retirePitcherSelected.length >= 4) return;
                      _retirePitcherSelected.add(p.id);
                    }
                  });
                },
              )),
          const SizedBox(height: 16),
          _SectionHeader(
            title: '入団する新人野手',
            subtitle: '${_plan.rookieFielderCandidates.length} 名の候補から、'
                '引退野手と同じ人数だけ選んでください。',
          ),
          ..._plan.rookieFielderCandidates.map((c) => _RookieFielderTile(
                candidate: c,
                selected: _takeFielderSelected.contains(c.id),
                onToggle: () {
                  setState(() {
                    if (_takeFielderSelected.contains(c.id)) {
                      _takeFielderSelected.remove(c.id);
                    } else {
                      if (_takeFielderSelected.length >= 4) return;
                      _takeFielderSelected.add(c.id);
                    }
                  });
                },
              )),
          const SizedBox(height: 16),
          _SectionHeader(
            title: '入団する新人投手',
            subtitle: '${_plan.rookiePitcherCandidates.length} 名の候補から、'
                '引退投手と同じ人数だけ選んでください。',
          ),
          ..._plan.rookiePitcherCandidates.map((c) => _RookiePitcherTile(
                candidate: c,
                selected: _takePitcherSelected.contains(c.id),
                onToggle: () {
                  setState(() {
                    if (_takePitcherSelected.contains(c.id)) {
                      _takePitcherSelected.remove(c.id);
                    } else {
                      if (_takePitcherSelected.length >= 4) return;
                      _takePitcherSelected.add(c.id);
                    }
                  });
                },
              )),
          const SizedBox(height: 80), // bottom bar との余白
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildIntro() {
    final c = widget.controller;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${c.seasonYear} シーズン目 終了',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '次シーズンに向けて、引退する選手と入団する新人を決めてください。\n'
              '引退・新人どちらも 0 名にすればチームを変えずに進めます。\n'
              '他球団 (CPU) の入れ替えは「次シーズン開始」時に自動実行されます。',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            const Text(
              '次シーズンの試合数',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            SeasonLengthSelector(
              value: _nextGamesPerTeam,
              onChanged: (v) => setState(() => _nextGamesPerTeam = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final valid = _isValid;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _summaryText,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  if (!valid)
                    Text(
                      '引退と新人の人数を揃えてください',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.red.shade700,
                      ),
                    ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: valid ? _confirmAndCommit : null,
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              child: const Text(
                '次シーズン開始',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}

/// 引退候補（野手）の行。
class _RetireFielderTile extends StatelessWidget {
  final Player player;
  final bool selected;
  final VoidCallback onToggle;

  const _RetireFielderTile({
    required this.player,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final positions = _fielderPositions(player);
    final stats = _abilityLine(player);
    return _CandidateTile(
      selected: selected,
      onTap: onToggle,
      title: '#${player.number} ${player.name}',
      subtitle: '${player.age}歳  $stats',
      trailing: positions,
    );
  }
}

/// 引退候補（投手）の行。
class _RetirePitcherTile extends StatelessWidget {
  final Player player;
  final bool isStarter;
  final bool selected;
  final VoidCallback onToggle;

  const _RetirePitcherTile({
    required this.player,
    required this.isStarter,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final stats = _pitcherAbilityLine(player);
    final role = isStarter
        ? '先発'
        : (player.reliefRole?.displayName ?? '救援');
    return _CandidateTile(
      selected: selected,
      onTap: onToggle,
      title: '#${player.number} ${player.name}',
      subtitle: '${player.age}歳  $stats',
      trailing: role,
    );
  }
}

/// 新人候補（野手）の行。
class _RookieFielderTile extends StatelessWidget {
  final RookieCandidate candidate;
  final bool selected;
  final VoidCallback onToggle;

  const _RookieFielderTile({
    required this.candidate,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final p = candidate.player;
    final positions = _fielderPositions(p);
    final stats = _abilityLine(p);
    return _CandidateTile(
      selected: selected,
      onTap: onToggle,
      badge: candidate.type,
      title: p.name,
      subtitle: '${p.age}歳  $stats',
      trailing: positions,
    );
  }
}

/// 新人候補（投手）の行。
/// 注: 新人投手は全員「先発寄り」で生成されるが、commit 時に引退者の役割を引き継ぐ
/// （SP 引退なら SP、RP 引退なら RP）。
class _RookiePitcherTile extends StatelessWidget {
  final RookieCandidate candidate;
  final bool selected;
  final VoidCallback onToggle;

  const _RookiePitcherTile({
    required this.candidate,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final p = candidate.player;
    final stats = _pitcherAbilityLine(p);
    return _CandidateTile(
      selected: selected,
      onTap: onToggle,
      badge: candidate.type,
      title: p.name,
      subtitle: '${p.age}歳  $stats',
      trailing: '新人',
    );
  }
}

class _CandidateTile extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final String title;
  final String subtitle;
  final String trailing;

  /// 新人候補のときだけタイプ（高卒 / 大卒 / 社会人）バッジを表示する。
  final RookieType? badge;

  const _CandidateTile({
    required this.selected,
    required this.onTap,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      color: selected ? Colors.green.shade50 : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: (_) => onTap(),
                visualDensity: VisualDensity.compact,
              ),
              if (badge != null) ...[
                _RookieTypeBadge(type: badge!),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Text(
                trailing,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 新人タイプ（高卒 / 大卒 / 社会人）の小さなカラーバッジ。
class _RookieTypeBadge extends StatelessWidget {
  final RookieType type;
  const _RookieTypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final color = switch (type) {
      RookieType.highSchool => Colors.blue.shade100,
      RookieType.college => Colors.amber.shade100,
      RookieType.corporate => Colors.deepPurple.shade100,
    };
    final textColor = switch (type) {
      RookieType.highSchool => Colors.blue.shade800,
      RookieType.college => Colors.amber.shade900,
      RookieType.corporate => Colors.deepPurple.shade800,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type.displayName,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }
}

/// 野手の能力サマリ: ミ/長/走/眼
String _abilityLine(Player p) {
  return 'ミ${p.meet ?? "-"} '
      '長${p.power ?? "-"} '
      '走${p.speed ?? "-"} '
      '眼${p.eye ?? "-"}';
}

/// 投手の能力サマリ: 球速/制球/球質/スタミナ
String _pitcherAbilityLine(Player p) {
  return '球${p.averageSpeed ?? "-"} '
      '制${p.control ?? "-"} '
      '質${p.fastball ?? "-"} '
      'ス${p.stamina ?? "-"}';
}

/// 野手が守れるポジションの短縮表示
String _fielderPositions(Player p) {
  final f = p.fielding;
  if (f == null) return '全ポジ';
  final positions = f.entries
      .where((e) => e.value > 0)
      .map((e) => '${e.key.shortName}${e.value}')
      .join(' ');
  return positions.isEmpty ? '-' : positions;
}

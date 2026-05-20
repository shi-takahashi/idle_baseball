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
    // 自動推奨はパラメータ非表示方針（SPEC §コンセプト）に反する（エンジンが
    // 能力で「引退すべき」を提示すると能力バレになる）ため適用しない。
    // ユーザーは年齢と当季成績を見て自分で選ぶ。
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
                '年齢と今シーズンの成績を見て選んでください。引退人数 = 加入人数になるよう選択してください。',
          ),
          // engine 側は能力低下スコア順で並ぶが、それ自体が能力ヒントになるため
          // 表示は背番号順に並べ直す（他の画面と一貫）。
          ...(_plan.retireCandidateFielders.toList()
                ..sort((a, b) => a.number.compareTo(b.number)))
              .map((p) => _RetireFielderTile(
                player: p,
                controller: widget.controller,
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
            subtitle:
                '年齢と今シーズンの成績を見て選んでください。先発・救援どちらも候補に含まれます。',
          ),
          ...(_plan.retireCandidatePitchers.toList()
                ..sort((a, b) => a.number.compareTo(b.number)))
              .map((p) => _RetirePitcherTile(
                player: p,
                controller: widget.controller,
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
                '引退野手と同じ人数だけ選んでください。\n'
                '※ 能力表示はスカウトの大雑把な評価です。'
                '実際にどう活躍するかは入団後に確かめてください。',
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
                '引退投手と同じ人数だけ選んでください。\n'
                '※ 能力表示はスカウトの大雑把な評価です。'
                '実際にどう活躍するかは入団後に確かめてください。',
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
  final SeasonController controller;
  final bool selected;
  final VoidCallback onToggle;

  const _RetireFielderTile({
    required this.player,
    required this.controller,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final positions = _fielderPositions(player);
    final stats = _fielderSeasonLine(controller, player);
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
  final SeasonController controller;
  final bool isStarter;
  final bool selected;
  final VoidCallback onToggle;

  const _RetirePitcherTile({
    required this.player,
    required this.controller,
    required this.isStarter,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final stats = _pitcherSeasonLine(controller, player);
    final role = isStarter
        ? '先発'
        : (player.pitcherRole?.displayName ?? '救援');
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
    final stats = _rookieAbilityLine(p);
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
    final stats = _rookiePitcherAbilityLine(p);
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

/// 新人野手のスカウト評価（A / B / C の 3 段階）。
/// 新人は試合に出ていないので結果ベースの推測ができないため、生数値ではなく
/// 「現時点の能力をスカウトの目で評価」した粗い指標を出す。
///   - 打撃 = (ミート + 長打) / 2（選球眼は含めない＝隠しパラメータ）
///   - 走力 = 走力そのまま
///   - 守備 = 守れるポジションのうち最高の守備力（肩は含めない）
/// ポテンシャル（隠し）で伸びるかは別なので、評価通りになるとは限らない。
/// 助っ人外国人（未実装）は「博打要素を強める」用途で別途設計予定。
String _rookieAbilityLine(Player p) {
  final batting = ((p.meet ?? 5) + (p.power ?? 5)) / 2;
  final running = (p.speed ?? 5).toDouble();
  final fielding = (p.fielding == null || p.fielding!.values.isEmpty)
      ? 0.0
      : p.fielding!.values.reduce((a, b) => a > b ? a : b).toDouble();
  return '打撃 ${_scoutRank(batting)} '
      '走力 ${_scoutRank(running)} '
      '守備 ${_scoutRank(fielding)}';
}

/// 新人投手のスカウト評価（A / B / C の 3 段階）。
///   - 球速 = 平均球速。NPB 平均 ~147 km/h を B 中央に置く
///     （150+ A / 145-149 B / それ未満 C）。伸び（fastball）は含めない＝隠し
///   - 制球 = 制球力そのまま
///   - 変化球 = 持ち球の中で一番得意な変化球の質
///     （ストレートの伸びは隠し、変化球の種類数も隠す）
String _rookiePitcherAbilityLine(Player p) {
  final speed = p.averageSpeed ?? 145;
  String speedRank() {
    if (speed >= 150) return 'A';
    if (speed >= 145) return 'B';
    return 'C';
  }
  // 持ち球 7 種類から一番得意なものを拾う（持っていない球種は null）
  final breakingValues = <int>[
    if (p.slider != null) p.slider!,
    if (p.curve != null) p.curve!,
    if (p.splitter != null) p.splitter!,
    if (p.changeup != null) p.changeup!,
    if (p.shoot != null) p.shoot!,
    if (p.cutter != null) p.cutter!,
    if (p.sinker != null) p.sinker!,
  ];
  final bestBreaking = breakingValues.isEmpty
      ? 0
      : breakingValues.reduce((a, b) => a > b ? a : b);
  return '球速 ${speedRank()} '
      '制球 ${_scoutRank((p.control ?? 5).toDouble())} '
      '変化球 ${_scoutRank(bestBreaking.toDouble())}';
}

/// 1〜10 の能力値を A / B / C の 3 段階に変換する。
///   - A: 7 以上（上位 ~20%）
///   - B: 4〜6（中位 ~60%）
///   - C: 3 以下（下位 ~20%）
String _scoutRank(double v) {
  if (v >= 7) return 'A';
  if (v >= 4) return 'B';
  return 'C';
}

/// 既存野手の当季シーズン成績サマリ。能力数値ではなく結果ベースで表示する
/// （パラメータ非表示方針 / SPEC §コンセプト）。
String _fielderSeasonLine(SeasonController c, Player p) {
  final s = c.batterStats[p.id];
  if (s == null || s.games == 0) return '出場なし';
  final ba = s.atBats == 0
      ? '-.---'
      : '.${(s.battingAverage * 1000).round().toString().padLeft(3, '0')}';
  return '試${s.games} 打率$ba 本${s.homeRuns} 点${s.rbi} 盗${s.stolenBases}';
}

/// 既存投手の当季シーズン成績サマリ。同上。
String _pitcherSeasonLine(SeasonController c, Player p) {
  final s = c.pitcherStats[p.id];
  if (s == null || s.games == 0) return '登板なし';
  final era = s.outsRecorded == 0 ? '-.--' : s.era.toStringAsFixed(2);
  return '登${s.games} 防率 $era 勝${s.wins} 負${s.losses} 回${s.inningsPitchedDisplay}';
}

/// 野手が守れるポジション（位置名のみ。守備力の数値は隠す: SPEC §2.0）。
String _fielderPositions(Player p) {
  final f = p.fielding;
  if (f == null) return '全ポジ';
  final positions = f.entries
      .where((e) => e.value > 0)
      .map((e) => e.key.shortName)
      .join('・');
  return positions.isEmpty ? '-' : positions;
}

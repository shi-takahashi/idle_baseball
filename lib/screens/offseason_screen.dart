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

class _OffseasonScreenState extends State<OffseasonScreen>
    with SingleTickerProviderStateMixin {
  late final OffseasonPlan _plan;
  late final TabController _tabController;

  /// 各候補の選択状態（id → 選択中か）
  final _retireFielderSelected = <String>{};
  final _retirePitcherSelected = <String>{};
  final _takeFielderSelected = <String>{};
  final _takePitcherSelected = <String>{};

  /// 外国人入替の選択状態。
  /// release: 現役外国人のうちユーザーが任意で切るもの（強制離脱とは別）。
  /// acquire: 候補から獲得するもの。投手枠と野手枠で個別に整合性を検証する。
  final _foreignReleaseSelected = <String>{};
  final _foreignAcquireSelected = <String>{};

  /// 次シーズンの試合数（30 / 90 / 150）。デフォルトは前シーズンの試合数。
  late int _nextGamesPerTeam;

  @override
  void initState() {
    super.initState();
    _plan = widget.controller.prepareOffseason();
    _nextGamesPerTeam = widget.controller.gamesPerTeam;
    _tabController = TabController(length: 2, vsync: this);
    // 自動推奨はパラメータ非表示方針（SPEC §コンセプト）に反する（エンジンが
    // 能力で「引退すべき」を提示すると能力バレになる）ため適用しない。
    // ユーザーは年齢と当季成績を見て自分で選ぶ。
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _clearAll() {
    setState(() {
      _retireFielderSelected.clear();
      _retirePitcherSelected.clear();
      _takeFielderSelected.clear();
      _takePitcherSelected.clear();
      _foreignReleaseSelected.clear();
      _foreignAcquireSelected.clear();
    });
  }

  /// チーム内の現役外国人選手（一意収集、id ベース）。
  List<Player> get _currentForeigners {
    final seen = <String>{};
    final result = <Player>[];
    final t = widget.controller.myTeam;
    for (final p in [
      ...t.players,
      ...t.startingRotation,
      ...t.bullpen,
      ...t.bench,
    ]) {
      if (!p.isForeign) continue;
      if (!seen.add(p.id)) continue;
      result.add(p);
    }
    return result;
  }

  /// 「強制離脱されるか」の判定（plan.foreignDepartures に含まれているか）。
  bool _isForcedDeparture(String id) =>
      _plan.foreignDepartures.any((p) => p.id == id);

  /// 外国人入替の整合性チェック。投手枠 / 野手枠ごとに
  /// 「現状 - 離脱 - カット + 獲得 = 想定枠（1 / 1）」を満たすか。
  /// 過去シーズンで何らかの経緯で空席ができている場合も、獲得だけで空席を
  /// 埋められるよう「離脱より獲得が多い」状態を許容する。
  bool get _foreignValid {
    final currentPitchers =
        _currentForeigners.where((p) => p.isPitcher).length;
    final currentFielders =
        _currentForeigners.where((p) => !p.isPitcher).length;
    int pitcherDepart = 0;
    int fielderDepart = 0;
    // 強制離脱
    for (final p in _plan.foreignDepartures) {
      if (p.isPitcher) {
        pitcherDepart++;
      } else {
        fielderDepart++;
      }
    }
    // ユーザー任意カット
    for (final id in _foreignReleaseSelected) {
      final p = _currentForeigners.firstWhere(
        (x) => x.id == id,
        orElse: () => Player(id: '', name: '', number: 0, age: 0),
      );
      if (p.id.isEmpty) continue;
      if (p.isPitcher) {
        pitcherDepart++;
      } else {
        fielderDepart++;
      }
    }
    // 獲得候補
    int pitcherAcquire = 0;
    int fielderAcquire = 0;
    for (final id in _foreignAcquireSelected) {
      final c = _plan.foreignCandidates.firstWhere(
        (x) => x.id == id,
        orElse: () => Player(id: '', name: '', number: 0, age: 0),
      );
      if (c.id.isEmpty) continue;
      if (c.isPitcher) {
        pitcherAcquire++;
      } else {
        fielderAcquire++;
      }
    }
    const targetPitchers = 2; // TeamRebuilder.targetForeignPitchers と同じ
    const targetFielders = 2;
    return (currentPitchers - pitcherDepart + pitcherAcquire) ==
            targetPitchers &&
        (currentFielders - fielderDepart + fielderAcquire) == targetFielders;
  }

  /// 引退・新人 + 外国人入替の両方が valid なら true。
  /// 0+0 でも valid（自チーム無編集で次シーズンへ。ただし強制離脱があると
  /// その分の獲得が必要）。
  bool get _isValid =>
      _retireFielderSelected.length == _takeFielderSelected.length &&
      _retirePitcherSelected.length == _takePitcherSelected.length &&
      _foreignValid;

  /// _isValid が false の時、ボトムバーに出すエラー文。
  /// 何が原因か（野手の人数 / 投手の人数 / 外国人枠）を伝える。
  String get _validationMessage {
    final issues = <String>[];
    if (_retireFielderSelected.length != _takeFielderSelected.length) {
      issues.add('野手の引退と新人の人数');
    }
    if (_retirePitcherSelected.length != _takePitcherSelected.length) {
      issues.add('投手の引退と新人の人数');
    }
    if (!_foreignValid) {
      issues.add('外国人の枠');
    }
    return '${issues.join("、")}を揃えてください';
  }

  /// 「○ 名引退 / ○ 名加入」の説明テキスト
  String get _summaryText {
    final rf = _retireFielderSelected.length;
    final rp = _retirePitcherSelected.length;
    final tf = _takeFielderSelected.length;
    final tp = _takePitcherSelected.length;
    final forcedDepart = _plan.foreignDepartures.length;
    final voluntaryRelease = _foreignReleaseSelected.length;
    final acquire = _foreignAcquireSelected.length;
    final foreignNote = (forcedDepart + voluntaryRelease + acquire) > 0
        ? '   外: 離脱$forcedDepart 解除$voluntaryRelease 獲得$acquire'
        : '';
    return '引退: 野手 $rf 名 / 投手 $rp 名   '
        '加入: 野手 $tf 名 / 投手 $tp 名$foreignNote';
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
      foreignReleaseIds: _foreignReleaseSelected.toList(),
      foreignAcquireIds: _foreignAcquireSelected.toList(),
    );

    // 引退・新人 + 外国人入替がすべて 0 件なら selection を渡さない（自チーム無編集）。
    // 外国人の強制離脱がある場合は plan を渡して acquire を反映させる必要がある。
    final hasAnyChange = selection.retireFielderIds.isNotEmpty ||
        selection.retirePitcherIds.isNotEmpty ||
        selection.foreignReleaseIds.isNotEmpty ||
        selection.foreignAcquireIds.isNotEmpty ||
        _plan.foreignDepartures.isNotEmpty;
    if (!hasAnyChange) {
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
      // 縦長問題への対処として、引退/新人/外国人を「野手 / 投手 / 外国人」
      // タブに分けた。引退と新人は同じタブ内に並べて人数を揃える操作を一括化。
      // イントロカード（試合数選択など）はタブ外に出して常時アクセス可能にする。
      body: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: _buildIntro(),
          ),
          TabBar(
            controller: _tabController,
            labelColor: Theme.of(context).colorScheme.primary,
            tabs: const [
              Tab(text: '野手'),
              Tab(text: '投手'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildFielderTab(),
                _buildPitcherTab(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  /// 野手タブ: 引退候補（全選手）と新人野手候補を縦に並べる。
  /// 同じタブ内に置くことで「引退人数 = 加入人数」を揃える操作が一画面で完結する。
  Widget _buildFielderTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
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
        ..._buildForeignSectionFor(isPitcher: false),
        const SizedBox(height: 80), // bottom bar との余白
      ],
    );
  }

  /// 投手タブ: 引退候補（全選手）と新人投手候補を縦に並べる。
  Widget _buildPitcherTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
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
        const SizedBox(height: 16),
        ..._buildForeignSectionFor(isPitcher: true),
        const SizedBox(height: 80),
      ],
    );
  }

  /// 空席がある時だけ表示するオレンジの警告チップ。想定枠 2 を満たしていれば
  /// 何も出さない。強制離脱もユーザーが見落とさないよう、ここで空席数を出す。
  Widget _buildForeignSlotStatusFor({required bool isPitcher}) {
    final current =
        _currentForeigners.where((p) => p.isPitcher == isPitcher).length;
    const target = 2;
    if (current >= target) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.orange.shade300),
        ),
        child: Text(
          '空席が ${target - current} 名あります。候補から獲得してください。',
          style: TextStyle(
            fontSize: 12,
            color: Colors.orange.shade900,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// タブ内の外国人セクション。投手タブには投手枠、野手タブには野手枠だけが出る。
  List<Widget> _buildForeignSectionFor({required bool isPitcher}) {
    final foreigners =
        _currentForeigners.where((p) => p.isPitcher == isPitcher).toList();
    final candidates =
        _plan.foreignCandidates.where((c) => c.isPitcher == isPitcher).toList();
    final label = isPitcher ? '外国人投手' : '外国人野手';
    return [
      _SectionHeader(
        title: label,
        subtitle: 'シーズン終了時に強制離脱することがあります。\n'
            '残った選手は任意で「契約解除」もできます。',
      ),
      _buildForeignSlotStatusFor(isPitcher: isPitcher),
      if (foreigners.isEmpty)
        const SizedBox.shrink()
      else
        ...foreigners.map((p) => _ForeignCurrentTile(
              player: p,
              controller: widget.controller,
              forcedDeparture: _isForcedDeparture(p.id),
              voluntaryRelease: _foreignReleaseSelected.contains(p.id),
              onToggleRelease: () {
                setState(() {
                  if (_foreignReleaseSelected.contains(p.id)) {
                    _foreignReleaseSelected.remove(p.id);
                  } else {
                    _foreignReleaseSelected.add(p.id);
                  }
                });
              },
            )),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 4),
        child: Text(
          '新候補',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade700,
          ),
        ),
      ),
      ...candidates.map((c) => _ForeignCandidateTile(
            player: c,
            selected: _foreignAcquireSelected.contains(c.id),
            onToggle: () {
              setState(() {
                if (_foreignAcquireSelected.contains(c.id)) {
                  _foreignAcquireSelected.remove(c.id);
                } else {
                  _foreignAcquireSelected.add(c.id);
                }
              });
            },
          )),
    ];
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
                      _validationMessage,
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
      subtitle: '${player.age}歳 ${_handednessLabel(player)}  $stats',
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
      subtitle: '${player.age}歳 ${_handednessLabel(player)}  $stats',
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
      subtitle: '${p.age}歳 ${_handednessLabel(p)}  $stats',
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
      subtitle: '${p.age}歳 ${_handednessLabel(p)}  $stats',
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
      '守備 ${_scoutRankMax(fielding)}';
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
      '変化球 ${_scoutRankMax(bestBreaking.toDouble())}';
}

/// 1〜10 の能力値を A / B / C の 3 段階に変換する（単一値・平均値用）。
///   - A: 7 以上（上位 ~20%）
///   - B: 4〜6（中位 ~60%）
///   - C: 3 以下（下位 ~20%）
String _scoutRank(double v) {
  if (v >= 7) return 'A';
  if (v >= 4) return 'B';
  return 'C';
}

/// 「複数の指標のうち最高値」を A / B / C に変換する（守備力・変化球用）。
/// max を取るぶん A が出やすくなり、特に複数球種・複数ポジション持ちの選手は
/// 普通の閾値だと C がほぼ出ない（例: 3 球種すべて 4 以下になる確率は 1.6% 程度）。
/// 「武器がある = A」「使える1つ以上はある = B」「どれも振るわない = C」が
/// 自然に出るよう閾値を 1 段ずつ厳しくしている。
///   - A: 8 以上（明確な武器あり）
///   - B: 5〜7（使えるレベル）
///   - C: 4 以下（どれも振るわない）
String _scoutRankMax(double v) {
  if (v >= 8) return 'A';
  if (v >= 5) return 'B';
  return 'C';
}

/// 既存野手の当季シーズン成績サマリ。能力数値ではなく結果ベースで表示する
/// （パラメータ非表示方針 / SPEC §コンセプト）。
/// オフシーズン編成は「衰えたベテランを引退させる」判断が中心なので、当季成績だけで
/// 十分。前年と並べると情報過多で見づらくなるため当季のみに留める。
/// 年度別推移は選手詳細画面の「年度別成績」セクションで確認できる。
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
  return '登${s.games} 防率$era 勝${s.wins} 負${s.losses} 回${s.inningsPitchedDisplay}';
}

/// 利き手 / 打席のラベル。野手は「打席（右/左/両）」、投手は「投げる手（右/左）」。
/// オフシーズン編成画面のタイル subtitle で年齢の隣に表示する。
String _handednessLabel(Player p) {
  final h = p.isPitcher ? p.throws : p.bats;
  switch (h) {
    case Handedness.right:
      return '右';
    case Handedness.left:
      return '左';
    case Handedness.both:
      return '両';
    case null:
      return '-';
  }
}

/// 野手が守れるポジション（位置名のみ。守備力の数値は隠す: SPEC §2.0）。
/// 並び順は enum 順（捕→一→二→三→遊→外）に統一し、選手ごとの揺らぎを排除する。
String _fielderPositions(Player p) {
  final f = p.fielding;
  if (f == null) return '全ポジ';
  final positions = [
    for (final dp in DefensePosition.values)
      if ((f[dp] ?? 0) > 0) dp.shortName,
  ].join('・');
  return positions.isEmpty ? '-' : positions;
}

/// 現役外国人 1 名の行。
/// 強制離脱した選手は赤系で `[離脱]` バッジ、任意カット可能な選手は青系で
/// 「切る」チェックを持つ。当季成績も表示する（ユーザーが「外れか」を判断する材料）。
class _ForeignCurrentTile extends StatelessWidget {
  final Player player;
  final SeasonController controller;
  final bool forcedDeparture;
  final bool voluntaryRelease;
  final VoidCallback onToggleRelease;

  const _ForeignCurrentTile({
    required this.player,
    required this.controller,
    required this.forcedDeparture,
    required this.voluntaryRelease,
    required this.onToggleRelease,
  });

  @override
  Widget build(BuildContext context) {
    final stats = player.isPitcher
        ? _pitcherSeasonLine(controller, player)
        : _fielderSeasonLine(controller, player);
    // 候補側と同じく、契約中の外国人にも「守備位置」を表示する。投手は「投手」、
    // 野手は守れるポジションを羅列（_fielderPositions ヘルパー）。
    final positions = player.isPitcher ? '投手' : _fielderPositions(player);
    final cardColor = forcedDeparture
        ? Colors.red.shade50
        : voluntaryRelease
            ? Colors.orange.shade50
            : null;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      color: cardColor,
      child: InkWell(
        onTap: forcedDeparture ? null : onToggleRelease,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              if (forcedDeparture)
                const _ForeignBadge(label: '離脱', color: Colors.red)
              else if (voluntaryRelease)
                const _ForeignBadge(label: '解除', color: Colors.orange)
              else
                const _ForeignBadge(label: '継続', color: Colors.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '#${player.number} ${player.name}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${player.age}歳 ${_handednessLabel(player)}  $positions  $stats',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (forcedDeparture)
                const Text(
                  '強制',
                  style: TextStyle(fontSize: 11, color: Colors.red),
                )
              else
                TextButton(
                  onPressed: onToggleRelease,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    voluntaryRelease ? '契約解除を取消' : '契約解除',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 新外国人候補 1 名の行。
/// 能力は完全非表示。守備位置（投手 or 野手の主ポジ）と年齢、苗字（名前）だけが
/// 事前情報。獲得後に試合結果で「当たり外れ」を判断する賭け体験。
class _ForeignCandidateTile extends StatelessWidget {
  final Player player;
  final bool selected;
  final VoidCallback onToggle;

  const _ForeignCandidateTile({
    required this.player,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final positions = player.isPitcher ? '投手' : _fielderPositions(player);
    final typeLabel = player.isPitcher ? '投手' : '野手';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      color: selected ? Colors.green.shade50 : null,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: (_) => onToggle(),
                visualDensity: VisualDensity.compact,
              ),
              _ForeignBadge(
                label: typeLabel,
                color: player.isPitcher ? Colors.deepPurple : Colors.indigo,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      player.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${player.age}歳 ${_handednessLabel(player)}  $positions',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                '助っ人',
                style: TextStyle(fontSize: 11, color: Colors.brown),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 外国人タイル用の小さなカラーバッジ（離脱 / カット / 継続 / 投手 / 野手）。
class _ForeignBadge extends StatelessWidget {
  final String label;
  final MaterialColor color;
  const _ForeignBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color.shade800,
        ),
      ),
    );
  }
}

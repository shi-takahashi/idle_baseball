import 'package:flutter/material.dart';

import '../engine/engine.dart';

/// 作戦画面（次の試合の自チームの編成を指定する）
///
/// 9 行のラインナップに「打順 + 守備配置」を一括で並べる。投手は通常 9 番に
/// 置くが、大谷型のラインナップ（投手を 1〜8 番に置く）も可能。
/// 投手と野手の判定は行 index ではなく `Player.isPitcher` で行う。
///
/// バリデーション:
///  - 9 人全員の選手・守備位置が選択済み
///  - 9 人重複なし
///  - 9 守備位置すべて埋まっている（重複なし）
///  - 守備位置「投手」の選手は投手（`isPitcher == true`）
///  - 投手以外の 8 守備位置の選手は野手
class StrategyScreen extends StatefulWidget {
  final SeasonController controller;
  final Listenable listenable;

  /// 「試合開始」ボタンが押されたときに親 [MainSeasonScreen] が
  /// `advanceDay` + 結果画面 push を行うコールバック。
  final VoidCallback? onStartGame;

  const StrategyScreen({
    super.key,
    required this.controller,
    required this.listenable,
    this.onStartGame,
  });

  @override
  State<StrategyScreen> createState() => StrategyScreenState();
}

/// 親 [MainSeasonScreen] が `GlobalKey<StrategyScreenState>` 経由で
/// `tryCommit()` を呼べるよう、State クラスは public にしている。
class StrategyScreenState extends State<StrategyScreen>
    with SingleTickerProviderStateMixin {
  /// 当日ベンチ入り 26 人の内訳（編成バリデーションで使う）。
  static const int _activeBenchTarget = 9; // ベンチ入り控え野手
  static const int _activeBullpenTarget = 8; // ベンチ入り救援

  /// _Slot.id 用の連番カウンタ。`_loadFromCurrent` で新規スロットを作る時に使う。
  int _slotIdCounter = 0;
  String _newSlotId() => 'slot-${_slotIdCounter++}';

  /// 「スタメン」「ベンチ入り」の 2 タブ。
  late final TabController _tabController =
      TabController(length: 2, vsync: this);

  /// 1〜9 番のスロット。投手は通常 [8]（9 番）だがどこでも置ける。
  late List<_Slot> _slots = List.generate(9, (_) => _Slot(id: _newSlotId()));

  /// 当日ベンチ入りさせる控え野手・救援投手の id 集合。
  /// 控え野手はスタメン9人を除いた野手プールから [_activeBenchTarget] 人、
  /// 救援は救援プールから [_activeBullpenTarget] 人を選ぶ。
  Set<String> _activeBenchIds = {};
  Set<String> _activeBullpenIds = {};

  /// 「元に戻す」ボタン用に、画面表示時点（= 編集前）の状態を覚えておく。
  /// `_loadFromCurrent` で更新される。
  late List<_Slot> _initialSlots =
      List.generate(9, (_) => _Slot(id: _newSlotId()));
  Set<String> _initialActiveBenchIds = {};
  Set<String> _initialActiveBullpenIds = {};

  /// `_loadFromCurrent` を呼んだ時の `currentDay`。
  /// 試合進行で次の日になったら、自動でフォームを再ロードする判定に使う。
  int _loadedForDay = -1;

  Team get _myTeam =>
      widget.controller.teams.firstWhere((t) => t.id == widget.controller.myTeamId);

  @override
  void initState() {
    super.initState();
    _loadFromCurrent();
    // 試合進行で `currentDay` が変わったら、次の試合のオート提案で
    // フォームを自動的にリロードする（編集中だった内容は捨てられる）。
    widget.listenable.addListener(_onControllerNotify);
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_onControllerNotify);
    _tabController.dispose();
    super.dispose();
  }

  void _onControllerNotify() {
    if (!mounted) return;
    if (widget.controller.currentDay != _loadedForDay) {
      setState(_loadFromCurrent);
    } else {
      // 同じ日内でも、選手編集（updatePlayer）等でフォームが保持する Player の
      // 能力が変わっている可能性がある。スロット順・守備位置は維持したまま、
      // 保持する Player を controller の最新インスタンスに差し替える。
      setState(_refreshSlotPlayers);
    }
  }

  /// `_slots` / `_initialSlots` 内の Player を controller の最新インスタンスに
  /// id で引き直す。スロット順・守備位置・スロット id は維持する。
  /// 選手編集をフォーム表示・commit 内容の両方に反映するため。
  void _refreshSlotPlayers() {
    _Slot refresh(_Slot s) {
      final p = s.player;
      if (p == null) return s;
      final latest = widget.controller.findPlayerById(p.id);
      if (latest == null || identical(latest, p)) return s;
      return s.copyWith(player: latest);
    }

    _slots = [for (final s in _slots) refresh(s)];
    _initialSlots = [for (final s in _initialSlots) refresh(s)];
  }

  /// 既存の作戦 or オート提案からフォームを初期化。
  /// 「元に戻す」が参照する初期スナップショットも同時に更新する。
  void _loadFromCurrent() {
    // 保存済み作戦があればそれ、無ければオート提案（どちらも当日ベンチ入りを含む）。
    final src = widget.controller.myStrategy ??
        widget.controller.suggestedStrategyForMyTeam();
    final List<_Slot> next;
    if (src == null) {
      next = List.generate(9, (_) => _Slot(id: _newSlotId()));
      _activeBenchIds = {};
      _activeBullpenIds = {};
    } else {
      next = [
        for (int i = 0; i < 9; i++)
          _Slot(
            id: _newSlotId(),
            player: src.lineup[i],
            position: _findPositionForPlayer(src.lineup[i], src.alignment),
          ),
      ];
      _activeBenchIds = src.activeBench.map((p) => p.id).toSet();
      _activeBullpenIds = src.activeBullpen.map((p) => p.id).toSet();
    }
    _slots = next;
    // 「元に戻す」用のスナップショット。_Slot は immutable なのでシャローコピーで足りる。
    _initialSlots = List.of(next);
    _initialActiveBenchIds = Set.of(_activeBenchIds);
    _initialActiveBullpenIds = Set.of(_activeBullpenIds);
    _loadedForDay = widget.controller.currentDay;
  }

  FieldPosition? _findPositionForPlayer(
      Player p, Map<FieldPosition, Player> alignment) {
    for (final e in alignment.entries) {
      if (e.value.id == p.id) return e.key;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.listenable,
      builder: (context, _) {
        final c = widget.controller;
        final next = c.nextScheduledGameForMyTeam;
        return Scaffold(
          appBar: AppBar(
            title: const Text('作戦'),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            automaticallyImplyLeading: false,
            actions: [
              TextButton(
                onPressed: c.isSeasonOver ? null : _revertToInitial,
                child: const Text('元に戻す'),
              ),
            ],
          ),
          body: c.isSeasonOver
              ? const Center(child: Text('シーズンは終了しました'))
              : next == null
                  ? const Center(child: Text('次の試合がありません'))
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                          child: _buildNextGameCard(next),
                        ),
                        TabBar(
                          controller: _tabController,
                          labelColor: Theme.of(context).colorScheme.primary,
                          tabs: const [
                            Tab(text: 'スタメン'),
                            Tab(text: 'ベンチ入り'),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildStarterTab(),
                              _buildBenchTab(),
                            ],
                          ),
                        ),
                        if (widget.onStartGame != null) _buildStartGameButton(),
                      ],
                    ),
        );
      },
    );
  }

  // ---------------------------------------------------
  // 試合開始ボタン
  // ---------------------------------------------------
  Widget _buildStartGameButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: ElevatedButton.icon(
        onPressed: widget.onStartGame == null ? null : _onTapStartGame,
        icon: const Icon(Icons.play_arrow),
        label: const Text('試合開始'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // 次の試合カード
  // ---------------------------------------------------
  Widget _buildNextGameCard(ScheduledGame next) {
    final c = widget.controller;
    final isHome = next.homeTeam.id == c.myTeamId;
    final opponent = isHome ? next.awayTeam : next.homeTeam;
    final opColor = Color(opponent.primaryColorValue);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Text('Day ${next.day}',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(width: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isHome ? Colors.deepOrange : Colors.indigo,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                isHome ? 'HOME' : 'AWAY',
                style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            const Text('vs',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(width: 6),
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: opColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                opponent.shortName,
                style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                opponent.name,
                style: const TextStyle(fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 編集内容の確定タイミングについての注記（両タブ共通）。
  Widget _buildEditNote() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Text(
        widget.controller.myStrategy != null
            ? '※ 編集内容は「試合開始」/「早送り」を押した時点で確定。次の試合のみ適用され、消化後はオートに戻ります。'
            : '※ 編集内容は「試合開始」/「早送り」を押した時点で反映されます（現在はオート編成）。',
        style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
      ),
    );
  }

  // ---------------------------------------------------
  // タブ 1: スタメン
  // ---------------------------------------------------
  Widget _buildStarterTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLineupCard(),
          const SizedBox(height: 4),
          _buildEditNote(),
        ],
      ),
    );
  }

  // ---------------------------------------------------
  // タブ 2: ベンチ入り（当日ベンチ入り26人のうち、控え野手9人 + 救援8人を選ぶ）
  // ---------------------------------------------------
  Widget _buildBenchTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildBenchFieldersCard(),
          const SizedBox(height: 8),
          _buildBullpenCard(),
          const SizedBox(height: 4),
          _buildEditNote(),
        ],
      ),
    );
  }

  /// スタメン9人に入っていない野手プール（控え野手 + スタメンを外れた主力野手）。
  /// ベンチ入り控え野手はこの中から選ぶ。背番号順（中立 — 能力序列を出さない）。
  List<Player> _benchFielderPool() {
    final lineupIds = <String>{
      for (final s in _slots)
        if (s.player != null) s.player!.id,
    };
    final pool = <Player>[
      for (final p in _myTeam.players.take(8))
        if (!p.isPitcher && !lineupIds.contains(p.id)) p,
      for (final p in _myTeam.bench)
        if (!p.isPitcher && !lineupIds.contains(p.id)) p,
    ];
    pool.sort((a, b) => a.number.compareTo(b.number));
    return pool;
  }

  /// ベンチ入り救援の候補プール（全18投手のうち、当日先発に指定した投手を除く）。
  /// 先発/中継ぎの区分は固定でなく、ユーザーが全投手から自由に選ぶ。背番号順。
  List<Player> _bullpenPool() {
    final lineupPitcherIds = <String>{
      for (final s in _slots)
        if (s.player?.isPitcher == true) s.player!.id,
    };
    final pool = <Player>[
      for (final p in [..._myTeam.startingRotation, ..._myTeam.bullpen])
        if (!lineupPitcherIds.contains(p.id)) p,
    ];
    pool.sort((a, b) => a.number.compareTo(b.number));
    return pool;
  }

  /// スタメン編集で野手プールが変わった後、ベンチ入り控え野手が
  /// [_activeBenchTarget] 人を下回っていたら能力上位から自動補充する。
  /// ユーザーが選んだ選手を勝手に外すことはしない（不足分を足すだけ）。
  void _healActiveBench() {
    final pool = _benchFielderPool();
    final poolIds = pool.map((p) => p.id).toSet();
    _activeBenchIds = _activeBenchIds.intersection(poolIds);
    for (final p in pool) {
      if (_activeBenchIds.length >= _activeBenchTarget) break;
      _activeBenchIds.add(p.id);
    }
  }

  void _toggleActive(Set<String> set, String id) {
    setState(() {
      if (!set.remove(id)) set.add(id);
    });
  }

  Widget _buildBenchFieldersCard() {
    final pool = _benchFielderPool();
    final count = pool.where((p) => _activeBenchIds.contains(p.id)).length;
    return _buildRosterCard(
      title: 'ベンチ入り 控え野手',
      hint: '代打・代走・守備交代の要員。スタメン9人を外れた野手から選ぶ。',
      count: count,
      target: _activeBenchTarget,
      rows: [for (final p in pool) _buildBenchFielderRow(p)],
    );
  }

  Widget _buildBullpenCard() {
    final pool = _bullpenPool();
    final count = pool.where((p) => _activeBullpenIds.contains(p.id)).length;
    return _buildRosterCard(
      title: 'ベンチ入り 救援投手',
      hint: '当日先発を除く全投手から、リリーフ登板する8人を選ぶ。'
          '右の役割（先発/抑え等）はタップで指定（変更後は継続）。'
          '先発役割の投手はベンチ入りさせても最後の砦としてのみ登板。',
      count: count,
      target: _activeBullpenTarget,
      rows: [for (final p in pool) _buildBullpenRow(p)],
    );
  }

  Widget _buildRosterCard({
    required String title,
    required String hint,
    required int count,
    required int target,
    required List<Widget> rows,
  }) {
    final ok = count == target;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold)),
                ),
                Text(
                  '$count / $target',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: ok ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
              ],
            ),
            Text(hint,
                style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
            const Divider(height: 12),
            ...rows,
          ],
        ),
      ),
    );
  }

  Widget _buildBenchFielderRow(Player p) {
    final active = _activeBenchIds.contains(p.id);
    final stats = _fielderStatsCompact(widget.controller, p);
    return _buildToggleRow(
      active: active,
      name: p.name,
      sub: '${_handednessLabel(p)}  ${_positionsLabel(p)}'
          '${stats.isEmpty ? '' : '  $stats'}',
      onTap: () => _toggleActive(_activeBenchIds, p.id),
    );
  }

  Widget _buildBullpenRow(Player p) {
    final active = _activeBullpenIds.contains(p.id);
    final fr = widget.controller.pitcherFreshness(p.id);
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          // ベンチ入りトグル（チェックボックス + 名前・成績）
          Icon(
            active ? Icons.check_box : Icons.check_box_outline_blank,
            size: 20,
            color: active ? primary : Colors.grey,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: () => _toggleActive(_activeBullpenIds, p.id),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    style: TextStyle(
                      fontSize: 14,
                      color: active ? null : Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    '${_handednessLabel(p)}  '
                    '${_pitcherStatsCompact(widget.controller, p)}'
                    '   体力 $fr%',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 役割チップ（タップで変更。永続）
          _buildRoleChip(p),
        ],
      ),
    );
  }

  /// 救援投手の役割チップ。タップで役割ピッカーを開く。
  Widget _buildRoleChip(Player p) {
    final role = p.pitcherRole ?? PitcherRole.middle;
    return InkWell(
      onTap: () => _pickPitcherRole(p),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(role.displayName, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 16, color: Colors.grey.shade600),
          ],
        ),
      ),
    );
  }

  /// 救援投手の役割を選ぶピッカー。選択すると永続的に変更される。
  Future<void> _pickPitcherRole(Player p) async {
    final picked = await showModalBottomSheet<PitcherRole>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              _SectionHeader('${p.name} の役割を指定'),
              for (final role in PitcherRole.values)
                ListTile(
                  dense: true,
                  leading: Icon(
                    (p.pitcherRole ?? PitcherRole.middle) == role
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: (p.pitcherRole ?? PitcherRole.middle) == role
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                  ),
                  title: Text(role.displayName),
                  onTap: () => Navigator.of(ctx).pop(role),
                ),
            ],
          ),
        );
      },
    );
    if (picked == null) return;
    // 役割は永続変更（次の試合だけの編成とは別レイヤー）。即座に反映する。
    widget.controller.setPitcherRole(p.id, picked);
  }

  Widget _buildToggleRow({
    required bool active,
    required String name,
    required String sub,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(
              active ? Icons.check_box : Icons.check_box_outline_blank,
              size: 20,
              color: active ? primary : Colors.grey,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 14,
                      color: active ? null : Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    sub,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
          ],
        ),
      ),
    );
  }

  /// 守れる守備位置を 1 文字略称で連結（例: "捕/一"）。
  String _positionsLabel(Player p) {
    final labels = <String>[
      for (final dp in DefensePosition.values)
        if (p.canPlay(dp)) _defensePositionShort(dp),
    ];
    return labels.isEmpty ? '守備適性なし' : labels.join('/');
  }

  String _defensePositionShort(DefensePosition dp) {
    switch (dp) {
      case DefensePosition.catcher:
        return '捕';
      case DefensePosition.first:
        return '一';
      case DefensePosition.second:
        return '二';
      case DefensePosition.third:
        return '三';
      case DefensePosition.shortstop:
        return '遊';
      case DefensePosition.outfield:
        return '外';
    }
  }

  // ---------------------------------------------------
  // 打順 + 守備配置（9 行統合 + 行を長押しドラッグで並び替え）
  // ---------------------------------------------------
  Widget _buildLineupCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('打順 + 守備配置（長押しドラッグで並び替え）',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold)),
            const Divider(height: 12),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              // デフォルトのドラッグハンドル（右端のアイコン）は出さず、
              // 行全体を長押しでドラッグ開始できるようにする。
              buildDefaultDragHandles: false,
              onReorder: _onReorder,
              children: [
                for (int i = 0; i < _slots.length; i++)
                  ReorderableDelayedDragStartListener(
                    key: ValueKey(_slots[i].id),
                    index: i,
                    child: _buildSlotRow(i),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// ドラッグ&ドロップで打順を入れ替えた時のハンドラ。
  /// 選手と守備位置のペア（_Slot）ごと移動するので、移動した選手の守備位置は
  /// 新しい打順位置でもそのまま維持される（野球的にも自然）。
  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      // ReorderableListView の慣用: 後ろに動かす場合は newIndex を 1 ずらす
      if (newIndex > oldIndex) newIndex--;
      final item = _slots.removeAt(oldIndex);
      _slots.insert(newIndex, item);
    });
  }

  Widget _buildSlotRow(int index) {
    final slot = _slots[index];
    final isDup = slot.player != null &&
        _slots
                .asMap()
                .entries
                .where(
                    (e) => e.key != index && e.value.player?.id == slot.player!.id)
                .isNotEmpty;
    final isPosDup = slot.position != null &&
        _slots
                .asMap()
                .entries
                .where((e) => e.key != index && e.value.position == slot.position)
                .isNotEmpty;

    // 投手位置と選手タイプの整合性チェック（保存時のバリデーションも担当するが
    // 視覚的にも分かるよう色付け）
    bool typeMismatch = false;
    if (slot.player != null && slot.position != null) {
      final isPitcherPos = slot.position == FieldPosition.pitcher;
      typeMismatch = isPitcherPos != slot.player!.isPitcher;
    }

    // 名前と成績を 1 行で並べる（縦スペース節約）
    final p = slot.player;
    final statsLine = p == null
        ? null
        : (p.isPitcher
            ? _pitcherStatsCompact(widget.controller, p)
            : _fielderStatsCompact(widget.controller, p));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 打順番号（「1」「2」…）
          SizedBox(
            width: 22,
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => _pickPlayer(index),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    if (slot.player?.isPitcher == true)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.sports_baseball,
                            size: 14, color: Colors.deepPurple),
                      ),
                    Flexible(
                      child: Text(
                        slot.player?.name ?? '(未選択)',
                        style: TextStyle(
                          fontSize: 14,
                          color: slot.player == null
                              ? Colors.grey
                              : isDup
                                  ? Colors.red
                                  : null,
                          decoration:
                              isDup ? TextDecoration.underline : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // 利き手（野手は打席、投手は投げる手）
                    if (p != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        _handednessLabel(p),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blueGrey.shade400,
                        ),
                      ),
                    ],
                    if (statsLine != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        statsLine,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // 守備位置は shortName (1文字: 投/捕/一/二/三/遊/左/中/右) で表示
          // ピッカー側は full name 表示なので、選択時に分かりにくくはならない。
          SizedBox(
            width: 36,
            child: InkWell(
              onTap: slot.player == null ? null : () => _pickPosition(index),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                child: Text(
                  slot.position?.shortName ?? '-',
                  style: TextStyle(
                    fontSize: 13,
                    color: slot.position == null
                        ? Colors.grey
                        : (isPosDup || typeMismatch)
                            ? Colors.red
                            : null,
                    decoration: (isPosDup || typeMismatch)
                        ? TextDecoration.underline
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------
  // 選手 / ポジションのピッカー
  // ---------------------------------------------------
  Future<void> _pickPlayer(int slotIndex) async {
    // 全選手（野手 + 先発ローテ投手）を 1 つのリストで表示する。
    // ソート 3 階層:
    //   1. このスロットの守備位置を守れる選手（緑ハイライト）
    //   2. 野手（非適性）
    //   3. 投手（非適性）
    // 各グループ内は背番号順。
    // セクション分け（現スタメン / ベンチ）はしない:
    // LineupPlanner で当日入れ替わった選手とのズレで紛らわしくなるため。
    final slotPos = _slots[slotIndex].position;
    bool isCompatible(Player p) => _isPlayerCompatibleWith(p, slotPos);
    int groupOf(Player p) {
      if (isCompatible(p)) return 0;
      return p.isPitcher ? 2 : 1;
    }

    // 投手スロットには全18投手（先発ローテ + 救援）が候補に出る。
    // 先発/中継ぎの区分は固定でなく、ユーザーが全投手から先発を選べる。
    final team = _myTeam;
    final all = <Player>[
      ...team.players.take(8),
      ...team.bench,
      ...team.startingRotation,
      ...team.bullpen,
    ];
    all.sort((a, b) {
      final ga = groupOf(a);
      final gb = groupOf(b);
      if (ga != gb) return ga.compareTo(gb);
      return a.number.compareTo(b.number);
    });

    final picked = await showModalBottomSheet<Player>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              if (slotPos != null)
                _SectionHeader(
                  '${slotPos.displayName} を守れる選手を緑色 + 上位表示',
                ),
              for (final p in all)
                _PlayerTile(
                  player: p,
                  selected: _slots[slotIndex].player?.id == p.id,
                  compatible: isCompatible(p),
                  slotPosition: slotPos,
                  controller: widget.controller,
                  onTap: () => Navigator.of(ctx).pop(p),
                ),
            ],
          ),
        );
      },
    );
    if (picked == null) return;
    setState(() {
      // 同じ選手が他のスロットにいたらクリア
      for (int i = 0; i < _slots.length; i++) {
        if (i != slotIndex && _slots[i].player?.id == picked.id) {
          _slots[i] = _slots[i].copyWith(clearPlayer: true);
        }
      }
      // 新しい選手のタイプ（投手 / 野手）に合わせて守備位置を自動補正
      _slots[slotIndex] = _slots[slotIndex].copyWith(
        player: picked,
        position: _adjustPositionFor(picked, _slots[slotIndex].position),
      );
      // 守備位置の自動補正で別スロットと衝突したらそっちもクリア
      _resolvePositionConflict(slotIndex);
      // スタメンが変わると控え野手プールも変わる。ベンチ入りが定員割れしたら補充。
      _healActiveBench();
    });
    // ※ ここでは setMyStrategy は呼ばない。中途半端な編集状態で保存されるのを
    //    避けるため、確定は「試合開始」「早送り」のタイミングだけにする。
  }

  Future<void> _pickPosition(int slotIndex) async {
    final p = _slots[slotIndex].player;
    if (p == null) return;
    final picked = await showModalBottomSheet<FieldPosition>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final pos in FieldPosition.values)
                _PositionTile(
                  position: pos,
                  player: p,
                  onTap: () => Navigator.of(ctx).pop(pos),
                ),
            ],
          ),
        );
      },
    );
    if (picked == null) return;
    setState(() {
      _slots[slotIndex] = _slots[slotIndex].copyWith(position: picked);
      _resolvePositionConflict(slotIndex);
    });
    // ※ 確定は「試合開始」「早送り」時にまとめて行うのでここでは保存しない。
  }

  void _resolvePositionConflict(int slotIndex) {
    final pos = _slots[slotIndex].position;
    if (pos == null) return;
    for (int i = 0; i < _slots.length; i++) {
      if (i != slotIndex && _slots[i].position == pos) {
        _slots[i] = _slots[i].copyWith(clearPosition: true);
      }
    }
  }

  /// このスロットに居る守備位置を、その選手が問題なく守れるかを判定。
  /// 投手位置なら投手、野手位置ならその守備位置を守れる野手のみ「適性あり」。
  bool _isPlayerCompatibleWith(Player p, FieldPosition? pos) {
    if (pos == null) return false;
    if (pos == FieldPosition.pitcher) return p.isPitcher;
    if (p.isPitcher) return false;
    final dp = pos.defensePosition;
    if (dp == null) return false;
    return p.canPlay(dp);
  }

  /// 選んだ選手のタイプ（投手/野手）と現在の守備位置が整合しなければ
  /// 自動で良いポジションに置き換える
  FieldPosition? _adjustPositionFor(Player p, FieldPosition? current) {
    if (p.isPitcher) {
      return FieldPosition.pitcher;
    }
    // 野手 → 投手位置に置こうとしていれば外す
    if (current == FieldPosition.pitcher) current = null;
    if (current != null) {
      final defPos = current.defensePosition;
      if (defPos != null && p.canPlay(defPos)) return current;
    }
    // 主ポジション（守備力が最も高い & 守れる位置）を探す
    int bestVal = -1;
    DefensePosition? best;
    for (final dp in DefensePosition.values) {
      if (!p.canPlay(dp)) continue;
      final v = p.getFielding(dp);
      if (v > bestVal) {
        bestVal = v;
        best = dp;
      }
    }
    if (best == null) return current;
    return _toFieldPosition(best);
  }

  FieldPosition _toFieldPosition(DefensePosition dp) {
    switch (dp) {
      case DefensePosition.catcher:
        return FieldPosition.catcher;
      case DefensePosition.first:
        return FieldPosition.first;
      case DefensePosition.second:
        return FieldPosition.second;
      case DefensePosition.third:
        return FieldPosition.third;
      case DefensePosition.shortstop:
        return FieldPosition.shortstop;
      case DefensePosition.outfield:
        return FieldPosition.left;
    }
  }

  // ---------------------------------------------------
  // 保存 / リセット
  // ---------------------------------------------------

  /// 編集前のスナップショット（画面を開いた時の状態）に戻す。
  /// エンジン側の `_myStrategy` は変えない（試合開始/早送りで commit するまでは
  /// そもそもエンジンに変更が反映されていないため）。
  void _revertToInitial() {
    setState(() {
      _slots = List.of(_initialSlots);
      _activeBenchIds = Set.of(_initialActiveBenchIds);
      _activeBullpenIds = Set.of(_initialActiveBullpenIds);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 2),
        content: Text('編集前の状態に戻しました'),
      ),
    );
  }

  /// フォームから [NextGameStrategy] を組み立てる。
  /// バリデーション失敗時は最初に見つかった理由を返す。
  ({NextGameStrategy? strategy, String? error}) _buildStrategyFromForm() {
    final lineup = <Player>[];
    final assigned = <FieldPosition>{};
    for (int i = 0; i < 9; i++) {
      final s = _slots[i];
      if (s.player == null) {
        return (strategy: null, error: '${i + 1} 番打者の選手が未選択です');
      }
      if (s.position == null) {
        return (strategy: null, error: '${i + 1} 番打者の守備位置が未選択です');
      }
      // _slots が保持する Player 参照は選手編集で古くなっている場合があるため、
      // commit 時に controller の最新 Player を id で引き直す。
      final player =
          widget.controller.findPlayerById(s.player!.id) ?? s.player!;
      if (assigned.contains(s.position)) {
        return (
          strategy: null,
          error: '守備位置 ${s.position!.displayName} が重複しています',
        );
      }
      if (s.position == FieldPosition.pitcher && !player.isPitcher) {
        return (
          strategy: null,
          error: '${i + 1} 番に投手以外を投手位置で指定しています',
        );
      }
      if (s.position != FieldPosition.pitcher && player.isPitcher) {
        return (
          strategy: null,
          error: '${i + 1} 番に投手を野手位置で指定しています',
        );
      }
      assigned.add(s.position!);
      lineup.add(player);
    }
    if (lineup.map((p) => p.id).toSet().length != 9) {
      return (strategy: null, error: '打順に重複した選手があります');
    }
    if (assigned.length != FieldPosition.values.length) {
      final missing = FieldPosition.values
          .where((p) => !assigned.contains(p))
          .map((p) => p.displayName)
          .join('・');
      return (strategy: null, error: '未配置のポジション: $missing');
    }

    // lineup[i] は _slots[i] と同じ並びで、controller の最新 Player に解決済み。
    final alignment = <FieldPosition, Player>{
      for (int i = 0; i < 9; i++) _slots[i].position!: lineup[i],
    };
    // 先発投手の中5日チェック（手動指定でも連投を許さない）
    final startingPitcher = alignment[FieldPosition.pitcher]!;
    if (!widget.controller.canStartNextGame(startingPitcher.id)) {
      return (
        strategy: null,
        error: '${startingPitcher.name} は登板間隔（中5日）が不足しています。'
            '別の投手を先発に指定してください',
      );
    }

    // ---- 当日ベンチ入り（控え野手 / 救援）の確定 ----
    // 選手編集を反映するため id で controller の最新インスタンスに引き直す。
    Player latest(Player p) =>
        widget.controller.findPlayerById(p.id) ?? p;
    final activeBench = [
      for (final p in _benchFielderPool())
        if (_activeBenchIds.contains(p.id)) latest(p),
    ];
    if (activeBench.length != _activeBenchTarget) {
      return (
        strategy: null,
        error: 'ベンチ入りタブ: 控え野手は $_activeBenchTarget 人選んでください'
            '（現在 ${activeBench.length} 人）',
      );
    }
    final activeBullpen = [
      for (final p in _bullpenPool())
        if (_activeBullpenIds.contains(p.id)) latest(p),
    ];
    if (activeBullpen.length != _activeBullpenTarget) {
      return (
        strategy: null,
        error: 'ベンチ入りタブ: 救援投手は $_activeBullpenTarget 人選んでください'
            '（現在 ${activeBullpen.length} 人）',
      );
    }

    return (
      strategy: NextGameStrategy(
        lineup: lineup,
        alignment: alignment,
        activeBench: activeBench,
        activeBullpen: activeBullpen,
      ),
      error: null,
    );
  }

  /// 現在の編集内容を「確定」する。
  /// - フォームが完全に valid → `setMyStrategy` で次戦に反映、true を返す
  /// - 不整合あり → 赤い SnackBar でエラー表示し、何も保存せず false を返す
  ///
  /// 親 [MainSeasonScreen] からも呼べるよう public にしている。
  /// 「試合開始」「早送り」を押された瞬間にこのメソッドが呼ばれる。
  bool tryCommit() {
    final result = _buildStrategyFromForm();
    if (result.error != null) {
      _showError('作戦に修正が必要です: ${result.error}');
      return false;
    }
    widget.controller.setMyStrategy(result.strategy!);
    return true;
  }

  /// 「試合開始」を押された時のハンドラ。
  /// 内部で [tryCommit] してから親に試合実行を依頼する。
  void _onTapStartGame() {
    if (!tryCommit()) return;
    widget.onStartGame?.call();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(msg),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }
}

// =====================================================
// 内部用 model / widget
// =====================================================

class _Slot {
  /// ReorderableListView 用の安定 Key として使う識別子。
  /// _loadFromCurrent で新規スロットを作る時にカウンタから生成し、
  /// `copyWith` では同じ id を保持するので、選手の差し替えやドラッグ並び替えで
  /// id が変わらず ReorderableListView が正しくアニメーションできる。
  final String id;
  final Player? player;
  final FieldPosition? position;

  _Slot({required this.id, this.player, this.position});

  _Slot copyWith({
    Player? player,
    FieldPosition? position,
    bool clearPlayer = false,
    bool clearPosition = false,
  }) {
    return _Slot(
      id: id,
      player: clearPlayer ? null : (player ?? this.player),
      position: clearPosition ? null : (position ?? this.position),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Colors.grey.shade200,
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _PlayerTile extends StatelessWidget {
  final Player player;
  final bool selected;
  final VoidCallback onTap;

  /// シーズン成績・コンディションを引くために渡す。
  /// スタメンを決める時の参考情報として subtitle に表示する。
  final SeasonController controller;

  /// このスロットの守備位置を「守れる」選手かどうか。
  /// true の場合、緑ハイライト（背景色 + leading アイコン）で強調する。
  final bool compatible;

  /// 比較対象の守備位置（守備力の数値表示用）。null の場合は表示しない。
  final FieldPosition? slotPosition;

  const _PlayerTile({
    required this.player,
    required this.selected,
    required this.onTap,
    required this.controller,
    this.compatible = false,
    this.slotPosition,
  });

  @override
  Widget build(BuildContext context) {
    final stats = player.isPitcher
        ? _pitcherStatsLine(controller, player)
        : _fielderStatsLine(controller, player);
    final subtitle = '${_handednessLabel(player)}  $stats';

    // 適性ありの場合の trailing:
    //  - 投手位置 → 体力（登板疲労の回復度、連投回避の目安）
    //  - 野手位置 → そのポジションの守備力
    Widget? trailing;
    if (compatible && slotPosition != null) {
      if (slotPosition == FieldPosition.pitcher) {
        final fr = controller.pitcherFreshness(player.id);
        trailing = Text(
          '体力 $fr%',
          style: TextStyle(
            fontSize: 11,
            color: _freshnessColor(fr),
            fontWeight: FontWeight.bold,
          ),
        );
      } else {
        final dp = slotPosition!.defensePosition;
        if (dp != null) {
          trailing = Text(
            '${slotPosition!.displayName} ${player.getFielding(dp)}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.green.shade700,
              fontWeight: FontWeight.bold,
            ),
          );
        }
      }
    }

    return Container(
      // 適性ありは緑の薄いハイライトで目立たせる
      color: compatible ? Colors.green.shade50 : null,
      child: ListTile(
        dense: true,
        selected: selected,
        leading: compatible
            ? Icon(Icons.check_circle,
                size: 20, color: Colors.green.shade600)
            : (player.isPitcher
                ? const Icon(Icons.sports_baseball,
                    size: 18, color: Colors.deepPurple)
                : const Icon(Icons.person, size: 18, color: Colors.grey)),
        title: Text(
          player.name,
          style: TextStyle(
            fontWeight: compatible ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 11),
        ),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}

/// 利き手の表示ラベル。
/// 野手は打席（右 / 左 / 両手）、投手は利き腕（右 / 左）。
String _handednessLabel(Player p) {
  if (p.isPitcher) {
    return p.effectiveThrows == Handedness.left ? '左' : '右';
  }
  switch (p.effectiveBatsBase) {
    case Handedness.left:
      return '左';
    case Handedness.both:
      return '両手';
    case Handedness.right:
      return '右';
  }
}

/// 野手の主要成績を 1 行で（picker subtitle 用、ラベル入りのフルバージョン）。
String _fielderStatsLine(SeasonController c, Player p) {
  final s = c.batterStats[p.id];
  if (s == null) return '記録なし';
  final ba = s.atBats == 0
      ? '-.---'
      : '.${(s.battingAverage * 1000).round().toString().padLeft(3, '0')}';
  return '打率 $ba / 本 ${s.homeRuns} / 点 ${s.rbi} / 盗 ${s.stolenBases}';
}

/// 投手の主要成績を 1 行で（picker subtitle 用）。
String _pitcherStatsLine(SeasonController c, Player p) {
  final s = c.pitcherStats[p.id];
  if (s == null) return '記録なし';
  final era = s.outsRecorded == 0 ? '-.--' : s.era.toStringAsFixed(2);
  final role =
      p.pitcherRole != null ? p.pitcherRole!.displayName : '先発';
  return '防率 $era / 勝 ${s.wins} / 負 ${s.losses} / S ${s.saves} [$role]';
}

/// 野手のコンパクト版（スタメン行で名前の隣に表示する）。
/// 例: "打.267 本3 点11 盗2"
String _fielderStatsCompact(SeasonController c, Player p) {
  final s = c.batterStats[p.id];
  if (s == null) return '';
  final ba = s.atBats == 0
      ? '-.---'
      : '.${(s.battingAverage * 1000).round().toString().padLeft(3, '0')}';
  return '打$ba 本${s.homeRuns} 点${s.rbi} 盗${s.stolenBases}';
}

/// 投手のコンパクト版（スタメン行で名前の隣に表示する）。
/// 例: "防3.42 2-1-0"  (W-L-S)
String _pitcherStatsCompact(SeasonController c, Player p) {
  final s = c.pitcherStats[p.id];
  if (s == null) return '';
  final era = s.outsRecorded == 0 ? '-.--' : s.era.toStringAsFixed(2);
  return '防$era ${s.wins}-${s.losses}-${s.saves}';
}

/// コンディションに応じた色（80↑=緑 / 60↑=橙 / それ以下=赤）
Color _freshnessColor(int freshness) {
  if (freshness >= 80) return Colors.green.shade700;
  if (freshness >= 60) return Colors.orange.shade700;
  return Colors.red.shade700;
}

class _PositionTile extends StatelessWidget {
  final FieldPosition position;
  final Player player;
  final VoidCallback onTap;

  const _PositionTile({
    required this.position,
    required this.player,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isPitcherPos = position == FieldPosition.pitcher;
    final isPlayerPitcher = player.isPitcher;
    final compatible = isPitcherPos == isPlayerPitcher;

    String trailingText;
    if (!compatible) {
      trailingText = isPitcherPos ? '※ 野手は不可' : '※ 投手は不可';
    } else if (isPitcherPos) {
      trailingText = '球速 ${player.averageSpeed ?? '-'}';
    } else {
      final dp = position.defensePosition!;
      trailingText = '守備力 ${player.getFielding(dp)}'
          '${player.canPlay(dp) ? '' : ' (非適性)'}';
    }

    return ListTile(
      dense: true,
      enabled: compatible,
      leading: Icon(
        compatible ? Icons.check_circle : Icons.block,
        size: 18,
        color: compatible
            ? (isPitcherPos
                ? Colors.deepPurple
                : (player.canPlay(position.defensePosition!)
                    ? Colors.green
                    : Colors.orange))
            : Colors.grey,
      ),
      title: Text(position.displayName),
      trailing: Text(
        trailingText,
        style: const TextStyle(fontSize: 11, color: Colors.grey),
      ),
      onTap: compatible ? onTap : null,
    );
  }
}

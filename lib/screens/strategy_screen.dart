import 'package:flutter/material.dart';

import '../billing/entitlements.dart';
import '../engine/engine.dart';
import 'help_screen.dart';

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

  const StrategyScreen({super.key, required this.controller, required this.listenable, this.onStartGame});

  @override
  State<StrategyScreen> createState() => StrategyScreenState();
}

/// 親 [MainSeasonScreen] が `GlobalKey<StrategyScreenState>` 経由で
/// `tryCommit()` を呼べるよう、State クラスは public にしている。
class StrategyScreenState extends State<StrategyScreen> with SingleTickerProviderStateMixin {
  /// 当日ベンチ入り 26 人の内訳（編成バリデーションで使う）。
  static const int _activeBenchTarget = 8; // ベンチ入り控え野手
  static const int _activeBullpenTarget = 9; // ベンチ入り救援

  /// _Slot.id 用の連番カウンタ。`_loadFromCurrent` で新規スロットを作る時に使う。
  int _slotIdCounter = 0;
  String _newSlotId() => 'slot-${_slotIdCounter++}';

  /// 「スタメン」「ベンチ入り」の 2 タブ。
  late final TabController _tabController = TabController(length: 3, vsync: this);

  /// 1〜9 番のスロット。投手は通常 [8]（9 番）だがどこでも置ける。
  late List<_Slot> _slots = List.generate(9, (_) => _Slot(id: _newSlotId()));

  /// DH 制で「投手を打席に立たせない」場合の先発投手（打順には含まれない守備の投手）。
  /// DH を使わない（大谷型・非DHリーグ）ときは null で、投手は打順スロットに入る。
  Player? _dhPitcher;
  Player? _initialDhPitcher;

  /// このシーズンがリーグ DH 採用か。
  bool get _leagueDH => widget.controller.enableDH;

  /// 現在のフォームが DH を使う編成か（リーグ DH 採用 + DH スロットがある）。
  /// 大谷型（打順に投手スロットを置く）は DH を使わないので false。
  bool get _useDHForm => _leagueDH && _slots.any((s) => s.isDH);

  /// 当日ベンチ入りさせる控え野手・救援投手の id 集合。
  /// 控え野手はスタメン8人を除いた野手プールから [_activeBenchTarget] 人、
  /// 救援は救援プールから [_activeBullpenTarget] 人を選ぶ。
  Set<String> _activeBenchIds = {};
  Set<String> _activeBullpenIds = {};

  /// 「元に戻す」ボタン用に、画面表示時点（= 編集前）の状態を覚えておく。
  /// `_loadFromCurrent` で更新される。
  late List<_Slot> _initialSlots = List.generate(9, (_) => _Slot(id: _newSlotId()));
  Set<String> _initialActiveBenchIds = {};
  Set<String> _initialActiveBullpenIds = {};

  /// `_loadFromCurrent` を呼んだ時の `currentDay`。
  /// 試合進行で次の日になったら、自動でフォームを再ロードする判定に使う。
  int _loadedForDay = -1;

  Team get _myTeam => widget.controller.teams.firstWhere((t) => t.id == widget.controller.myTeamId);

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
    // DH 制の先発投手も最新インスタンスに引き直す。
    if (_dhPitcher != null) {
      _dhPitcher = widget.controller.findPlayerById(_dhPitcher!.id) ?? _dhPitcher;
    }
    if (_initialDhPitcher != null) {
      _initialDhPitcher = widget.controller.findPlayerById(_initialDhPitcher!.id) ?? _initialDhPitcher;
    }
  }

  /// 既存の作戦 or オート提案からフォームを初期化。
  /// 「元に戻す」が参照する初期スナップショットも同時に更新する。
  ///
  /// **Day 1 で前年の編成を継承する分岐**: 保存済み作戦が無く、エンジンに
  /// 前年最終スタメン snapshot が残っていれば、その snapshot から `_Slot` を
  /// 組み立てる。引退・移籍で抜けた選手は `player: null`（空白スロット）として
  /// 残し、ユーザーに UI で補完してもらう（試合開始時の既存バリデーションが
  /// 未補完を弾く）。同様にベンチ入り野手・投手も引退者を除外して足りない状態で
  /// 起動し、ユーザーが補完する流れ。
  void _loadFromCurrent() {
    final c = widget.controller;
    if (c.myStrategy == null && c.currentDay == 0 && c.previousLineupSnapshot != null) {
      _loadFromPreviousSnapshot();
    } else {
      _loadFromStrategyOrAuto();
    }
    // 表示中の先発投手が登板不可（前日登板など）なら、ピッカー順で条件を満たす
    // 先頭の投手に差し替える。保存済み作戦の SP が古い（前回の先発のまま）でも、
    // デフォルトが必ず登板可能な投手になることを保証する。
    _ensureStartableStarter();
    // 「元に戻す」用のスナップショット。_Slot は immutable なのでシャローコピーで足りる。
    _initialSlots = List.of(_slots);
    _initialActiveBenchIds = Set.of(_activeBenchIds);
    _initialActiveBullpenIds = Set.of(_activeBullpenIds);
    _initialDhPitcher = _dhPitcher;
    _loadedForDay = c.currentDay;
  }

  /// 通常パス: 保存済み作戦 → オート提案の順で読み込む。
  void _loadFromStrategyOrAuto() {
    final src = widget.controller.myStrategy ?? widget.controller.suggestedStrategyForMyTeam();
    if (src == null) {
      _slots = List.generate(9, (_) => _Slot(id: _newSlotId()));
      _activeBenchIds = {};
      _activeBullpenIds = {};
      _dhPitcher = null;
      return;
    }
    // DH採用時、打順に居て守備配置に居ない選手が DH。投手は打順に居ないので別保持。
    final dhId = src.useDH ? src.designatedHitter?.id : null;
    _slots = [
      for (int i = 0; i < 9; i++)
        _Slot(
          id: _newSlotId(),
          player: src.lineup[i],
          position: src.lineup[i].id == dhId ? null : _findPositionForPlayer(src.lineup[i], src.alignment),
          isDH: src.lineup[i].id == dhId,
        ),
    ];
    _dhPitcher = src.useDH ? src.startingPitcher : null;
    _activeBenchIds = src.activeBench.map((p) => p.id).toSet();
    _activeBullpenIds = src.activeBullpen.map((p) => p.id).toSet();
  }

  /// Day 1 限定: 前年最終 snapshot から `_Slot` を組み立てる。
  /// 引退者は `player: null`（守備位置だけ保持して空白スロット表示）にする。
  /// ベンチ入りも ID 解決して現役のみ残し、引退者ぶんは「不足」状態のまま。
  void _loadFromPreviousSnapshot() {
    final c = widget.controller;
    final snapshot = c.previousLineupSnapshot!;
    _slots = [
      for (int i = 0; i < snapshot.length; i++)
        _Slot(
          id: _newSlotId(),
          // 投手スロットは中4日ゲートのため毎日選び直す必要があり、前年最終の
          // 投手をそのまま埋めても不適切。null（未選択）にしてユーザーに選ばせる
          // のも 1 案だが、オート提案の SP を初期値として入れた方が操作量が
          // 少なくなるので、ここでは中立提案を流用する。
          // DH スロット（守備に就かない）は前年の選手をそのまま埋める。
          player: snapshot[i].position == FieldPosition.pitcher ? _suggestedStarter() : c.findPlayerById(snapshot[i].playerId),
          position: snapshot[i].position,
          isDH: snapshot[i].isDH,
        ),
    ];
    // DH採用シーズンを継承する場合、投手は打順に居ないので別途中立提案から埋める
    // （前年の投手は中4日ゲートで選び直しが必要なため）。
    _dhPitcher = c.previousUseDH ? _suggestedStarter() : null;
    final benchIds = c.previousActiveBenchIds ?? const [];
    _activeBenchIds = {
      for (final id in benchIds)
        if (c.findPlayerById(id) != null) id,
    };
    final bullpenIds = c.previousActiveBullpenIds ?? const [];
    _activeBullpenIds = {
      for (final id in bullpenIds)
        if (c.findPlayerById(id) != null) id,
    };
  }

  /// 表示中の先発投手が登板不可なら、登板可能なデフォルト先発に差し替える。
  /// - DH 制: 別カードの [_dhPitcher]。
  /// - 非DH/大谷: 守備位置が「投手」のスロットの選手。
  void _ensureStartableStarter() {
    final c = widget.controller;
    // 打順に入っている選手は先発候補から除外（DH に起用中の投手＝大谷を含む。
    // 同じ選手が DH で打席に立ちつつ先発もすることはありえない）。
    final lineupIds = <String>{
      for (final s in _slots)
        if (s.player != null) s.player!.id,
    };
    if (_dhPitcher != null) {
      if (!c.canStartNextGame(_dhPitcher!.id)) {
        final def = c.defaultStarterForMyTeam(excludeIds: lineupIds);
        if (def != null) {
          _dhPitcher = def;
          _activeBullpenIds.remove(def.id); // 先発と救援の二重登録を防ぐ
        }
      }
      return;
    }
    for (int i = 0; i < _slots.length; i++) {
      final s = _slots[i];
      if (s.isDH || s.position != FieldPosition.pitcher) continue;
      final sp = s.player;
      if (sp == null || !c.canStartNextGame(sp.id)) {
        // 非DH/大谷: この投手スロットの選手は差し替え対象なので除外集合から外す。
        final exclude = lineupIds.where((id) => id != sp?.id).toSet();
        final def = c.defaultStarterForMyTeam(excludeIds: exclude);
        if (def != null) {
          _slots[i] = s.copyWith(player: def);
          _activeBullpenIds.remove(def.id);
        }
      }
      return;
    }
  }

  /// 中立提案の SP（投手スロットの初期値）。
  /// `suggestedStrategyForMyTeam` の中で選ばれた投手をそのまま採用する。
  Player? _suggestedStarter() {
    final src = widget.controller.suggestedStrategyForMyTeam();
    if (src == null) return null;
    return src.alignment[FieldPosition.pitcher];
  }

  FieldPosition? _findPositionForPlayer(Player p, Map<FieldPosition, Player> alignment) {
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
        final showStartGame = widget.onStartGame != null && !c.isSeasonOver && next != null;
        return Scaffold(
          appBar: AppBar(
            title: const Text('作戦'),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            automaticallyImplyLeading: false,
            actions: [
              TextButton(onPressed: c.isSeasonOver ? null : _revertToInitial, child: const Text('元に戻す')),
              HelpScreen.appBarAction(context),
            ],
          ),
          // 「試合結果を確認する」は全幅ボタンを下部に置くと、その上の編成エリアの
          // 表示領域を削り、DH 制の「先発投手」カードがスクロールしないと出てこない
          // 原因になっていた。右下のフローティングボタンにして編成エリアを広げる。
          floatingActionButton: showStartGame
              ? FloatingActionButton.extended(
                  onPressed: _onTapStartGame,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('試合結果を確認'),
                )
              : null,
          body: c.isSeasonOver
              ? const Center(child: Text('シーズンは終了しました'))
              : next == null
              ? const Center(child: Text('次の試合がありません'))
              : Column(
                  children: [
                    Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 0), child: _buildNextGameCard(next)),
                    TabBar(
                      controller: _tabController,
                      labelColor: Theme.of(context).colorScheme.primary,
                      labelPadding: EdgeInsets.zero,
                      tabs: const [
                        Tab(text: 'スタメン'),
                        Tab(text: 'ベンチ入り野手'),
                        Tab(text: 'ベンチ入り投手'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(controller: _tabController, children: [_buildStarterTab(), _buildBenchFieldersTab(), _buildBenchPitchersTab()]),
                    ),
                  ],
                ),
        );
      },
    );
  }

  /// 「5月29日 21:00」のような表示用の文字列を組み立てる。
  /// 設定時刻は時単位なので分はゼロ固定で 2 桁表示。
  String _formatUnlockTime(DateTime t) {
    final hh = t.hour.toString().padLeft(2, '0');
    return '${t.month}月${t.day}日 $hh:00';
  }

  /// 未解禁時のダイアログ。次の解禁時刻と理由を伝える。
  void _showLockedDialog(DateTime nextUnlock) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('まだ確認できません'),
        content: Text(
          '次の試合結果は\n'
          '${_formatUnlockTime(nextUnlock)}\n'
          'に公開されます。\n\n'
          '※ 無料プレイは 1日1試合の制約です。\n'
          'ショップで時間スキップを購入すると、何度でも結果を確認できます。',
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('閉じる'))],
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
            Text('Day ${next.day}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: isHome ? Colors.deepOrange : Colors.indigo, borderRadius: BorderRadius.circular(10)),
              child: Text(
                isHome ? 'HOME' : 'AWAY',
                style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            const Text('vs', style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(width: 6),
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: opColor, borderRadius: BorderRadius.circular(4)),
              child: Text(
                opponent.shortName,
                style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(opponent.name, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis),
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
        '※ 編集内容は「試合結果を確認」を押すと次の試合に反映されます。',
        style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
      ),
    );
  }

  // ---------------------------------------------------
  // タブ 1: スタメン
  // ---------------------------------------------------
  Widget _buildStarterTab() {
    return SingleChildScrollView(
      // 下部の余白は、右下のフローティングボタンに最後の要素が隠れないように確保。
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLineupCard(),
          // DH を使う編成のときだけ、打席に立たない先発投手を別途選ぶカードを出す。
          if (_useDHForm) ...[const SizedBox(height: 10), _buildDhPitcherCard()],
          const SizedBox(height: 4),
          _buildEditNote(),
        ],
      ),
    );
  }

  /// DH 制で打席に立たない先発投手を選ぶカード（[_useDHForm] のときのみ表示）。
  Widget _buildDhPitcherCard() {
    final p = _dhPitcher;
    final disabledReason = p == null ? null : widget.controller.starterDisabledReason(p.id);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('先発投手', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const Divider(height: 12),
            InkWell(
              onTap: _pickDhPitcher,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.sports_baseball, size: 16, color: Colors.deepPurple),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        p?.name ?? '(未選択)',
                        style: TextStyle(fontSize: 14, color: p == null ? Colors.grey : (disabledReason != null ? Colors.red : null)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (p != null) ...[
                      Text('体力 ${widget.controller.pitcherFreshness(p.id)}%', style: TextStyle(fontSize: 12, color: _freshnessColor(widget.controller.pitcherFreshness(p.id)), fontWeight: FontWeight.bold)),
                      const SizedBox(width: 6),
                    ],
                    const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                  ],
                ),
              ),
            ),
            if (disabledReason != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('※ $disabledReason のため先発できません。別の投手を選んでください。', style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
              ),
          ],
        ),
      ),
    );
  }

  /// DH 制の先発投手ピッカー。全18投手を作戦画面の投手ピッカーと同じ並び
  /// （ロール優先度→体力→背番号）で出し、中4日・体力ゲートで選べない投手は無効化。
  Future<void> _pickDhPitcher() async {
    final team = _myTeam;
    // 打順に入っている選手は先発投手にできない（DH 起用中の投手＝大谷を含む。
    // 同じ選手が DH で打席に立ちつつ別人として投げることはありえないため除外）。
    final lineupIds = <String>{
      for (final s in _slots)
        if (s.player != null) s.player!.id,
    };
    final pitchers = <Player>[
      for (final p in [...team.startingRotation, ...team.bullpen])
        if (!lineupIds.contains(p.id)) p,
    ]..sort((a, b) {
        final ra = pitcherRoleStarterPriority(a.pitcherRole);
        final rb = pitcherRoleStarterPriority(b.pitcherRole);
        if (ra != rb) return ra.compareTo(rb);
        final fa = widget.controller.pitcherFreshness(a.id);
        final fb = widget.controller.pitcherFreshness(b.id);
        if (fa != fb) return fb.compareTo(fa);
        return a.number.compareTo(b.number);
      });
    final picked = await showModalBottomSheet<Player>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final p in pitchers)
                _PlayerTile(
                  player: p,
                  lineupStatus: _dhPitcher?.id == p.id ? _LineupStatus.current : _LineupStatus.available,
                  compatible: true,
                  slotPosition: FieldPosition.pitcher,
                  controller: widget.controller,
                  disabledReason: widget.controller.starterDisabledReason(p.id),
                  onTap: () => Navigator.of(ctx).pop(p),
                ),
            ],
          ),
        );
      },
    );
    if (picked == null) return;
    setState(() {
      _dhPitcher = picked;
      // 先発に選んだ投手がベンチ入り救援に入っていたら外す（先発と救援の二重登録防止）。
      _activeBullpenIds.remove(picked.id);
    });
  }

  // ---------------------------------------------------
  // タブ 2: ベンチ入り野手（控え野手9人を選ぶ）
  // ---------------------------------------------------
  Widget _buildBenchFieldersTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_buildBenchFieldersCard(), const SizedBox(height: 4), _buildEditNote()]),
    );
  }

  // ---------------------------------------------------
  // タブ 3: ベンチ入り投手（救援8人を選ぶ）
  // ---------------------------------------------------
  Widget _buildBenchPitchersTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_buildBullpenCard(), const SizedBox(height: 4), _buildEditNote()]),
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
    // DH 制で別途選んだ先発投手も救援候補から除外する。
    if (_useDHForm && _dhPitcher != null) lineupPitcherIds.add(_dhPitcher!.id);
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
      hint:
          '当日先発を除く全投手から、リリーフ登板する9人を選ぶ。'
          '右の役割（先発/抑え等）はタップで指定（変更後は継続）。'
          '先発役割の投手はベンチ入りさせても最後の砦としてのみ登板。',
      count: count,
      target: _activeBullpenTarget,
      rows: [for (final p in pool) _buildBullpenRow(p)],
    );
  }

  Widget _buildRosterCard({required String title, required String hint, required int count, required int target, required List<Widget> rows}) {
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
                  child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                ),
                Text(
                  '$count / $target',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: ok ? Colors.green.shade700 : Colors.red.shade700),
                ),
              ],
            ),
            Text(hint, style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
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
      sub:
          '${_handednessLabel(p)}  ${_positionsLabel(p)}'
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
          // ベンチ入りトグル: チェックボックスと名前・成績をまとめて1つの
          // タップ領域にする（チェックボックスをタップしても切り替わるように）。
          Expanded(
            child: InkWell(
              onTap: () => _toggleActive(_activeBullpenIds, p.id),
              child: Row(
                children: [
                  Icon(active ? Icons.check_box : Icons.check_box_outline_blank, size: 20, color: active ? primary : Colors.grey),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name, style: TextStyle(fontSize: 14, color: active ? null : Colors.grey.shade600)),
                        Text(
                          '${_handednessLabel(p)}  '
                          '${_pitcherStatsCompact(widget.controller, p)}'
                          '   体力 $fr%',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                      ],
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
                    (p.pitcherRole ?? PitcherRole.middle) == role ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 18,
                    color: (p.pitcherRole ?? PitcherRole.middle) == role ? Theme.of(context).colorScheme.primary : Colors.grey,
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

  Widget _buildToggleRow({required bool active, required String name, required String sub, required VoidCallback onTap, Widget? trailing}) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(active ? Icons.check_box : Icons.check_box_outline_blank, size: 20, color: active ? primary : Colors.grey),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: TextStyle(fontSize: 14, color: active ? null : Colors.grey.shade600)),
                  Text(
                    sub,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontFeatures: const [FontFeature.tabularFigures()]),
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
            const Text('打順 + 守備配置（長押しドラッグで並び替え）', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const Divider(height: 12),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              // デフォルトのドラッグハンドル（右端のアイコン）は出さず、
              // 行全体を長押しでドラッグ開始できるようにする。
              buildDefaultDragHandles: false,
              onReorder: _onReorder,
              children: [
                for (int i = 0; i < _slots.length; i++) ReorderableDelayedDragStartListener(key: ValueKey(_slots[i].id), index: i, child: _buildSlotRow(i)),
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
    final isDup = slot.player != null && _slots.asMap().entries.where((e) => e.key != index && e.value.player?.id == slot.player!.id).isNotEmpty;
    // 守備位置の重複（DH は守備に就かないので、DH スロット同士の重複だけを見る）。
    final isPosDup = slot.isDH
        ? _slots.asMap().entries.where((e) => e.key != index && e.value.isDH).isNotEmpty
        : (slot.position != null && _slots.asMap().entries.where((e) => e.key != index && !e.value.isDH && e.value.position == slot.position).isNotEmpty);

    // 投手位置と選手タイプの整合性チェック（保存時のバリデーションも担当するが
    // 視覚的にも分かるよう色付け）。DH は誰でも可なので不整合にしない。
    bool typeMismatch = false;
    if (slot.player != null && !slot.isDH && slot.position != null) {
      final isPitcherPos = slot.position == FieldPosition.pitcher;
      typeMismatch = isPitcherPos != slot.player!.isPitcher;
    }

    // 野手が「守れない（適性のない）守備位置」に就いているか。
    // スワップ等で適性のない位置に置かれることがあるので、警告表示する。
    // DH スロットは守備に就かないので対象外。
    bool cantField = false;
    if (slot.player != null && !slot.isDH && slot.position != null && !slot.player!.isPitcher) {
      final dp = slot.position!.defensePosition;
      cantField = dp != null && !slot.player!.canPlay(dp);
    }

    // 名前と成績を 1 行に並べる（縦スペース節約）。
    // 推測ゲーム成立のため、打撃指標だけでなく出場数・四球・三振・失策まで
    // 1 行に詰めて、スタメン編成の手がかりをひと目で読める形にする。
    final p = slot.player;
    // DH は打席に立つので、投手登録の選手でも打撃成績を表示する。
    final statsLine = p == null
        ? null
        : (p.isPitcher && !slot.isDH ? _pitcherStatsCompact(widget.controller, p) : _fielderStatsCompact(widget.controller, p));

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
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
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
                        child: Icon(Icons.sports_baseball, size: 14, color: Colors.deepPurple),
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
                          decoration: isDup ? TextDecoration.underline : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // 利き手（野手・DH は打席の左右、投手は投げる手）
                    if (p != null) ...[const SizedBox(width: 6), Text(_handednessLabel(p, asBatter: slot.isDH), style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade400))],
                    if (statsLine != null && statsLine.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      // 成績は Expanded で「残り幅をすべて」確保する。
                      // 名前と成績の両方が Flexible(flex:1) だと残り幅を等分してしまい、
                      // 数値が2-3桁になった時に成績が ellipsis で切れる一方、名前側に
                      // 使われない余白が出る。Expanded にすると名前は中身の幅で済み、
                      // 残りすべてが成績欄になるので、数字が伸びても余白を有効活用できる。
                      Expanded(
                        child: Text(
                          statsLine,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontFeatures: const [FontFeature.tabularFigures()]),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // 守備位置は shortName (1文字: 投/捕/一/二/三/遊/左/中/右) で表示。
          // 適性のない位置（cantField）はオレンジ + 警告アイコンで知らせる。
          // 警告アイコン + 1文字 の組み合わせは Icon ウィジェットの内部キャンバス
          // を含めると 28px に収まらないため 40px 確保（アイコンなしの行と幅が
          // 揃うよう全行共通）。余ったぶんは成績欄（Expanded）に自動で流れる。
          SizedBox(
            width: 40,
            child: InkWell(
              onTap: slot.player == null ? null : () => _pickPosition(index),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (cantField) ...[Icon(Icons.warning_amber_rounded, size: 13, color: Colors.orange.shade800), const SizedBox(width: 2)],
                    Text(
                      slot.isDH ? 'DH' : (slot.position?.shortName ?? '-'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: cantField ? FontWeight.bold : null,
                        // DH は守備位置を持たない（position=null）が「選択済み」なので、
                        // 未選択のグレーにはせず通常色で表示する。
                        color: (!slot.isDH && slot.position == null)
                            ? Colors.grey
                            : (isPosDup || typeMismatch)
                            ? Colors.red
                            : cantField
                            ? Colors.orange.shade800
                            : null,
                        decoration: (isPosDup || typeMismatch) ? TextDecoration.underline : null,
                      ),
                    ),
                  ],
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
    final isDHSlot = _slots[slotIndex].isDH;
    final isPitcherSlot = slotPos == FieldPosition.pitcher;
    // DH スロットは野手なら誰でも適合（守備位置を問わない）。
    bool isCompatible(Player p) => isDHSlot ? !p.isPitcher : _isPlayerCompatibleWith(p, slotPos);
    int groupOf(Player p) {
      if (isCompatible(p)) return 0;
      return p.isPitcher ? 2 : 1;
    }

    // 投手スロットには全18投手（先発ローテ + 救援）が候補に出る。
    // 先発/中継ぎの区分は固定でなく、ユーザーが全投手から先発を選べる。
    final team = _myTeam;
    final all = <Player>[...team.players.take(8), ...team.bench, ...team.startingRotation, ...team.bullpen];
    // 投手スロットの並び（適性グループ内のみ）:
    //   ロール優先度 → 体力降順 → 背番号
    // それ以外のスロットは従来どおり背番号順。
    all.sort((a, b) {
      final ga = groupOf(a);
      final gb = groupOf(b);
      if (ga != gb) return ga.compareTo(gb);
      if (isPitcherSlot && a.isPitcher && b.isPitcher) {
        final ra = pitcherRoleStarterPriority(a.pitcherRole);
        final rb = pitcherRoleStarterPriority(b.pitcherRole);
        if (ra != rb) return ra.compareTo(rb);
        final fa = widget.controller.pitcherFreshness(a.id);
        final fb = widget.controller.pitcherFreshness(b.id);
        if (fa != fb) return fb.compareTo(fa);
      }
      return a.number.compareTo(b.number);
    });

    // 各選手が打順にどう絡んでいるか（この打順 / 他の打順＝スタメン / 控え）。
    _LineupStatus statusOf(Player p) {
      if (_slots[slotIndex].player?.id == p.id) {
        return _LineupStatus.current;
      }
      for (int i = 0; i < _slots.length; i++) {
        if (i != slotIndex && _slots[i].player?.id == p.id) {
          return _LineupStatus.otherSlot;
        }
      }
      return _LineupStatus.available;
    }

    final picked = await showModalBottomSheet<Player>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              // 投手スロットは「全候補が投手」なので凡例を出す意味が薄く、かつ
              // 登板不可（中4日不足／体力不足）でグレーアウトされる投手もあるため、
              // 「緑＝投手」は誤解を招く。投手スロットではヘッダーを出さない。
              if (isDHSlot) const _SectionHeader('緑＝DH に使える野手') else if (slotPos != null && !isPitcherSlot) _SectionHeader('緑＝${slotPos.displayName}を守れる選手'),
              for (final p in all)
                _PlayerTile(
                  player: p,
                  lineupStatus: statusOf(p),
                  compatible: isCompatible(p),
                  slotPosition: slotPos,
                  controller: widget.controller,
                  // DH スロットでは投手登録の選手でも打撃成績で表示する。
                  asBatter: isDHSlot,
                  // 投手スロットだけ「中4日不足／体力不足」で選択不可にする。
                  // 「現在」スロットに既に入っている投手は disable 化しても
                  // 元から選択する意味がないので統一して disable で構わない。
                  disabledReason: isPitcherSlot && p.isPitcher ? widget.controller.starterDisabledReason(p.id) : null,
                  onTap: () => Navigator.of(ctx).pop(p),
                ),
            ],
          ),
        );
      },
    );
    if (picked == null) return;
    setState(() {
      // picked が既にスタメン（別の打順スロット）にいるか探す。
      int otherIndex = -1;
      for (int i = 0; i < _slots.length; i++) {
        if (i != slotIndex && _slots[i].player?.id == picked.id) {
          otherIndex = i;
          break;
        }
      }
      if (otherIndex >= 0) {
        // スタメン同士の選択 → 長押しドラッグと同じく、選手・守備位置ごと
        // スロットを丸ごとスワップする。
        final tmp = _slots[slotIndex];
        _slots[slotIndex] = _slots[otherIndex];
        _slots[otherIndex] = tmp;
      } else if (_slots[slotIndex].isDH) {
        // DH スロットは守備位置を持たない。選手だけ差し替える（DH のまま）。
        _slots[slotIndex] = _slots[slotIndex].copyWith(player: picked);
      } else {
        // ベンチ選手の選択 → 守備位置は維持したまま選手だけ差し替える。
        // （投手↔野手のタイプ不一致・位置未設定のときだけ _adjustPositionFor が補正）
        final oldPos = _slots[slotIndex].position;
        final newPos = _adjustPositionFor(picked, oldPos);
        _slots[slotIndex] = _slots[slotIndex].copyWith(player: picked, position: newPos, clearPosition: newPos == null);
        // 守備位置が別スロットと衝突したら、旧位置を相手に渡してスワップ
        _swapDisplacedPosition(slotIndex, newPos, oldPos);
      }
      // スタメンが変わると控え野手プールも変わる。ベンチ入りが定員割れしたら補充。
      _healActiveBench();
    });
    // ※ ここでは setMyStrategy は呼ばない。中途半端な編集状態で保存されるのを
    //    避けるため、確定は「試合開始」「早送り」のタイミングだけにする。
  }

  Future<void> _pickPosition(int slotIndex) async {
    final p = _slots[slotIndex].player;
    if (p == null) return;
    final picked = await showModalBottomSheet<_PosResult>(
      context: context,
      // デフォルトだと高さが画面の約半分に制限され、項目（投手+DH+8守備位置=10）が
      // 収まらずスクロールが要る。内容の高さに合わせて全項目を 1 画面に出す。
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final pos in FieldPosition.values) ...[
                _PositionTile(position: pos, player: p, onTap: () => Navigator.of(ctx).pop(_PosResult.field(pos))),
                // DH は「投手（大谷）」と並ぶ打席役割なので、投手の直後（上の方）に
                // 出してスクロールせずに見えるようにする。リーグ DH 採用時のみ。
                if (_leagueDH && pos == FieldPosition.pitcher) _DHPositionTile(player: p, onTap: () => Navigator.of(ctx).pop(const _PosResult.dh())),
              ],
            ],
          ),
        );
      },
    );
    if (picked == null) return;
    setState(() {
      if (picked.isDH) {
        // DH スロットにする（選手はそのまま。投手登録の選手でも DH 可）。
        // DH は 1 人だけなので、既存の DH スロットは解除し、そこに今のスロットの
        // 旧守備位置（投手以外）を引き継がせる。
        final cur = _slots[slotIndex];
        final oldPos = cur.position;
        for (int i = 0; i < _slots.length; i++) {
          if (i == slotIndex || !_slots[i].isDH) continue;
          _slots[i] = (oldPos != null && oldPos != FieldPosition.pitcher) ? _slots[i].copyWith(isDH: false, position: oldPos) : _slots[i].copyWith(isDH: false, clearPosition: true);
        }
        _slots[slotIndex] = cur.copyWith(isDH: true, clearPosition: true);
      } else {
        final pos = picked.field!;
        final wasDH = _slots[slotIndex].isDH;
        final oldPos = _slots[slotIndex].position;
        _slots[slotIndex] = _slots[slotIndex].copyWith(position: pos, isDH: false);
        // 元々 pos を守っていたスロットに、このスロットの旧位置を渡す（スワップ）。
        // DH から守備位置へ変えた場合は引き継ぐ旧位置が無いので相手は空白になる。
        _swapDisplacedPosition(slotIndex, pos, wasDH ? null : oldPos);
      }
    });
    // ※ 確定は「試合開始」「早送り」時にまとめて行うのでここでは保存しない。
  }

  /// [slotIndex] の守備位置が [newPos] に変わったとき、同じ [newPos] を持って
  /// いた他スロットに、このスロットの**元の守備位置** [oldPos] を渡す（スワップ）。
  /// 守備位置を空白のまま放置せず、自動で入れ替えてユーザーの手間を減らす。
  /// 入れ替えた相手がそのポジションを守れるとは限らないが、それは
  /// [_buildSlotRow] が「適性なし」を色 + 警告アイコンで示すので、ユーザーは
  /// 気になる場合だけ追加で直せばよい。
  void _swapDisplacedPosition(int slotIndex, FieldPosition? newPos, FieldPosition? oldPos) {
    if (newPos == null) return;
    for (int i = 0; i < _slots.length; i++) {
      if (i == slotIndex) continue;
      if (_slots[i].position == newPos) {
        _slots[i] = oldPos == null ? _slots[i].copyWith(clearPosition: true) : _slots[i].copyWith(position: oldPos);
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

  /// 選手を入れ替えたときの守備位置を決める。
  ///
  /// **守備位置はできるだけ維持する**。野手が既に野手位置に就いているなら、
  /// その位置を守れなくてもそのまま維持する（勝手に別位置へ動かさない。
  /// 適性がない場合は [_buildSlotRow] が「非適性」を色で示すので、ユーザーが
  /// 必要なときだけ直せばよい）。位置を補正するのは「選手タイプと位置タイプが
  /// 食い違う場合」（投手↔野手）と「位置未設定」のときだけ。
  FieldPosition? _adjustPositionFor(Player p, FieldPosition? current) {
    if (p.isPitcher) {
      return FieldPosition.pitcher; // 投手は必ず投手位置
    }
    // 野手で、既に野手位置が設定されているならそのまま維持（守備適性は問わない）。
    if (current != null && current != FieldPosition.pitcher) {
      return current;
    }
    // 位置未設定 or 投手位置に野手が来た → 守れる主ポジションを割り当てる。
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
    if (best == null) return null; // 守れる位置が無い → 未設定（ユーザーが選ぶ）
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
      _dhPitcher = _initialDhPitcher;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 2), content: Text('編集前の状態に戻しました')));
  }

  /// フォームから [NextGameStrategy] を組み立てる。
  /// バリデーション失敗時は最初に見つかった理由を返す。
  ({NextGameStrategy? strategy, String? error}) _buildStrategyFromForm() {
    ({NextGameStrategy? strategy, String? error}) err(String m) => (strategy: null, error: m);

    // commit 時に controller の最新 Player を id で引き直す（選手編集を反映）。
    Player latest(Player p) => widget.controller.findPlayerById(p.id) ?? p;

    // ---- 打順 9 人を集める（選手の有無のみ先にチェック） ----
    final lineup = <Player>[];
    for (int i = 0; i < 9; i++) {
      final s = _slots[i];
      if (s.player == null) return err('${i + 1} 番打者の選手が未選択です');
      if (!s.isDH && s.position == null) {
        return err('${i + 1} 番打者の守備位置が未選択です');
      }
      lineup.add(latest(s.player!));
    }
    if (lineup.map((p) => p.id).toSet().length != 9) {
      return err('打順に重複した選手があります');
    }

    final hasDH = _slots.any((s) => s.isDH);
    final hasPitcherSlot = _slots.any((s) => !s.isDH && s.position == FieldPosition.pitcher);
    if (hasDH && !_leagueDH) {
      return err('このシーズンは DH 制ではありません');
    }
    if (hasDH && hasPitcherSlot) {
      return err('DH と 投手 を同時に打順へ置けません（どちらか一方を選んでください）');
    }
    if (_leagueDH && !hasDH && !hasPitcherSlot) {
      return err('打順に DH か 投手 のどちらかを置いてください');
    }

    final useDH = _leagueDH && hasDH;
    final Map<FieldPosition, Player> alignment;

    if (useDH) {
      // DH モード: 打順 9 人は全員野手（8 守備野手 + DH）。投手は別途。
      final assigned = <FieldPosition>{};
      for (int i = 0; i < 9; i++) {
        final s = _slots[i];
        final player = lineup[i];
        if (s.isDH) {
          // DH は誰でも可（二刀流選手を登板しない日に DH 起用するケースを含む）。
          continue;
        }
        if (player.isPitcher) return err('${i + 1} 番に投手を野手位置で指定しています');
        if (assigned.contains(s.position)) {
          return err('守備位置 ${s.position!.displayName} が重複しています');
        }
        assigned.add(s.position!);
      }
      final fieldPositions = {
        for (final p in FieldPosition.values)
          if (p != FieldPosition.pitcher) p,
      };
      if (!assigned.containsAll(fieldPositions)) {
        final missing = fieldPositions.where((p) => !assigned.contains(p)).map((p) => p.displayName).join('・');
        return err('未配置のポジション: $missing');
      }
      // 別途指定する先発投手。
      final sp = _dhPitcher;
      if (sp == null) return err('先発投手が未選択です（DH制）');
      final spLatest = latest(sp);
      if (!spLatest.isPitcher) return err('先発投手に野手が指定されています');
      if (lineup.any((p) => p.id == spLatest.id)) {
        return err('先発投手が打順にも入っています');
      }
      final disabledReason = widget.controller.starterDisabledReason(spLatest.id);
      if (disabledReason != null) {
        return err('${spLatest.name} は先発できません（$disabledReason）。別の投手を指定してください');
      }
      alignment = {
        for (int i = 0; i < 9; i++)
          if (!_slots[i].isDH) _slots[i].position!: lineup[i],
        FieldPosition.pitcher: spLatest,
      };
    } else {
      // 非DH / 大谷型: 打順 9 人に投手 1 人を含む。守備 9 人と一致。
      final assigned = <FieldPosition>{};
      for (int i = 0; i < 9; i++) {
        final s = _slots[i];
        final player = lineup[i];
        if (assigned.contains(s.position)) {
          return err('守備位置 ${s.position!.displayName} が重複しています');
        }
        if (s.position == FieldPosition.pitcher && !player.isPitcher) {
          return err('${i + 1} 番に投手以外を投手位置で指定しています');
        }
        if (s.position != FieldPosition.pitcher && player.isPitcher) {
          return err('${i + 1} 番に投手を野手位置で指定しています');
        }
        assigned.add(s.position!);
      }
      if (assigned.length != FieldPosition.values.length) {
        final missing = FieldPosition.values.where((p) => !assigned.contains(p)).map((p) => p.displayName).join('・');
        return err('未配置のポジション: $missing');
      }
      alignment = {for (int i = 0; i < 9; i++) _slots[i].position!: lineup[i]};
      // 先発投手のゲート（中4日 + 体力100%）。手動指定でも連投・疲労登板は許さない。
      final startingPitcher = alignment[FieldPosition.pitcher]!;
      final disabledReason = widget.controller.starterDisabledReason(startingPitcher.id);
      if (disabledReason != null) {
        return err('${startingPitcher.name} は先発できません（$disabledReason）。別の投手を先発に指定してください');
      }
    }

    // ---- 当日ベンチ入り（控え野手 / 救援）の確定（DH 有無で共通） ----
    final activeBench = [
      for (final p in _benchFielderPool())
        if (_activeBenchIds.contains(p.id)) latest(p),
    ];
    if (activeBench.length != _activeBenchTarget) {
      return err('ベンチ入りタブ: 控え野手は $_activeBenchTarget 人選んでください（現在 ${activeBench.length} 人）');
    }
    final activeBullpen = [
      for (final p in _bullpenPool())
        if (_activeBullpenIds.contains(p.id)) latest(p),
    ];
    if (activeBullpen.length != _activeBullpenTarget) {
      return err('ベンチ入りタブ: 救援投手は $_activeBullpenTarget 人選んでください（現在 ${activeBullpen.length} 人）');
    }

    return (strategy: NextGameStrategy(lineup: lineup, alignment: alignment, useDH: useDH, activeBench: activeBench, activeBullpen: activeBullpen), error: null);
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

  /// 「試合結果を確認する」を押された時のハンドラ。
  /// 1日1試合制約: 解禁前ならダイアログだけ出して試合は進めない。
  /// 解禁中なら [tryCommit] してから親に試合実行を依頼する。
  void _onTapStartGame() {
    final now = DateTime.now();
    final hasTimeSkipSub = Entitlements.instance.hasTimeSkipSub;
    final gate = widget.controller.unlockGate(hasTimeSkipSub: hasTimeSkipSub);
    if (!gate.isViewable(now)) {
      _showLockedDialog(gate.nextUnlockAt(now));
      return;
    }
    if (!tryCommit()) return;
    widget.onStartGame?.call();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 2), content: Text(msg), backgroundColor: Colors.red.shade700));
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

  /// DH（指名打者）スロットか。true のとき [position] は null（守備に就かない）。
  /// リーグ DH 採用時のみ立ちうる。
  final bool isDH;

  _Slot({required this.id, this.player, this.position, this.isDH = false});

  _Slot copyWith({Player? player, FieldPosition? position, bool? isDH, bool clearPlayer = false, bool clearPosition = false}) {
    return _Slot(
      id: id,
      player: clearPlayer ? null : (player ?? this.player),
      position: clearPosition ? null : (position ?? this.position),
      isDH: isDH ?? this.isDH,
    );
  }
}

/// 守備位置ピッカーの選択結果。通常の守備位置 [field] か、DH（[isDH]=true）。
class _PosResult {
  final FieldPosition? field;
  final bool isDH;
  const _PosResult.field(this.field) : isDH = false;
  const _PosResult.dh()
      : field = null,
        isDH = true;
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Colors.grey.shade200,
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}

/// 選手ピッカー内で、その選手が打順（スタメン）にどう絡んでいるか。
enum _LineupStatus {
  current, // 編集中の打順スロットに今いる選手
  otherSlot, // 別の打順スロットにいる（＝既にスタメン）
  available, // 打順に入っていない（＝控え）
}

class _PlayerTile extends StatelessWidget {
  final Player player;

  /// この選手が打順（スタメン）にどう絡んでいるか。タグで表示する。
  final _LineupStatus lineupStatus;
  final VoidCallback onTap;

  /// シーズン成績・コンディションを引くために渡す。
  /// スタメンを決める時の参考情報として subtitle に表示する。
  final SeasonController controller;

  /// このスロットの守備位置を「守れる」選手かどうか。
  /// true の場合、緑ハイライト（背景色 + leading アイコン）で強調する。
  final bool compatible;

  /// 比較対象の守備位置（守備力の数値表示用）。null の場合は表示しない。
  final FieldPosition? slotPosition;

  /// このスロットにこの選手を選べない場合の理由。
  /// 非 null のとき、行をグレーアウトし、タップを無効化、trailing に赤字で
  /// 理由を表示する。投手スロットで「中4日不足／体力不足」のケースで使う。
  final String? disabledReason;

  /// DH スロット用。true のとき投手登録の選手でも打撃成績・打席の左右で表示する。
  final bool asBatter;

  const _PlayerTile({
    required this.player,
    required this.lineupStatus,
    required this.onTap,
    required this.controller,
    this.compatible = false,
    this.slotPosition,
    this.disabledReason,
    this.asBatter = false,
  });

  /// 打順絡みを示すタグ（この打順 / スタメン / 控え or 投手）。
  /// available（スタメンに入っていない）の投手は「控え」だと先発ローテに
  /// 入っている投手まで控え扱いに見えるため、投手の場合は「投手」と表示。
  Widget _buildStatusChip() {
    final String label;
    final Color color;
    switch (lineupStatus) {
      case _LineupStatus.current:
        label = '現在';
        color = Colors.green.shade600;
      case _LineupStatus.otherSlot:
        label = 'スタメン';
        color = Colors.indigo.shade400;
      case _LineupStatus.available:
        label = player.isPitcher ? '投手' : '控え';
        color = Colors.grey.shade500;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // DH スロット（asBatter）では投手登録の選手でも打撃成績・打席の左右を表示。
    final stats = (player.isPitcher && !asBatter) ? _pitcherStatsLine(controller, player) : _fielderStatsLine(controller, player);
    final subtitle = '${_handednessLabel(player, asBatter: asBatter)}  $stats';
    final disabled = disabledReason != null;

    // 適性ありの場合の trailing:
    //  - 投手位置 → 体力 + 先発不可ならその理由を赤字で
    //  - 野手位置 → そのポジション名のみ（守備力の数値は隠す: SPEC §2.0）
    Widget? trailing;
    if (compatible && slotPosition != null) {
      if (slotPosition == FieldPosition.pitcher) {
        final fr = controller.pitcherFreshness(player.id);
        trailing = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '体力 $fr%',
              style: TextStyle(fontSize: 11, color: _freshnessColor(fr), fontWeight: FontWeight.bold),
            ),
            if (disabled)
              Text(
                disabledReason!,
                style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.bold),
              ),
          ],
        );
      } else {
        final dp = slotPosition!.defensePosition;
        if (dp != null) {
          trailing = Text(
            slotPosition!.displayName,
            style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.bold),
          );
        }
      }
    }

    return Container(
      // 適性あり: 緑の薄いハイライト。先発不可: グレーの薄いハイライトで上書き。
      color: disabled ? Colors.grey.shade200 : (compatible ? Colors.green.shade50 : null),
      child: ListTile(
        dense: true,
        enabled: !disabled,
        // 打順絡みはタグで示すので、selected による文字色の微妙な変化は使わない。
        leading: compatible
            ? Icon(Icons.check_circle, size: 20, color: disabled ? Colors.grey.shade400 : Colors.green.shade600)
            : (player.isPitcher
                  ? const Icon(Icons.sports_baseball, size: 18, color: Colors.deepPurple)
                  : const Icon(Icons.person, size: 18, color: Colors.grey)),
        title: Row(
          children: [
            Flexible(
              child: Text(
                player.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: compatible ? FontWeight.bold : FontWeight.normal, color: disabled ? Colors.grey.shade600 : null),
              ),
            ),
            // 外国人マークはカタカナ表記で識別できるため表示しない
            const SizedBox(width: 6),
            _buildStatusChip(),
          ],
        ),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 11, color: disabled ? Colors.grey.shade600 : null)),
        trailing: trailing,
        onTap: disabled ? null : onTap,
      ),
    );
  }
}

/// 利き手の表示ラベル。
/// 打席に立つ選手（野手・DH）は打席（右 / 左 / 両）、投手として出る場合は利き腕（右 / 左）。
/// [asBatter] true のとき、投手登録の選手でも打席の左右を返す（DH 起用時）。
String _handednessLabel(Player p, {bool asBatter = false}) {
  if (p.isPitcher && !asBatter) {
    return p.effectiveThrows == Handedness.left ? '左' : '右';
  }
  switch (p.effectiveBatsBase) {
    case Handedness.left:
      return '左';
    case Handedness.both:
      return '両';
    case Handedness.right:
      return '右';
  }
}

/// 野手の主要成績（picker subtitle 用）。スタメン行と同じコンパクト形式で表示し、
/// 開幕日（Day 1）のみ前年成績を括弧書きでフォールバックする。当季出場も前年も
/// ないなら「記録なし」。
String _fielderStatsLine(SeasonController c, Player p) {
  final compact = _fielderStatsCompact(c, p);
  return compact.isEmpty ? '記録なし' : compact;
}

/// 投手の主要成績（picker subtitle 用）。野手と同じく compact 形式を流用しつつ、
/// 末尾にロール表示 `[先発]` 等を付ける。ロール表示はピッカーで先発候補を選ぶ
/// 時の手がかり（試合結果から推測したロールが正しいか即見える）。
String _pitcherStatsLine(SeasonController c, Player p) {
  final role = p.pitcherRole != null ? p.pitcherRole!.displayName : '先発';
  final compact = _pitcherStatsCompact(c, p);
  return compact.isEmpty ? '記録なし [$role]' : '$compact [$role]';
}

/// 野手のコンパクト版（スタメン行で名前の隣に 1 行で表示）。
/// 例: ".267 本3 点11 盗2 失1"
/// 推測ゲームの手がかりを最低限揃えつつ、1 行で切れない長さに収める:
/// 打撃 4 項目（打率/本/点/盗）+ 守備の手がかり（失策）。出場数・四球・三振は
/// チーム成績画面側で確認する想定。
///
/// **Day 1（開幕直前 = `currentDay == 0`）は当季試合が無いため、前年成績を
/// 括弧書きで表示**。これがないと開幕日に「全員 .--- 本0 ...」だけになって
/// スタメン編成の手がかりが失われる。Day 2 以降は当季成績のみ。
String _fielderStatsCompact(SeasonController c, Player p) {
  final cur = c.batterStats[p.id];
  if (cur != null && cur.games > 0) {
    return _formatBatterCompact(cur);
  }
  if (c.currentDay == 0) {
    final prev = c.previousBatterStatsOf(p.id);
    if (prev != null && prev.games > 0) {
      // 「前年」ラベルは省略。括弧書き自体が前年表示の合図として機能する。
      return '(${_formatBatterCompact(prev)})';
    }
  }
  return '';
}

String _formatBatterCompact(BatterSeasonStats s) {
  final ba = s.atBats == 0 ? '-.---' : '.${(s.battingAverage * 1000).round().toString().padLeft(3, '0')}';
  // 「打率」ラベルは省略。"." で始まる小数は文脈で打率と分かる + ReorderableListView
  // 由来の右側余白で表示幅が限られるため、文字数を切り詰めて切れを回避。
  return '$ba 本${s.homeRuns} 点${s.rbi} '
      '盗${s.stolenBases} 失${s.errors}';
}

/// 投手のコンパクト版（スタメン行で名前の隣に 1 行で表示）。
/// 例: "3.00 勝3 負1 S2 H5"
/// 野手と同程度の長さに揃える: 防率/勝/負/S/H。
/// セーブ・ホールドを並べておくことで、起用ロール（先発/抑え/中継ぎ）を試合結果
/// から推測しやすくする。Day 1 のみ前年成績にフォールバック。
String _pitcherStatsCompact(SeasonController c, Player p) {
  final cur = c.pitcherStats[p.id];
  if (cur != null && cur.games > 0) {
    return _formatPitcherCompact(cur);
  }
  if (c.currentDay == 0) {
    final prev = c.previousPitcherStatsOf(p.id);
    if (prev != null && prev.games > 0) {
      return '(${_formatPitcherCompact(prev)})';
    }
  }
  return '';
}

String _formatPitcherCompact(PitcherSeasonStats s) {
  final era = s.outsRecorded == 0 ? '-.--' : s.era.toStringAsFixed(2);
  // 「防率」ラベルは省略（先頭の小数で防御率と分かる）。野手と同じく切れ回避優先。
  return '$era 勝${s.wins} 負${s.losses} '
      'S${s.saves} H${s.holds}';
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

  const _PositionTile({required this.position, required this.player, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isPitcherPos = position == FieldPosition.pitcher;
    final isPlayerPitcher = player.isPitcher;
    final compatible = isPitcherPos == isPlayerPitcher;
    // 野手位置で、その守備位置を守れるか（守備適性があるか）。
    final canField = compatible && !isPitcherPos && player.canPlay(position.defensePosition!);

    // 守備力・球速の数値は能力バレなので出さない（SPEC §2.0）。
    // 守備適性の有無のみを質的に示す。
    String trailingText;
    if (!compatible) {
      trailingText = isPitcherPos ? '※ 野手は不可' : '※ 投手は不可';
    } else if (isPitcherPos) {
      trailingText = '投手位置';
    } else if (canField) {
      trailingText = '守れる';
    } else {
      // 配置自体は可能だが強制配置のペナルティがかかる。
      trailingText = '適性なし';
    }

    // アイコン: 守れる=緑チェック / 守れない=オレンジ警告（チェックにしない。
    // チェックだと「守れる」と誤解されるため）/ 投手位置OK=紫チェック /
    // 選手タイプ不一致=グレー禁止。
    final IconData iconData;
    final Color iconColor;
    if (!compatible) {
      iconData = Icons.block;
      iconColor = Colors.grey;
    } else if (isPitcherPos) {
      iconData = Icons.check_circle;
      iconColor = Colors.deepPurple;
    } else if (canField) {
      iconData = Icons.check_circle;
      iconColor = Colors.green;
    } else {
      iconData = Icons.warning_amber_rounded;
      iconColor = Colors.orange;
    }

    return ListTile(
      dense: true,
      enabled: compatible,
      leading: Icon(iconData, size: 18, color: iconColor),
      title: Text(position.displayName),
      trailing: Text(trailingText, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      onTap: compatible ? onTap : null,
    );
  }
}

/// DH（指名打者）を選ぶタイル。DH は打席だけ立ち守備には就かない。
/// 誰でも DH に指名できる（投手登録の二刀流選手を登板しない日に DH 起用も可）。
/// DH を使うときは、守備に就く先発投手を別途カードで指定する。
class _DHPositionTile extends StatelessWidget {
  final Player player;
  final VoidCallback onTap;

  const _DHPositionTile({required this.player, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.sports_baseball_outlined, size: 18, color: Colors.teal),
      title: const Text('DH（指名打者）'),
      trailing: const Text('打席のみ・守備なし', style: TextStyle(fontSize: 11, color: Colors.grey)),
      onTap: onTap,
    );
  }
}

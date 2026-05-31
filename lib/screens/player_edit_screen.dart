import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../billing/entitlements.dart';
import '../engine/engine.dart';

/// 選手能力の編集画面
///
/// 投手・野手それぞれのパラメータをスライダーやトグルで編集する。
/// 「保存」を押すと [SeasonController.updatePlayer] で全参照を差し替え、
/// シーズンの統計は維持しつつ以降の試合に新しい能力で出場するようになる。
///
/// ※ 将来的にはサブスク解放機能の予定だが、現状は誰でも自由に編集できる。
class PlayerEditScreen extends StatefulWidget {
  final SeasonController controller;
  final Player initial;

  const PlayerEditScreen({super.key, required this.controller, required this.initial});

  @override
  State<PlayerEditScreen> createState() => _PlayerEditScreenState();
}

class _PlayerEditScreenState extends State<PlayerEditScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _numberCtrl;
  late TextEditingController _ageCtrl;
  late TextEditingController _speedCtrl;

  late Handedness _bats;
  late Handedness _throws; // 投手のみ
  // null = 先発、それ以外 = 救援ロール
  late PitcherRole? _pitcherRole;

  // 投手能力（1〜10）
  late int _control;
  late int _fastball;
  late int _stamina;

  // 球種（null = 投げない）
  late int? _slider;
  late int? _curve;
  late int? _splitter;
  late int? _changeup;
  late int? _shoot;
  late int? _cutter;
  late int? _sinker;

  // 打撃（投手は参考、野手は本能力）
  late int _meet;
  late int _power;
  late int _eye;

  // 野手能力
  late int _speed;
  late int _arm;

  // 守備力（0=守れない、1〜10=値）。常に6ポジション分のキーを持つ。
  late Map<DefensePosition, int> _fielding;

  // 背番号の重複エラー（同一チームに同じ番号がいると非null）
  String? _numberError;
  // 重複している相手選手。保存時の「入れ替え確認」ダイアログで使う。
  Player? _numberConflictPlayer;

  bool get _isPitcher => widget.initial.isPitcher;

  /// 能力開示＆編集サブスク購入済みか。OFF だと能力系の編集が無効化され、
  /// 背番号と投手ロールだけが編集可能になる（SPEC §コンセプト / §5）。
  bool get _disclosed => Entitlements.instance.hasAbilityDisclosureSub;

  // 球速の許容範囲。
  // 上限 165 = 試合中の調子+5km の揺らぎを乗せても 170km/h に収まり、
  // メジャー最高記録 (Aroldis Chapman 105.1mph ≒ 169km/h) と概ね同等。
  // 下限 100 はマイナスや 0 など極端な値で挙動が壊れないようにするための保険。
  static const int _minSpeed = 100;
  static const int _maxSpeed = 165;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _nameCtrl = TextEditingController(text: p.name);
    _numberCtrl = TextEditingController(text: p.number.toString());
    _ageCtrl = TextEditingController(text: p.age.toString());
    _speedCtrl = TextEditingController(text: (p.averageSpeed ?? 145).toString());

    _bats = p.effectiveBatsBase;
    _throws = p.effectiveThrows;
    // 投手は必ずロールを持つ扱いにする（旧データ・CPU 生成で null の先発投手は
    // 「先発」ロールに正規化）。起用ドロップダウンの value が必ず項目と一致するよう。
    _pitcherRole = p.pitcherRole ?? (p.isPitcher ? PitcherRole.starter : null);

    _control = p.control ?? 5;
    _fastball = p.fastball ?? 5;
    _stamina = p.stamina ?? 5;

    _slider = p.slider;
    _curve = p.curve;
    _splitter = p.splitter;
    _changeup = p.changeup;
    _shoot = p.shoot;
    _cutter = p.cutter;
    _sinker = p.sinker;

    _meet = p.meet ?? 1;
    _power = p.power ?? 1;
    _eye = p.eye ?? 1;
    // 走力は投手も野手も持つ。null フォールバックは生成時の典型値に合わせる
    //   (野手 mean 5、投手 mean 3.5)。
    _speed = p.speed ?? (p.isPitcher ? 3 : 5);
    _arm = p.arm ?? 5;

    // fielding マップを6ポジション分そろえる
    _fielding = {for (final pos in DefensePosition.values) pos: p.fielding == null ? 5 : (p.fielding![pos] ?? 0)};

    _numberCtrl.addListener(_validateNumber);
  }

  /// 同一チーム内で背番号が他の選手と重複していないかをチェック。
  /// 重複していたら `_numberError` にメッセージを入れて TextField に表示する。
  /// 重複している相手 Player は `_numberConflictPlayer` にも保存し、
  /// 保存時の「入れ替え確認」ダイアログで使う。
  void _validateNumber() {
    final text = _numberCtrl.text;
    final n = int.tryParse(text);
    String? error;
    Player? conflict;
    if (text.isNotEmpty && n != null) {
      final team = _findTeamOf(widget.initial.id);
      if (team != null) {
        final seen = <String>{};
        for (final p in [...team.players, ...team.startingRotation, ...team.bullpen, ...team.bench]) {
          if (p.id == widget.initial.id) continue;
          if (!seen.add(p.id)) continue; // 重複参照（先発ローテと players の交差）を除外
          if (p.number == n) {
            error = '背番号 $n は ${p.name} が使用中';
            conflict = p;
            break;
          }
        }
      }
    }
    if (error != _numberError || conflict?.id != _numberConflictPlayer?.id) {
      setState(() {
        _numberError = error;
        _numberConflictPlayer = conflict;
      });
    }
  }

  /// 指定 id の選手が所属するチームを teams から探す。
  Team? _findTeamOf(String playerId) {
    for (final t in widget.controller.teams) {
      for (final p in [...t.players, ...t.startingRotation, ...t.bullpen, ...t.bench]) {
        if (p.id == playerId) return t;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _numberCtrl.dispose();
    _ageCtrl.dispose();
    _speedCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Entitlements.instance,
      builder: (context, _) {
        final disclosed = _disclosed;
        return Scaffold(
          appBar: AppBar(
            title: const Text('選手編集'),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            actions: [TextButton(onPressed: _save, child: const Text('保存'))],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildBasicCard(disclosed: disclosed),
                const SizedBox(height: 8),
                if (disclosed)
                  if (_isPitcher) ..._buildPitcherCards() else ..._buildFielderCards()
                else
                  _buildLockedHint(),
              ],
            ),
          ),
        );
      },
    );
  }

  /// サブスク未購入時に「ここから先は能力編集サブスクで解放」と知らせるカード。
  Widget _buildLockedHint() {
    return Card(
      margin: EdgeInsets.zero,
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.lock_outline, color: Colors.amber.shade800, size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('ショップで「能力の表示と編集」を入手すると、選手の能力を自由に変更できるようになります。', style: TextStyle(fontSize: 12))),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // 基本情報
  // ---------------------------------------------------
  /// 開示サブスク状態に応じて構造を切り替える:
  ///  - 未購入: 「プロフィール（表示専用、名前のみ）」 +
  ///            「背番号と起用」セクションの 2 枚カード
  ///  - 購入済み: 既存どおり「基本情報」1 枚にまとめる（名前・背番号・年齢・利き手・
  ///              打席・起用）
  Widget _buildBasicCard({required bool disclosed}) {
    if (!disclosed) return _buildLockedBasicCards();
    return _buildFullBasicCard();
  }

  Widget _buildLockedBasicCards() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(
          title: 'プロフィール',
          children: [
            _LabelRow(
              label: '名前',
              child: Text(widget.initial.name, style: const TextStyle(fontSize: 14)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _Section(
          title: _isPitcher ? '背番号・起用' : '背番号',
          children: [
            _LabelRow(
              label: '背番号',
              child: SizedBox(
                width: 80,
                child: TextField(
                  controller: _numberCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 3,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                  decoration: InputDecoration(
                    counterText: '',
                    isDense: true,
                    enabledBorder: _numberError != null ? const UnderlineInputBorder(borderSide: BorderSide(color: Colors.red)) : null,
                    focusedBorder: _numberError != null ? const UnderlineInputBorder(borderSide: BorderSide(color: Colors.red, width: 2)) : null,
                  ),
                ),
              ),
            ),
            if (_numberError != null) ...[const SizedBox(height: 4), Text(_numberError!, style: const TextStyle(fontSize: 11, color: Colors.red))],
            if (_isPitcher) ...[
              const SizedBox(height: 12),
              _LabelRow(
                label: '起用',
                child: DropdownButton<PitcherRole?>(
                  value: _pitcherRole,
                  isDense: true,
                  onChanged: (v) => setState(() => _pitcherRole = v),
                  items: [for (final r in PitcherRole.values) DropdownMenuItem(value: r, child: Text(r.displayName))],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildFullBasicCard() {
    return _Section(
      title: '基本情報',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: '名前', isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 1,
              child: TextField(
                controller: _numberCtrl,
                keyboardType: TextInputType.number,
                maxLength: 3,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                decoration: InputDecoration(
                  labelText: '背番号',
                  counterText: '',
                  isDense: true,
                  enabledBorder: _numberError != null ? const UnderlineInputBorder(borderSide: BorderSide(color: Colors.red)) : null,
                  focusedBorder: _numberError != null ? const UnderlineInputBorder(borderSide: BorderSide(color: Colors.red, width: 2)) : null,
                ),
              ),
            ),
          ],
        ),
        if (_numberError != null) ...[const SizedBox(height: 4), Text(_numberError!, style: const TextStyle(fontSize: 11, color: Colors.red))],
        const SizedBox(height: 8),
        _LabelRow(
          label: '年齢',
          child: SizedBox(
            width: 80,
            child: TextField(
              controller: _ageCtrl,
              keyboardType: TextInputType.number,
              maxLength: 2,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
              decoration: const InputDecoration(isDense: true, suffixText: '歳', counterText: ''),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_isPitcher) ...[
          _LabelRow(
            label: '利き腕',
            child: SegmentedButton<Handedness>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: Handedness.right, label: Text('右')),
                ButtonSegment(value: Handedness.left, label: Text('左')),
              ],
              selected: {_throws},
              onSelectionChanged: (s) => setState(() => _throws = s.first),
            ),
          ),
          const SizedBox(height: 8),
        ],
        _LabelRow(
          label: '打席',
          child: SegmentedButton<Handedness>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: Handedness.right, label: Text('右')),
              ButtonSegment(value: Handedness.left, label: Text('左')),
              ButtonSegment(value: Handedness.both, label: Text('両')),
            ],
            selected: {_bats},
            onSelectionChanged: (s) => setState(() => _bats = s.first),
          ),
        ),
        if (_isPitcher) ...[
          const SizedBox(height: 8),
          _LabelRow(
            label: '起用',
            child: DropdownButton<PitcherRole?>(
              value: _pitcherRole,
              isDense: true,
              onChanged: (v) => setState(() => _pitcherRole = v),
              items: [for (final r in PitcherRole.values) DropdownMenuItem(value: r, child: Text(r.displayName))],
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------
  // 投手セクション
  // ---------------------------------------------------
  List<Widget> _buildPitcherCards() {
    return [
      _Section(
        title: '基本能力',
        children: [
          Row(
            children: [
              const SizedBox(width: 96, child: Text('球速', style: TextStyle(fontSize: 13))),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _speedCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    isDense: true,
                    suffixText: 'km/h',
                    helperText: '$_minSpeed〜$_maxSpeed',
                    helperStyle: TextStyle(fontSize: 10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _Slider1to10(label: '伸び', value: _fastball, onChanged: (v) => setState(() => _fastball = v)),
          _Slider1to10(label: '制球', value: _control, onChanged: (v) => setState(() => _control = v)),
          _Slider1to10(label: 'スタミナ', value: _stamina, onChanged: (v) => setState(() => _stamina = v)),
        ],
      ),
      const SizedBox(height: 8),
      _Section(
        title: '球種',
        children: [
          _ToggleSlider(label: 'スライダー', value: _slider, onChanged: (v) => setState(() => _slider = v)),
          _ToggleSlider(label: 'カーブ', value: _curve, onChanged: (v) => setState(() => _curve = v)),
          _ToggleSlider(label: 'スプリット', value: _splitter, onChanged: (v) => setState(() => _splitter = v)),
          _ToggleSlider(label: 'チェンジアップ', value: _changeup, onChanged: (v) => setState(() => _changeup = v)),
          _ToggleSlider(label: 'シュート', value: _shoot, onChanged: (v) => setState(() => _shoot = v)),
          _ToggleSlider(label: 'カットボール', value: _cutter, onChanged: (v) => setState(() => _cutter = v)),
          _ToggleSlider(label: 'シンカー', value: _sinker, onChanged: (v) => setState(() => _sinker = v)),
        ],
      ),
      const SizedBox(height: 8),
      _Section(
        title: '打撃・走塁（参考）',
        children: [
          _Slider1to10(label: 'ミート', value: _meet, onChanged: (v) => setState(() => _meet = v)),
          _Slider1to10(label: '長打', value: _power, onChanged: (v) => setState(() => _power = v)),
          _Slider1to10(label: '選球眼', value: _eye, onChanged: (v) => setState(() => _eye = v)),
          _Slider1to10(label: '走力', value: _speed, onChanged: (v) => setState(() => _speed = v)),
        ],
      ),
    ];
  }

  // ---------------------------------------------------
  // 野手セクション
  // ---------------------------------------------------
  List<Widget> _buildFielderCards() {
    return [
      _Section(
        title: '打撃',
        children: [
          _Slider1to10(label: 'ミート', value: _meet, onChanged: (v) => setState(() => _meet = v)),
          _Slider1to10(label: '長打', value: _power, onChanged: (v) => setState(() => _power = v)),
          _Slider1to10(label: '選球眼', value: _eye, onChanged: (v) => setState(() => _eye = v)),
        ],
      ),
      const SizedBox(height: 8),
      _Section(
        title: '走塁・守備',
        children: [
          _Slider1to10(label: '走力', value: _speed, onChanged: (v) => setState(() => _speed = v)),
          _Slider1to10(label: '肩', value: _arm, onChanged: (v) => setState(() => _arm = v)),
        ],
      ),
      const SizedBox(height: 8),
      _Section(
        title: '守備力（ポジション別）',
        children: [
          for (final pos in DefensePosition.values)
            _ToggleSlider(
              label: pos.displayName,
              // 0 = 守れない、1〜10 = 値
              value: (_fielding[pos] ?? 0) == 0 ? null : _fielding[pos],
              onChanged: (v) => setState(() {
                _fielding[pos] = v ?? 0;
              }),
            ),
        ],
      ),
    ];
  }

  // ---------------------------------------------------
  // 保存
  // ---------------------------------------------------
  /// 能力開示＆編集サブスク未購入時の保存。背番号と投手ロールだけ更新する。
  /// 背番号重複時の入れ替えダイアログはフル保存と同じく出す。
  Future<void> _saveRestricted(Player p, int number) async {
    _validateNumber();
    if (_numberConflictPlayer != null) {
      final other = _numberConflictPlayer!;
      final swap = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('背番号 $number は使用中'),
          content: Text(
            '${other.name} と背番号を入れ替えますか？\n\n'
            '${other.name}: ${other.number} → ${p.number}\n'
            '${p.name}: ${p.number} → $number',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('入れ替える')),
          ],
        ),
      );
      if (swap != true) return;
      widget.controller.updatePlayer(other.withNumber(p.number));
    } else if (_numberError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 2), content: Text(_numberError!)));
      return;
    }

    var updated = p.withNumber(number);
    if (_isPitcher && _pitcherRole != null && _pitcherRole != p.pitcherRole) {
      updated = updated.withPitcherRole(_pitcherRole!);
    }
    widget.controller.updatePlayer(updated);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _save() async {
    final p = widget.initial;
    final number = int.tryParse(_numberCtrl.text) ?? p.number;

    // 能力開示＆編集サブスク未購入の場合は、背番号と投手ロールのみ更新する。
    // 名前・年齢・利き手・打席・各能力は原本そのまま（UI でも非編集にしてある）。
    if (!_disclosed) {
      await _saveRestricted(p, number);
      return;
    }

    final name = _nameCtrl.text.trim().isEmpty ? p.name : _nameCtrl.text.trim();
    final age = (int.tryParse(_ageCtrl.text) ?? p.age).clamp(15, 60);
    final rawSpeed = int.tryParse(_speedCtrl.text) ?? (p.averageSpeed ?? 145);
    final speed = rawSpeed.clamp(_minSpeed, _maxSpeed);

    // 背番号が同一チーム内の他選手と重複している場合は、入れ替え確認ダイアログを
    // 出してユーザーが OK すれば相手の番号もこちらの旧番号に書き換える。
    _validateNumber();
    if (_numberConflictPlayer != null) {
      final other = _numberConflictPlayer!;
      final swap = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('背番号 $number は使用中'),
          content: Text(
            '${other.name} と背番号を入れ替えますか？\n\n'
            '${other.name}: ${other.number} → ${p.number}\n'
            '$name: ${p.number} → $number',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('入れ替える')),
          ],
        ),
      );
      if (swap != true) return;
      // 相手の選手の番号を、こちらの旧番号に更新（updatePlayer は全リスト同期）。
      widget.controller.updatePlayer(other.withNumber(p.number));
    } else if (_numberError != null) {
      // 競合相手は特定できないがエラーが残っている（タイミングの問題）→ 保存を止める
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 2), content: Text(_numberError!)));
      return;
    }

    final updated = Player(
      id: p.id,
      name: name,
      number: number,
      age: age,
      // 投手能力
      averageSpeed: _isPitcher ? speed : null,
      fastball: _isPitcher ? _fastball : null,
      control: _isPitcher ? _control : null,
      slider: _isPitcher ? _slider : null,
      curve: _isPitcher ? _curve : null,
      splitter: _isPitcher ? _splitter : null,
      changeup: _isPitcher ? _changeup : null,
      shoot: _isPitcher ? _shoot : null,
      cutter: _isPitcher ? _cutter : null,
      sinker: _isPitcher ? _sinker : null,
      stamina: _isPitcher ? _stamina : null,
      // 打撃（投手も野手も持つ）
      meet: _meet,
      power: _power,
      eye: _eye,
      // 走力は投手も野手も持つ（_speed をそのまま保存）。
      // ※ 旧バグで投手保存時に null 上書きしていたため、過去セーブの投手は
      //   null になっているが、その場合は _speed の初期化時に投手向けデフォルト 3 で
      //   復元される。
      speed: _speed,
      arm: _isPitcher ? null : _arm,
      // 守備力（野手のみ）
      fielding: _isPitcher ? null : Map.unmodifiable(_fielding),
      // 利き手・ロール
      throws: _isPitcher ? _throws : null,
      bats: _bats,
      pitcherRole: _isPitcher ? _pitcherRole : null,
    );

    widget.controller.updatePlayer(updated);

    if (!mounted) return;
    // 球速が範囲外で補正された場合だけ通知する
    if (_isPitcher && rawSpeed != speed) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(duration: const Duration(seconds: 2), content: Text('球速を $speed km/h に補正しました（許容: $_minSpeed〜$_maxSpeed）')));
    }

    Navigator.of(context).pop();
  }
}

// =====================================================
// 共通ウィジェット
// =====================================================

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const Divider(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _LabelRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _LabelRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 96, child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(child: child),
      ],
    );
  }
}

/// 1〜10 のスライダー行
class _Slider1to10 extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const _Slider1to10({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 96, child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(
          child: Slider(min: 1, max: 10, divisions: 9, value: value.toDouble().clamp(1, 10), label: '$value', onChanged: (v) => onChanged(v.round())),
        ),
        SizedBox(
          width: 24,
          child: Text('$value', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13)),
        ),
      ],
    );
  }
}

/// 「持つ/持たない」のトグル + 1〜10 スライダーの行
/// value が null = 持たない、それ以外 = 持つ
class _ToggleSlider extends StatelessWidget {
  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;

  const _ToggleSlider({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final enabled = value != null;
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(label, style: TextStyle(fontSize: 13, color: enabled ? null : Colors.grey)),
        ),
        Switch(value: enabled, onChanged: (on) => onChanged(on ? 5 : null), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
        Expanded(
          child: enabled
              ? Slider(min: 1, max: 10, divisions: 9, value: value!.toDouble().clamp(1, 10), label: '$value', onChanged: (v) => onChanged(v.round()))
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('なし', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ),
        ),
        SizedBox(
          width: 24,
          child: Text(
            enabled ? '$value' : '-',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 13, color: enabled ? null : Colors.grey),
          ),
        ),
      ],
    );
  }
}

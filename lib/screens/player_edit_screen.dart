import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  const PlayerEditScreen({
    super.key,
    required this.controller,
    required this.initial,
  });

  @override
  State<PlayerEditScreen> createState() => _PlayerEditScreenState();
}

class _PlayerEditScreenState extends State<PlayerEditScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _numberCtrl;
  late TextEditingController _speedCtrl;

  late Handedness _bats;
  late Handedness _throws; // 投手のみ
  // null = 先発、それ以外 = 救援ロール
  late ReliefRole? _reliefRole;

  // 投手能力（1〜10）
  late int _control;
  late int _fastball;
  late int _stamina;

  // 球種（null = 投げない）
  late int? _slider;
  late int? _curve;
  late int? _splitter;
  late int? _changeup;

  // 打撃（投手は参考、野手は本能力）
  late int _meet;
  late int _power;
  late int _eye;

  // 野手能力
  late int _speed;
  late int _arm;
  late int? _lead; // 捕手のみ

  // 守備力（0=守れない、1〜10=値）。常に6ポジション分のキーを持つ。
  late Map<DefensePosition, int> _fielding;

  // 背番号の重複エラー（同一チームに同じ番号がいると非null）
  String? _numberError;

  bool get _isPitcher => widget.initial.isPitcher;

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
    _speedCtrl =
        TextEditingController(text: (p.averageSpeed ?? 145).toString());

    _bats = p.effectiveBatsBase;
    _throws = p.effectiveThrows;
    _reliefRole = p.reliefRole;

    _control = p.control ?? 5;
    _fastball = p.fastball ?? 5;
    _stamina = p.stamina ?? 5;

    _slider = p.slider;
    _curve = p.curve;
    _splitter = p.splitter;
    _changeup = p.changeup;

    _meet = p.meet ?? 1;
    _power = p.power ?? 1;
    _eye = p.eye ?? 1;
    _speed = p.speed ?? 5;
    _arm = p.arm ?? 5;
    _lead = p.lead;

    // fielding マップを6ポジション分そろえる
    _fielding = {
      for (final pos in DefensePosition.values)
        pos: p.fielding == null ? 5 : (p.fielding![pos] ?? 0),
    };

    _numberCtrl.addListener(_validateNumber);
  }

  /// 同一チーム内で背番号が他の選手と重複していないかをチェック。
  /// 重複していたら `_numberError` にメッセージを入れて TextField に表示する。
  void _validateNumber() {
    final text = _numberCtrl.text;
    final n = int.tryParse(text);
    String? error;
    if (text.isNotEmpty && n != null) {
      final team = _findTeamOf(widget.initial.id);
      if (team != null) {
        final seen = <String>{};
        for (final p in [
          ...team.players,
          ...team.startingRotation,
          ...team.bullpen,
          ...team.bench,
        ]) {
          if (p.id == widget.initial.id) continue;
          if (!seen.add(p.id)) continue; // 重複参照（先発ローテと players の交差）を除外
          if (p.number == n) {
            error = '背番号 $n は ${p.name} が使用中';
            break;
          }
        }
      }
    }
    if (error != _numberError) {
      setState(() => _numberError = error);
    }
  }

  /// 指定 id の選手が所属するチームを teams から探す。
  Team? _findTeamOf(String playerId) {
    for (final t in widget.controller.teams) {
      for (final p in [
        ...t.players,
        ...t.startingRotation,
        ...t.bullpen,
        ...t.bench,
      ]) {
        if (p.id == playerId) return t;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _numberCtrl.dispose();
    _speedCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('選手編集'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildBasicCard(),
            const SizedBox(height: 8),
            if (_isPitcher) ..._buildPitcherCards() else ..._buildFielderCards(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // 基本情報
  // ---------------------------------------------------
  Widget _buildBasicCard() {
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
                decoration: const InputDecoration(
                  labelText: '名前',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 1,
              child: TextField(
                controller: _numberCtrl,
                keyboardType: TextInputType.number,
                maxLength: 3,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                decoration: InputDecoration(
                  labelText: '背番号',
                  counterText: '',
                  isDense: true,
                  // errorText は TextField の幅で折り返されて見切れるので、
                  // 行の下に全幅で表示する（下の if (_numberError != null) の行）。
                  // ここでは枠だけ赤くする。
                  enabledBorder: _numberError != null
                      ? const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.red))
                      : null,
                  focusedBorder: _numberError != null
                      ? const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.red, width: 2))
                      : null,
                ),
              ),
            ),
          ],
        ),
        if (_numberError != null) ...[
          const SizedBox(height: 4),
          Text(
            _numberError!,
            style: const TextStyle(fontSize: 11, color: Colors.red),
          ),
        ],
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
            child: DropdownButton<ReliefRole?>(
              value: _reliefRole,
              isDense: true,
              onChanged: (v) => setState(() => _reliefRole = v),
              items: const [
                DropdownMenuItem(value: null, child: Text('先発')),
                DropdownMenuItem(
                    value: ReliefRole.closer, child: Text('抑え')),
                DropdownMenuItem(
                    value: ReliefRole.setup, child: Text('セットアッパー')),
                DropdownMenuItem(
                    value: ReliefRole.middle, child: Text('中継ぎ')),
                DropdownMenuItem(
                    value: ReliefRole.situational, child: Text('ワンポイント')),
                DropdownMenuItem(
                    value: ReliefRole.long, child: Text('ロング')),
                DropdownMenuItem(
                    value: ReliefRole.mopUp, child: Text('敗戦処理')),
              ],
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
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
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
          _Slider1to10(
            label: '制球',
            value: _control,
            onChanged: (v) => setState(() => _control = v),
          ),
          _Slider1to10(
            label: 'ストレートの質',
            value: _fastball,
            onChanged: (v) => setState(() => _fastball = v),
          ),
          _Slider1to10(
            label: 'スタミナ',
            value: _stamina,
            onChanged: (v) => setState(() => _stamina = v),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _Section(
        title: '球種',
        children: [
          _ToggleSlider(
            label: 'スライダー',
            value: _slider,
            onChanged: (v) => setState(() => _slider = v),
          ),
          _ToggleSlider(
            label: 'カーブ',
            value: _curve,
            onChanged: (v) => setState(() => _curve = v),
          ),
          _ToggleSlider(
            label: 'スプリット',
            value: _splitter,
            onChanged: (v) => setState(() => _splitter = v),
          ),
          _ToggleSlider(
            label: 'チェンジアップ',
            value: _changeup,
            onChanged: (v) => setState(() => _changeup = v),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _Section(
        title: '打撃（参考）',
        children: [
          _Slider1to10(
            label: 'ミート',
            value: _meet,
            onChanged: (v) => setState(() => _meet = v),
          ),
          _Slider1to10(
            label: '長打',
            value: _power,
            onChanged: (v) => setState(() => _power = v),
          ),
          _Slider1to10(
            label: '選球眼',
            value: _eye,
            onChanged: (v) => setState(() => _eye = v),
          ),
        ],
      ),
    ];
  }

  // ---------------------------------------------------
  // 野手セクション
  // ---------------------------------------------------
  List<Widget> _buildFielderCards() {
    final canCatch = (_fielding[DefensePosition.catcher] ?? 0) > 0;
    return [
      _Section(
        title: '打撃',
        children: [
          _Slider1to10(
            label: 'ミート',
            value: _meet,
            onChanged: (v) => setState(() => _meet = v),
          ),
          _Slider1to10(
            label: '長打',
            value: _power,
            onChanged: (v) => setState(() => _power = v),
          ),
          _Slider1to10(
            label: '選球眼',
            value: _eye,
            onChanged: (v) => setState(() => _eye = v),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _Section(
        title: '走塁・守備',
        children: [
          _Slider1to10(
            label: '走力',
            value: _speed,
            onChanged: (v) => setState(() => _speed = v),
          ),
          _Slider1to10(
            label: '肩',
            value: _arm,
            onChanged: (v) => setState(() => _arm = v),
          ),
          if (canCatch)
            _ToggleSlider(
              label: 'リード',
              value: _lead,
              onChanged: (v) => setState(() => _lead = v),
            ),
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
                // 捕手から外したらリードもクリアして矛盾防止
                if (pos == DefensePosition.catcher && (v ?? 0) == 0) {
                  _lead = null;
                }
              }),
            ),
        ],
      ),
    ];
  }

  // ---------------------------------------------------
  // 保存
  // ---------------------------------------------------
  void _save() {
    final p = widget.initial;
    final name = _nameCtrl.text.trim().isEmpty ? p.name : _nameCtrl.text.trim();
    final number = int.tryParse(_numberCtrl.text) ?? p.number;
    final rawSpeed =
        int.tryParse(_speedCtrl.text) ?? (p.averageSpeed ?? 145);
    final speed = rawSpeed.clamp(_minSpeed, _maxSpeed);

    // 背番号が同一チーム内の他選手と重複していたら保存をブロック
    _validateNumber();
    if (_numberError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(_numberError!),
        ),
      );
      return;
    }

    final canCatch = (_fielding[DefensePosition.catcher] ?? 0) > 0;

    final updated = Player(
      id: p.id,
      name: name,
      number: number,
      // 投手能力
      averageSpeed: _isPitcher ? speed : null,
      fastball: _isPitcher ? _fastball : null,
      control: _isPitcher ? _control : null,
      stamina: _isPitcher ? _stamina : null,
      slider: _isPitcher ? _slider : null,
      curve: _isPitcher ? _curve : null,
      splitter: _isPitcher ? _splitter : null,
      changeup: _isPitcher ? _changeup : null,
      // 打撃（投手も野手も持つ）
      meet: _meet,
      power: _power,
      eye: _eye,
      // 野手能力
      speed: _isPitcher ? null : _speed,
      arm: _isPitcher ? null : _arm,
      lead: (!_isPitcher && canCatch) ? _lead : null,
      // 守備力（野手のみ）
      fielding: _isPitcher ? null : Map.unmodifiable(_fielding),
      // 利き手・ロール
      throws: _isPitcher ? _throws : null,
      bats: _bats,
      reliefRole: _isPitcher ? _reliefRole : null,
    );

    widget.controller.updatePlayer(updated);

    // 球速が範囲外で補正された場合だけ通知する
    if (_isPitcher && rawSpeed != speed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text('球速を $speed km/h に補正しました（許容: $_minSpeed〜$_maxSpeed）'),
        ),
      );
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
            Text(
              title,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold),
            ),
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
        SizedBox(
            width: 96,
            child: Text(label, style: const TextStyle(fontSize: 13))),
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

  const _Slider1to10({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
            width: 96,
            child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(
          child: Slider(
            min: 1,
            max: 10,
            divisions: 9,
            value: value.toDouble().clamp(1, 10),
            label: '$value',
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(
          width: 24,
          child: Text(
            '$value',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13),
          ),
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

  const _ToggleSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = value != null;
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: enabled ? null : Colors.grey,
            ),
          ),
        ),
        Switch(
          value: enabled,
          onChanged: (on) => onChanged(on ? 5 : null),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        Expanded(
          child: enabled
              ? Slider(
                  min: 1,
                  max: 10,
                  divisions: 9,
                  value: value!.toDouble().clamp(1, 10),
                  label: '$value',
                  onChanged: (v) => onChanged(v.round()),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'なし',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500),
                  ),
                ),
        ),
        SizedBox(
          width: 24,
          child: Text(
            enabled ? '$value' : '-',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              color: enabled ? null : Colors.grey,
            ),
          ),
        ),
      ],
    );
  }
}

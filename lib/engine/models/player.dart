import 'enums.dart';

/// 選手
class Player {
  final String id;
  final String name;
  final int number; // 背番号

  // 投手能力
  final int? averageSpeed; // 平均球速（km/h）、野手はnull
  final int? fastball; // ストレートの質（1〜10）、nullは基準値5（キレ、ノビ等）
  final int? control; // 制球力（1〜10）、野手はnull
  final int? stamina; // スタミナ（1〜10）、nullは基準値5、高いほど疲労しにくい
  final int? slider; // スライダー（1〜10）、nullの場合は投げられない
  final int? curve; // カーブ（1〜10）、nullの場合は投げられない
  final int? splitter; // スプリット（1〜10）、nullの場合は投げられない
  final int? changeup; // チェンジアップ（1〜10）、nullの場合は投げられない

  // 野手能力
  final int? meet; // ミート力（1〜10）
  final int? power; // 長打力（1〜10）
  final int? speed; // 走力（1〜10）、高いほど盗塁成功率UP
  final int? eye; // 選球眼（1〜10）、高いほど四球が増える
  final int? arm; // 肩の強さ（1〜10）、捕手は盗塁阻止、外野手はタッチアップ阻止、内野手は内野安打阻止

  // 捕手専用能力
  final int? lead; // リード（1〜10）、捕手のみ、高いほど被打率が下がる（おまけ程度）

  // 利き手・打席
  // throws: 投手の利き腕（right/left）、野手やnullはright
  // bats: 打者の打席（right/left/both）、投手やnullはright
  //   both(両打ち)は投手の利き腕によって打席が決まる（対右投手→左、対左投手→右）
  final Handedness? throws;
  final Handedness? bats;

  // 救援投手のロール（先発投手・野手は null）
  // 投手交代戦略がこのロールを参照して起用判断を行う。
  final ReliefRole? reliefRole;

  // 守備能力（ポジションごと、0〜10）
  // fielding マップ自体が null  : 全ポジションをデフォルト値5で守れる（未設定の選手用）
  // fielding マップが明示されている: 列挙されたポジションのみ守れる
  //   - 値0   : 明示的に「守れない」
  //   - 値1〜10: 守備力
  //   - キー無し: 守れない（マップは「守れるポジションのリスト」として解釈）
  final Map<DefensePosition, int>? fielding;

  const Player({
    required this.id,
    required this.name,
    required this.number,
    this.averageSpeed,
    this.fastball,
    this.control,
    this.stamina,
    this.slider,
    this.curve,
    this.splitter,
    this.changeup,
    this.meet,
    this.power,
    this.speed,
    this.eye,
    this.arm,
    this.lead,
    this.fielding,
    this.throws,
    this.bats,
    this.reliefRole,
  });

  /// 投手かどうか
  bool get isPitcher => averageSpeed != null;

  /// 利き腕（nullはright）
  Handedness get effectiveThrows => throws ?? Handedness.right;

  /// 打席の基本設定（nullはright、bothは両打ち）
  Handedness get effectiveBatsBase => bats ?? Handedness.right;

  /// 対指定投手のときの実際の打席
  /// 両打ち(both)は投手の利き腕の逆（対右投手→左、対左投手→右）
  /// それ以外は基本設定通り
  Handedness effectiveBatsAgainst(Player pitcher) {
    final base = effectiveBatsBase;
    if (base != Handedness.both) return base;
    return pitcher.effectiveThrows == Handedness.right
        ? Handedness.left
        : Handedness.right;
  }

  /// 指定ポジションの守備力を取得（0〜10）
  /// fielding マップが null の場合はデフォルト値5を返す
  /// マップに該当ポジションが列挙されていない場合は、強制配置時の最低値1を返す
  int getFielding(DefensePosition position) {
    final map = fielding;
    if (map == null) return 5;
    return map[position] ?? 1;
  }

  /// 指定ポジションを守れるかどうか
  /// fielding マップが null の場合はどのポジションも守れる
  /// マップが明示されている場合は、列挙されたポジション（0でない値）のみ守れる
  bool canPlay(DefensePosition position) {
    final map = fielding;
    if (map == null) return true;
    final value = map[position];
    if (value == null) return false; // 列挙されていない = 守れない
    return value != 0; // 0は明示的に守れない
  }

  // ---- 永続化 ----

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'number': number,
      if (averageSpeed != null) 'averageSpeed': averageSpeed,
      if (fastball != null) 'fastball': fastball,
      if (control != null) 'control': control,
      if (stamina != null) 'stamina': stamina,
      if (slider != null) 'slider': slider,
      if (curve != null) 'curve': curve,
      if (splitter != null) 'splitter': splitter,
      if (changeup != null) 'changeup': changeup,
      if (meet != null) 'meet': meet,
      if (power != null) 'power': power,
      if (speed != null) 'speed': speed,
      if (eye != null) 'eye': eye,
      if (arm != null) 'arm': arm,
      if (lead != null) 'lead': lead,
      if (fielding != null)
        'fielding': {
          for (final e in fielding!.entries) e.key.name: e.value,
        },
      if (throws != null) 'throws': throws!.name,
      if (bats != null) 'bats': bats!.name,
      if (reliefRole != null) 'reliefRole': reliefRole!.name,
    };
  }

  factory Player.fromJson(Map<String, dynamic> json) {
    Map<DefensePosition, int>? fielding;
    final f = json['fielding'];
    if (f is Map) {
      fielding = {};
      for (final e in f.entries) {
        final pos = DefensePosition.values.firstWhere((p) => p.name == e.key);
        fielding[pos] = e.value as int;
      }
    }
    Handedness? parseHand(Object? v) {
      if (v == null) return null;
      return Handedness.values.firstWhere((h) => h.name == v);
    }

    return Player(
      id: json['id'] as String,
      name: json['name'] as String,
      number: json['number'] as int,
      averageSpeed: json['averageSpeed'] as int?,
      fastball: json['fastball'] as int?,
      control: json['control'] as int?,
      stamina: json['stamina'] as int?,
      slider: json['slider'] as int?,
      curve: json['curve'] as int?,
      splitter: json['splitter'] as int?,
      changeup: json['changeup'] as int?,
      meet: json['meet'] as int?,
      power: json['power'] as int?,
      speed: json['speed'] as int?,
      eye: json['eye'] as int?,
      arm: json['arm'] as int?,
      lead: json['lead'] as int?,
      fielding: fielding,
      throws: parseHand(json['throws']),
      bats: parseHand(json['bats']),
      reliefRole: json['reliefRole'] == null
          ? null
          : ReliefRole.values
              .firstWhere((r) => r.name == json['reliefRole']),
    );
  }

  @override
  String toString() => '$name (#$number)';
}

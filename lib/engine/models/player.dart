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

  // 守備能力（ポジションごと、0〜10）
  // 0: そのポジションは守れない
  // 1〜10: 守備力（高いほど良い）
  // null: デフォルト値5として扱う
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
  /// 設定されていない場合はデフォルト値5を返す
  int getFielding(DefensePosition position) {
    return fielding?[position] ?? 5;
  }

  /// 指定ポジションを守れるかどうか
  /// 守備力が0の場合は守れない
  bool canPlay(DefensePosition position) {
    final value = fielding?[position];
    // 明示的に0が設定されている場合のみ守れない
    // nullの場合はデフォルト値5で守れる
    return value != 0;
  }

  @override
  String toString() => '$name (#$number)';
}

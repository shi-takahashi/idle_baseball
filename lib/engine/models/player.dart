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
  final int? slider; // スライダー（1〜10）、nullの場合は投げられない
  final int? curve; // カーブ（1〜10）、nullの場合は投げられない
  final int? splitter; // スプリット（1〜10）、nullの場合は投げられない
  final int? changeup; // チェンジアップ（1〜10）、nullの場合は投げられない

  // 野手能力
  final int? meet; // ミート力（1〜10）
  final int? power; // 長打力（1〜10）
  final int? speed; // 走力（1〜10）、高いほど盗塁成功率UP

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
    this.slider,
    this.curve,
    this.splitter,
    this.changeup,
    this.meet,
    this.power,
    this.speed,
    this.fielding,
  });

  /// 投手かどうか
  bool get isPitcher => averageSpeed != null;

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

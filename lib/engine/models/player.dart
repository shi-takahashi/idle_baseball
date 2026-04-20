/// 選手
class Player {
  final String id;
  final String name;
  final int number; // 背番号

  // 投手能力
  final int? averageSpeed; // 平均球速（km/h）、野手はnull
  final int? control; // 制球力（1〜10）、野手はnull

  // 野手能力
  final int? meet; // ミート力（1〜10）

  const Player({
    required this.id,
    required this.name,
    required this.number,
    this.averageSpeed,
    this.control,
    this.meet,
  });

  /// 投手かどうか
  bool get isPitcher => averageSpeed != null;

  @override
  String toString() => '$name (#$number)';
}

/// 選手
class Player {
  final String id;
  final String name;
  final int number; // 背番号

  // 投手能力
  final int? averageSpeed; // 平均球速（km/h）、野手はnull

  const Player({
    required this.id,
    required this.name,
    required this.number,
    this.averageSpeed,
  });

  /// 投手かどうか
  bool get isPitcher => averageSpeed != null;

  @override
  String toString() => '$name (#$number)';
}

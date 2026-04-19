/// 選手
class Player {
  final String id;
  final String name;
  final int number; // 背番号

  const Player({
    required this.id,
    required this.name,
    required this.number,
  });

  @override
  String toString() => '$name (#$number)';
}

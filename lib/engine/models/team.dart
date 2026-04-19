import 'player.dart';

/// チーム
class Team {
  final String id;
  final String name;
  final List<Player> players; // 9人

  const Team({
    required this.id,
    required this.name,
    required this.players,
  });

  /// 打順からプレイヤーを取得（0-indexed）
  Player getBatter(int battingOrder) {
    return players[battingOrder % 9];
  }

  /// 投手（Phase 1aでは最初の選手が投げ続ける想定だが、別途指定できるように）
  Player get pitcher => players[0];

  @override
  String toString() => name;
}

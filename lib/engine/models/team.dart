import 'player.dart';
import 'enums.dart';

/// チーム
class Team {
  final String id;
  final String name;
  final List<Player> players; // 9人（先発メンバー、players[0]は先発投手）

  // 控え投手（救援投手）
  // 先発投手はplayers[0]として扱い、ここには含めない
  final List<Player> bullpen;

  // 控え野手（代打・代走・守備固め要員）
  // スタメンはplayers[0..8]として扱い、ここには含めない
  final List<Player> bench;

  // 守備配置（FieldPosition -> Player）
  // 誰がどのポジションを守っているか
  // null の場合はデフォルト配置を使用
  final Map<FieldPosition, Player>? defenseAlignment;

  const Team({
    required this.id,
    required this.name,
    required this.players,
    this.bullpen = const [],
    this.bench = const [],
    this.defenseAlignment,
  });

  /// 打順からプレイヤーを取得（0-indexed）
  Player getBatter(int battingOrder) {
    return players[battingOrder % 9];
  }

  /// 先発投手
  Player get pitcher => players[0];

  /// 指定ポジションの守備を担当する選手を取得
  /// defenseAlignment が設定されていない場合はデフォルト配置を使用
  Player? getFielder(FieldPosition position) {
    // 明示的な守備配置がある場合はそれを使用
    if (defenseAlignment != null) {
      return defenseAlignment![position];
    }

    // デフォルト配置（打順でポジションを割り当て）
    // 0: 投手, 1: 捕手, 2: 一塁, 3: 二塁, 4: 三塁, 5: 遊撃, 6: 左翼, 7: 中堅, 8: 右翼
    switch (position) {
      case FieldPosition.pitcher:
        return players[0];
      case FieldPosition.catcher:
        return players[1];
      case FieldPosition.first:
        return players[2];
      case FieldPosition.second:
        return players[3];
      case FieldPosition.third:
        return players[4];
      case FieldPosition.shortstop:
        return players[5];
      case FieldPosition.left:
        return players[6];
      case FieldPosition.center:
        return players[7];
      case FieldPosition.right:
        return players[8];
    }
  }

  /// 指定ポジションの守備力を取得
  /// 守備者がいない場合や投手方向の場合は null
  int? getFieldingAt(FieldPosition fieldPosition) {
    final defensePos = fieldPosition.defensePosition;
    if (defensePos == null) return null; // 投手方向

    final fielder = getFielder(fieldPosition);
    if (fielder == null) return null;

    return fielder.getFielding(defensePos);
  }

  @override
  String toString() => name;
}

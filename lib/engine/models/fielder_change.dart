import 'enums.dart';
import 'player.dart';

/// 野手交代の種類
enum FielderChangeType {
  pinchHit, // 代打
  pinchRun, // 代走（将来実装）
  defensiveReplacement, // 守備固め（将来実装）
}

extension FielderChangeTypeExtension on FielderChangeType {
  String get displayName {
    switch (this) {
      case FielderChangeType.pinchHit:
        return '代打';
      case FielderChangeType.pinchRun:
        return '代走';
      case FielderChangeType.defensiveReplacement:
        return '守備固め';
    }
  }
}

/// 守備ポジションの移動
/// 代打に伴う守備再編で、既存の野手がポジションを移動する場合に使用
class FielderPositionChange {
  final Player player;
  final FieldPosition from;
  final FieldPosition to;

  const FielderPositionChange({
    required this.player,
    required this.from,
    required this.to,
  });
}

/// 野手交代イベント
/// 代打/代走/守備固めを一つのモデルで表現する
class FielderChangeEvent {
  final FielderChangeType type;
  final int inning;
  final bool isTop;
  final int atBatIndex; // この打席の前に発生

  // メインの交代
  final Player outgoing; // 退く選手
  final Player incoming; // 入る選手
  final int battingOrder; // 打順（0-8）

  // 守備再編（代打後の守備配置変更）
  // incomingが本来のポジションを守れない場合に発生するスワップなど
  final FieldPosition?
      incomingNewPosition; // incomingが次の守備で守るポジション（nullは守備に付かない特殊ケース）
  final List<FielderPositionChange> otherMoves; // 既存野手のポジション移動

  final String reason;

  const FielderChangeEvent({
    required this.type,
    required this.inning,
    required this.isTop,
    required this.atBatIndex,
    required this.outgoing,
    required this.incoming,
    required this.battingOrder,
    this.incomingNewPosition,
    this.otherMoves = const [],
    required this.reason,
  });

  /// 守備再編が発生したかどうか（incomingが元の位置とは異なるポジションに入った場合など）
  bool get hasDefensiveReshuffle => otherMoves.isNotEmpty;

  @override
  String toString() =>
      '$inning回${isTop ? "表" : "裏"} ${type.displayName}: ${outgoing.name} → ${incoming.name}';
}

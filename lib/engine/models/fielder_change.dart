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

/// 野手交代イベント（攻撃面のみ）
/// 代打/代走/守備固めの「誰と誰が入れ替わったか」だけを記録する
/// 守備位置の変更は DefensiveChange で別途記録される（守備ハーフ開始時に確定）
class FielderChangeEvent {
  final FielderChangeType type;
  final int inning;
  final bool isTop;
  final int atBatIndex; // この打席の前に発生

  final Player outgoing; // 退く選手
  final Player incoming; // 入る選手
  final int battingOrder; // 打順（0-8）

  final String reason;

  const FielderChangeEvent({
    required this.type,
    required this.inning,
    required this.isTop,
    required this.atBatIndex,
    required this.outgoing,
    required this.incoming,
    required this.battingOrder,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'inning': inning,
        'isTop': isTop,
        'atBatIndex': atBatIndex,
        'outgoing': outgoing.id,
        'incoming': incoming.id,
        'battingOrder': battingOrder,
        'reason': reason,
      };

  factory FielderChangeEvent.fromJson(
    Map<String, dynamic> json,
    Map<String, Player> playerById,
  ) =>
      FielderChangeEvent(
        type: FielderChangeType.values
            .firstWhere((t) => t.name == json['type']),
        inning: json['inning'] as int,
        isTop: json['isTop'] as bool,
        atBatIndex: json['atBatIndex'] as int,
        outgoing: playerById[json['outgoing']]!,
        incoming: playerById[json['incoming']]!,
        battingOrder: json['battingOrder'] as int,
        reason: json['reason'] as String,
      );

  @override
  String toString() =>
      '$inning回${isTop ? "表" : "裏"} ${type.displayName}: ${outgoing.name} → ${incoming.name}';
}

/// 守備配置の変更
/// 守備ハーフイニングの開始時に確定する
/// - 新しくフィールドに入った選手（代打・代走からの繰り上げ）
/// - ポジション移動（既存選手が別の位置へ）
class DefensiveChange {
  final Player player;

  /// 移動前のポジション（nullは試合に初めて出場する選手）
  final FieldPosition? fromPosition;

  /// 移動後のポジション
  final FieldPosition toPosition;

  const DefensiveChange({
    required this.player,
    required this.fromPosition,
    required this.toPosition,
  });

  /// ベンチから新規出場したかどうか
  bool get isNewOnField => fromPosition == null;

  Map<String, dynamic> toJson() => {
        'player': player.id,
        if (fromPosition != null) 'fromPosition': fromPosition!.name,
        'toPosition': toPosition.name,
      };

  factory DefensiveChange.fromJson(
    Map<String, dynamic> json,
    Map<String, Player> playerById,
  ) =>
      DefensiveChange(
        player: playerById[json['player']]!,
        fromPosition: json['fromPosition'] == null
            ? null
            : FieldPosition.values
                .firstWhere((p) => p.name == json['fromPosition']),
        toPosition: FieldPosition.values
            .firstWhere((p) => p.name == json['toPosition']),
      );

  @override
  String toString() {
    if (fromPosition == null) {
      return '${player.name} → ${toPosition.displayName}';
    }
    return '${player.name} ${fromPosition!.displayName} → ${toPosition.displayName}';
  }
}

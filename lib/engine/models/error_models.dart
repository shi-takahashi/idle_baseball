import 'enums.dart';

/// バッテリーエラー（ワイルドピッチ/パスボール）の種類
enum BatteryErrorType {
  wildPitch,   // 暴投
  passedBall,  // 捕逸
}

extension BatteryErrorTypeExtension on BatteryErrorType {
  String get displayName {
    switch (this) {
      case BatteryErrorType.wildPitch:
        return '暴投';
      case BatteryErrorType.passedBall:
        return '捕逸';
    }
  }

  String get shortName {
    switch (this) {
      case BatteryErrorType.wildPitch:
        return 'WP';
      case BatteryErrorType.passedBall:
        return 'PB';
    }
  }
}

/// バッテリーエラーの結果
class BatteryError {
  final BatteryErrorType type;
  final int runsScored; // このエラーによる得点

  const BatteryError({
    required this.type,
    required this.runsScored,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'runsScored': runsScored,
      };

  factory BatteryError.fromJson(Map<String, dynamic> json) => BatteryError(
        type: BatteryErrorType.values
            .firstWhere((t) => t.name == json['type']),
        runsScored: json['runsScored'] as int,
      );

  @override
  String toString() => '$type.displayName${runsScored > 0 ? "($runsScored点)" : ""}';
}

/// フィールディングエラーの種類
enum FieldingErrorType {
  fielding,  // 捕球エラー
  throwing,  // 送球エラー
  cushion,   // クッションボール処理エラー
}

extension FieldingErrorTypeExtension on FieldingErrorType {
  String get displayName {
    switch (this) {
      case FieldingErrorType.fielding:
        return '捕球エラー';
      case FieldingErrorType.throwing:
        return '送球エラー';
      case FieldingErrorType.cushion:
        return '処理エラー';
    }
  }

  String get shortName {
    switch (this) {
      case FieldingErrorType.fielding:
        return 'E';
      case FieldingErrorType.throwing:
        return 'E送';
      case FieldingErrorType.cushion:
        return 'E処';
    }
  }
}

/// フィールディングエラー
class FieldingError {
  final FieldingErrorType type;
  final FieldPosition position; // エラーしたポジション
  final int runsScored; // このエラーによる得点

  const FieldingError({
    required this.type,
    required this.position,
    required this.runsScored,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'position': position.name,
        'runsScored': runsScored,
      };

  factory FieldingError.fromJson(Map<String, dynamic> json) => FieldingError(
        type: FieldingErrorType.values
            .firstWhere((t) => t.name == json['type']),
        position: FieldPosition.values
            .firstWhere((p) => p.name == json['position']),
        runsScored: json['runsScored'] as int,
      );

  @override
  String toString() => '${position.shortName}${type.shortName}${runsScored > 0 ? "($runsScored点)" : ""}';
}

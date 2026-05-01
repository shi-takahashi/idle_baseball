import 'base_runners.dart';
import 'enums.dart';
import 'error_models.dart';
import 'player.dart';

/// 1球の結果
class PitchResult {
  final PitchResultType type;
  final PitchType pitchType; // 球種
  final BattedBallType? battedBallType; // インプレー時のみ
  final FieldPosition? fieldPosition; // インプレー時の打球方向
  final int speed; // 球速（km/h）
  final List<StealAttempt>? steals; // 盗塁の試み（ダブルスチール対応）
  final BatteryError? batteryError; // バッテリーエラー（ワイルドピッチ/パスボール）

  const PitchResult({
    required this.type,
    required this.pitchType,
    this.battedBallType,
    this.fieldPosition,
    required this.speed,
    this.steals,
    this.batteryError,
  });

  /// 盗塁があったかどうか
  bool get hasSteal => steals != null && steals!.isNotEmpty;

  /// 盗塁失敗があったかどうか
  bool get hasFailedSteal => steals?.any((s) => !s.success) ?? false;

  /// バッテリーエラーがあったかどうか
  bool get hasBatteryError => batteryError != null;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'pitchType': pitchType.name,
        if (battedBallType != null) 'battedBallType': battedBallType!.name,
        if (fieldPosition != null) 'fieldPosition': fieldPosition!.name,
        'speed': speed,
        if (steals != null) 'steals': [for (final s in steals!) s.toJson()],
        if (batteryError != null) 'batteryError': batteryError!.toJson(),
      };

  factory PitchResult.fromJson(
    Map<String, dynamic> json,
    Map<String, Player> playerById,
  ) =>
      PitchResult(
        type: PitchResultType.values
            .firstWhere((t) => t.name == json['type']),
        pitchType: PitchType.values
            .firstWhere((p) => p.name == json['pitchType']),
        battedBallType: json['battedBallType'] == null
            ? null
            : BattedBallType.values
                .firstWhere((b) => b.name == json['battedBallType']),
        fieldPosition: json['fieldPosition'] == null
            ? null
            : FieldPosition.values
                .firstWhere((f) => f.name == json['fieldPosition']),
        speed: json['speed'] as int,
        steals: json['steals'] == null
            ? null
            : [
                for (final s in (json['steals'] as List))
                  StealAttempt.fromJson(
                      s as Map<String, dynamic>, playerById),
              ],
        batteryError: json['batteryError'] == null
            ? null
            : BatteryError.fromJson(
                json['batteryError'] as Map<String, dynamic>),
      );
}

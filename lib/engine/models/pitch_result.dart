import 'base_runners.dart';
import 'enums.dart';
import 'error_models.dart';

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
}

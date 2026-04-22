import 'base_runners.dart';
import 'enums.dart';
import 'error_models.dart';
import 'pitch_result.dart';
import 'player.dart';

/// 1打席の結果
class AtBatResult {
  final Player batter;
  final Player pitcher;
  final int inning;
  final bool isTop; // 表かどうか
  final List<PitchResult> pitches; // 全投球
  final AtBatResultType result;
  final FieldPosition? fieldPosition; // 打球方向（インプレー時のみ）
  final int rbiCount; // 打点
  final int outsBefore; // 打席前のアウトカウント
  final BaseRunners runnersBefore; // 打席前のランナー状況
  final List<TagUpAttempt>? tagUps; // タッチアップの試み
  final FieldingError? fieldingError; // フィールディングエラー

  const AtBatResult({
    required this.batter,
    required this.pitcher,
    required this.inning,
    required this.isTop,
    required this.pitches,
    required this.result,
    this.fieldPosition,
    required this.rbiCount,
    required this.outsBefore,
    required this.runnersBefore,
    this.tagUps,
    this.fieldingError,
  });

  /// 球数
  int get pitchCount => pitches.length;

  /// タッチアップがあったかどうか
  bool get hasTagUp => tagUps != null && tagUps!.isNotEmpty;

  /// フィールディングエラーがあったかどうか
  bool get hasFieldingError => fieldingError != null;

  /// タッチアップ失敗があったかどうか
  bool get hasFailedTagUp => tagUps?.any((t) => !t.success) ?? false;
}

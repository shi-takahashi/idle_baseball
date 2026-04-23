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

  /// 打席が未完了で終了したかどうか
  /// true: 打席の途中で盗塁死によってイニングが終了（resultはダミー）
  /// 用途: batting統計では打席として数えない。pitching統計では投球数・盗塁死のみ計上
  final bool isIncomplete;

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
    this.isIncomplete = false,
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

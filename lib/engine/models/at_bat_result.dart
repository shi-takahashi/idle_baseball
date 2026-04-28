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

  /// この打席で記録された失点を投手別に分配したもの（pitcher.id → 失点数）
  /// インヘリット走者（前任投手が出した走者）が生還した場合、その失点は前任投手に
  /// 計上される。打席で生還した走者の責任投手を追跡して算出する。
  final Map<String, int> runsByPitcher;

  /// この打席で記録された自責点を投手別に分配したもの（pitcher.id → 自責点数）
  /// 不自責のケース:
  ///   - 走者がエラー出塁で塁に出たまま生還
  ///   - エラーがなければイニングが終わっていた状態以降の得点
  ///   - パスボールで生還した（ワイルドピッチは自責）
  final Map<String, int> earnedRunsByPitcher;

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
    this.runsByPitcher = const {},
    this.earnedRunsByPitcher = const {},
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

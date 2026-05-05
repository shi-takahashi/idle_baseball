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

  /// この打席で本塁を踏んだ選手（個人「得点」集計に使用）。
  /// 含まれるもの:
  ///   - 走塁による生還（_processTagUp / _advanceOn... の scoringRunners）
  ///   - 本塁打を打った打者自身
  ///   - ワイルドピッチ・パスボールで生還した走者（batteryErrorScorers）
  final List<Player> scoringRunners;

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
    this.scoringRunners = const [],
  });

  /// 球数
  int get pitchCount => pitches.length;

  /// タッチアップがあったかどうか
  bool get hasTagUp => tagUps != null && tagUps!.isNotEmpty;

  /// フィールディングエラーがあったかどうか
  bool get hasFieldingError => fieldingError != null;

  /// タッチアップ失敗があったかどうか
  bool get hasFailedTagUp => tagUps?.any((t) => !t.success) ?? false;

  Map<String, dynamic> toJson() => {
        'batter': batter.id,
        'pitcher': pitcher.id,
        'inning': inning,
        'isTop': isTop,
        'pitches': [for (final p in pitches) p.toJson()],
        'result': result.name,
        if (fieldPosition != null) 'fieldPosition': fieldPosition!.name,
        'rbiCount': rbiCount,
        'outsBefore': outsBefore,
        'runnersBefore': runnersBefore.toJson(),
        if (tagUps != null) 'tagUps': [for (final t in tagUps!) t.toJson()],
        if (fieldingError != null) 'fieldingError': fieldingError!.toJson(),
        'isIncomplete': isIncomplete,
        if (runsByPitcher.isNotEmpty) 'runsByPitcher': runsByPitcher,
        if (earnedRunsByPitcher.isNotEmpty)
          'earnedRunsByPitcher': earnedRunsByPitcher,
        if (scoringRunners.isNotEmpty)
          'scoringRunners': [for (final p in scoringRunners) p.id],
      };

  factory AtBatResult.fromJson(
    Map<String, dynamic> json,
    Map<String, Player> playerById,
  ) =>
      AtBatResult(
        batter: playerById[json['batter']]!,
        pitcher: playerById[json['pitcher']]!,
        inning: json['inning'] as int,
        isTop: json['isTop'] as bool,
        pitches: [
          for (final p in (json['pitches'] as List))
            PitchResult.fromJson(p as Map<String, dynamic>, playerById),
        ],
        result: AtBatResultType.values
            .firstWhere((r) => r.name == json['result']),
        fieldPosition: json['fieldPosition'] == null
            ? null
            : FieldPosition.values
                .firstWhere((p) => p.name == json['fieldPosition']),
        rbiCount: json['rbiCount'] as int,
        outsBefore: json['outsBefore'] as int,
        runnersBefore: BaseRunners.fromJson(
            json['runnersBefore'] as Map<String, dynamic>, playerById),
        tagUps: json['tagUps'] == null
            ? null
            : [
                for (final t in (json['tagUps'] as List))
                  TagUpAttempt.fromJson(
                      t as Map<String, dynamic>, playerById),
              ],
        fieldingError: json['fieldingError'] == null
            ? null
            : FieldingError.fromJson(
                json['fieldingError'] as Map<String, dynamic>),
        isIncomplete: (json['isIncomplete'] as bool?) ?? false,
        runsByPitcher: json['runsByPitcher'] == null
            ? const {}
            : Map<String, int>.from(json['runsByPitcher'] as Map),
        earnedRunsByPitcher: json['earnedRunsByPitcher'] == null
            ? const {}
            : Map<String, int>.from(json['earnedRunsByPitcher'] as Map),
        scoringRunners: json['scoringRunners'] == null
            ? const []
            : [
                for (final id in (json['scoringRunners'] as List))
                  playerById[id as String]!,
              ],
      );
}

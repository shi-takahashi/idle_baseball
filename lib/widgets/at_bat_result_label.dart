import 'package:flutter/material.dart';
import '../engine/models/at_bat_result.dart';
import '../engine/models/enums.dart';

/// 打席結果の表示名（打球方向を含む）。
///
/// 「左フライ」「遊ゴロ」「右翼安」のように、結果と打球方向を組み合わせて
/// 具体的に表示する。打球方向がない結果（三振・四球・死球・送りバント等）は
/// enum の displayName をそのまま使う。
///
/// スコアボードのイニング詳細と打撃成績タブの両方から共有して使う。
String atBatResultDisplayName(AtBatResult atBat) {
  final fieldPos = atBat.fieldPosition;

  if (fieldPos != null) {
    final posShort = fieldPos.shortName; // 「遊」「右」「中」など

    switch (atBat.result) {
      case AtBatResultType.groundOut:
        return '$posShortゴロ';
      case AtBatResultType.flyOut:
        return '$posShortフライ';
      case AtBatResultType.lineOut:
        return '$posShortライナー';
      case AtBatResultType.single:
        return '${fieldPos.displayName}安'; // 「遊撃安」「右翼安」
      case AtBatResultType.double_:
        return '${fieldPos.displayName}二';
      case AtBatResultType.triple:
        return '${fieldPos.displayName}三';
      case AtBatResultType.homeRun:
        return '本塁打';
      case AtBatResultType.reachedOnError:
        return '$posShortエラー'; // 「遊エラー」「三エラー」
      case AtBatResultType.fieldersChoice:
        // バント失敗はそのまま、三遊ゴロの3塁封殺は通常のゴロアウトと同じ表示。
        // 野選（前走者OUT・打者1塁SAFE）は走者の状況を次打者の行で確認できるため、
        // 「遊ゴロ」とだけ出して見た目を簡潔にする。
        return atBat.isBunt ? 'バント失敗' : '$posShortゴロ';
      default:
        return atBat.result.displayName;
    }
  }

  return atBat.result.displayName;
}

/// 打席結果のテキスト表示色。
///
/// 安打=緑 / 四球=青 / 死球=紫 / 失策出塁=赤 / アウト系=null（既定色のまま）。
/// アウト（三振・ゴロ・フライ・ライナー・併殺・犠打・犠飛・バント失敗）は
/// 大多数なので色を付けず、出塁系だけを色分けして見分けやすくする。
Color? atBatResultTextColor(AtBatResultType type) {
  if (type.isHit) return Colors.green.shade700;
  switch (type) {
    case AtBatResultType.walk:
      return Colors.blue.shade700;
    case AtBatResultType.hitByPitch:
      return Colors.deepPurple.shade600;
    case AtBatResultType.reachedOnError:
      return Colors.red.shade600;
    default:
      return null;
  }
}

import 'package:flutter/material.dart';
import '../engine/engine.dart';

/// 投手成績ウィジェット
class PitchingStats extends StatelessWidget {
  final GameResult gameResult;

  const PitchingStats({super.key, required this.gameResult});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTeamStats(context, gameResult.awayTeamName, true),
          const SizedBox(height: 16),
          _buildTeamStats(context, gameResult.homeTeamName, false),
        ],
      ),
    );
  }

  Widget _buildTeamStats(BuildContext context, String teamName, bool isAway) {
    // このチームの投手成績を集計
    final pitcherStats = _collectPitcherStats(isAway);

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // チーム名ヘッダー
          Container(
            padding: const EdgeInsets.all(8),
            color: isAway ? Colors.blue.shade100 : Colors.red.shade100,
            child: Text(
              teamName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          // テーブル
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 16,
              headingRowHeight: 36,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 32,
              columns: const [
                DataColumn(label: Text('選手', style: TextStyle(fontSize: 12))),
                DataColumn(label: Text('投球回', style: TextStyle(fontSize: 12))),
                DataColumn(label: Text('投球数', style: TextStyle(fontSize: 12))),
                DataColumn(label: Text('打者', style: TextStyle(fontSize: 12))),
                DataColumn(label: Text('被安打', style: TextStyle(fontSize: 12))),
                DataColumn(label: Text('被本塁打', style: TextStyle(fontSize: 12))),
                DataColumn(label: Text('奪三振', style: TextStyle(fontSize: 12))),
                DataColumn(label: Text('与四球', style: TextStyle(fontSize: 12))),
                DataColumn(label: Text('失点', style: TextStyle(fontSize: 12))),
              ],
              rows: pitcherStats.map((stat) => _buildPitcherRow(stat)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  DataRow _buildPitcherRow(_PitcherGameStats stat) {
    return DataRow(
      cells: [
        DataCell(Text(stat.playerName, style: const TextStyle(fontSize: 12))),
        DataCell(Text(stat.inningsPitchedDisplay, style: const TextStyle(fontSize: 12))),
        DataCell(Text('${stat.pitchCount}', style: const TextStyle(fontSize: 12))),
        DataCell(Text('${stat.battersFaced}', style: const TextStyle(fontSize: 12))),
        DataCell(Text('${stat.hitsAllowed}', style: const TextStyle(fontSize: 12))),
        DataCell(Text('${stat.homeRunsAllowed}', style: const TextStyle(fontSize: 12))),
        DataCell(Text('${stat.strikeouts}', style: const TextStyle(fontSize: 12))),
        DataCell(Text('${stat.walks}', style: const TextStyle(fontSize: 12))),
        DataCell(Text('${stat.runsAllowed}', style: const TextStyle(fontSize: 12))),
      ],
    );
  }

  List<_PitcherGameStats> _collectPitcherStats(bool isAway) {
    final Map<String, _PitcherGameStats> statsMap = {};

    for (final halfInning in gameResult.halfInnings) {
      // 守備側（相手チームが攻撃中）のイニングを処理
      if (halfInning.isTop != isAway) {
        for (final atBat in halfInning.atBats) {
          final playerId = atBat.pitcher.id;

          if (!statsMap.containsKey(playerId)) {
            statsMap[playerId] = _PitcherGameStats(
              playerName: atBat.pitcher.name,
            );
          }

          final stat = statsMap[playerId]!;

          // 投球数（未完了打席でもカウント）
          stat.pitchCount += atBat.pitches.length;

          // 投球中の盗塁死（未完了打席でもカウント）
          for (final pitch in atBat.pitches) {
            if (pitch.steals != null) {
              for (final steal in pitch.steals!) {
                if (steal.isOut) stat.outsRecorded++;
              }
            }
          }

          // 未完了打席（盗塁死でイニング終了）は以降の集計対象外
          if (atBat.isIncomplete) continue;

          // 打者数
          stat.battersFaced++;

          // アウトカウント（投球回計算用）
          // 打席結果によるアウト
          if (atBat.result.isOut) {
            stat.outsRecorded++;
          }
          // 併殺打は追加で1アウト（1塁ランナーもアウト）
          if (atBat.result.isDoublePlay) {
            stat.outsRecorded++;
          }
          // タッチアップ失敗による追加アウト
          if (atBat.tagUps != null) {
            for (final tagUp in atBat.tagUps!) {
              if (!tagUp.success) stat.outsRecorded++;
            }
          }

          // 被安打
          if (atBat.result.isHit) {
            stat.hitsAllowed++;
          }

          // 被本塁打
          if (atBat.result == AtBatResultType.homeRun) {
            stat.homeRunsAllowed++;
          }

          // 奪三振
          if (atBat.result == AtBatResultType.strikeout) {
            stat.strikeouts++;
          }

          // 与四球
          if (atBat.result == AtBatResultType.walk) {
            stat.walks++;
          }

          // 失点
          stat.runsAllowed += atBat.rbiCount;
        }
      }
    }

    return statsMap.values.toList();
  }
}

class _PitcherGameStats {
  final String playerName;
  int pitchCount = 0;
  int battersFaced = 0;
  int outsRecorded = 0;
  int hitsAllowed = 0;
  int homeRunsAllowed = 0;
  int strikeouts = 0;
  int walks = 0;
  int runsAllowed = 0;

  _PitcherGameStats({required this.playerName});

  /// 投球回の表示（例: 6.0, 5.1, 5.2）
  String get inningsPitchedDisplay {
    final fullInnings = outsRecorded ~/ 3;
    final remainder = outsRecorded % 3;
    return '$fullInnings.$remainder';
  }
}

import 'package:flutter/material.dart';
import '../engine/engine.dart';

/// 打撃成績ウィジェット
class BattingStats extends StatelessWidget {
  final GameResult gameResult;

  const BattingStats({super.key, required this.gameResult});

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
    // このチームの打席結果を集計
    final batterStats = _collectBatterStats(isAway);

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
              columnSpacing: 12,
              headingRowHeight: 36,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 32,
              columns: const [
                DataColumn(label: Text('選手', style: TextStyle(fontSize: 12))),
                DataColumn(label: Text('打数', style: TextStyle(fontSize: 12))),
                DataColumn(label: Text('安打', style: TextStyle(fontSize: 12))),
                DataColumn(label: Text('本塁打', style: TextStyle(fontSize: 12))),
                DataColumn(label: Text('打点', style: TextStyle(fontSize: 12))),
                DataColumn(label: Text('三振', style: TextStyle(fontSize: 12))),
                DataColumn(label: Text('四球', style: TextStyle(fontSize: 12))),
                DataColumn(label: Text('1回', style: TextStyle(fontSize: 12))),
                DataColumn(label: Text('2回', style: TextStyle(fontSize: 12))),
                DataColumn(label: Text('3回', style: TextStyle(fontSize: 12))),
                DataColumn(label: Text('4回', style: TextStyle(fontSize: 12))),
                DataColumn(label: Text('5回', style: TextStyle(fontSize: 12))),
                DataColumn(label: Text('6回', style: TextStyle(fontSize: 12))),
                DataColumn(label: Text('7回', style: TextStyle(fontSize: 12))),
                DataColumn(label: Text('8回', style: TextStyle(fontSize: 12))),
                DataColumn(label: Text('9回', style: TextStyle(fontSize: 12))),
              ],
              rows: batterStats.map((stat) => _buildBatterRow(stat)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  DataRow _buildBatterRow(_BatterGameStats stat) {
    return DataRow(
      cells: [
        DataCell(Text(stat.playerName, style: const TextStyle(fontSize: 12))),
        DataCell(Text('${stat.atBats}', style: const TextStyle(fontSize: 12))),
        DataCell(Text('${stat.hits}', style: const TextStyle(fontSize: 12))),
        DataCell(Text('${stat.homeRuns}', style: const TextStyle(fontSize: 12))),
        DataCell(Text('${stat.rbi}', style: const TextStyle(fontSize: 12))),
        DataCell(Text('${stat.strikeouts}', style: const TextStyle(fontSize: 12))),
        DataCell(Text('${stat.walks}', style: const TextStyle(fontSize: 12))),
        ...stat.inningResults.map((result) => DataCell(
              _buildResultCell(result),
            )),
      ],
    );
  }

  Widget _buildResultCell(String? result) {
    if (result == null || result.isEmpty) {
      return const Text('', style: TextStyle(fontSize: 11));
    }

    Color? textColor;
    // ヒット系は赤（三塁打は含むが三振は含まない）
    if (result.contains('安打') ||
        result.contains('本塁打') ||
        result.contains('二塁打') ||
        result.contains('三塁打')) {
      textColor = Colors.red;
    } else if (result.contains('四球')) {
      textColor = Colors.blue;
    }
    // 三振、ゴロ、飛球等はデフォルト（黒）

    return Text(
      result,
      style: TextStyle(fontSize: 11, color: textColor),
    );
  }

  List<_BatterGameStats> _collectBatterStats(bool isAway) {
    final Map<String, _BatterGameStats> statsMap = {};

    for (final halfInning in gameResult.halfInnings) {
      // 攻撃側のイニングを処理
      if (halfInning.isTop == isAway) {
        for (final atBat in halfInning.atBats) {
          final playerId = atBat.batter.id;

          if (!statsMap.containsKey(playerId)) {
            statsMap[playerId] = _BatterGameStats(
              playerName: atBat.batter.name,
            );
          }

          final stat = statsMap[playerId]!;

          // 打数（四球は含まない）
          if (atBat.result != AtBatResultType.walk) {
            stat.atBats++;
          }

          // 安打
          if (atBat.result.isHit) {
            stat.hits++;
          }

          // 本塁打
          if (atBat.result == AtBatResultType.homeRun) {
            stat.homeRuns++;
          }

          // 打点
          stat.rbi += atBat.rbiCount;

          // 三振
          if (atBat.result == AtBatResultType.strikeout) {
            stat.strikeouts++;
          }

          // 四球
          if (atBat.result == AtBatResultType.walk) {
            stat.walks++;
          }

          // イニングごとの結果
          final inningIndex = halfInning.inning - 1;
          if (inningIndex < 9) {
            final currentResult = stat.inningResults[inningIndex];
            final newResult = _getResultShortName(atBat.result);
            if (currentResult == null || currentResult.isEmpty) {
              stat.inningResults[inningIndex] = newResult;
            } else {
              stat.inningResults[inningIndex] = '$currentResult, $newResult';
            }
          }
        }
      }
    }

    return statsMap.values.toList();
  }

  String _getResultShortName(AtBatResultType result) {
    switch (result) {
      case AtBatResultType.strikeout:
        return '三振';
      case AtBatResultType.walk:
        return '四球';
      case AtBatResultType.single:
        return '安打';
      case AtBatResultType.infieldHit:
        return '内安';
      case AtBatResultType.double_:
        return '二塁打';
      case AtBatResultType.triple:
        return '三塁打';
      case AtBatResultType.homeRun:
        return '本塁打';
      case AtBatResultType.groundOut:
        return 'ゴロ';
      case AtBatResultType.doublePlay:
        return '併殺';
      case AtBatResultType.flyOut:
        return '飛球';
      case AtBatResultType.lineOut:
        return '直球';
    }
  }
}

class _BatterGameStats {
  final String playerName;
  int atBats = 0;
  int hits = 0;
  int homeRuns = 0;
  int rbi = 0;
  int strikeouts = 0;
  int walks = 0;
  List<String?> inningResults = List.filled(9, null);

  _BatterGameStats({required this.playerName});
}

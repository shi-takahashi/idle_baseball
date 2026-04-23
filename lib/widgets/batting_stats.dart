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
          _buildTeamStats(context, gameResult.awayTeam, true),
          const SizedBox(height: 16),
          _buildTeamStats(context, gameResult.homeTeam, false),
        ],
      ),
    );
  }

  Widget _buildTeamStats(BuildContext context, Team team, bool isAway) {
    final rows = _computeRows(team, isAway);

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // チーム名ヘッダー
          Container(
            padding: const EdgeInsets.all(8),
            color: isAway ? Colors.blue.shade100 : Colors.red.shade100,
            child: Text(
              team.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 10,
              headingRowHeight: 32,
              dataRowMinHeight: 28,
              dataRowMaxHeight: 28,
              columns: const [
                DataColumn(label: Text('位置', style: TextStyle(fontSize: 11))),
                DataColumn(label: Text('選手', style: TextStyle(fontSize: 11))),
                DataColumn(label: Text('打数', style: TextStyle(fontSize: 11))),
                DataColumn(label: Text('安打', style: TextStyle(fontSize: 11))),
                DataColumn(label: Text('本塁打', style: TextStyle(fontSize: 11))),
                DataColumn(label: Text('打点', style: TextStyle(fontSize: 11))),
                DataColumn(label: Text('三振', style: TextStyle(fontSize: 11))),
                DataColumn(label: Text('四球', style: TextStyle(fontSize: 11))),
                DataColumn(label: Text('1回', style: TextStyle(fontSize: 11))),
                DataColumn(label: Text('2回', style: TextStyle(fontSize: 11))),
                DataColumn(label: Text('3回', style: TextStyle(fontSize: 11))),
                DataColumn(label: Text('4回', style: TextStyle(fontSize: 11))),
                DataColumn(label: Text('5回', style: TextStyle(fontSize: 11))),
                DataColumn(label: Text('6回', style: TextStyle(fontSize: 11))),
                DataColumn(label: Text('7回', style: TextStyle(fontSize: 11))),
                DataColumn(label: Text('8回', style: TextStyle(fontSize: 11))),
                DataColumn(label: Text('9回', style: TextStyle(fontSize: 11))),
              ],
              rows: rows.map(_buildRow).toList(),
            ),
          ),
        ],
      ),
    );
  }

  DataRow _buildRow(_BatterRow row) {
    final stat = row.stats;
    // 位置表示: 履歴を「、」で連結。「(一)」「(一、遊)」など
    final posText = row.positions.isEmpty
        ? ''
        : '(${row.positions.map((p) => p.shortName).join('、')})';
    // 代替選手は位置の前にスペースを入れてインデント
    final posLabel = row.isStarter ? posText : '  $posText';
    // 代替選手は名前の前に小さな種類ラベル（「代打」など）
    final subTypeLabel = row.subType?.displayName;

    final nameStyle = TextStyle(
      fontSize: 11,
      color: row.isStarter ? null : Colors.grey.shade700,
    );

    return DataRow(
      cells: [
        DataCell(Text(posLabel, style: nameStyle)),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!row.isStarter) const SizedBox(width: 12),
              if (subTypeLabel != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.lightBlue.shade100,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    subTypeLabel,
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.lightBlue.shade900,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Text(row.player.name, style: nameStyle),
            ],
          ),
        ),
        DataCell(Text('${stat.atBats}', style: nameStyle)),
        DataCell(Text('${stat.hits}', style: nameStyle)),
        DataCell(Text('${stat.homeRuns}', style: nameStyle)),
        DataCell(Text('${stat.rbi}', style: nameStyle)),
        DataCell(Text('${stat.strikeouts}', style: nameStyle)),
        DataCell(Text('${stat.walks}', style: nameStyle)),
        ...List.generate(9,
            (i) => DataCell(_buildResultCell(stat.inningResults[i], nameStyle))),
      ],
    );
  }

  Widget _buildResultCell(String? result, TextStyle baseStyle) {
    if (result == null || result.isEmpty) {
      return Text('', style: baseStyle);
    }

    Color? textColor;
    if (result.contains('安打') ||
        result.contains('本塁打') ||
        result.contains('二塁打') ||
        result.contains('三塁打')) {
      textColor = Colors.red;
    } else if (result.contains('四球')) {
      textColor = Colors.blue;
    }

    return Text(
      result,
      style: baseStyle.copyWith(color: textColor ?? baseStyle.color),
    );
  }

  /// 打者行の一覧を構築する
  /// 打順スロット(0-8)ごとに先発→代替選手の順で並べる
  /// 各選手の守備位置は「試合中に守った全てのポジションを順番に」表示
  /// 例: 「(一、遊)」= 最初は一塁、途中から遊撃を守った
  List<_BatterRow> _computeRows(Team team, bool isAway) {
    // このチームの野手交代イベント
    final events = <FielderChangeEvent>[];
    for (final h in gameResult.halfInnings) {
      if (h.isTop == isAway) {
        events.addAll(h.fielderChanges);
      }
    }

    // 試合開始時の守備位置
    final initialPositions = <String, FieldPosition>{};
    for (final pos in FieldPosition.values) {
      final p = team.getFielder(pos);
      if (p != null) initialPositions[p.id] = pos;
    }

    // 各選手の守備位置履歴（同じポジションは重複させない）
    final positionHistory = <String, List<FieldPosition>>{};
    for (final entry in initialPositions.entries) {
      positionHistory[entry.key] = [entry.value];
    }

    void appendPosition(String playerId, FieldPosition pos) {
      final history = positionHistory.putIfAbsent(playerId, () => []);
      if (history.isEmpty || history.last != pos) {
        history.add(pos);
      }
    }

    // イベントを順番に適用
    for (final event in events) {
      // incoming は新しい位置に入る（履歴の先頭になる）
      if (event.incomingNewPosition != null) {
        appendPosition(event.incoming.id, event.incomingNewPosition!);
      }
      // 既存野手のポジション移動
      for (final m in event.otherMoves) {
        appendPosition(m.player.id, m.to);
      }
      // outgoing は退場。履歴はそのまま固定（追加なし）
    }

    // 打順スロットごとに選手の並びを構築
    final rows = <_BatterRow>[];
    for (int slot = 0; slot < 9; slot++) {
      final starter = team.players[slot];
      rows.add(_BatterRow(
        battingOrder: slot,
        player: starter,
        positions: positionHistory[starter.id] ?? const [],
        isStarter: true,
        subType: null,
        stats: _BatterGameStats(),
      ));

      // このスロットで発生した交代を発生順に追加
      for (final event in events.where((e) => e.battingOrder == slot)) {
        rows.add(_BatterRow(
          battingOrder: slot,
          player: event.incoming,
          positions: positionHistory[event.incoming.id] ?? const [],
          isStarter: false,
          subType: event.type,
          stats: _BatterGameStats(),
        ));
      }
    }

    // 各行のstatsを打席結果から集計
    for (final row in rows) {
      for (final halfInning in gameResult.halfInnings) {
        if (halfInning.isTop != isAway) continue;
        for (final atBat in halfInning.atBats) {
          if (atBat.isIncomplete) continue;
          if (atBat.batter.id != row.player.id) continue;
          _accumulate(row.stats, atBat, halfInning.inning);
        }
      }
    }

    return rows;
  }

  void _accumulate(_BatterGameStats stat, AtBatResult atBat, int inning) {
    if (atBat.result != AtBatResultType.walk) stat.atBats++;
    if (atBat.result.isHit) stat.hits++;
    if (atBat.result == AtBatResultType.homeRun) stat.homeRuns++;
    stat.rbi += atBat.rbiCount;
    if (atBat.result == AtBatResultType.strikeout) stat.strikeouts++;
    if (atBat.result == AtBatResultType.walk) stat.walks++;

    final inningIndex = inning - 1;
    if (inningIndex >= 0 && inningIndex < 9) {
      final current = stat.inningResults[inningIndex];
      final newResult = _resultShortName(atBat.result);
      stat.inningResults[inningIndex] =
          (current == null || current.isEmpty) ? newResult : '$current, $newResult';
    }
  }

  String _resultShortName(AtBatResultType result) {
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
      case AtBatResultType.reachedOnError:
        return 'エラー';
    }
  }
}

/// 1人の打者の試合成績（1つの出場分）
class _BatterGameStats {
  int atBats = 0;
  int hits = 0;
  int homeRuns = 0;
  int rbi = 0;
  int strikeouts = 0;
  int walks = 0;
  List<String?> inningResults = List.filled(9, null);
}

/// 打撃成績の1行分のデータ
class _BatterRow {
  final int battingOrder; // 0-8
  final Player player;
  // この選手が試合中に守ったポジション履歴（順番に、重複なし）
  // 例: [first, shortstop] = 最初は一塁、途中から遊撃を守った
  final List<FieldPosition> positions;
  final bool isStarter;
  final FielderChangeType? subType; // starterの場合はnull
  final _BatterGameStats stats;

  _BatterRow({
    required this.battingOrder,
    required this.player,
    required this.positions,
    required this.isStarter,
    required this.subType,
    required this.stats,
  });
}

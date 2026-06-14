import 'package:flutter/material.dart';
import '../engine/engine.dart';
import 'at_bat_result_label.dart';

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
    final inningCount = gameResult.inningScores.length;
    final rows = _computeRows(team, isAway, inningCount);

    // チームカラーをパステルにしてバナー背景に使う（テキストは黒で読みやすく保つ）
    final primary = Color(team.primaryColorValue);
    final bannerBg = Color.lerp(Colors.white, primary, 0.25)!;
    final accentText = Color.lerp(Colors.black, primary, 0.7)!;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // チーム名ヘッダー（チームカラーのパステル背景）
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bannerBg,
              border: Border(left: BorderSide(color: primary, width: 4)),
            ),
            child: Text(
              team.name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: accentText,
              ),
            ),
          ),
          // 左：選手列（固定） / 右：位置〜イニング別（横スクロール）
          // 行ごとに高さを固定して左右テーブルの行を揃える
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPlayerColumn(rows),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _buildStatsTable(rows, inningCount),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 左固定の「選手」列。行高は右側のテーブルと揃えるため固定値を使う。
  Widget _buildPlayerColumn(List<_BatterRow> rows) {
    return DataTable(
      columnSpacing: 10,
      horizontalMargin: 8,
      headingRowHeight: 32,
      dataRowMinHeight: 28,
      dataRowMaxHeight: 28,
      columns: const [
        DataColumn(label: Text('選手', style: TextStyle(fontSize: 11))),
      ],
      rows: rows.map((r) => DataRow(cells: [DataCell(_buildPlayerCell(r))])).toList(),
    );
  }

  /// 右側の横スクロールテーブル。位置〜イニング別の全列をまとめる。
  Widget _buildStatsTable(List<_BatterRow> rows, int inningCount) {
    return DataTable(
      columnSpacing: 10,
      horizontalMargin: 8,
      headingRowHeight: 32,
      dataRowMinHeight: 28,
      dataRowMaxHeight: 28,
      columns: [
        const DataColumn(label: Text('位置', style: TextStyle(fontSize: 11))),
        const DataColumn(label: Text('打数', style: TextStyle(fontSize: 11))),
        const DataColumn(label: Text('安打', style: TextStyle(fontSize: 11))),
        const DataColumn(label: Text('本塁打', style: TextStyle(fontSize: 11))),
        const DataColumn(label: Text('打点', style: TextStyle(fontSize: 11))),
        const DataColumn(label: Text('三振', style: TextStyle(fontSize: 11))),
        const DataColumn(label: Text('四球', style: TextStyle(fontSize: 11))),
        const DataColumn(label: Text('犠打', style: TextStyle(fontSize: 11))),
        for (int i = 1; i <= inningCount; i++)
          DataColumn(label: Text('$i回', style: const TextStyle(fontSize: 11))),
      ],
      rows: rows.map((r) => _buildStatsRow(r, inningCount)).toList(),
    );
  }

  /// 選手列のセル（代替選手のインデント・種類バッジ含む）
  Widget _buildPlayerCell(_BatterRow row) {
    // 代替選手は名前の前に小さな種類ラベル
    // - 守備交代の新規出場: 「守備」（代打が守備につかず引き継いだ選手）
    // - その他 subType あり: 代打/代走を表示
    // - subType なしで starter でない: 投手交代（DH非採用）で入った投手
    String? subTypeLabel;
    if (row.subType == FielderChangeType.defensiveReplacement) {
      subTypeLabel = '守備';
    } else if (row.subType != null) {
      subTypeLabel = row.subType!.displayName;
    } else if (!row.isStarter) {
      subTypeLabel = '投手';
    }

    final nameStyle = TextStyle(
      fontSize: 11,
      color: row.isStarter ? null : Colors.grey.shade700,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!row.isStarter) const SizedBox(width: 12),
        if (subTypeLabel != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
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
    );
  }

  /// 右テーブルの1行分（位置〜イニング別）
  DataRow _buildStatsRow(_BatterRow row, int inningCount) {
    final stat = row.stats;
    // 位置表示: 履歴を「、」で連結。「(一)」「(一、遊)」など。
    // DH（守備に就かない打者）は守備位置の代わりに「(DH)」を表示する。
    final posText = row.isDH
        ? '(DH)'
        : row.positions.isEmpty
            ? ''
            : '(${row.positions.map((p) => p.shortName).join('、')})';

    final nameStyle = TextStyle(
      fontSize: 11,
      color: row.isStarter ? null : Colors.grey.shade700,
    );

    return DataRow(
      cells: [
        DataCell(Text(posText, style: nameStyle)),
        DataCell(Text('${stat.atBats}', style: nameStyle)),
        DataCell(Text('${stat.hits}', style: nameStyle)),
        DataCell(Text('${stat.homeRuns}', style: nameStyle)),
        DataCell(Text('${stat.rbi}', style: nameStyle)),
        DataCell(Text('${stat.strikeouts}', style: nameStyle)),
        DataCell(Text('${stat.walks}', style: nameStyle)),
        DataCell(Text('${stat.sacrifices}', style: nameStyle)),
        ...List.generate(inningCount,
            (i) => DataCell(_buildResultCell(stat.inningResults[i], nameStyle))),
      ],
    );
  }

  Widget _buildResultCell(List<_InningEntry> entries, TextStyle baseStyle) {
    if (entries.isEmpty) {
      return Text('', style: baseStyle);
    }

    // 同一イニングに複数打席ある場合は「, 」区切り。打席ごとに色分けする
    // （安打=緑 / 四球=青 / 死球=紫 / 失策出塁=赤 / アウト=既定色）。
    final spans = <TextSpan>[];
    for (int i = 0; i < entries.length; i++) {
      if (i > 0) {
        spans.add(TextSpan(text: ', ', style: baseStyle));
      }
      final color = atBatResultTextColor(entries[i].type);
      spans.add(TextSpan(
        text: entries[i].label,
        style: baseStyle.copyWith(color: color ?? baseStyle.color),
      ));
    }
    return Text.rich(TextSpan(children: spans));
  }

  /// 打者行の一覧を構築する
  /// 打順スロット(0-8)ごとに先発→代替選手の順で並べる
  /// 各選手の守備位置は「そのチームが守備側だったハーフイニングで実際についた位置」だけを履歴に残す
  /// → 代打→代走のように、割り当てられた守備位置に一度もつかずに退場した選手は履歴が空になる
  /// 例: 「(一、遊)」= 最初は一塁、途中から遊撃を守った
  List<_BatterRow> _computeRows(Team team, bool isAway, int inningCount) {
    // 現在の守備配置（選手ID → ポジション）
    final playerPos = <String, FieldPosition>{};
    for (final pos in FieldPosition.values) {
      final p = team.getFielder(pos);
      if (p != null) playerPos[p.id] = pos;
    }

    // DH 制の試合（投手が打順に居ない）では、打順に居て守備配置に居ない選手が DH。
    // その打順スロットは守備位置を持たないので、表示は「(DH)」にする。
    int dhSlot = -1;
    if (team.pitcherBattingIndex < 0) {
      for (int i = 0; i < team.players.length && i < 9; i++) {
        if (!playerPos.containsKey(team.players[i].id)) {
          dhSlot = i;
          break;
        }
      }
    }

    // 各選手の守備位置履歴（同じポジションは重複させない）
    final positionHistory = <String, List<FieldPosition>>{};
    void snapshot() {
      // 現在の playerPos の全員分をそれぞれの履歴に追加
      // 直前と同じポジションなら重複させない
      for (final entry in playerPos.entries) {
        final history = positionHistory.putIfAbsent(entry.key, () => []);
        if (history.isEmpty || history.last != entry.value) {
          history.add(entry.value);
        }
      }
    }

    // このチームのスロット交代を発生順に収集（表示の並び順用）
    // 代打・代走（攻撃ハーフ）、投手交代・守備交代（守備ハーフ）をすべて含める
    final subs = <_SlotSub>[];

    // 既に行として把握済みの選手 ID（先発 + 交代で入った選手）。
    // 守備交代の新規出場者を二重に追加しないために使う。
    final knownIds = <String>{for (final p in team.players.take(9)) p.id};

    // ハーフイニングを順番に進めながら、守備半ではスナップショット、攻撃半では退場処理
    for (final halfInning in gameResult.halfInnings) {
      if (halfInning.isTop != isAway) {
        // このチームが守備側のハーフ
        // 1. ハーフ開始時の守備配置変更（前の攻撃ハーフの結果）を適用
        for (final change in halfInning.defensiveChangesAtStart) {
          playerPos[change.player.id] = change.toPosition;
        }
        // 2. ハーフ冒頭の状態をスナップショット
        snapshot();
        // 3. 代打などが守備につかず、ベンチから別選手がその打順スロットを
        //    引き継いで守備についたケースを打者行として拾う。
        //    （代打本人が守備につく場合は knownIds 済みなのでここでは追加しない）
        for (final change in halfInning.defensiveChangesAtStart) {
          if (!change.isNewOnField) continue;
          if (change.battingOrder == null) continue;
          if (knownIds.contains(change.player.id)) continue;
          knownIds.add(change.player.id);
          subs.add(_SlotSub(
            battingOrder: change.battingOrder!,
            outgoing: null,
            incoming: change.player,
            fielderType: FielderChangeType.defensiveReplacement,
          ));
        }
        // 4. このハーフで発生した投手交代を適用＆スナップショット
        for (final pc in halfInning.pitcherChanges) {
          playerPos.remove(pc.oldPitcher.id);
          playerPos[pc.newPitcher.id] = FieldPosition.pitcher;
          snapshot();
          knownIds.add(pc.newPitcher.id);
          subs.add(_SlotSub(
            battingOrder: pc.battingOrder,
            outgoing: pc.oldPitcher,
            incoming: pc.newPitcher,
            fielderType: null, // 投手交代
          ));
        }
      } else {
        // このチームが攻撃側のハーフ
        // 代打・代走で退場した選手を playerPos から除外（履歴に残さないため）
        for (final event in halfInning.fielderChanges) {
          playerPos.remove(event.outgoing.id);
          knownIds.add(event.incoming.id);
          subs.add(_SlotSub(
            battingOrder: event.battingOrder,
            outgoing: event.outgoing,
            incoming: event.incoming,
            fielderType: event.type,
          ));
        }
      }
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
        isDH: slot == dhSlot,
        stats: _BatterGameStats(inningCount),
      ));

      // このスロットで発生した交代を発生順に追加
      for (final sub in subs.where((s) => s.battingOrder == slot)) {
        rows.add(_BatterRow(
          battingOrder: slot,
          player: sub.incoming,
          positions: positionHistory[sub.incoming.id] ?? const [],
          isStarter: false,
          subType: sub.fielderType,
          // DH スロットを引き継いだ代打・代走も守備に就かないので DH 扱い。
          isDH: slot == dhSlot,
          stats: _BatterGameStats(inningCount),
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
    final isWalk = atBat.result == AtBatResultType.walk;
    final isHbp = atBat.result == AtBatResultType.hitByPitch;
    final isSacFly = atBat.result == AtBatResultType.sacrificeFly;
    final isSacBunt = atBat.result == AtBatResultType.sacrificeBunt;
    // 打数: 打席 - 四球 - 死球 - 犠飛 - 犠打
    if (!isWalk && !isHbp && !isSacFly && !isSacBunt) stat.atBats++;
    if (atBat.result.isHit) stat.hits++;
    if (atBat.result == AtBatResultType.homeRun) stat.homeRuns++;
    stat.rbi += atBat.rbiCount;
    if (atBat.result == AtBatResultType.strikeout) stat.strikeouts++;
    if (isWalk) stat.walks++;
    if (isSacFly || isSacBunt) stat.sacrifices++;

    final inningIndex = inning - 1;
    if (inningIndex >= 0 && inningIndex < stat.inningResults.length) {
      stat.inningResults[inningIndex].add(
        _InningEntry(atBatResultDisplayName(atBat), atBat.result),
      );
    }
  }
}

/// イニング内の1打席分の結果（表示ラベルと結果タイプ）。
/// タイプは色分けに使う。
class _InningEntry {
  final String label;
  final AtBatResultType type;
  const _InningEntry(this.label, this.type);
}

/// 1人の打者の試合成績（1つの出場分）
class _BatterGameStats {
  int atBats = 0;
  int hits = 0;
  int homeRuns = 0;
  int rbi = 0;
  int strikeouts = 0;
  int walks = 0;
  int sacrifices = 0; // 犠打（送りバント成功 + 犠飛 の合算）
  // イニングごとの打席結果（同一イニングに複数打席あればリストに追加）
  final List<List<_InningEntry>> inningResults;

  _BatterGameStats(int inningCount)
      : inningResults =
            List.generate(inningCount, (_) => <_InningEntry>[], growable: false);
}

/// 打撃成績の1行分のデータ
class _BatterRow {
  final int battingOrder; // 0-8
  final Player player;
  // この選手が試合中に守ったポジション履歴（順番に、重複なし）
  // 例: [first, shortstop] = 最初は一塁、途中から遊撃を守った
  final List<FieldPosition> positions;
  final bool isStarter;
  final FielderChangeType? subType; // starterや投手交代の場合はnull
  final bool isDH; // DH（守備に就かず打席だけ立つ）
  final _BatterGameStats stats;

  _BatterRow({
    required this.battingOrder,
    required this.player,
    required this.positions,
    required this.isStarter,
    required this.subType,
    this.isDH = false,
    required this.stats,
  });
}

/// 打順スロットの交代情報（代打・代走・投手交代・守備交代を横断的に扱う）
class _SlotSub {
  final int battingOrder;
  final Player? outgoing; // 守備交代の新規出場者では不明（null）
  final Player incoming;
  final FielderChangeType? fielderType; // nullの場合は投手交代

  const _SlotSub({
    required this.battingOrder,
    required this.outgoing,
    required this.incoming,
    required this.fielderType,
  });
}

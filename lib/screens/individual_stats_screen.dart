import 'package:flutter/material.dart';

import '../engine/engine.dart';
import '../utils/stat_format.dart';

/// 打撃ランキング（Scaffold/AppBar なし）。
///
/// `StatsScreen` の「打撃」タブから埋め込まれる。
/// 表示: 首位打者(打率) / 本塁打王 / 打点王 / 盗塁王 / OPS。自チームの選手は青色太字。
class BatterRankingView extends StatelessWidget {
  final SeasonController controller;

  const BatterRankingView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final all = c.batterStats.values.toList();
    // 規定打席: シーズン試合数 × 3.1（現時点まで消化した試合数をベース）
    final qualifiedPA = (c.currentDay * 3.1).ceil();
    // currentDay == 0（1試合も消化前）は規定打席フィルタが事実上ザルになり
    // 全選手が並ぶので、ランキング系は空にする。
    final qualified = c.currentDay == 0
        ? <BatterSeasonStats>[]
        : all.where((b) => b.plateAppearances >= qualifiedPA).toList();

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        _buildHeader('Day ${c.currentDay}/${c.totalDays}   '
            '規定打席: $qualifiedPA'),
        _BatterRankingCard(
          title: '首位打者 (打率)',
          batters: qualified,
          myTeamId: c.myTeamId,
          getValue: (b) => b.battingAverage,
          format: (v) => formatRate3(v),
        ),
        _BatterRankingCard(
          title: '本塁打王',
          batters: all,
          myTeamId: c.myTeamId,
          getValue: (b) => b.homeRuns.toDouble(),
          format: (v) => v.toInt().toString(),
          min: 1,
        ),
        _BatterRankingCard(
          title: '打点王',
          batters: all,
          myTeamId: c.myTeamId,
          getValue: (b) => b.rbi.toDouble(),
          format: (v) => v.toInt().toString(),
          min: 1,
        ),
        _BatterRankingCard(
          title: '盗塁王',
          batters: all,
          myTeamId: c.myTeamId,
          getValue: (b) => b.stolenBases.toDouble(),
          format: (v) => v.toInt().toString(),
          min: 1,
        ),
        _BatterRankingCard(
          title: 'OPS',
          batters: qualified,
          myTeamId: c.myTeamId,
          getValue: (b) => b.ops,
          format: (v) => formatRate3(v),
        ),
      ],
    );
  }
}

/// 投手ランキング（Scaffold/AppBar なし）。
///
/// `StatsScreen` の「投手」タブから埋め込まれる。
/// 表示: 最優秀防御率 / 最多勝 / 最多奪三振 / 最多セーブ / 最優秀中継ぎ(HP) / WHIP。
class PitcherRankingView extends StatelessWidget {
  final SeasonController controller;

  const PitcherRankingView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final all = c.pitcherStats.values.toList();
    // 規定投球回: シーズン試合数 × 1.0
    final qualifiedIP = c.currentDay.toDouble();
    // currentDay == 0（1試合も消化前）は全投手が IP 0 で並ぶので、ランキング系は空に。
    final qualified = c.currentDay == 0
        ? <PitcherSeasonStats>[]
        : all.where((p) => p.inningsPitched >= qualifiedIP).toList();

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        _buildHeader('Day ${c.currentDay}/${c.totalDays}   '
            '規定投球回: ${qualifiedIP.toInt()}'),
        _PitcherRankingCard(
          title: '最優秀防御率',
          pitchers: qualified,
          myTeamId: c.myTeamId,
          getValue: (p) => p.era,
          format: (v) => v.toStringAsFixed(2),
          ascending: true,
        ),
        _PitcherRankingCard(
          title: '最多勝',
          pitchers: all,
          myTeamId: c.myTeamId,
          getValue: (p) => p.wins.toDouble(),
          format: (v) => v.toInt().toString(),
          min: 1,
        ),
        _PitcherRankingCard(
          title: '最多奪三振',
          pitchers: all,
          myTeamId: c.myTeamId,
          getValue: (p) => p.strikeoutsRecorded.toDouble(),
          format: (v) => v.toInt().toString(),
          min: 1,
        ),
        _PitcherRankingCard(
          title: '最多セーブ',
          pitchers: all,
          myTeamId: c.myTeamId,
          getValue: (p) => p.saves.toDouble(),
          format: (v) => v.toInt().toString(),
          min: 1,
        ),
        _PitcherRankingCard(
          title: '最優秀中継ぎ (HP=ホールド+救援勝利)',
          pitchers: all,
          myTeamId: c.myTeamId,
          getValue: (p) =>
              (p.holds + (p.starts == 0 ? p.wins : 0)).toDouble(),
          format: (v) => v.toInt().toString(),
          min: 1,
        ),
        _PitcherRankingCard(
          title: 'WHIP',
          pitchers: qualified,
          myTeamId: c.myTeamId,
          getValue: (p) => p.whip,
          format: (v) => v.toStringAsFixed(2),
          ascending: true,
        ),
      ],
    );
  }
}

Widget _buildHeader(String text) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
    ),
  );
}

/// ソート済みリストから「順位 ≤ topN」の項目を返す。
/// 同値はタイ（同じ順位）として扱い、タイで topN を超えても全員含める。
/// 例: 値 [10, 10, 8, 7, 7, 6, 5] / topN=5 → 順位 [1, 1, 3, 4, 4]、6位以降は除外。
List<({int rank, T item})> _topNWithTies<T>(
  List<T> sorted,
  double Function(T) getValue,
  int topN,
) {
  final result = <({int rank, T item})>[];
  for (int i = 0; i < sorted.length; i++) {
    final int rank;
    if (i == 0) {
      rank = 1;
    } else if (getValue(sorted[i]) == getValue(sorted[i - 1])) {
      rank = result.last.rank;
    } else {
      rank = i + 1;
    }
    if (rank > topN) break;
    result.add((rank: rank, item: sorted[i]));
  }
  return result;
}

class _BatterRankingCard extends StatelessWidget {
  final String title;
  final List<BatterSeasonStats> batters;
  final String myTeamId;
  final double Function(BatterSeasonStats) getValue;
  final String Function(double) format;
  final double min;

  const _BatterRankingCard({
    required this.title,
    required this.batters,
    required this.myTeamId,
    required this.getValue,
    required this.format,
    this.min = 0,
  });

  @override
  Widget build(BuildContext context) {
    final filtered = batters.where((b) => getValue(b) >= min).toList();
    filtered.sort((a, b) => getValue(b).compareTo(getValue(a)));
    final top = _topNWithTies(filtered, getValue, 5);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            if (top.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('該当選手なし',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              )
            else
              for (final entry in top)
                _BatterRow(
                  rank: entry.rank,
                  stats: entry.item,
                  myTeamId: myTeamId,
                  getValue: getValue,
                  format: format,
                ),
          ],
        ),
      ),
    );
  }
}

class _BatterRow extends StatelessWidget {
  final int rank;
  final BatterSeasonStats stats;
  final String myTeamId;
  final double Function(BatterSeasonStats) getValue;
  final String Function(double) format;

  const _BatterRow({
    required this.rank,
    required this.stats,
    required this.myTeamId,
    required this.getValue,
    required this.format,
  });

  @override
  Widget build(BuildContext context) {
    final b = stats;
    final isMyTeam = b.team.id == myTeamId;
    final mainStyle = TextStyle(
      fontSize: 13,
      fontWeight: isMyTeam ? FontWeight.bold : FontWeight.normal,
      color: isMyTeam ? Colors.blue.shade800 : null,
    );
    final subStyle = TextStyle(
      fontSize: 10,
      color: isMyTeam ? Colors.blue.shade700 : Colors.grey.shade600,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 24, child: Text('$rank.', style: mainStyle)),
          SizedBox(
              width: 56,
              child: Text(format(getValue(b)),
                  style: mainStyle.copyWith(fontWeight: FontWeight.bold))),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${b.player.name}  (${b.team.name})',
                  style: mainStyle,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '打${formatRate3(b.battingAverage)}  '
                  '本${b.homeRuns}  '
                  '点${b.rbi}  '
                  '盗${b.stolenBases}  '
                  '三${b.strikeouts}  '
                  '四${b.walks}  '
                  'OPS${formatRate3(b.ops)}',
                  style: subStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PitcherRankingCard extends StatelessWidget {
  final String title;
  final List<PitcherSeasonStats> pitchers;
  final String myTeamId;
  final double Function(PitcherSeasonStats) getValue;
  final String Function(double) format;
  final double min;
  final bool ascending;

  const _PitcherRankingCard({
    required this.title,
    required this.pitchers,
    required this.myTeamId,
    required this.getValue,
    required this.format,
    this.min = 0,
    this.ascending = false,
  });

  @override
  Widget build(BuildContext context) {
    final filtered = pitchers.where((p) => getValue(p) >= min).toList();
    filtered.sort((a, b) => ascending
        ? getValue(a).compareTo(getValue(b))
        : getValue(b).compareTo(getValue(a)));
    final top = _topNWithTies(filtered, getValue, 5);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            if (top.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('該当選手なし',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              )
            else
              for (final entry in top)
                _PitcherRow(
                  rank: entry.rank,
                  stats: entry.item,
                  myTeamId: myTeamId,
                  getValue: getValue,
                  format: format,
                ),
          ],
        ),
      ),
    );
  }
}

class _PitcherRow extends StatelessWidget {
  final int rank;
  final PitcherSeasonStats stats;
  final String myTeamId;
  final double Function(PitcherSeasonStats) getValue;
  final String Function(double) format;

  const _PitcherRow({
    required this.rank,
    required this.stats,
    required this.myTeamId,
    required this.getValue,
    required this.format,
  });

  @override
  Widget build(BuildContext context) {
    final p = stats;
    final isMyTeam = p.team.id == myTeamId;
    final mainStyle = TextStyle(
      fontSize: 13,
      fontWeight: isMyTeam ? FontWeight.bold : FontWeight.normal,
      color: isMyTeam ? Colors.blue.shade800 : null,
    );
    final subStyle = TextStyle(
      fontSize: 10,
      color: isMyTeam ? Colors.blue.shade700 : Colors.grey.shade600,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 24, child: Text('$rank.', style: mainStyle)),
          SizedBox(
              width: 56,
              child: Text(format(getValue(p)),
                  style: mainStyle.copyWith(fontWeight: FontWeight.bold))),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${p.player.name}  (${p.team.name})',
                  style: mainStyle,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '防${p.era.toStringAsFixed(2)}  '
                  '勝${p.wins}  '
                  '負${p.losses}  '
                  'S${p.saves}  '
                  'H${p.holds}  '
                  '回${p.inningsPitchedDisplay}  '
                  '三${p.strikeoutsRecorded}  '
                  '四${p.walksAllowed}',
                  style: subStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

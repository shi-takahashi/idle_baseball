import 'package:flutter/material.dart';

import '../engine/engine.dart';

/// 指定チーム視点の対戦成績画面
///
/// 他5チームそれぞれに対する 勝-敗-分 と得失点差を表示し、
/// 勝ち越し/負け越し/五分を一目で分かるよう色とマークで示す。
/// チーム一覧の「対戦成績」リンクから push される。
class TeamHeadToHeadScreen extends StatelessWidget {
  final SeasonController controller;
  final Listenable listenable;
  final String teamId;

  const TeamHeadToHeadScreen({
    super.key,
    required this.controller,
    required this.listenable,
    required this.teamId,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final team = controller.teams.firstWhere((t) => t.id == teamId);
        final primary = Color(team.primaryColorValue);

        // 他5チームそれぞれとの対戦成績を集計
        final records = <_H2HRecord>[];
        for (final opp in controller.teams) {
          if (opp.id == teamId) continue;
          records.add(_compute(controller, teamId, opp));
        }
        // 自前の表示順は teams の順（順位表と一致）

        // 全対戦の合計（自チームの通算と一致するはず）
        int totalW = 0, totalL = 0, totalD = 0;
        int totalRf = 0, totalRa = 0;
        for (final r in records) {
          totalW += r.wins;
          totalL += r.losses;
          totalD += r.draws;
          totalRf += r.runsFor;
          totalRa += r.runsAgainst;
        }

        return Scaffold(
          appBar: AppBar(
            title: Text('${team.name}　対戦成績'),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            flexibleSpace: Align(
              alignment: Alignment.bottomCenter,
              child: Container(height: 3, color: primary),
            ),
          ),
          body: Column(
            children: [
              _SummaryBar(
                wins: totalW,
                losses: totalL,
                draws: totalD,
                runsFor: totalRf,
                runsAgainst: totalRa,
              ),
              const _HeaderRow(),
              Expanded(
                child: ListView.separated(
                  itemCount: records.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: Colors.grey.shade200,
                  ),
                  itemBuilder: (context, i) => _OpponentRow(record: records[i]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 自チーム vs `opp` の通算（消化分のみ）を集計
  static _H2HRecord _compute(
      SeasonController controller, String teamId, Team opp) {
    int w = 0, l = 0, d = 0;
    int rf = 0, ra = 0;
    int played = 0, remaining = 0;
    for (final sg in controller.schedule.games) {
      final isOurGame = sg.homeTeam.id == teamId || sg.awayTeam.id == teamId;
      if (!isOurGame) continue;
      final isVsOpp = sg.homeTeam.id == opp.id || sg.awayTeam.id == opp.id;
      if (!isVsOpp) continue;

      final result = controller.resultFor(sg.gameNumber);
      if (result == null) {
        remaining++;
        continue;
      }
      played++;
      final isHome = sg.homeTeam.id == teamId;
      final my = isHome ? result.homeScore : result.awayScore;
      final op = isHome ? result.awayScore : result.homeScore;
      rf += my;
      ra += op;
      if (my > op) {
        w++;
      } else if (my < op) {
        l++;
      } else {
        d++;
      }
    }
    return _H2HRecord(
      opponent: opp,
      wins: w,
      losses: l,
      draws: d,
      runsFor: rf,
      runsAgainst: ra,
      played: played,
      remaining: remaining,
    );
  }
}

class _H2HRecord {
  final Team opponent;
  final int wins;
  final int losses;
  final int draws;
  final int runsFor;
  final int runsAgainst;
  final int played;
  final int remaining;

  const _H2HRecord({
    required this.opponent,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.runsFor,
    required this.runsAgainst,
    required this.played,
    required this.remaining,
  });

  /// 勝率の差（勝-敗）。+1以上で勝ち越し、-1以下で負け越し。
  int get diff => wins - losses;
  int get runDiff => runsFor - runsAgainst;
}

/// 上部の通算サマリ
class _SummaryBar extends StatelessWidget {
  final int wins;
  final int losses;
  final int draws;
  final int runsFor;
  final int runsAgainst;

  const _SummaryBar({
    required this.wins,
    required this.losses,
    required this.draws,
    required this.runsFor,
    required this.runsAgainst,
  });

  @override
  Widget build(BuildContext context) {
    final played = wins + losses + draws;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.grey.shade100,
      child: Row(
        children: [
          Text('$played 試合消化', style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 12),
          Text(
            '$wins 勝 $losses 敗 $draws 分',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Text(
            '$runsFor - $runsAgainst',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.grey.shade200,
      child: const Row(
        children: [
          Expanded(child: _Hd('対戦相手')),
          SizedBox(width: 32, child: _Hd('勝', center: true)),
          SizedBox(width: 32, child: _Hd('敗', center: true)),
          SizedBox(width: 32, child: _Hd('分', center: true)),
          SizedBox(width: 56, child: _Hd('得失差', center: true)),
          SizedBox(width: 28, child: _Hd('', center: true)),
        ],
      ),
    );
  }
}

class _Hd extends StatelessWidget {
  final String label;
  final bool center;

  const _Hd(this.label, {this.center = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textAlign: center ? TextAlign.center : TextAlign.left,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
    );
  }
}

class _OpponentRow extends StatelessWidget {
  final _H2HRecord record;

  const _OpponentRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final opColor = Color(record.opponent.primaryColorValue);

    // 勝ち越し/負け越しの強調
    String mark;
    Color markColor;
    if (record.diff > 0) {
      mark = '勝';
      markColor = Colors.red.shade700;
    } else if (record.diff < 0) {
      mark = '負';
      markColor = Colors.blue.shade700;
    } else {
      mark = '−';
      markColor = Colors.grey.shade600;
    }

    final runDiffText = record.runDiff > 0
        ? '+${record.runDiff}'
        : '${record.runDiff}';
    final runDiffColor = record.runDiff > 0
        ? Colors.red.shade700
        : record.runDiff < 0
            ? Colors.blue.shade700
            : Colors.grey.shade700;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          // 対戦相手のカラーバッジ + チーム名
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(right: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: opColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    record.opponent.shortName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    record.opponent.name,
                    style: const TextStyle(fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // 勝・敗・分
          SizedBox(
            width: 32,
            child: Text(
              '${record.wins}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          SizedBox(
            width: 32,
            child: Text(
              '${record.losses}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          SizedBox(
            width: 32,
            child: Text(
              '${record.draws}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          // 得失点差
          SizedBox(
            width: 56,
            child: Text(
              record.played == 0 ? '-' : runDiffText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: record.played == 0 ? Colors.grey : runDiffColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          // 勝/負/五分マーク
          SizedBox(
            width: 28,
            child: Text(
              record.played == 0 ? '-' : mark,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: record.played == 0 ? Colors.grey : markColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

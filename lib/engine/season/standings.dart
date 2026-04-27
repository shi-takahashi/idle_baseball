import '../models/team.dart';

/// 1チームの通算成績（順位表用）
class TeamRecord {
  final Team team;
  int games = 0;
  int wins = 0;
  int losses = 0;
  int ties = 0;
  int runsScored = 0;
  int runsAllowed = 0;
  // 守備失策（フィールディングエラー）数
  // バッテリーエラー（暴投・パスボール）はチーム失策には含めない
  int errors = 0;

  TeamRecord(this.team);

  /// 勝率 = 勝利数 / (勝利数 + 敗北数)  ※引き分けはカウントしない
  double get winningPct {
    final decided = wins + losses;
    return decided == 0 ? 0 : wins / decided;
  }

  /// 得失点差
  int get runDifferential => runsScored - runsAllowed;
}

/// 順位表
class Standings {
  final List<TeamRecord> records;

  Standings(this.records);

  /// 順位順にソートしたリスト
  /// 優先順: 勝率降順 → 勝利数降順 → 得失点差降順
  List<TeamRecord> get sorted {
    final list = [...records];
    list.sort((a, b) {
      final pctCompare = b.winningPct.compareTo(a.winningPct);
      if (pctCompare != 0) return pctCompare;
      final winsCompare = b.wins.compareTo(a.wins);
      if (winsCompare != 0) return winsCompare;
      return b.runDifferential.compareTo(a.runDifferential);
    });
    return list;
  }

  /// リーダー（首位チーム）に対するゲーム差を計算
  /// GB = ((leader.wins - r.wins) + (r.losses - leader.losses)) / 2
  double gamesBehind(TeamRecord record, TeamRecord leader) {
    return ((leader.wins - record.wins) + (record.losses - leader.losses)) /
        2.0;
  }
}

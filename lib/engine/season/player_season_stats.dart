import '../models/player.dart';
import '../models/team.dart';

/// 野手のシーズン成績
class BatterSeasonStats {
  // 選手・所属チームは編集機能（PlayerEditScreen）で差し替えられるので非final。
  // 累積カウンタは維持したまま player/team の参照だけ最新版に更新する。
  Player player;
  Team team;

  int games = 0;
  int plateAppearances = 0; // 打席数
  int atBats = 0; // 打数（打席 - 四球 - 犠飛）
  int hits = 0; // 安打
  int doubles = 0; // 二塁打
  int triples = 0; // 三塁打
  int homeRuns = 0; // 本塁打
  int rbi = 0; // 打点
  int walks = 0; // 四球
  int strikeouts = 0; // 三振
  int stolenBases = 0; // 盗塁成功
  int caughtStealing = 0; // 盗塁死
  int sacFlies = 0; // 犠飛
  int sacrificeBunts = 0; // 犠打（送りバント成功）

  BatterSeasonStats({required this.player, required this.team});

  /// 打率 = 安打 / 打数
  double get battingAverage => atBats == 0 ? 0 : hits / atBats;

  /// 出塁率 = (安打 + 四球) / (打数 + 四球 + 犠飛)
  /// ※ 簡略: 死球は未実装のため 0 扱い
  double get onBasePct {
    final denom = atBats + walks + sacFlies;
    return denom == 0 ? 0 : (hits + walks) / denom;
  }

  /// 長打率 = 塁打数 / 打数
  /// 塁打数 = 単打×1 + 二塁打×2 + 三塁打×3 + 本塁打×4
  double get sluggingPct {
    if (atBats == 0) return 0;
    final singles = hits - doubles - triples - homeRuns;
    final totalBases = singles + doubles * 2 + triples * 3 + homeRuns * 4;
    return totalBases / atBats;
  }

  /// OPS = 出塁率 + 長打率
  double get ops => onBasePct + sluggingPct;
}

/// 投手のシーズン成績
class PitcherSeasonStats {
  // 選手・所属チームは編集機能（PlayerEditScreen）で差し替えられるので非final。
  Player player;
  Team team;

  int games = 0; // 登板数
  int starts = 0; // 先発登板数
  int wins = 0; // 勝利
  int losses = 0; // 敗戦
  int saves = 0; // セーブ
  int holds = 0; // ホールド
  int outsRecorded = 0; // 奪ったアウト数（投球回×3）
  int hitsAllowed = 0; // 被安打
  int homeRunsAllowed = 0; // 被本塁打
  int walksAllowed = 0; // 与四球
  int strikeoutsRecorded = 0; // 奪三振
  int runsAllowed = 0; // 失点（責任投手にホームインされた点をカウント）
  int earnedRuns = 0; // 自責点（エラーが無ければ無かった失点を除く）

  PitcherSeasonStats({required this.player, required this.team});

  /// 投球回表示（例: "6.0", "5.1", "5.2"）
  String get inningsPitchedDisplay {
    final full = outsRecorded ~/ 3;
    final rem = outsRecorded % 3;
    return '$full.$rem';
  }

  /// 投球回（小数）
  double get inningsPitched => outsRecorded / 3.0;

  /// 防御率 = (自責点 × 27) / 奪ったアウト数
  double get era {
    if (outsRecorded == 0) return 0;
    return (earnedRuns * 27) / outsRecorded;
  }

  /// WHIP = (与四球 + 被安打) × 3 / 奪ったアウト数
  double get whip {
    if (outsRecorded == 0) return 0;
    return (walksAllowed + hitsAllowed) * 3 / outsRecorded;
  }
}

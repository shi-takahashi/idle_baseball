import '../models/player.dart';

/// 1試合のサマリー情報
/// スコアボード下に表示する「勝利投手・敗戦投手・セーブ・本塁打」をまとめる。
class GameSummary {
  /// 勝利投手（引き分けや決定不能なら null）。その試合終了時点の通算成績付き。
  final PitcherDecisionRecord? winning;

  /// 敗戦投手（引き分けや決定不能なら null）。その試合終了時点の通算成績付き。
  final PitcherDecisionRecord? losing;

  /// セーブ投手（セーブ条件を満たさなければ null）。その試合終了時点の通算成績付き。
  final PitcherDecisionRecord? saving;

  /// この試合で打たれた本塁打のリスト（時系列順、両チーム合算）
  final List<HomeRunRecord> homeRuns;

  const GameSummary({
    this.winning,
    this.losing,
    this.saving,
    this.homeRuns = const [],
  });

  static const empty = GameSummary();
}

/// 勝利・敗戦・セーブ投手とその時点での通算成績
class PitcherDecisionRecord {
  final Player pitcher;
  final int wins;
  final int losses;
  final int saves;

  const PitcherDecisionRecord({
    required this.pitcher,
    required this.wins,
    required this.losses,
    required this.saves,
  });
}

/// 本塁打の記録
class HomeRunRecord {
  /// 打者
  final Player batter;

  /// 通算第何号か（その打者がシーズン開始から記録した本塁打数、この試合分含む）
  final int seasonNumber;

  /// 攻撃側がアウェイチームだったかどうか（表示色分け等に使う）
  final bool isAway;

  /// 何回に打ったか
  final int inning;

  const HomeRunRecord({
    required this.batter,
    required this.seasonNumber,
    required this.isAway,
    required this.inning,
  });
}

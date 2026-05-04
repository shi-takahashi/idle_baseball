import '../models/team.dart';
import 'schedule.dart';
import 'scheduled_game.dart';

/// シーズンの試合日程を生成する（3連戦方式）
///
/// 6チーム前提:
/// - サークル法で5ラウンド（15カード）を構成し、各ラウンドを3連戦として消化
/// - 前半15日: 5ラウンド × 3日 = 全15カードを1回ずつ消化
/// - 後半15日: 同じ5ラウンドを再度消化（ホーム/ビジターは反転）
/// - 各カード合計6試合、ホーム3:ビジター3
/// - Day15→Day16の境界で対戦相手が必ず変わる（=6連戦回避）
///
/// 1チームの年間試合数は `15 × halves`（halves=2 なら 30 試合）。
/// UI で選択できる試合数（30 / 90 / 150）はそれぞれ halves=2 / 6 / 10 に対応。
class ScheduleGenerator {
  const ScheduleGenerator();

  /// 1チームあたりの試合数として UI から選択できる値。
  /// halves に変換する際は `gamesPerTeam ~/ 15`。
  static const List<int> allowedGamesPerTeam = [30, 90, 150];

  /// デフォルトの 1 チームあたり試合数。
  static const int defaultGamesPerTeam = 30;

  /// 1チームあたりの試合数 → halves の変換。
  /// 6 チーム × サークル法では 1 half あたり 15 試合（前半 or 後半 1 周分）。
  static int halvesForGamesPerTeam(int gamesPerTeam) {
    if (gamesPerTeam <= 0 || gamesPerTeam % 15 != 0) {
      throw ArgumentError(
          'gamesPerTeam は 15 の倍数である必要があります (受け取り: $gamesPerTeam)');
    }
    return gamesPerTeam ~/ 15;
  }

  /// 1チームあたりの試合数を指定して日程を生成（UI 連携用の薄いラッパー）。
  Schedule generateForGamesPerTeam(
    List<Team> teams,
    int gamesPerTeam, {
    int gamesPerCard = 3,
  }) {
    return generate(
      teams,
      gamesPerCard: gamesPerCard,
      halves: halvesForGamesPerTeam(gamesPerTeam),
    );
  }

  /// 指定チームで日程を生成
  /// `gamesPerCard`: 1連戦の試合数（デフォルト3）
  /// `halves`: 前半・後半を何周するか（デフォルト2 = 30試合シーズン）
  Schedule generate(
    List<Team> teams, {
    int gamesPerCard = 3,
    int halves = 2,
  }) {
    if (teams.length != 6) {
      throw ArgumentError('現在は6チームのみ対応（${teams.length}チームが渡されました）');
    }

    final rounds = _circleMethodRounds(teams); // 5ラウンド × 3ペア

    final scheduled = <ScheduledGame>[];
    int day = 0;
    int gameNumber = 0;

    for (int half = 0; half < halves; half++) {
      for (int r = 0; r < rounds.length; r++) {
        final pairs = rounds[r];
        // このラウンドは gamesPerCard 日間、同じカードが続く（3連戦）
        for (int dayInBlock = 0; dayInBlock < gamesPerCard; dayInBlock++) {
          day++;
          for (int slot = 0; slot < pairs.length; slot++) {
            final (first, second) = pairs[slot];
            // ホーム/ビジター振り分け:
            // 前半: ラウンドが偶数なら first ホーム、奇数なら second ホーム
            // 後半: 上記を反転
            // これでカードごとに 3:3、チーム全体でも 15:15 になる
            final firstIsHome = (half == 0) ? r.isEven : r.isOdd;
            final (home, away) = firstIsHome ? (first, second) : (second, first);
            gameNumber++;
            scheduled.add(ScheduledGame(
              gameNumber: gameNumber,
              day: day,
              slotInDay: slot + 1,
              homeTeam: home,
              awayTeam: away,
            ));
          }
        }
      }
    }
    return Schedule(games: scheduled);
  }

  /// サークル法で1サイクル分のラウンドを生成
  /// 戻り値: List<ラウンド>、各ラウンドは (teamA, teamB) のペアのリスト
  ///
  /// 6チームの場合、5ラウンド×3ペア = 15カードを全て1回ずつ含む
  List<List<(Team, Team)>> _circleMethodRounds(List<Team> teams) {
    final n = teams.length;
    // 1番目を固定し、残りを円状に回転させることで総当たりを実現
    final rotating = List<Team>.from(teams);
    final rounds = <List<(Team, Team)>>[];

    for (int r = 0; r < n - 1; r++) {
      final pairs = <(Team, Team)>[];
      for (int i = 0; i < n ~/ 2; i++) {
        pairs.add((rotating[i], rotating[n - 1 - i]));
      }
      rounds.add(pairs);
      // インデックス0は固定、残りを1つ回転（末尾を位置1に挿入）
      final last = rotating.removeLast();
      rotating.insert(1, last);
    }
    return rounds;
  }
}

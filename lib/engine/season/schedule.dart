import 'scheduled_game.dart';

/// シーズンの試合日程
class Schedule {
  final List<ScheduledGame> games;

  const Schedule({required this.games});

  /// シーズンの総日数
  int get totalDays =>
      games.isEmpty ? 0 : games.map((g) => g.day).reduce((a, b) => a > b ? a : b);

  /// 指定日の試合一覧（slotInDay順）
  List<ScheduledGame> gamesOnDay(int day) {
    final result = games.where((g) => g.day == day).toList();
    result.sort((a, b) => a.slotInDay.compareTo(b.slotInDay));
    return result;
  }
}

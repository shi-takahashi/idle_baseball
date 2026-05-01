import '../models/team.dart';

/// スケジュール上の1試合（まだシミュレーションされていない）
class ScheduledGame {
  /// シーズン通算のゲーム番号（1-indexed）
  final int gameNumber;

  /// シーズン何日目か（1-indexed）
  final int day;

  /// その日の何試合目か（1-indexed、同時進行する試合の識別用）
  final int slotInDay;

  final Team homeTeam;
  final Team awayTeam;

  const ScheduledGame({
    required this.gameNumber,
    required this.day,
    required this.slotInDay,
    required this.homeTeam,
    required this.awayTeam,
  });

  Map<String, dynamic> toJson() => {
        'gameNumber': gameNumber,
        'day': day,
        'slotInDay': slotInDay,
        'homeTeamId': homeTeam.id,
        'awayTeamId': awayTeam.id,
      };

  factory ScheduledGame.fromJson(
    Map<String, dynamic> json,
    Map<String, Team> teamById,
  ) =>
      ScheduledGame(
        gameNumber: json['gameNumber'] as int,
        day: json['day'] as int,
        slotInDay: json['slotInDay'] as int,
        homeTeam: teamById[json['homeTeamId']]!,
        awayTeam: teamById[json['awayTeamId']]!,
      );

  @override
  String toString() =>
      'Day$day-#$slotInDay: ${awayTeam.name} @ ${homeTeam.name}';
}

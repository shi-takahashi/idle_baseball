import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 投手1人ずつに meet / power / eye が個別に設定されているか確認
void main() {
  final teams = TeamGenerator(random: Random(42)).generateLeague();
  for (final team in teams) {
    print('${team.name}:');
    final pitchers = [
      ...team.startingRotation,
      ...team.bullpen,
    ];
    for (final p in pitchers) {
      print('  #${p.number.toString().padLeft(2)} ${p.name.padRight(8)} '
          'meet=${p.meet} power=${p.power} eye=${p.eye}');
    }
  }
}

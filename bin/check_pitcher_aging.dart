import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';
import 'package:idle_baseball/engine/offseason/player_aging.dart';

void main() {
  const trials = 300;
  final ages = [22, 25, 27, 30, 32, 35, 38, 40];
  final samples = <int, Map<String, List<int>>>{};
  for (final a in ages) {
    samples[a] = {'speed': [], 'control': [], 'fastball': [], 'slider': []};
  }
  for (int t = 0; t < trials; t++) {
    final aging = PlayerAging(random: Random(t));
    Player p = Player(
      id: 'test', name: 'テスト', number: 1, age: 18,
      averageSpeed: 150, fastball: 9, control: 9,
      slider: 9, curve: 9, splitter: 9,
      potentials: {'fastball': 9, 'control': 9, 'slider': 9, 'curve': 9, 'splitter': 9},
      potentialAverageSpeed: 158,
    );
    for (int year = 0; year < 23; year++) {
      if (samples.containsKey(p.age)) {
        samples[p.age]!['speed']!.add(p.averageSpeed ?? 0);
        samples[p.age]!['control']!.add(p.control ?? 0);
        samples[p.age]!['fastball']!.add(p.fastball ?? 0);
        samples[p.age]!['slider']!.add(p.slider ?? 0);
      }
      p = aging.ageOneYear(p);
    }
  }
  print('球速150 / 全能力9 のエース投手 $trials 試行平均');
  print('age   speed control fastball slider');
  for (final a in ages) {
    final s = samples[a]!;
    String avg(String k) {
      final l = s[k]!;
      return (l.reduce((x, y) => x + y) / l.length).toStringAsFixed(1).padLeft(5);
    }
    print('${a.toString().padLeft(3)}  ${avg("speed")} ${avg("control")} ${avg("fastball")}  ${avg("slider")}');
  }
}

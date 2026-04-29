import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 捕手リードパラメータのテスト
void main() {
  print('=== 捕手リード 被打率テスト ===\n');

  final random = Random(42);

  // チーム作成（捕手のリードを指定）
  Team createTeam(int leadValue, String name) {
    return Team(
      id: name,
      name: name,
      players: [
        // 1番=捕手（リード値を指定）
        Player(
          id: 'catcher',
          name: '捕手',
          number: 2,
          meet: 5,
          power: 5,
          speed: 5,
          lead: leadValue,
        ),
        // 2〜8番の野手
        ...List.generate(
          7,
          (i) => Player(
            id: '${name}_$i',
            name: '$name${i + 1}',
            number: i + 3,
            meet: 5,
            power: 5,
            speed: 5,
          ),
        ),
        // 9番=投手（標準）
        const Player(
          id: 'pitcher',
          name: 'テスト投手',
          number: 18,
          averageSpeed: 145,
          fastball: 5,
          control: 5,
          stamina: 5,
          slider: 5,
        ),
      ],
    );
  }

  // 打撃チーム（標準）
  final battingTeam = Team(
    id: 'batting',
    name: '打撃チーム',
    players: [
      ...List.generate(
        8,
        (i) => Player(
          id: 'batter_$i',
          name: '打者${i + 1}',
          number: i + 1,
          meet: 5,
          power: 5,
          speed: 5,
          eye: 5,
        ),
      ),
      const Player(
        id: 'b_pitcher',
        name: '投手',
        number: 18,
        averageSpeed: 145,
        fastball: 5,
        control: 5,
        stamina: 5,
      ),
    ],
  );

  // 各リード値で50試合ずつシミュレーション
  void simulateGames(Team pitchingTeam, String label) {
    int totalAtBats = 0;
    int hits = 0;
    int outs = 0;

    for (int gameNum = 0; gameNum < 50; gameNum++) {
      final simulator = GameSimulator(random: Random(random.nextInt(10000)));
      final result = simulator.simulate(pitchingTeam, battingTeam);

      // 表イニング（battingTeam=awayの攻撃）を集計
      for (final half in result.halfInnings.where((h) => h.isTop)) {
        for (final ab in half.atBats) {
          totalAtBats++;
          if (ab.result.isHit) hits++;
          if (ab.result.isOut) outs++;
        }
      }
    }

    final hitRate = (hits / totalAtBats * 100).toStringAsFixed(1);
    final outRate = (outs / totalAtBats * 100).toStringAsFixed(1);

    print('$label:');
    print('  打席数: $totalAtBats');
    print('  安打率: $hitRate% ($hits安打)');
    print('  アウト率: $outRate%');
    print('');
  }

  print('--- リード値による被打率の変化 ---');
  final leadValues = [1, 5, 10];
  for (final leadValue in leadValues) {
    final team = createTeam(leadValue, 'リード$leadValue');
    simulateGames(team, 'リード$leadValue');
  }

  print('=== 期待される傾向 ===');
  print('- リードが高いほど被打率がわずかに下がる');
  print('- 効果は小さい（おまけ程度）');
  print('- リード1→10で約2.5%程度のアウト率上昇');
}

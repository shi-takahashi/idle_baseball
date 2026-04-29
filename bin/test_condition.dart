import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 投手の調子システムのテスト
void main() {
  print('=== 投手の調子システム テスト ===\n');

  final random = Random(42);

  // 標準的な投手
  final pitcher = const Player(
    id: 'test_pitcher',
    name: 'テスト投手',
    number: 18,
    averageSpeed: 145,
    fastball: 6,
    control: 5,
    stamina: 5,
    slider: 6,
    curve: 5,
  );

  // チーム作成
  Team createTeam(Player pitcher, String name) {
    return Team(
      id: name,
      name: name,
      players: [
        ...List.generate(
          8,
          (i) => Player(
            id: '${name}_$i',
            name: '$name${i + 1}',
            number: i + 1,
            meet: 5,
            power: 5,
            speed: 5,
          ),
        ),
        pitcher,
      ],
    );
  }

  // 対戦相手
  final opponent = Team(
    id: 'opponent',
    name: '相手',
    players: [
      ...List.generate(
        8,
        (i) => Player(
          id: 'opp_$i',
          name: '相手${i + 1}',
          number: i + 1,
          meet: 5,
          power: 5,
          speed: 5,
        ),
      ),
      const Player(
        id: 'p',
        name: '投手',
        number: 18,
        averageSpeed: 145,
        control: 5,
        stamina: 5,
      ),
    ],
  );

  final team = createTeam(pitcher, pitcher.name);

  // 調子の影響をテスト
  void simulateWithConditions(String label, int numGames) {
    int totalRuns = 0;
    int totalHits = 0;
    int totalStrikeouts = 0;
    int totalWalks = 0;
    int totalAtBats = 0;

    print('--- $label ($numGames試合) ---');

    for (int i = 0; i < numGames; i++) {
      final simulator = GameSimulator(random: Random(random.nextInt(10000)));
      final result = simulator.simulate(team, opponent);

      // 表イニング（相手の攻撃=投手の結果）を集計
      for (final half in result.halfInnings.where((h) => h.isTop)) {
        totalRuns += half.runs;
        for (final ab in half.atBats) {
          totalAtBats++;
          if (ab.result.isHit) totalHits++;
          if (ab.result == AtBatResultType.strikeout) totalStrikeouts++;
          if (ab.result == AtBatResultType.walk) totalWalks++;
        }
      }
    }

    print('  失点合計: $totalRuns (平均: ${(totalRuns / numGames).toStringAsFixed(1)})');
    print('  被安打率: ${(totalHits / totalAtBats * 100).toStringAsFixed(1)}%');
    print('  三振率: ${(totalStrikeouts / totalAtBats * 100).toStringAsFixed(1)}%');
    print('  四球率: ${(totalWalks / totalAtBats * 100).toStringAsFixed(1)}%');
    print('');
  }

  // 通常の試合を20試合シミュレーション
  simulateWithConditions('ランダムな調子で20試合', 20);

  // 調子の分布を確認
  print('--- 調子の分布（100回生成） ---');
  final conditionCounts = <String, int>{};
  for (int i = 0; i < 100; i++) {
    final condition = PitcherCondition.random(Random(i));
    final total = condition.speedModifier +
        condition.fastballModifier +
        condition.controlModifier +
        condition.sliderModifier +
        condition.curveModifier +
        condition.splitterModifier +
        condition.changeupModifier;
    final category = total < -4
        ? '絶不調(-5以下)'
        : total < 0
            ? '不調(-4〜-1)'
            : total == 0
                ? '普通(0)'
                : total < 5
                    ? '好調(+1〜+4)'
                    : '絶好調(+5以上)';
    conditionCounts[category] = (conditionCounts[category] ?? 0) + 1;
  }
  for (final entry in conditionCounts.entries) {
    print('  ${entry.key}: ${entry.value}回');
  }

  print('\n=== 調子の例 ===');
  for (int i = 0; i < 5; i++) {
    final condition = PitcherCondition.random(Random(i * 7));
    print('  試合${i + 1}: $condition');
  }
}

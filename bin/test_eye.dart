import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 選球眼・長打力の四球率テスト
void main() {
  print('=== 選球眼・長打力 四球率テスト ===\n');

  final random = Random(42);

  // 標準的な投手
  final pitcher = const Player(
    id: 'pitcher',
    name: 'テスト投手',
    number: 18,
    averageSpeed: 145,
    fastball: 5,
    control: 5,
    stamina: 5,
    slider: 5,
  );

  // チーム作成（選球眼を指定）
  Team createTeam(int eyeValue, int powerValue, String name) {
    return Team(
      id: name,
      name: name,
      players: [
        pitcher,
        ...List.generate(
          8,
          (i) => Player(
            id: '${name}_$i',
            name: '$name${i + 1}',
            number: i + 1,
            meet: 5,
            power: powerValue,
            speed: 5,
            eye: eyeValue,
          ),
        ),
      ],
    );
  }

  // チーム作成（長打力を指定）
  Team createTeamWithPower(int eyeValue, int powerValue, String name) {
    return createTeam(eyeValue, powerValue, name);
  }

  // カスタムチーム作成
  Team createCustomTeam({required int meet, required int power, required int eye, required String name}) {
    return Team(
      id: name,
      name: name,
      players: [
        pitcher,
        ...List.generate(
          8,
          (i) => Player(
            id: '${name}_$i',
            name: '$name${i + 1}',
            number: i + 1,
            meet: meet,
            power: power,
            speed: 5,
            eye: eye,
          ),
        ),
      ],
    );
  }

  // 対戦相手（普通の投手）
  final opponent = Team(
    id: 'opponent',
    name: '相手',
    players: [
      pitcher,
      ...List.generate(
        8,
        (i) => Player(
          id: 'opp_$i',
          name: '相手${i + 1}',
          number: i + 1,
          meet: 5,
          power: 5,
          speed: 5,
          eye: 5,
        ),
      ),
    ],
  );

  // 各選球眼値で30試合ずつシミュレーション
  void simulateGames(Team battingTeam, String label) {
    int totalAtBats = 0;
    int walks = 0;
    int strikeouts = 0;
    int hits = 0;

    for (int gameNum = 0; gameNum < 30; gameNum++) {
      final simulator = GameSimulator(random: Random(random.nextInt(10000)));
      final result = simulator.simulate(opponent, battingTeam);

      // 表イニング（battingTeam=awayの攻撃）を集計
      for (final half in result.halfInnings.where((h) => h.isTop)) {
        for (final ab in half.atBats) {
          totalAtBats++;
          if (ab.result == AtBatResultType.walk) walks++;
          if (ab.result == AtBatResultType.strikeout) strikeouts++;
          if (ab.result.isHit) hits++;
        }
      }
    }

    final walkRate = (walks / totalAtBats * 100).toStringAsFixed(1);
    final strikeoutRate = (strikeouts / totalAtBats * 100).toStringAsFixed(1);
    final hitRate = (hits / totalAtBats * 100).toStringAsFixed(1);

    print('$label:');
    print('  四球率: $walkRate% ($walks/$totalAtBats)');
    print('  三振率: $strikeoutRate%');
    print('  安打率: $hitRate%');
    print('');
  }

  print('--- 選球眼の影響 ---');
  final eyeValues = [1, 5, 10];
  for (final eyeValue in eyeValues) {
    final team = createTeam(eyeValue, 5, '選球眼$eyeValue');
    simulateGames(team, '選球眼$eyeValue（長打力5）');
  }

  print('--- 長打力の影響（選球眼5固定）---');
  final powerValues = [1, 5, 10];
  for (final powerValue in powerValues) {
    final team = createTeamWithPower(5, powerValue, '長打力$powerValue');
    simulateGames(team, '長打力$powerValue（選球眼5）');
  }

  print('--- 強打者タイプ（長打力高・ミート低）---');
  final slugger = createCustomTeam(meet: 3, power: 9, eye: 5, name: '強打者');
  simulateGames(slugger, '強打者（ミ3/長9/眼5）');

  final contact = createCustomTeam(meet: 8, power: 3, eye: 7, name: '巧打者');
  simulateGames(contact, '巧打者（ミ8/長3/眼7）');

  print('=== 期待される傾向 ===');
  print('- 選球眼が高いほど四球率が上がる');
  print('- 長打力が高いほど四球率が上がる（警戒される）');
  print('- 強打者は四球多め・三振多め');
  print('- 巧打者は四球多め・三振少なめ');
}

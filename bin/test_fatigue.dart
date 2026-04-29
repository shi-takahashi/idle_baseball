import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 投手疲労システムのテスト
void main() {
  print('=== 投手疲労システム テスト ===\n');

  final random = Random(42);

  // スタミナが低い投手（疲労しやすい）
  final lowStaminaPitcher = const Player(
    id: 'low_stamina',
    name: 'スタミナ不足',
    number: 18,
    averageSpeed: 145,
    fastball: 6,
    control: 5,
    stamina: 2, // スタミナ2（疲労開始: 55球、完全疲労: 85球）
    splitter: 7,
  );

  // 標準的な投手
  final normalPitcher = const Player(
    id: 'normal',
    name: '標準投手',
    number: 11,
    averageSpeed: 145,
    fastball: 6,
    control: 5,
    stamina: 5, // スタミナ5（疲労開始: 70球、完全疲労: 100球）
    splitter: 7,
  );

  // タフな投手（疲労しにくい）
  final highStaminaPitcher = const Player(
    id: 'high_stamina',
    name: '鉄腕投手',
    number: 15,
    averageSpeed: 145,
    fastball: 6,
    control: 5,
    stamina: 9, // スタミナ9（疲労開始: 90球、完全疲労: 120球）
    splitter: 7,
  );

  // スタミナ未設定（デフォルト5として扱う）
  final defaultStaminaPitcher = const Player(
    id: 'default',
    name: 'デフォルト投手',
    number: 20,
    averageSpeed: 145,
    fastball: 6,
    control: 5,
    // stamina: null（デフォルト）
    splitter: 7,
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

  // 対戦相手（普通のチーム）
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
          id: 'p', name: '投手', number: 18, averageSpeed: 145, control: 5, stamina: 5),
    ],
  );

  // 各投手で10試合ずつシミュレーション
  void simulateGames(Team pitchingTeam, String label) {
    int totalPitches = 0;
    int totalAtBats = 0;
    int runsAllowed = 0;
    int hits = 0;
    int walks = 0;
    int strikeouts = 0;
    int extraBaseHits = 0;

    // イニング別の成績を追跡
    final inningStats = <int, _InningStats>{};
    for (int i = 1; i <= 9; i++) {
      inningStats[i] = _InningStats();
    }

    for (int gameNum = 0; gameNum < 10; gameNum++) {
      final simulator = GameSimulator(random: Random(random.nextInt(10000)));
      final result = simulator.simulate(pitchingTeam, opponent);

      runsAllowed += result.awayScore;

      for (final half in result.halfInnings.where((h) => h.isTop)) {
        final inning = half.inning;
        for (final ab in half.atBats) {
          totalAtBats++;
          inningStats[inning]!.atBats++;

          if (ab.result == AtBatResultType.strikeout) {
            strikeouts++;
            inningStats[inning]!.strikeouts++;
          }
          if (ab.result == AtBatResultType.walk) {
            walks++;
            inningStats[inning]!.walks++;
          }
          if (ab.result.isHit) {
            hits++;
            inningStats[inning]!.hits++;
            if (ab.result == AtBatResultType.double_ ||
                ab.result == AtBatResultType.triple ||
                ab.result == AtBatResultType.homeRun) {
              extraBaseHits++;
              inningStats[inning]!.extraBaseHits++;
            }
          }

          totalPitches += ab.pitches.length;
          inningStats[inning]!.pitches += ab.pitches.length;
        }
      }
    }

    final strikeoutRate = (strikeouts / totalAtBats * 100).toStringAsFixed(1);
    final walkRate = (walks / totalAtBats * 100).toStringAsFixed(1);
    final hitRate = (hits / totalAtBats * 100).toStringAsFixed(1);
    final xbhRate = (extraBaseHits / totalAtBats * 100).toStringAsFixed(1);

    print('--- $label ---');
    print('  平均投球数: ${(totalPitches / 10).toStringAsFixed(1)}球/試合');
    print('  三振率: $strikeoutRate%、四球率: $walkRate%');
    print('  被安打率: $hitRate%、被長打率: $xbhRate%');
    print('  失点: $runsAllowed');
    print('');
    print('  イニング別（被安打率 / 四球率）:');
    for (int i = 1; i <= 9; i++) {
      final stats = inningStats[i]!;
      if (stats.atBats == 0) continue;
      final hr = (stats.hits / stats.atBats * 100).toStringAsFixed(1);
      final wr = (stats.walks / stats.atBats * 100).toStringAsFixed(1);
      print('    ${i}回: 被安打$hr% / 四球$wr%');
    }
    print('');
  }

  final pitchers = [
    (lowStaminaPitcher, 'スタミナ不足（スタミナ2）'),
    (normalPitcher, '標準投手（スタミナ5）'),
    (highStaminaPitcher, '鉄腕投手（スタミナ9）'),
    (defaultStaminaPitcher, 'デフォルト投手（スタミナnull）'),
  ];

  for (final (pitcher, label) in pitchers) {
    final team = createTeam(pitcher, pitcher.name);
    simulateGames(team, label);
  }

  print('=== 期待される傾向 ===');
  print('- スタミナ低い投手: 後半イニングで被安打率・四球率が上昇');
  print('- スタミナ高い投手: 9回まで安定したパフォーマンス');
  print('- 特にスプリットは疲労の影響を受けやすい（落ちなくなる）');
}

class _InningStats {
  int atBats = 0;
  int pitches = 0;
  int hits = 0;
  int walks = 0;
  int strikeouts = 0;
  int extraBaseHits = 0;
}

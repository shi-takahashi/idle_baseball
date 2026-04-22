import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 各球種の実装テスト
void main() {
  print('=== 変化球実装テスト ===\n');

  final random = Random(42);

  // 各タイプの投手を作成

  // ストレートのみ（変化球なし）
  final fastballOnlyPitcher = const Player(
    id: 'fastball_only',
    name: '剛速球',
    number: 18,
    averageSpeed: 150,
    fastball: 7,
    control: 5,
  );

  // スライダー主体
  final sliderPitcher = const Player(
    id: 'slider',
    name: 'スラ職人',
    number: 11,
    averageSpeed: 145,
    fastball: 5,
    slider: 8,
    control: 5,
  );

  // カーブ主体
  final curvePitcher = const Player(
    id: 'curve',
    name: 'カーブ王',
    number: 15,
    averageSpeed: 140,
    fastball: 5,
    curve: 8,
    control: 5,
  );

  // スプリット主体（決め球）
  final splitterPitcher = const Player(
    id: 'splitter',
    name: 'フォーク魔神',
    number: 20,
    averageSpeed: 145,
    fastball: 5,
    splitter: 9,
    control: 5,
  );

  // チェンジアップ主体
  final changeupPitcher = const Player(
    id: 'changeup',
    name: 'チェンジ使い',
    number: 21,
    averageSpeed: 145,
    fastball: 5,
    changeup: 8,
    control: 5,
  );

  // 万能型（複数球種）
  final versatilePitcher = const Player(
    id: 'versatile',
    name: '万能投手',
    number: 17,
    averageSpeed: 145,
    fastball: 6,
    slider: 6,
    curve: 5,
    splitter: 5,
    changeup: 5,
    control: 6,
  );

  // チーム作成
  Team createTeam(Player pitcher, String name) {
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
            power: 5,
            speed: 5,
          ),
        ),
      ],
    );
  }

  // 対戦相手（普通のチーム）
  final opponent = Team(
    id: 'opponent',
    name: '相手',
    players: [
      const Player(
          id: 'p', name: '投手', number: 18, averageSpeed: 145, control: 5),
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
    ],
  );

  // 各投手で10試合ずつシミュレーション
  void simulateGames(Team pitchingTeam, String label) {
    int totalPitches = 0;
    int strikeouts = 0;
    int walks = 0;
    int totalAtBats = 0;
    int runsAllowed = 0;
    int hits = 0;
    int extraBaseHits = 0;
    final pitchCounts = <PitchType, int>{};
    final speeds = <PitchType, List<int>>{};

    for (int i = 0; i < 10; i++) {
      final simulator = GameSimulator(random: Random(random.nextInt(10000)));
      final result = simulator.simulate(pitchingTeam, opponent);

      runsAllowed += result.awayScore;

      for (final half in result.halfInnings.where((h) => h.isTop)) {
        for (final ab in half.atBats) {
          totalAtBats++;
          if (ab.result == AtBatResultType.strikeout) strikeouts++;
          if (ab.result == AtBatResultType.walk) walks++;
          if (ab.result.isHit) {
            hits++;
            if (ab.result == AtBatResultType.double_ ||
                ab.result == AtBatResultType.triple ||
                ab.result == AtBatResultType.homeRun) {
              extraBaseHits++;
            }
          }

          for (final pitch in ab.pitches) {
            totalPitches++;
            pitchCounts[pitch.pitchType] =
                (pitchCounts[pitch.pitchType] ?? 0) + 1;
            speeds.putIfAbsent(pitch.pitchType, () => []).add(pitch.speed);
          }
        }
      }
    }

    final strikeoutRate = (strikeouts / totalAtBats * 100).toStringAsFixed(1);
    final walkRate = (walks / totalAtBats * 100).toStringAsFixed(1);
    final hitRate = (hits / totalAtBats * 100).toStringAsFixed(1);
    final xbhRate = (extraBaseHits / totalAtBats * 100).toStringAsFixed(1);

    print('--- $label ---');
    print('  三振率: $strikeoutRate%、四球率: $walkRate%');
    print('  被安打率: $hitRate%、被長打率: $xbhRate%');
    print('  失点: $runsAllowed');
    print('  球種内訳:');
    for (final type in PitchType.values) {
      final count = pitchCounts[type] ?? 0;
      if (count == 0) continue;
      final pct = (count / totalPitches * 100).toStringAsFixed(1);
      final avgSpeed = speeds[type]!.isNotEmpty
          ? (speeds[type]!.reduce((a, b) => a + b) / speeds[type]!.length)
              .toStringAsFixed(0)
          : '-';
      print('    ${type.displayName}: $pct% (平均${avgSpeed}km/h)');
    }
    print('');
  }

  final pitchers = [
    (fastballOnlyPitcher, '剛速球（ストレートのみ、150km、質7）'),
    (sliderPitcher, 'スラ職人（スライダー8）'),
    (curvePitcher, 'カーブ王（カーブ8）'),
    (splitterPitcher, 'フォーク魔神（スプリット9）'),
    (changeupPitcher, 'チェンジ使い（チェンジアップ8）'),
    (versatilePitcher, '万能投手（5球種）'),
  ];

  for (final (pitcher, label) in pitchers) {
    final team = createTeam(pitcher, pitcher.name);
    simulateGames(team, label);
  }

  print('=== 期待される傾向 ===');
  print('ストレート: 被打率・被長打率高め、ボール率低め');
  print('スライダー: 三振率高め、被打率低め、万能');
  print('カーブ: 三振率中、被長打率やや高め、ボール率やや高め');
  print('スプリット: 三振率最高、被打率低め、ボール率高め');
  print('チェンジアップ: 三振率中〜高、被長打率低め');
}

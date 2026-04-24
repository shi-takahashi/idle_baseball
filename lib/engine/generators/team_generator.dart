import 'dart:math';
import '../models/models.dart';
import 'player_generator.dart';

/// チームを自動生成する
///
/// 1チーム25人構成:
/// - 先発投手 1 (players[0])
/// - スタメン野手 8 (players[1..8]: 捕/一/二/三/遊/左/中/右)
/// - 救援投手 4 (bullpen)
/// - 控え野手 12 (bench: 控え捕手1・内野UT4・外野UT4・万能UT3)
class TeamGenerator {
  final PlayerGenerator _playerGen;

  TeamGenerator({Random? random})
      : _playerGen = PlayerGenerator(random: random);

  /// 6チームを一括生成
  List<Team> generateLeague() {
    const teamInfos = [
      (id: 'team_phoenix', name: 'フェニックス'),
      (id: 'team_dragoons', name: 'ドラグーンズ'),
      (id: 'team_comets', name: 'コメッツ'),
      (id: 'team_auroras', name: 'オーロラズ'),
      (id: 'team_thunders', name: 'サンダーズ'),
      (id: 'team_blizzards', name: 'ブリザーズ'),
    ];
    return [for (final info in teamInfos) _generateTeam(info.id, info.name)];
  }

  Team _generateTeam(String id, String name) {
    // ---- スタメン野手8人（打順1〜8、players[1..8]の順序でデフォルト守備位置に対応） ----
    // Teamのデフォルト配置:
    // players[1]=捕 / [2]=一 / [3]=二 / [4]=三 / [5]=遊 / [6]=左 / [7]=中 / [8]=右
    final starterPositions = [
      DefensePosition.catcher,
      DefensePosition.first,
      DefensePosition.second,
      DefensePosition.third,
      DefensePosition.shortstop,
      DefensePosition.outfield, // 左
      DefensePosition.outfield, // 中
      DefensePosition.outfield, // 右
    ];
    final starters = <Player>[];
    for (int i = 0; i < 8; i++) {
      starters.add(_playerGen.generateStarterFielder(
        number: i + 1,
        primaryPosition: starterPositions[i],
      ));
    }

    // ---- 先発投手 (players[0]) ----
    final startingPitcher = _playerGen.generateStartingPitcher(number: 18);

    // ---- 救援投手 4人 ----
    final bullpen = <Player>[
      for (int i = 0; i < 4; i++)
        _playerGen.generateReliefPitcher(number: 21 + i),
    ];

    // ---- 控え野手 12人 ----
    final bench = <Player>[];
    int benchNumber = 30;

    // 控え捕手 1人
    bench.add(_playerGen.generateBenchFielder(
      number: benchNumber++,
      positions: [DefensePosition.catcher, DefensePosition.first],
    ));

    // 内野UT 4人（2〜3ポジション守れる）
    final infieldCombos = [
      [DefensePosition.first, DefensePosition.third],
      [DefensePosition.second, DefensePosition.shortstop],
      [DefensePosition.first, DefensePosition.second, DefensePosition.third],
      [DefensePosition.second, DefensePosition.shortstop, DefensePosition.third],
    ];
    for (final combo in infieldCombos) {
      bench.add(_playerGen.generateBenchFielder(
        number: benchNumber++,
        positions: combo,
      ));
    }

    // 外野UT 4人（外野 + 1ポジション）
    final outfieldCombos = [
      [DefensePosition.outfield],
      [DefensePosition.outfield, DefensePosition.first],
      [DefensePosition.outfield, DefensePosition.third],
      [DefensePosition.outfield],
    ];
    for (final combo in outfieldCombos) {
      bench.add(_playerGen.generateBenchFielder(
        number: benchNumber++,
        positions: combo,
      ));
    }

    // 万能UT 3人（内外野複数ポジション）
    final utilityCombos = [
      [
        DefensePosition.second,
        DefensePosition.shortstop,
        DefensePosition.outfield
      ],
      [
        DefensePosition.third,
        DefensePosition.first,
        DefensePosition.outfield
      ],
      [
        DefensePosition.outfield,
        DefensePosition.second,
        DefensePosition.third
      ],
    ];
    for (final combo in utilityCombos) {
      bench.add(_playerGen.generateBenchFielder(
        number: benchNumber++,
        positions: combo,
      ));
    }

    return Team(
      id: id,
      name: name,
      players: [startingPitcher, ...starters],
      bullpen: bullpen,
      bench: bench,
    );
  }
}

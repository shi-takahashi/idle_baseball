import 'dart:math';
import '../models/models.dart';
import 'player_generator.dart';

/// チームを自動生成する
///
/// 1チーム29人構成:
/// - 先発ローテ 6 (startingRotation、うち1人が試合ごとに players[0] に入る)
/// - スタメン野手 8 (players[1..8]: 捕/一/二/三/遊/左/中/右)
/// - 救援投手 7 (bullpen: 中継6 + 抑え1)
/// - 控え野手 8 (bench: 控え捕手1・内野UT3・外野UT2・万能UT2)
class TeamGenerator {
  final PlayerGenerator _playerGen;
  final Random _random;

  TeamGenerator({Random? random})
      : _random = random ?? Random(),
        _playerGen = PlayerGenerator(random: random);

  /// 6チームを一括生成
  List<Team> generateLeague() {
    const teamInfos = [
      (id: 'team_phoenix', name: 'フェニックス', shortName: 'P'),
      (id: 'team_dragoons', name: 'ドラグーンズ', shortName: 'D'),
      (id: 'team_comets', name: 'コメッツ', shortName: 'C'),
      (id: 'team_auroras', name: 'オーロラズ', shortName: 'A'),
      (id: 'team_thunders', name: 'サンダーズ', shortName: 'T'),
      (id: 'team_blizzards', name: 'ブリザーズ', shortName: 'B'),
    ];
    return [
      for (final info in teamInfos)
        _generateTeam(info.id, info.name, info.shortName),
    ];
  }

  Team _generateTeam(String id, String name, String shortName) {
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

    // ---- 先発ローテ 6人 ----
    // players[0] には rotation[0] を初期値として入れておく（最初の試合の先発）。
    // 以降は SeasonController が日々選んで差し替える。
    //
    // 並び順をランダムにシャッフルする狙い:
    // チームごとのローテ周期は 6日で同期しているため、もし全チームが
    // rotation[0] からスタートすると「常に A0 が B のローテ位置 X 番目と
    // 当たる」という固定マッチアップになってしまう。シャッフルすることで
    // チーム間の cycle phase がズレ、対戦カードに変化が生まれる。
    final rotation = <Player>[
      for (int i = 0; i < 6; i++)
        _playerGen.generateStartingPitcher(number: 11 + i),
    ];
    rotation.shuffle(_random);

    // ---- 救援投手 8人（ロール別構成） ----
    //   抑え 1 / セットアッパー 1 / 中継ぎ 2 / ワンポイント 1 / ロング 1 / 敗戦処理 2
    // ロールごとに能力ブースト・利き腕・スタミナ下限を調整して生成。
    final bullpen = <Player>[
      _playerGen.generateReliefPitcher(
        number: 21,
        reliefRole: ReliefRole.closer,
        abilityBoost: 1.5, // チーム最強級のリリーフ
      ),
      _playerGen.generateReliefPitcher(
        number: 22,
        reliefRole: ReliefRole.setup,
        abilityBoost: 1.0,
      ),
      _playerGen.generateReliefPitcher(
        number: 23,
        reliefRole: ReliefRole.middle,
        abilityBoost: 0.5,
      ),
      _playerGen.generateReliefPitcher(
        number: 24,
        reliefRole: ReliefRole.middle,
        abilityBoost: 0.5,
      ),
      _playerGen.generateReliefPitcher(
        number: 25,
        reliefRole: ReliefRole.situational,
        abilityBoost: 0.0,
        forcedThrows: Handedness.left, // ワンポイントは左投手
      ),
      _playerGen.generateReliefPitcher(
        number: 26,
        reliefRole: ReliefRole.long,
        abilityBoost: 0.0,
        minStamina: 7, // ロングは長いイニングを投げる必要がある
      ),
      _playerGen.generateReliefPitcher(
        number: 27,
        reliefRole: ReliefRole.mopUp,
        abilityBoost: -0.5,
      ),
      _playerGen.generateReliefPitcher(
        number: 28,
        reliefRole: ReliefRole.mopUp,
        abilityBoost: -0.5,
      ),
    ];

    // ---- 控え野手 8人 ----
    final bench = <Player>[];
    int benchNumber = 30;

    // 控え捕手 1人
    bench.add(_playerGen.generateBenchFielder(
      number: benchNumber++,
      positions: [DefensePosition.catcher, DefensePosition.first],
    ));

    // 内野UT 3人（2〜3ポジション守れる）
    final infieldCombos = [
      [DefensePosition.first, DefensePosition.third],
      [DefensePosition.second, DefensePosition.shortstop],
      [DefensePosition.second, DefensePosition.shortstop, DefensePosition.third],
    ];
    for (final combo in infieldCombos) {
      bench.add(_playerGen.generateBenchFielder(
        number: benchNumber++,
        positions: combo,
      ));
    }

    // 外野UT 2人
    final outfieldCombos = [
      [DefensePosition.outfield],
      [DefensePosition.outfield, DefensePosition.first],
    ];
    for (final combo in outfieldCombos) {
      bench.add(_playerGen.generateBenchFielder(
        number: benchNumber++,
        positions: combo,
      ));
    }

    // 万能UT 2人（内外野複数ポジション）
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
      shortName: shortName,
      players: [rotation[0], ...starters],
      startingRotation: rotation,
      bullpen: bullpen,
      bench: bench,
    );
  }
}

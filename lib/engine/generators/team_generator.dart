import 'dart:math';
import '../models/models.dart';
import 'player_generator.dart';

/// チームを自動生成する
///
/// 1チーム40人構成（投手18 / 野手22）:
/// - スタメン野手 8 (players[0..7]: 1〜8番。捕/一/二/三/遊/左/中/右)
/// - 先発ローテ 6 (startingRotation、うち1人が試合ごとに players[8]=9番 に入る)
/// - 救援投手 12 (bullpen: 抑え1 + セットアッパー2 + 中継4 + ワンポイント1 + ロング2 + 敗戦処理2)
/// - 控え野手 14 (bench: 控え捕手2・内野UT4・外野UT8)
///
/// このうち実際に各試合に出るのは「当日ベンチ入り26人」
/// （SeasonController が 40 人から日次で選定）。生成時点では 40 人プール全体を作る。
///
/// 捕手はチームに必ず 3 人（先発 1 + 控え 2）。捕手は専門性が高いポジション
/// なので、自動生成時は他ポジションを兼任しない（チーム編集画面では制約なし）。
///
/// 開幕時に各ポジションを守れる選手の人数:
///   捕手 3 / 一塁 5 / 二塁 4 / 三塁 5 / 遊撃 4 / 外野 11
/// 試合中の代打・代走で控えを使っても、守備配置を回せるだけの厚みを確保。
class TeamGenerator {
  final PlayerGenerator _playerGen;
  final Random _random;

  TeamGenerator({Random? random})
      : _random = random ?? Random(),
        _playerGen = PlayerGenerator(random: random);

  /// 6チームを一括生成
  /// 各チームに見分けやすい色を割り当てる（バナーやアイコンで使用）
  List<Team> generateLeague() {
    const teamInfos = [
      // フェニックス: 赤（不死鳥）
      (id: 'team_phoenix', name: 'フェニックス', shortName: 'P', color: 0xFFE53935),
      // ドラグーンズ: 紺（重騎兵）
      (id: 'team_dragoons', name: 'ドラグーンズ', shortName: 'D', color: 0xFF3949AB),
      // コメッツ: 黄（彗星）
      (id: 'team_comets', name: 'コメッツ', shortName: 'C', color: 0xFFFBC02D),
      // オーロラズ: 紫（オーロラ）
      (id: 'team_auroras', name: 'オーロラズ', shortName: 'A', color: 0xFF8E24AA),
      // サンダーズ: 橙（雷）
      (id: 'team_thunders', name: 'サンダーズ', shortName: 'T', color: 0xFFEF6C00),
      // ブリザーズ: 水色（吹雪）
      (id: 'team_blizzards', name: 'ブリザーズ', shortName: 'B', color: 0xFF039BE5),
    ];
    return [
      for (final info in teamInfos)
        _generateTeam(info.id, info.name, info.shortName, info.color),
    ];
  }

  Team _generateTeam(String id, String name, String shortName, int color) {
    // ---- スタメン野手8人（打順1〜8、players[0..7]の順序でデフォルト守備位置に対応） ----
    // Teamのデフォルト配置:
    // players[0]=捕 / [1]=一 / [2]=二 / [3]=三 / [4]=遊 / [5]=左 / [6]=中 / [7]=右
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
    // 背番号は 1〜40 をシャッフルして割り当てる（1チーム40人）。位置で固定
    // （捕手が必ず1番など）にすると全チーム同じ並びになり実在感が無いため。
    // 手動編集では 99 番なども可能だが、初期状態は 1〜40 に収める。
    final numberPool = [for (int i = 1; i <= 40; i++) i]..shuffle(_random);
    int numberIdx = 0;
    int nextNumber() => numberPool[numberIdx++];

    final starters = <Player>[];
    for (int i = 0; i < 8; i++) {
      starters.add(_playerGen.generateStarterFielder(
        number: nextNumber(),
        primaryPosition: starterPositions[i],
      ));
    }

    // ---- 先発ローテ 6人（うち 1 人は外国人）----
    // players[8]（=9番打者枠）には rotation[0] を初期値として入れておく（最初の試合の先発）。
    // 以降は SeasonController が日々選んで差し替える。
    //
    // 並び順をランダムにシャッフルする狙い:
    // チームごとのローテ周期は 6日で同期しているため、もし全チームが
    // rotation[0] からスタートすると「常に A0 が B のローテ位置 X 番目と
    // 当たる」という固定マッチアップになってしまう。シャッフルすることで
    // チーム間の cycle phase がズレ、対戦カードに変化が生まれる。
    // 外国人先発 1人（当たり外れ大、球速 +、制球 -）。新規チームなので teamSurnames は空。
    final foreignStarter = _playerGen.generateForeignPitcher(
      number: nextNumber(),
      pitcherRole: PitcherRole.starter,
    );
    final rotation = <Player>[
      foreignStarter,
      for (int i = 1; i < 6; i++)
        _playerGen.generateStartingPitcher(number: nextNumber()),
    ];
    rotation.shuffle(_random);

    // ---- 救援投手 12人（ロール別構成） ----
    //   抑え 1 / セットアッパー 2 / 中継ぎ 4 / ワンポイント 1 / ロング 2 / 敗戦処理 2
    // ロールごとに能力ブースト・利き腕を調整して生成。
    // 試合に出るのはこのうち当日ベンチ入りした 8 人（SeasonController が選定）。
    // ワンポイント（左投手）の指定がある以外は (role, boost) のリストで宣言的に生成。
    const reliefSpec = <({PitcherRole role, double boost, bool forceLeft})>[
      (role: PitcherRole.closer, boost: 1.5, forceLeft: false),
      (role: PitcherRole.setup, boost: 1.0, forceLeft: false),
      (role: PitcherRole.setup, boost: 1.0, forceLeft: false),
      (role: PitcherRole.middle, boost: 0.5, forceLeft: false),
      (role: PitcherRole.middle, boost: 0.5, forceLeft: false),
      (role: PitcherRole.middle, boost: 0.5, forceLeft: false),
      (role: PitcherRole.middle, boost: 0.5, forceLeft: false),
      (role: PitcherRole.situational, boost: 0.0, forceLeft: true),
      (role: PitcherRole.long, boost: 0.0, forceLeft: false),
      (role: PitcherRole.long, boost: 0.0, forceLeft: false),
      (role: PitcherRole.mopUp, boost: -0.5, forceLeft: false),
      (role: PitcherRole.mopUp, boost: -0.5, forceLeft: false),
    ];
    final bullpen = <Player>[
      for (final s in reliefSpec)
        _playerGen.generateReliefPitcher(
          number: nextNumber(),
          pitcherRole: s.role,
          abilityBoost: s.boost,
          forcedThrows: s.forceLeft ? Handedness.left : null,
        ),
    ];

    // ---- 控え野手 14人 ----
    // 当日ベンチ入りするのはこのうち 9 人（SeasonController が選定）。
    //   控え捕手 2 / 内野UT 4 / 外野UT 8（外野系には万能UTを含む）
    // 1B/3B は守備イマイチでも務まる、2B/SS は守備が得意な選手の組み合わせが多い。
    final benchCombos = <List<DefensePosition>>[
      // 控え捕手 2人（捕手は専門性が高いので兼任なし）
      [DefensePosition.catcher],
      [DefensePosition.catcher],
      // 内野UT 4人
      [DefensePosition.first, DefensePosition.third],
      [DefensePosition.first, DefensePosition.third],
      [DefensePosition.second, DefensePosition.shortstop],
      [DefensePosition.second, DefensePosition.shortstop],
      // 外野UT 8人（外野は試合中の主役で控えも厚くする）
      [DefensePosition.outfield],
      [DefensePosition.outfield],
      [DefensePosition.outfield],
      [DefensePosition.outfield, DefensePosition.first],
      [DefensePosition.outfield, DefensePosition.first],
      [DefensePosition.outfield, DefensePosition.third],
      [DefensePosition.outfield, DefensePosition.third],
      // 万能UT（内外野複数ポジション）
      [
        DefensePosition.second,
        DefensePosition.shortstop,
        DefensePosition.outfield,
      ],
    ];
    // 控え 14 のうち最後の 1 枠は外国人野手（守備位置抽選、当たり外れ大）
    final bench = <Player>[
      for (int i = 0; i < benchCombos.length - 1; i++)
        _playerGen.generateBenchFielder(
          number: nextNumber(),
          positions: benchCombos[i],
        ),
      // 外国人野手は同チームの外国人先発と同苗字にならないように除外して抽選。
      _playerGen.generateForeignFielder(
        number: nextNumber(),
        teamSurnames: {foreignSurnameOf(foreignStarter.name)},
      ),
    ];

    return Team(
      id: id,
      name: name,
      shortName: shortName,
      players: [...starters, rotation[0]],
      startingRotation: rotation,
      bullpen: bullpen,
      bench: bench,
      primaryColorValue: color,
    );
  }
}

import 'dart:math';
import '../models/models.dart';
import 'player_generator.dart';

/// チームを自動生成する
///
/// 1チーム29人構成:
/// - スタメン野手 8 (players[0..7]: 1〜8番。捕/一/二/三/遊/左/中/右)
/// - 先発ローテ 6 (startingRotation、うち1人が試合ごとに players[8]=9番 に入る)
/// - 救援投手 7 (bullpen: 中継6 + 抑え1)
/// - 控え野手 8 (bench: 控え捕手2・内野UT2・外野UT3・万能UT1)
///
/// 捕手はチームに必ず 3 人（先発 1 + 控え 2）。捕手は専門性が高いポジション
/// なので、自動生成時は他ポジションを兼任しない（チーム編集画面では制約なし）。
///
/// 開幕時に各ポジションを守れる選手の人数:
///   捕手 3 / 一塁 3 / 二塁 3 / 三塁 3 / 遊撃 3 / 外野 7
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
    // 背番号はランダムに割り当てる。位置で固定（捕手が必ず1番など）にすると
    // 全チーム同じ並びになり実在感が無いため。主力ほど若い番号・控えほど
    // 大きい番号、というゆるい傾向だけ役割ごとの範囲で持たせる。
    final usedNumbers = <int>{};

    final starters = <Player>[];
    for (int i = 0; i < 8; i++) {
      starters.add(_playerGen.generateStarterFielder(
        number: _pickNumber(1, 48, usedNumbers),
        primaryPosition: starterPositions[i],
      ));
    }

    // ---- 先発ローテ 6人 ----
    // players[8]（=9番打者枠）には rotation[0] を初期値として入れておく（最初の試合の先発）。
    // 以降は SeasonController が日々選んで差し替える。
    //
    // 並び順をランダムにシャッフルする狙い:
    // チームごとのローテ周期は 6日で同期しているため、もし全チームが
    // rotation[0] からスタートすると「常に A0 が B のローテ位置 X 番目と
    // 当たる」という固定マッチアップになってしまう。シャッフルすることで
    // チーム間の cycle phase がズレ、対戦カードに変化が生まれる。
    final rotation = <Player>[
      for (int i = 0; i < 6; i++)
        _playerGen.generateStartingPitcher(
            number: _pickNumber(11, 48, usedNumbers)),
    ];
    rotation.shuffle(_random);

    // ---- 救援投手 8人（ロール別構成） ----
    //   抑え 1 / セットアッパー 1 / 中継ぎ 2 / ワンポイント 1 / ロング 1 / 敗戦処理 2
    // ロールごとに能力ブースト・利き腕・スタミナ下限を調整して生成。
    final bullpen = <Player>[
      _playerGen.generateReliefPitcher(
        number: _pickNumber(11, 69, usedNumbers),
        reliefRole: ReliefRole.closer,
        abilityBoost: 1.5, // チーム最強級のリリーフ
      ),
      _playerGen.generateReliefPitcher(
        number: _pickNumber(11, 69, usedNumbers),
        reliefRole: ReliefRole.setup,
        abilityBoost: 1.0,
      ),
      _playerGen.generateReliefPitcher(
        number: _pickNumber(11, 69, usedNumbers),
        reliefRole: ReliefRole.middle,
        abilityBoost: 0.5,
      ),
      _playerGen.generateReliefPitcher(
        number: _pickNumber(11, 69, usedNumbers),
        reliefRole: ReliefRole.middle,
        abilityBoost: 0.5,
      ),
      _playerGen.generateReliefPitcher(
        number: _pickNumber(11, 69, usedNumbers),
        reliefRole: ReliefRole.situational,
        abilityBoost: 0.0,
        forcedThrows: Handedness.left, // ワンポイントは左投手
      ),
      _playerGen.generateReliefPitcher(
        number: _pickNumber(11, 69, usedNumbers),
        reliefRole: ReliefRole.long,
        abilityBoost: 0.0,
        minStamina: 7, // ロングは長いイニングを投げる必要がある
      ),
      _playerGen.generateReliefPitcher(
        number: _pickNumber(11, 69, usedNumbers),
        reliefRole: ReliefRole.mopUp,
        abilityBoost: -0.5,
      ),
      _playerGen.generateReliefPitcher(
        number: _pickNumber(11, 69, usedNumbers),
        reliefRole: ReliefRole.mopUp,
        abilityBoost: -0.5,
      ),
    ];

    // ---- 控え野手 8人 ----
    // 控えは大きめの番号（40〜88）。
    final bench = <Player>[];

    // 控え捕手 2人（捕手は専門性が高いので兼任なし）
    for (int i = 0; i < 2; i++) {
      bench.add(_playerGen.generateBenchFielder(
        number: _pickNumber(40, 88, usedNumbers),
        positions: [DefensePosition.catcher],
      ));
    }

    // 内野UT 2人（2〜3ポジション守れる）
    // 1B/3B は守備イマイチでも務まる、2B/SS は守備が得意な選手の組み合わせが多い
    final infieldCombos = [
      [DefensePosition.first, DefensePosition.third],
      [DefensePosition.second, DefensePosition.shortstop],
    ];
    for (final combo in infieldCombos) {
      bench.add(_playerGen.generateBenchFielder(
        number: _pickNumber(40, 88, usedNumbers),
        positions: combo,
      ));
    }

    // 外野UT 3人（外野は試合中の主役で控えも厚くする）
    final outfieldCombos = [
      [DefensePosition.outfield],
      [DefensePosition.outfield, DefensePosition.first],
      [DefensePosition.outfield, DefensePosition.third],
    ];
    for (final combo in outfieldCombos) {
      bench.add(_playerGen.generateBenchFielder(
        number: _pickNumber(40, 88, usedNumbers),
        positions: combo,
      ));
    }

    // 万能UT 1人（内外野複数ポジション）
    bench.add(_playerGen.generateBenchFielder(
      number: _pickNumber(40, 88, usedNumbers),
      positions: [
        DefensePosition.second,
        DefensePosition.shortstop,
        DefensePosition.outfield,
      ],
    ));

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

  /// 未使用の背番号を [min]〜[max] からランダムに 1 つ選び、[used] に追加して返す。
  /// 範囲がすべて埋まっていたら [min] から上方向へ走査してフォールバックする。
  int _pickNumber(int min, int max, Set<int> used) {
    for (int attempt = 0; attempt < 200; attempt++) {
      final n = min + _random.nextInt(max - min + 1);
      if (used.add(n)) return n;
    }
    int n = min;
    while (!used.add(n)) {
      n++;
    }
    return n;
  }
}

import 'dart:math';
import '../models/models.dart';
import 'player_generator.dart';

/// チームを自動生成する
///
/// 1チーム40人構成（投手20 / 野手20）:
/// - スタメン野手 8 (players[0..7]: 1〜8番。捕/一/二/三/遊/左/中/右)
/// - 先発ローテ 6 (startingRotation、うち1人が試合ごとに players[8]=9番 に入る)
/// - 救援投手 14 (bullpen: 抑え1 + セットアッパー2 + 中継6 + ワンポイント1 + ロング2 + 敗戦処理2)
/// - 控え野手 12 (bench: 控え捕手2・内野UT4・外野UT6)
///
/// このうち実際に各試合に出るのは「当日ベンチ入り26人」（投手 9 + 野手 17）
/// （SeasonController が 40 人から日次で選定）。生成時点では 40 人プール全体を作る。
///
/// **設計**: 投手 20 / 野手 20 にすることで、引退 3 名/チーム/年が両者で
/// 同じ世代交代率 (15%/年) となり、ピーク年齢層比率も対称化する。これにより
/// 投手と野手の能力分布が対称的になる（[feedback_unified_logic_principle]）。
///
/// 捕手はチームに必ず 3 人（先発 1 + 控え 2）。捕手は専門性が高いポジション
/// なので、自動生成時は他ポジションを兼任しない（チーム編集画面では制約なし）。
///
/// 開幕時に各ポジションを守れる選手の人数:
///   捕手 3 / 一塁 4 / 二塁 3 / 三塁 4 / 遊撃 3 / 外野 8
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
    // 背番号は 1〜40 をシャッフルして割り当てる（1チーム40人）。位置で固定
    // （捕手が必ず1番など）にすると全チーム同じ並びになり実在感が無いため。
    // 手動編集では 99 番なども可能だが、初期状態は 1〜40 に収める。
    final numberPool = [for (int i = 1; i <= 40; i++) i]..shuffle(_random);
    int numberIdx = 0;
    int nextNumber() => numberPool[numberIdx++];

    // ---- 投手 20人（日本人 18 + 外国人 2、役割なしフラット生成 → 能力ベース割り当て） ----
    // 設計（2026-05-23）:
    // 旧版は生成時に「先発6 / 抑え1 / セットアッパー2 / 中継ぎ4 / ...」と役割別に
    // 能力 boost をつけて生成していた（reliefSpec）。さらに外国人 2 人は両方 starter
    // で固定生成 → 「外国人投手が全員先発」という不自然な構造になっていた。
    //
    // 新版は 18 人を全員フラット (mean=5 / role なし) で生成し、能力スコア順に
    // ロールを割り当てる。日本人・外国人の区別なく、能力に応じた役割になる:
    //   1位     → 先発エース
    //   2-6位   → 先発ローテ
    //   7位     → 抑え（最強の救援）
    //   8-9位   → セットアッパー
    //   10-13位 → 中継ぎ 4 人
    //   14-15位 → ロング 2 人
    //   16位    → ワンポイント（左投手いれば優先、なければ右投手）
    //   17-18位 → 敗戦処理 2 人
    // 外国人投手は球速 +3 km/h 等の生成バフがあるので、自然と先発・抑え寄りに
    // 割り当てられやすい。ただしハズレ外国人（能力ガチャ次第）は敗戦処理に
    // 回ることもある。これが「外国人だけ特別扱いせず、能力ベースで役割を決める」設計。
    //
    // 自チームについては SeasonController.newSeason で「中立な初期ロール
    // （先発6→starter / 救援12→middle）」に上書きされる（推測ゲームのリーク防止、
    // [feedback_no_ability_based_auto_assignment]）。CPU 5 球団はこの能力割り当てを
    // そのまま使う。
    final pitcherPool = <Player>[];

    // 外国人投手 2 人を生成（苗字重複回避）。pitcherRole は後で割り当てるので null。
    final foreignSurnamesUsed = <String>{};
    for (int i = 0; i < 2; i++) {
      final fp = _playerGen.generateForeignPitcher(
        number: nextNumber(),
        pitcherRole: null,
        teamSurnames: foreignSurnamesUsed,
      );
      pitcherPool.add(fp);
      foreignSurnamesUsed.add(foreignSurnameOf(fp.name));
    }

    // 日本人投手 18 人をフラット生成
    for (int i = 0; i < 18; i++) {
      pitcherPool.add(_playerGen.generatePitcher(number: nextNumber()));
    }

    // 能力スコア順に並べてロール割り当て
    assignPitcherRoles(pitcherPool);

    // rotation 6 (starter) と bullpen 12 (それ以外) に振り分け
    // rotation は登板順序をランダムシャッフル（チーム間の cycle phase をずらす）
    final rotation = pitcherPool
        .where((p) => p.pitcherRole == PitcherRole.starter)
        .toList()
      ..shuffle(_random);
    final bullpen = pitcherPool
        .where((p) => p.pitcherRole != PitcherRole.starter)
        .toList();

    // ---- 野手 20人（日本人 18 + 外国人 2、全員フラット生成 → 能力ベースでスタメン選定） ----
    // 設計（2026-05-23）:
    // 旧版は「スタメン用 8 名 (mean 5.0) + 控え用 12 名 (mean 4.5) + 外国人 2 名」と、
    // 生成時に役割（スタメン or 控え）と能力差を仕込んでいた。これは「最初から
    // スタメン枠の選手」「最初から控え枠の選手」が固定される構造で、現実の
    // プロ野球（22 人の選手がいて監督が能力で選ぶ）と乖離する。
    //
    // 新版は 22 人全員をフラット (mean 5.0) で生成し、能力スコア順にポジション別に
    // スタメン 8 名を選定する。日本人・外国人の区別なく、能力が高い選手がスタメン、
    // 能力が低い選手が控え → 当日ベンチ入り選定で外れて事実上ベンチ外、となる。
    // 外国人野手は power +0.5 等の国籍別オフセットで結果的にスタメンに上がりやすいが、
    // ハズレ外国人は控えに回る（NPB 実態に合致）。
    //
    // 自チームについては SeasonController.newSeason で背番号順に中立化される
    // （推測ゲームのリーク防止、[feedback_no_ability_based_auto_assignment]）。
    final fielderPool = <Player>[];

    // 外国人野手 2 人を生成（守備位置抽選、苗字重複回避）
    final foreignFielderSurnames = <String>{};
    for (int i = 0; i < 2; i++) {
      final ff = _playerGen.generateForeignFielder(
        number: nextNumber(),
        teamSurnames: foreignFielderSurnames,
      );
      fielderPool.add(ff);
      foreignFielderSurnames.add(foreignSurnameOf(ff.name));
    }

    // 日本人野手 18 人をポジションパターン付きでフラット生成。
    // 各ポジションを守れる選手数の最低ライン (日本人 18 + 外国人 2 = 20 名):
    //   捕手 3 / 一塁 4+ / 二塁 3+ / 三塁 4+ / 遊撃 3+ / 外野 8+
    // スタメン 8 名（捕1/一1/二1/三1/遊1/外3）を選定でき、当日ベンチ入り
    // 17 名（スタメン 8 + 控え 9）も回せる厚みを確保。
    const fielderPositionPatterns = <List<DefensePosition>>[
      // 捕手 3 名（専門性が高いので兼任なし）
      [DefensePosition.catcher],
      [DefensePosition.catcher],
      [DefensePosition.catcher],
      // 内野手 7 名（一/三、二/遊 を兼任するパターンが多い）
      [DefensePosition.first],
      [DefensePosition.first, DefensePosition.third],
      [DefensePosition.second],
      [DefensePosition.second, DefensePosition.shortstop],
      [DefensePosition.third],
      [DefensePosition.shortstop],
      [DefensePosition.first, DefensePosition.third, DefensePosition.outfield],
      // 外野手 8 名（外野単独 4、内外野兼任 3、万能UT 1）
      [DefensePosition.outfield],
      [DefensePosition.outfield],
      [DefensePosition.outfield],
      [DefensePosition.outfield],
      [DefensePosition.outfield, DefensePosition.first],
      [DefensePosition.outfield, DefensePosition.first],
      [DefensePosition.outfield, DefensePosition.third],
      [
        DefensePosition.second,
        DefensePosition.shortstop,
        DefensePosition.outfield,
      ],
    ];
    for (final pattern in fielderPositionPatterns) {
      fielderPool.add(_playerGen.generateFielder(
        number: nextNumber(),
        positions: pattern,
      ));
    }

    // 能力ベースでポジション別にスタメン 8 名を選定（捕/一/二/三/遊/外/外/外）。
    // 残り 14 名は bench に。
    final starters = _selectFielderStarters(fielderPool);
    final benchedFielders = fielderPool
        .where((p) => !starters.contains(p))
        .toList();

    return Team(
      id: id,
      name: name,
      shortName: shortName,
      players: [...starters, rotation[0]],
      startingRotation: rotation,
      bullpen: bullpen,
      bench: benchedFielders,
      primaryColorValue: color,
    );
  }

  /// 20 人の投手をフラット生成した後、能力スコア順にロールを割り当てる。
  ///
  /// 割り当て規則（能力スコア降順）:
  ///   1-6位   → starter（先発ローテ 6 人）
  ///   7位     → closer（抑え 1 人）
  ///   8-9位   → setup（セットアッパー 2 人）
  ///   10-15位 → middle（中継ぎ 6 人）
  ///   16-17位 → long（ロング 2 人）
  ///   18位    → situational（ワンポイント、左投手優先）
  ///   19-20位 → mopUp（敗戦処理 2 人）
  ///
  /// situational は左投手としての特殊起用なので、能力順位 18 位ぴったりの
  /// 投手より「中継ぎ系の中で能力が比較的下位の左投手」を優先する。
  /// 左投手がいなければ右投手のまま situational に割り当てる。
  ///
  /// オフシーズン後の再評価（[TeamRebuilder]）からも static で呼べるよう公開。
  /// 入力リストの要素を `withPitcherRole` で差し替える破壊的更新。
  static void assignPitcherRoles(List<Player> pitchers) {
    // 能力スコア降順でソート
    final sorted = [...pitchers]
      ..sort((a, b) =>
          _pitcherAbilityScore(b).compareTo(_pitcherAbilityScore(a)));

    // 順位 → 役割の割当（20 名構成）
    const roleByRank = <PitcherRole>[
      PitcherRole.starter, // 1
      PitcherRole.starter, // 2
      PitcherRole.starter, // 3
      PitcherRole.starter, // 4
      PitcherRole.starter, // 5
      PitcherRole.starter, // 6
      PitcherRole.closer, // 7
      PitcherRole.setup, // 8
      PitcherRole.setup, // 9
      PitcherRole.middle, // 10
      PitcherRole.middle, // 11
      PitcherRole.middle, // 12
      PitcherRole.middle, // 13
      PitcherRole.middle, // 14
      PitcherRole.middle, // 15
      PitcherRole.long, // 16
      PitcherRole.long, // 17
      PitcherRole.situational, // 18
      PitcherRole.mopUp, // 19
      PitcherRole.mopUp, // 20
    ];

    // situational 用に左投手を優先選択する。割当 18 位の投手が右投手の場合、
    // bullpen 圏内（7〜20位）の左投手と入れ替えてその左投手を situational に。
    // 入れ替えで動く相手の元ロールを 18 位だった投手に渡す。
    final situationalIdx = roleByRank.indexOf(PitcherRole.situational);
    if (sorted[situationalIdx].effectiveThrows != Handedness.left) {
      // 7〜20 位の中から左投手を探す（先発エース層は崩さない）
      int? leftIdx;
      for (int i = 6; i < sorted.length; i++) {
        if (i == situationalIdx) continue;
        if (sorted[i].effectiveThrows == Handedness.left) {
          leftIdx = i;
          break;
        }
      }
      if (leftIdx != null) {
        // 順序を swap（能力スコア順は崩れるが、situational に左投手を割り当てる方を優先）
        final tmp = sorted[situationalIdx];
        sorted[situationalIdx] = sorted[leftIdx];
        sorted[leftIdx] = tmp;
      }
    }

    // ロールを書き換えて、元の pitchers リストに反映
    for (int i = 0; i < sorted.length; i++) {
      final updated = sorted[i].withPitcherRole(roleByRank[i]);
      final idx = pitchers.indexWhere((p) => p.id == sorted[i].id);
      if (idx >= 0) pitchers[idx] = updated;
    }
  }

  /// 20 名の野手プールから、能力スコア順にポジション別スタメン 8 名を選ぶ。
  ///
  /// 選定順序: 捕 → 一 → 二 → 三 → 遊 → 外 → 外 → 外
  /// 各ポジションについて「そのポジションを守れる未選定の選手」の中で能力スコア
  /// 最上位を選ぶ。ユーティリティ性のある選手（一/三や二/遊 兼任）は、後の
  /// ポジションでの選定にも回せるため、捕手・専門性の高いポジションから順に
  /// 確定させていく greedy 法。
  ///
  /// 万一そのポジションを守れる選手が枯渇した場合（外国人ガチャの結果に依る）は、
  /// 残った中で能力スコア最上位を「強制配置」（守れないポジションに配置）する。
  /// LineupPlanner と同じ挙動で、強制配置中はエラー率 ×3 のペナルティが乗る。
  ///
  /// 自チームは SeasonController.newSeason で「背番号順に中立化」されるため、
  /// この能力ベース選定が反映されるのは CPU 5 球団のみ。
  List<Player> _selectFielderStarters(List<Player> pool) {
    const slotPositions = [
      DefensePosition.catcher,
      DefensePosition.first,
      DefensePosition.second,
      DefensePosition.third,
      DefensePosition.shortstop,
      DefensePosition.outfield,
      DefensePosition.outfield,
      DefensePosition.outfield,
    ];
    final starters = <Player>[];
    final usedIds = <String>{};
    for (final pos in slotPositions) {
      final candidates = pool
          .where((p) => !usedIds.contains(p.id) && p.canPlay(pos))
          .toList()
        ..sort((a, b) =>
            _fielderAbilityScore(b).compareTo(_fielderAbilityScore(a)));
      final chosen = candidates.isNotEmpty
          ? candidates.first
          : (pool
                  .where((p) => !usedIds.contains(p.id))
                  .toList()
                ..sort((a, b) =>
                    _fielderAbilityScore(b).compareTo(_fielderAbilityScore(a))))
              .first;
      starters.add(chosen);
      usedIds.add(chosen.id);
    }
    return starters;
  }

  /// 野手の能力スコア（高いほど強い）。
  /// 打撃 4 能力 + 走力 + 肩 + 主守備位置の守備力 の平均。
  static double _fielderAbilityScore(Player p) {
    final values = <double>[
      (p.meet ?? 5).toDouble(),
      (p.power ?? 5).toDouble(),
      (p.eye ?? 5).toDouble(),
      (p.speed ?? 5).toDouble(),
      (p.arm ?? 5).toDouble(),
    ];
    // 主守備位置の守備力も加味（守れない場合は 0）
    final bestFielding = (p.fielding ?? const {})
        .values
        .fold<int>(0, (a, b) => a > b ? a : b);
    if (bestFielding > 0) {
      values.add(bestFielding.toDouble());
    }
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// 投手の能力スコア（高いほど強い）。
  /// 球速・伸び・制球・最強変化球の質の平均で評価する。
  /// [TeamRebuilder._abilityScore] と同じ式（共通化はしていないが式は一致）。
  static double _pitcherAbilityScore(Player p) {
    final speed = (p.averageSpeed ?? 145).toDouble();
    final speedScale = ((speed - 130) / 30.0 * 10).clamp(1.0, 10.0);
    final values = <double>[
      speedScale,
      (p.fastball ?? 5).toDouble(),
      (p.control ?? 5).toDouble(),
    ];
    final pitches = <int>[
      if (p.slider != null) p.slider!,
      if (p.curve != null) p.curve!,
      if (p.splitter != null) p.splitter!,
      if (p.changeup != null) p.changeup!,
      if (p.shoot != null) p.shoot!,
      if (p.cutter != null) p.cutter!,
      if (p.sinker != null) p.sinker!,
    ];
    if (pitches.isNotEmpty) {
      values.add(pitches.reduce((a, b) => a > b ? a : b).toDouble());
    }
    return values.reduce((a, b) => a + b) / values.length;
  }
}

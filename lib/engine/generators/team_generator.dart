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

    // ---- 投手 18人（日本人 16 + 外国人 2、役割なしフラット生成 → 能力ベース割り当て） ----
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

    // 日本人投手 16 人をフラット生成
    for (int i = 0; i < 16; i++) {
      pitcherPool.add(_playerGen.generatePitcher(number: nextNumber()));
    }

    // 能力スコア順に並べてロール割り当て
    _assignPitcherRoles(pitcherPool);

    // rotation 6 (starter) と bullpen 12 (それ以外) に振り分け
    // rotation は登板順序をランダムシャッフル（チーム間の cycle phase をずらす）
    final rotation = pitcherPool
        .where((p) => p.pitcherRole == PitcherRole.starter)
        .toList()
      ..shuffle(_random);
    final bullpen = pitcherPool
        .where((p) => p.pitcherRole != PitcherRole.starter)
        .toList();

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
    // 控え 14 のうち最後の 2 枠は外国人野手（守備位置抽選、当たり外れ大）
    final foreignFielder1 = _playerGen.generateForeignFielder(
      number: nextNumber(),
      teamSurnames: foreignSurnamesUsed,
    );
    final foreignFielder2 = _playerGen.generateForeignFielder(
      number: nextNumber(),
      teamSurnames: {
        ...foreignSurnamesUsed,
        foreignSurnameOf(foreignFielder1.name),
      },
    );
    final bench = <Player>[
      for (int i = 0; i < benchCombos.length - 2; i++)
        _playerGen.generateBenchFielder(
          number: nextNumber(),
          positions: benchCombos[i],
        ),
      foreignFielder1,
      foreignFielder2,
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

  /// 18 人の投手をフラット生成した後、能力スコア順にロールを割り当てる。
  ///
  /// 割り当て規則（能力スコア降順）:
  ///   1-6位   → starter（先発ローテ 6 人）
  ///   7位     → closer（抑え 1 人）
  ///   8-9位   → setup（セットアッパー 2 人）
  ///   10-13位 → middle（中継ぎ 4 人）
  ///   14-15位 → long（ロング 2 人）
  ///   16位    → situational（ワンポイント、左投手優先）
  ///   17-18位 → mopUp（敗戦処理 2 人）
  ///
  /// situational は左投手としての特殊起用なので、能力順位 16 位ぴったりの
  /// 投手より「中継ぎ系の中で能力が比較的下位の左投手」を優先する。
  /// 左投手がいなければ右投手のまま situational に割り当てる。
  /// long も球速の遅い投手の方が適性が高いが、本実装では能力順のみで割り当てる
  /// （シンプル化、必要なら後で球速ソートを足す）。
  void _assignPitcherRoles(List<Player> pitchers) {
    // 能力スコア降順でソート
    final sorted = [...pitchers]
      ..sort((a, b) =>
          _pitcherAbilityScore(b).compareTo(_pitcherAbilityScore(a)));

    // 順位 → 役割の割当
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
      PitcherRole.long, // 14
      PitcherRole.long, // 15
      PitcherRole.situational, // 16
      PitcherRole.mopUp, // 17
      PitcherRole.mopUp, // 18
    ];

    // situational 用に左投手を優先選択する。割当 16 位の投手が右投手の場合、
    // bullpen 圏内（7〜18位）の左投手と入れ替えてその左投手を situational に。
    // 入れ替えで動く相手の元ロールを 16 位だった投手に渡す。
    final situationalIdx = roleByRank.indexOf(PitcherRole.situational);
    if (sorted[situationalIdx].effectiveThrows != Handedness.left) {
      // 7〜18 位の中から左投手を探す（先発エース層は崩さない）
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

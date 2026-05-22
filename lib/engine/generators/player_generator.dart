import 'dart:math';
import '../models/models.dart';
import 'name_data.dart';
import 'random_utils.dart';

/// 守備位置による打撃・走力傾向のオフセット。
///
/// 能力値生成時の **平均（mean）に加算** し、標準偏差（sd 1.5）は変えない。
/// これにより「一塁手はだいたい長打あり鈍足」という傾向は明確に出るが、
/// ハードな分岐ではないので、分布の裾で例外（大型遊撃手・打てる捕手）が
/// 数%の確率で自然に発生する。
class _PositionalProfile {
  final double meet;
  final double power;
  final double speed;
  final double arm;
  const _PositionalProfile({
    this.meet = 0,
    this.power = 0,
    this.speed = 0,
    this.arm = 0,
  });
}

/// 選手を自動生成する
///
/// - 名前は苗字＋名前のランダム組み合わせで、同一ジェネレーター内では重複しない
/// - 能力値は平均5・標準偏差1.5の正規分布で1〜10にクリップ
/// - 守備位置ごとに打撃・走力の平均をオフセット（[_profileForPosition]）。
///   一三塁＝長打型、二遊＝俊足型、捕手＝打撃控えめ、外野＝3型を抽選。
/// - ポテンシャル（[Player.potentials] / [Player.potentialFielding] /
///   [Player.potentialAverageSpeed]）は生成時に確定し、加齢成長時の上限となる
class PlayerGenerator {
  final RandomUtils _r;
  final Set<String> _usedNames;
  int _idCounter;

  // ---- ポテンシャル算出パラメータ（素質ガチャ方式） ----
  //
  // 設計: 「線形に initial + 一律マージン」ではなく、能力ごとに **素質レベル** を
  // 独立抽選して非線形に伸びしろを決める。
  //
  //   普通型 70%: cap = round(initial + gauss(mean=0.4, sd=0.4))、cap上限 = 7
  //     → 入団時の能力でほぼ確定、プロでもほとんど伸びない大多数の選手
  //   中位型 25%: cap = round(initial + gauss(mean=1.5, sd=0.6))、cap上限 = 8
  //     → 中堅レベルまで伸びる選手。「7 で優秀」の層に入る可能性
  //   素質型  5%: cap = round(initial + gauss(mean=3.0, sd=0.8))、cap上限 = 9
  //     → 一握りの「9 に届く可能性のある」素質型。それでも initial が低いと届かない
  //
  // 9 に届くには「素質型(5%) × initial 6 以上(~55%) × 成長運」が必要。
  // リーグ 132 野手で素質型 ≈ 7 人、その中で initial 6+ ≈ 4 人。さらに成長カーブの
  // 確率性で実際に 9 まで伸びるのはその一部 → 平衡で 0〜2 人 / リーグ。
  static const double _talentMiddleChance = 0.30;
  static const double _talentEliteChance = 0.05;

  /// 素質レベル別の成長マージン平均 / sd / cap上限。
  /// key: 'normal' / 'middle' / 'elite'
  ///
  /// cap の設計:
  ///   normal: cap=7 → 大多数の選手は 7 までで頭打ち
  ///   middle: cap=8 → 中位の選手は 8 まで届きうる（「タイトル争いの 8」を支える層）
  ///   elite:  cap=9 → 一握りの素質型だけが 9 に届きうる
  ///
  /// 中位/素質型の比率はリーグの「8 が常時 3〜5 人」を維持するよう調整。
  /// 確率の和: normal 65% + middle 30% + elite 5% = 100%。
  static const Map<String, ({double mean, double sd, int cap})> _talentTiers = {
    'normal': (mean: 0.4, sd: 0.4, cap: 7),
    'middle': (mean: 1.5, sd: 0.6, cap: 8),
    'elite': (mean: 3.0, sd: 0.8, cap: 9),
  };

  /// 守備力（fielding map 内の各ポジション値）も同じ素質ガチャ方式を使う。
  /// 技術系で大きく伸びうる性質を残すため、素質型の確率を 8% に上げる。
  static const double _fieldingTalentEliteChance = 0.08;
  static const double _fieldingTalentMiddleChance = 0.30;
  // 球速 (km/h) のポテンシャル成長マージン。
  // 平均 +5 km/h、ガウス揺らぎ sd=2 で「+1 〜 +9 km/h」のレンジ。
  // 高卒 boost (+1.5 × 2 = +3 km/h) と組み合わせると「+4 〜 +12 km/h」になり、
  // 大谷型「高卒157→165 (+8)」や田中型「高卒155→ピーク160 (+5)」の双方が
  // 出現可能。多くの選手は +3〜+6 km/h 程度の伸び。
  static const double _speedBaseMargin = 5.0;
  static const double _speedSd = 2.0;
  // 球速の自然上限。147 km/h ≒ ability 5、160 km/h ≒ ability 10 のマッピングで、
  // 1〜10 能力の ceiling=9 と同様に「ability 9 相当 = 158 km/h」で抑える。
  // initial >= 158 の選手は initial 値を維持（clamp の lower で吸収）。
  // 編集 UI からは 165 km/h まで設定可能だが、自然生成・成長では出ない。
  static const int _speedCeiling = 158;

  /// 新人タイプ別のポテンシャルボーナス（mean に加算）
  /// - 高卒: +1.5（伸びしろ重視、初期値は低いが将来性は高い）
  /// - 大卒: 0.0
  /// - 社会人: -0.5（即戦力だが伸び鈍）
  /// - 既存リーグ生成（rookie でない）: 0.0
  static double _potentialBonusForRookieType(RookieType? type) {
    switch (type) {
      case RookieType.highSchool:
        return 1.5;
      case RookieType.college:
        return 0.0;
      case RookieType.corporate:
        return -0.5;
      case null:
        return 0.0;
    }
  }

  /// - [random]: RNG
  /// - [idStart]: id 連番の開始値（ロード時に既存選手の最大 id を渡してデフォ値を超えないようにする）
  /// - [usedNames]: すでに使われている名前。ロード時に渡せばシーズン跨ぎでの重複を回避
  PlayerGenerator({
    Random? random,
    int idStart = 0,
    Set<String>? usedNames,
  })  : _r = RandomUtils(random),
        _idCounter = idStart,
        _usedNames = usedNames ?? <String>{};

  /// 先発投手を生成
  Player generateStartingPitcher({required int number}) {
    return _generatePitcher(number: number, isStarter: true);
  }

  /// 役割なしのフラット投手を生成する。リーグ生成時に「18人をフラット生成
  /// → 能力ベースでロール割り当て」する用途で使う。
  ///
  /// `isStarter` は球種選択等のロジックには影響しないが、生成時に
  /// `pitcherRole` を null にしておき、呼び出し側で能力スコアを見て
  /// 後からロールを割り当てる前提。
  Player generatePitcher({required int number}) {
    return _generatePitcher(
      number: number,
      isStarter: true,
      pitcherRole: null,
    );
  }

  /// 救援投手を生成
  ///
  /// - [pitcherRole]: 救援ロール（指定すれば Player.pitcherRole にセットされる）
  /// - [abilityBoost]: 能力値の平均オフセット（+1.0 でエース級、-1.0 で控え級）
  /// - [forcedThrows]: 利き腕を強制（例: situational lefty）
  Player generateReliefPitcher({
    required int number,
    PitcherRole? pitcherRole,
    double abilityBoost = 0.0,
    Handedness? forcedThrows,
  }) {
    return _generatePitcher(
      number: number,
      isStarter: false,
      pitcherRole: pitcherRole,
      abilityBoost: abilityBoost,
      forcedThrows: forcedThrows,
    );
  }

  Player _generatePitcher({
    required int number,
    required bool isStarter,
    PitcherRole? pitcherRole,
    double abilityBoost = 0.0,
    Handedness? forcedThrows,
    int? ageOverride,
    RookieType? rookieType,
  }) {
    // 球速: NPB 平均の 147 km/h を中心に正規分布（sd=3）
    // - 自動生成は「だいたい 140〜155 km/h」に収まるよう sd を絞り clamp [139,156]。
    //   現代プロに 140 km/h 未満は稀、常時 160 km/h 超もほぼいないため。
    // - 140 未満 / 156 超の特殊な投手は編集 UI（最大 165 km/h）からのみ作成可能。
    // - abilityBoost 1 ポイントごとに +2 km/h（抑え・エースは速い）
    final speedMean = 147.0 + abilityBoost * 2.0;
    final avgSpeed =
        (speedMean + _r.nextGaussian() * 3.0).round().clamp(139, 156);

    // 球種: ストレート + 変化球。各変化球を独立確率で抽選する。保有確率は
    // NPB 2016 の「投じた投手の割合」（images/breaking-ball.png）に準拠。
    // 「どれだけ投げるか」は別要素（at_bat_simulator の _pitchTypeUsageWeight）で
    // 表現するため、ここは「誰が持つか」だけを決める。
    // 例外: シュート/シンカーは画像（49.8% / 12.6%）だとシンカー保有者が少なすぎ
    // 投球割合を 5% 弱まで上げられないため、ツーシームの分類が曖昧なことも踏まえ
    // 両者を対称に 33% へ均した。変化球を全く持たない投手はいないため最低 2 種類を
    // 保証し（合計ストレート込み 3 種類）、現実的な上限として変化球は最大 5 種類。
    const breakingProbs = <String, double>{
      'slider': 0.88,
      'curve': 0.70,
      'splitter': 0.58,
      'changeup': 0.39,
      'shoot': 0.33,
      'cutter': 0.27,
      'sinker': 0.33,
    };
    final chosen = <String>[];
    for (final e in breakingProbs.entries) {
      if (_r.chance(e.value)) chosen.add(e.key);
    }
    // 最低 2 種類保証（不足ぶんは保有率の高い球種から順に補う）
    while (chosen.length < 2) {
      chosen.add(breakingProbs.keys.firstWhere((k) => !chosen.contains(k)));
    }
    // 最大 5 種類（超過ぶんはランダムに外す）
    while (chosen.length > 5) {
      chosen.removeAt(_r.random.nextInt(chosen.length));
    }
    // 変化球の質は全球種共通で平均 5（abilityBoost で底上げ）。「どれだけ投げるか」は
    // 質ではなく球種別の使用頻度重み（at_bat_simulator の _pitchTypeUsageWeight）で
    // 表現する。質＝被打率・空振り、使用頻度＝投球割合、と役割を分離している。
    int? slider, curve, splitter, changeup, shoot, cutter, sinker;
    for (final t in chosen) {
      final v = _r.abilityInt(mean: 5.0 + abilityBoost);
      switch (t) {
        case 'slider':
          slider = v;
          break;
        case 'curve':
          curve = v;
          break;
        case 'splitter':
          splitter = v;
          break;
        case 'changeup':
          changeup = v;
          break;
        case 'shoot':
          shoot = v;
          break;
        case 'cutter':
          cutter = v;
          break;
        case 'sinker':
          sinker = v;
          break;
      }
    }

    // 投手の利き腕: forcedThrows 指定があればそれ、なければ 右70%・左30%
    final throws = forcedThrows ??
        (_r.chance(0.3) ? Handedness.left : Handedness.right);

    final fastball = _r.abilityInt(mean: 5.0 + abilityBoost);
    final control = _r.abilityInt(mean: 5.0 + abilityBoost);
    final meet = _r.normalInt(mean: 2.0, sd: 0.8);
    final power = _r.normalInt(mean: 1.5, sd: 0.7);
    final eye = _r.normalInt(mean: 2.5, sd: 0.8);
    final speed = _r.normalInt(mean: 3.5, sd: 1.5);

    final potentialBonus = _potentialBonusForRookieType(rookieType);

    return Player(
      id: _newId(),
      name: _uniqueName(),
      number: number,
      age: ageOverride ?? _generateAge(),
      averageSpeed: avgSpeed,
      fastball: fastball,
      control: control,
      slider: slider,
      curve: curve,
      splitter: splitter,
      changeup: changeup,
      shoot: shoot,
      cutter: cutter,
      sinker: sinker,
      throws: throws,
      // 投手の打撃能力（DH非採用なので打席に立つ。野手より低め）
      // 個別に設定されているので、後でバランス調整しやすい
      meet: meet,
      power: power,
      eye: eye,
      // 投手の走力は低め（平均3.5）
      speed: speed,
      // 打席（投手も打つ）
      bats: _batterHandedness(),
      pitcherRole: pitcherRole,
      potentials: _buildPotentials(
        meet: meet,
        power: power,
        speed: speed,
        eye: eye,
        fastball: fastball,
        control: control,
        slider: slider,
        curve: curve,
        splitter: splitter,
        changeup: changeup,
        shoot: shoot,
        cutter: cutter,
        sinker: sinker,
        bonus: potentialBonus,
      ),
      potentialAverageSpeed:
          _potentialAverageSpeed(avgSpeed, bonus: potentialBonus),
    );
  }

  /// 守備位置ごとの打撃・走力傾向を返す。
  ///
  /// - 一塁: 長距離砲・鈍足
  /// - 三塁: 強打＋強肩
  /// - 二塁: 巧打俊足・長打少なめ
  /// - 遊撃: 守備の要・強肩・長打少なめ
  /// - 捕手: 打撃控えめ・強肩・鈍足
  /// - 外野: 強打型 / 守備型 / 中距離型 を抽選（[_rollOutfieldProfile]）
  _PositionalProfile _profileForPosition(DefensePosition pos) {
    switch (pos) {
      case DefensePosition.first:
        return const _PositionalProfile(
            power: 1.5, speed: -2.0, meet: 0.5, arm: -0.5);
      case DefensePosition.third:
        return const _PositionalProfile(power: 1.0, speed: -1.0, arm: 1.0);
      case DefensePosition.second:
        return const _PositionalProfile(power: -1.0, speed: 1.5, meet: 0.5);
      case DefensePosition.shortstop:
        return const _PositionalProfile(power: -1.0, speed: 1.5, arm: 1.0);
      case DefensePosition.catcher:
        return const _PositionalProfile(
            power: -1.0, speed: -2.0, meet: -0.5, arm: 1.0);
      case DefensePosition.outfield:
        return _rollOutfieldProfile();
    }
  }

  /// 外野手の型を抽選する。
  /// 強打型 40% / 守備型 35% / 中距離型 25%。
  /// 外野は LF/CF/RF を区別しない作りなので、生成時に1回だけ型を引いて個性とする。
  _PositionalProfile _rollOutfieldProfile() {
    final roll = _r.random.nextDouble();
    if (roll < 0.40) {
      // 強打型: 長打を期待される代わりにやや足が落ちる
      return const _PositionalProfile(power: 1.0, speed: -0.5);
    }
    if (roll < 0.75) {
      // 守備型: 広い守備範囲と強肩、長打は控えめ
      return const _PositionalProfile(power: -0.5, speed: 1.5, arm: 1.0);
    }
    // 中距離型: 平均的（オフセットなし）
    return const _PositionalProfile();
  }

  /// 主ポジション → サブポジションの典型的なコンバート関係。
  /// `chance` の確率で「低めの守備力で守れる」位置として fielding に追加する。
  /// 「2 塁手だけど 1 塁も守れる」「3 塁手だけど 1 塁・外野もできる」のような
  /// NPB で実際にあるユーティリティ性を再現し、「2 塁しか守れない使いづらい選手」を
  /// 減らす狙い。生成時に確定するので、シーズン途中の急なコンバートは起きない
  /// （= ユーザーの「この選手はここを守る」認識を壊さない）。
  static const Map<DefensePosition,
      List<({DefensePosition pos, double chance})>> _secondaryFielding = {
    DefensePosition.catcher: [
      // 捕手はほぼ専門。ベテランで一塁回りが稀にある程度
      (pos: DefensePosition.first, chance: 0.15),
    ],
    DefensePosition.first: [
      (pos: DefensePosition.third, chance: 0.35),
      (pos: DefensePosition.outfield, chance: 0.35),
    ],
    DefensePosition.second: [
      (pos: DefensePosition.shortstop, chance: 0.55),
      (pos: DefensePosition.third, chance: 0.45),
    ],
    DefensePosition.third: [
      (pos: DefensePosition.first, chance: 0.45),
      (pos: DefensePosition.outfield, chance: 0.35),
      (pos: DefensePosition.second, chance: 0.20),
    ],
    DefensePosition.shortstop: [
      (pos: DefensePosition.second, chance: 0.60),
      (pos: DefensePosition.third, chance: 0.40),
    ],
    DefensePosition.outfield: [
      (pos: DefensePosition.first, chance: 0.25),
      (pos: DefensePosition.third, chance: 0.20),
    ],
  };

  /// 主ポジションに紐づくサブポジションを抽選し、`fielding` map に低めの守備力で追加する。
  void _attachSecondaryPositions(
    Map<DefensePosition, int> fielding,
    DefensePosition primary,
  ) {
    final secondaries = _secondaryFielding[primary] ?? const [];
    for (final entry in secondaries) {
      if (fielding.containsKey(entry.pos)) continue;
      if (!_r.chance(entry.chance)) continue;
      // サブポジは「守れるが下手」の幅。mean 3.5 で 1〜6 程度に分布。
      fielding[entry.pos] = _r.normalInt(mean: 3.5, sd: 1.5);
    }
  }

  /// 野手を生成する。フラット mean 5.0 で生成し、スタメン/控えの役割は呼び出し側で
  /// 能力ベースで決める（[TeamGenerator] のスタメン選定）。
  ///
  /// 設計（2026-05-23 統合）:
  /// 旧版は `generateStarterFielder`（mean 5.0）と `generateBenchFielder`（mean 4.5）
  /// で生成時に「スタメン用は能力高め / 控え用は能力低め」と仕込んでいた。これだと
  /// 「最初からスタメンと決まっている選手」「最初から控えと決まっている選手」が
  /// 生成段階で固定され、現実のプロ野球（選手がいて監督が能力で選ぶ）と乖離する。
  /// 22 人をフラットに生成すれば、能力ガチャの結果でスタメン/控えが自然に決まる。
  ///
  /// [positions] の第 1 要素を主守備位置（守備力 mean 6.5）、それ以降を
  /// 追加で守れるポジション（mean 4.5）として登録する。主ポジションに紐づく
  /// 典型的なサブポジション（[_secondaryFielding]）も確率的に付与される。
  /// 主ポジションのプロファイル（一塁手は power +1.5、二遊は speed +1.5 等）を
  /// 打撃・走力・肩の生成 mean に適用（これは「現実のポジションごとの傾向」を
  /// 反映する自然な属性で、「役割を仕込む小細工」ではない）。
  Player generateFielder({
    required int number,
    required List<DefensePosition> positions,
  }) {
    final primaryPosition = positions.first;
    final fielding = <DefensePosition, int>{
      primaryPosition: _r.abilityInt(mean: 6.5),
    };
    for (int i = 1; i < positions.length; i++) {
      fielding[positions[i]] = _r.abilityInt(mean: 4.5);
    }
    _attachSecondaryPositions(fielding, primaryPosition);
    final profile = _profileForPosition(primaryPosition);
    final meet = _r.abilityInt(mean: 5.0 + profile.meet);
    final power = _r.abilityInt(mean: 5.0 + profile.power);
    final speed = _r.abilityInt(mean: 5.0 + profile.speed);
    final eye = _r.abilityInt();
    final arm = _r.abilityInt(mean: 5.0 + profile.arm);
    return Player(
      id: _newId(),
      name: _uniqueName(),
      number: number,
      age: _generateAge(),
      meet: meet,
      power: power,
      speed: speed,
      eye: eye,
      arm: arm,
      bats: _batterHandedness(),
      throws: _r.chance(0.15) ? Handedness.left : Handedness.right,
      fielding: fielding,
      potentials: _buildPotentials(
        meet: meet,
        power: power,
        speed: speed,
        eye: eye,
        arm: arm,
      ),
      potentialFielding: _buildPotentialFielding(fielding),
    );
  }

  /// 開幕時の年齢分布: 平均 26、標準偏差 4、18〜36 にクリップ。
  /// プロ野球の年齢構成（10代後半 〜 30代前半中心）に近い形。
  int _generateAge() {
    return _r.normalInt(mean: 26.0, sd: 4.0, min: 18, max: 36);
  }

  /// 新人タイプ別の年齢:
  /// - 高卒: 18 固定
  /// - 大卒: 22 固定
  /// - 社会人: 21〜25 (mean 23, sd 1)
  int _ageForRookieType(RookieType type) {
    switch (type) {
      case RookieType.highSchool:
        return 18;
      case RookieType.college:
        return 22;
      case RookieType.corporate:
        return _r.normalInt(mean: 23.0, sd: 1.0, min: 21, max: 25);
    }
  }

  /// 新人タイプ別の能力ブースト（年齢が高いほど能力高め、ただし sd は維持なので
  /// まれに高卒の即戦力や、社会人の伸び悩みも出る）。
  /// - 高卒: -1.5 (能力低、伸びしろ)
  /// - 大卒: -0.3 (中堅）
  /// - 社会人: 0.0 (即戦力）
  double _abilityBoostForRookieType(RookieType type) {
    switch (type) {
      case RookieType.highSchool:
        return -1.5;
      case RookieType.college:
        return -0.3;
      case RookieType.corporate:
        return 0.0;
    }
  }

  /// 新人の守備プロファイル候補（現実的な組み合わせ）。
  /// 1〜3 ポジションをランダムに抽選してその選手の個性とする。
  /// 引退者のポジションには連動させない（新人は新人で独立した個性を持つ）。
  ///
  /// 捕手は専門性が高いポジションなので、自動生成時は単独パターンのみ。
  /// チーム編集画面では引き続き任意のポジションを兼任設定できる。
  static const _rookieFieldingPatterns = <List<DefensePosition>>[
    // スペシャリスト（1 ポジション）。外野は実数が多いので重複させて確率を上げる
    [DefensePosition.catcher],
    [DefensePosition.catcher],
    [DefensePosition.first],
    [DefensePosition.second],
    [DefensePosition.third],
    [DefensePosition.shortstop],
    [DefensePosition.outfield],
    [DefensePosition.outfield],
    [DefensePosition.outfield],
    // 内外野ユーティリティ（2 ポジション）
    [DefensePosition.first, DefensePosition.third],
    [DefensePosition.second, DefensePosition.shortstop],
    [DefensePosition.second, DefensePosition.third],
    [DefensePosition.first, DefensePosition.outfield],
    [DefensePosition.third, DefensePosition.outfield],
    // スーパーユーティリティ（3 ポジション）
    [DefensePosition.second, DefensePosition.shortstop, DefensePosition.third],
    [DefensePosition.first, DefensePosition.third, DefensePosition.outfield],
  ];

  /// 引退者の代わりに加入する新人野手。
  /// - 守備: 自分独自のプロファイル（[_rookieFieldingPatterns] からランダム抽選）
  /// - 能力: タイプによって平均能力が変わる
  ///   - 高卒: 平均 -1.5（伸びしろ重視）
  ///   - 大卒: 平均 -0.3（中堅）
  ///   - 社会人: 平均 0.0（即戦力）
  ///   ただし sd は維持しているので、まれに高卒の即戦力や社会人の凡才も出る
  /// - 年齢: タイプによる（[_ageForRookieType] 参照）
  ///
  /// 守備位置の整合性は LineupPlanner 側で吸収される
  /// （守れない選手はベンチから昇格してきた選手と入れ替わる）。
  Player generateRookieFielder({
    required int number,
    RookieType type = RookieType.college,
    List<DefensePosition>? forcedPositions,
  }) {
    final boost = _abilityBoostForRookieType(type);
    final potentialBonus = _potentialBonusForRookieType(type);
    final List<DefensePosition> positions =
        forcedPositions ?? _r.pick(_rookieFieldingPatterns);
    final fielding = <DefensePosition, int>{};
    // 1つ目（メイン）は若手平均、サブはやや低めにする
    for (int i = 0; i < positions.length; i++) {
      final mean = (i == 0 ? 5.5 : 4.5) + boost;
      fielding[positions[i]] = _r.abilityInt(mean: mean);
    }
    // 主ポジションに紐づくサブポジションも低めで追加
    _attachSecondaryPositions(fielding, positions.first);
    // 守備傾向は主ポジション（positions の先頭）で決める
    final profile = _profileForPosition(positions.first);
    // 新人は能力のばらつきがやや大きい（sd 1.5）。abilityInt で max=8 + 9プロモート抽選
    final meet = _r.abilityInt(mean: 5.0 + boost + profile.meet, sd: 1.5);
    final power = _r.abilityInt(mean: 5.0 + boost + profile.power, sd: 1.5);
    final speed = _r.abilityInt(mean: 5.5 + boost + profile.speed);
    final eye = _r.abilityInt(mean: 4.5 + boost);
    final arm = _r.abilityInt(mean: 5.0 + boost + profile.arm);
    return Player(
      id: _newId(),
      name: _uniqueName(),
      number: number,
      age: _ageForRookieType(type),
      meet: meet,
      power: power,
      speed: speed, // 若い分やや走れる
      eye: eye,
      arm: arm,
      bats: _batterHandedness(),
      throws: _r.chance(0.15) ? Handedness.left : Handedness.right,
      fielding: fielding,
      potentials: _buildPotentials(
        meet: meet,
        power: power,
        speed: speed,
        eye: eye,
        arm: arm,
        bonus: potentialBonus,
      ),
      potentialFielding:
          _buildPotentialFielding(fielding, bonus: potentialBonus),
    );
  }

  /// 引退者の代わりに加入する新人投手。
  /// - 役割: 引退者と同じロール（先発 or 救援＋ロール種類）
  /// - 能力: タイプ別の abilityBoost を適用（[_abilityBoostForRookieType]）
  /// - 年齢: タイプによる（[_ageForRookieType] 参照）
  Player generateRookiePitcher({
    required int number,
    bool isStarter = true,
    PitcherRole? pitcherRole,
    RookieType type = RookieType.college,
  }) {
    return _generatePitcher(
      number: number,
      isStarter: isStarter,
      pitcherRole: pitcherRole,
      abilityBoost: _abilityBoostForRookieType(type),
      ageOverride: _ageForRookieType(type),
      rookieType: type,
    );
  }

  /// 1〜10 能力のポテンシャル上限を計算する（素質ガチャ方式）。
  ///
  /// initial が 10 のときはそのまま 10 を返す（手動編集で 10 を作った選手の維持）。
  /// それ以外は能力ごとに **素質レベル** を抽選し、tier に応じた margin / cap で
  /// ポテンシャル上限を決める（[_talentTiers] 参照）。
  ///
  /// [isFielding] が true のときは fielding 用の確率配分を使う（素質型 8% で
  /// 練習系の伸びを表現）。それ以外は [_talentEliteChance] / [_talentMiddleChance]。
  ///
  /// [bonus] は新人タイプ別の補正（高卒+1.5 等）で margin に加算される。
  int _potentialFor(
    int? initial, {
    String? key,
    bool isFielding = false,
    double bonus = 0.0,
  }) {
    if (initial == null) return 0;
    if (initial >= 10) return 10;
    final eliteCh =
        isFielding ? _fieldingTalentEliteChance : _talentEliteChance;
    final middleCh =
        isFielding ? _fieldingTalentMiddleChance : _talentMiddleChance;
    final roll = _r.random.nextDouble();
    final tier = roll < eliteCh
        ? _talentTiers['elite']!
        : (roll < eliteCh + middleCh
            ? _talentTiers['middle']!
            : _talentTiers['normal']!);
    // initial が tier.cap を上回るケース（例: 9 プロモートされた選手が普通型に
    // 分類された）は initial をそのまま維持（成長は起きないが初期値は守られる）
    if (initial >= tier.cap) return initial;
    final raw =
        initial + tier.mean + bonus + _r.nextGaussian() * tier.sd;
    return raw.round().clamp(initial, tier.cap);
  }

  /// 球速 (km/h) のポテンシャル上限を計算する。
  /// 1〜10 とはスケールが違うので別係数。
  /// initial が ceiling を超えて生成された選手（初期 159〜160 km/h の超剛速球派）は
  /// その initial 値をそのまま potential として保持する（成長は無いが衰えは普通に進行）。
  int _potentialAverageSpeed(int initial, {double bonus = 0.0}) {
    if (initial >= _speedCeiling) return initial;
    final raw = initial +
        _speedBaseMargin +
        bonus * 2.0 +
        _r.nextGaussian() * _speedSd;
    return raw.round().clamp(initial, _speedCeiling);
  }

  /// 「眠った変化球ポテンシャル」を仕込む確率（未習得の球種ごとに抽選）。
  /// 20% で「将来カーブを覚える可能性のある投手」のような余地を残す。
  /// ポテンシャル質は通常の能力分布（mean 5, sd 1.5）から仮 initial を立てて
  /// `_potentialFor` で算出するので、3〜9 の範囲に分布する。
  static const double _hiddenPitchPotentialChance = 0.20;
  static const Set<String> _breakingBallKeys = {
    'slider', 'curve', 'splitter', 'changeup',
    'shoot', 'cutter', 'sinker',
  };

  /// 1〜10 能力一式（field name → potential）のマップを構築するヘルパー。
  /// initial が null のキーは原則含めないが、変化球は別扱い:
  /// 投手の場合、持っていない変化球にも一定確率で「眠ったポテンシャル」を仕込み、
  /// 加齢処理 (`PlayerAging`) で習得判定の対象にする。
  Map<String, int> _buildPotentials({
    int? meet,
    int? power,
    int? speed,
    int? eye,
    int? arm,
    int? fastball,
    int? control,
    int? slider,
    int? curve,
    int? splitter,
    int? changeup,
    int? shoot,
    int? cutter,
    int? sinker,
    double bonus = 0.0,
  }) {
    final map = <String, int>{};
    // 投手判定: 投手能力（fastball / control）のいずれかが non-null なら投手扱い
    final isPitcher = fastball != null || control != null;
    void put(String key, int? v) {
      if (v != null) {
        // 能力名 key を渡して、_abilityGrowthMargin から能力別マージンを引く
        map[key] = _potentialFor(v, key: key, bonus: bonus);
        return;
      }
      // 投手の未習得変化球: 確率で「眠ったポテンシャル」を仕込む
      if (isPitcher && _breakingBallKeys.contains(key)) {
        if (_r.chance(_hiddenPitchPotentialChance)) {
          // 仮 initial を平均的な能力分布から作り、その上でポテンシャル算出
          final virtualInitial = _r.abilityInt();
          map[key] = _potentialFor(virtualInitial, key: key, bonus: bonus);
        }
      }
    }

    put('meet', meet);
    put('power', power);
    put('speed', speed);
    put('eye', eye);
    put('arm', arm);
    put('fastball', fastball);
    put('control', control);
    put('slider', slider);
    put('curve', curve);
    put('splitter', splitter);
    put('changeup', changeup);
    put('shoot', shoot);
    put('cutter', cutter);
    put('sinker', sinker);
    return map;
  }

  /// fielding 能力一式のポテンシャル上限マップを構築する。
  /// 値 0（守れない）はそのまま 0 を保持する。
  Map<DefensePosition, int>? _buildPotentialFielding(
    Map<DefensePosition, int>? fielding, {
    double bonus = 0.0,
  }) {
    if (fielding == null) return null;
    final out = <DefensePosition, int>{};
    for (final e in fielding.entries) {
      if (e.value == 0) {
        out[e.key] = 0;
      } else {
        // 守備力は技術系で大きく伸びうるため fielding 用の素質ガチャを使う
        out[e.key] = _potentialFor(
          e.value,
          isFielding: true,
          bonus: bonus,
        );
      }
    }
    return out;
  }

  /// 打者の打席: 右65%、左30%、両5%
  Handedness _batterHandedness() {
    final roll = _r.random.nextDouble();
    if (roll < 0.65) return Handedness.right;
    if (roll < 0.95) return Handedness.left;
    return Handedness.both;
  }

  // ===========================================================
  // 外国人選手の生成
  // ===========================================================

  /// 外国人選手の能力値: 日本人より若干バラつくが、中央集中の傾向は維持。
  /// 日本人 sd 1.2（abilityInt のデフォルト）に対して外国人は sd 1.4 でやや裾広め。
  /// 9 への昇格抽選は通常より高め（0.3%）で「外国人は当たれば大砲」のニュアンス。
  /// それでもリーグ 24 人 × 5 能力 × 0.3% = 0.36 人 / 年 程度なので、9 は依然として稀。
  /// 当たり外れ感は mean を主能力で動かすことで出す（パワー型は mean 5.5 など）。
  int _foreignAbility({double mean = 5.0}) {
    return _r.abilityInt(mean: mean, sd: 1.4, promoteNineChance: 0.003);
  }

  /// 新規獲得時の外国人選手の年齢分布: mean 27 / sd 3.5 / 22〜35。
  /// NPB の外国人選手獲得は中堅（27〜30 歳）中心で、35 歳以上の新規獲得は
  /// 実例が稀（チーム所属で加齢して 35+ になるのは別問題、これは初期生成のみ）。
  int _foreignAge() {
    return _r.normalInt(mean: 27.0, sd: 3.5, min: 22, max: 35);
  }

  /// 外国人野手の主ポジションを抽選（捕手なし、一塁・外野中心）。
  /// 重みは NPB の外国人野手の起用傾向に近づける:
  ///   一塁 30% / 外野 40% / 三塁 15% / 二塁 10% / 遊撃 5%
  DefensePosition _foreignFielderPrimary() {
    final roll = _r.random.nextDouble();
    if (roll < 0.30) return DefensePosition.first;
    if (roll < 0.70) return DefensePosition.outfield;
    if (roll < 0.85) return DefensePosition.third;
    if (roll < 0.95) return DefensePosition.second;
    return DefensePosition.shortstop;
  }

  /// 外国人野手を生成する。
  /// 能力分布は中央集中 + 国籍別オフセット（ミート -0.5 / 長打 +0.5 /
  /// 走力 -0.5 / 選眼・肩 同等）に加え、**ポジションオフセットも日本人と同じ
  /// ロジックで適用**する（[_profileForPosition]）。
  ///
  /// 旧版は日本人だけにポジションオフセットがついていたため、日本人一塁手
  /// （mean 5.0 + 1.5 = 6.5）が外国人一塁手（mean 5.5 フラット）より長打が
  /// 強いという逆転構造になっていた（2026-05-23 修正、CHANGELOG 参照）。
  /// 守備位置は 1 つだけ（NPB の外国人野手のユーティリティ性は低い）。
  Player generateForeignFielder({
    required int number,
    Set<String> teamSurnames = const <String>{},
  }) {
    final primary = _foreignFielderPrimary();
    final profile = _profileForPosition(primary);
    final fielding = <DefensePosition, int>{
      primary: _foreignAbility(mean: 4.0), // 守備力は弱め
    };
    // 国籍別オフセット（日本人 mean 5.0 を基準とした増減）:
    //   ミート: 細かいテクニックは日本人優位（-0.5）
    //   長打: パワー型が多い（+0.5）
    //   走力: 鈍足傾向（-0.5）
    //   選球眼・肩: 同等（±0）
    // これに [_profileForPosition] のポジションオフセットを加算する。
    // 例: 一塁の外国人 power = 5.5 + 1.5 = 7.0、二塁の外国人 power = 5.5 - 1.0 = 4.5。
    final meet = _foreignAbility(mean: 4.5 + profile.meet);
    final power = _foreignAbility(mean: 5.5 + profile.power);
    final speed = _foreignAbility(mean: 4.5 + profile.speed);
    final eye = _foreignAbility(mean: 5.0);
    final arm = _foreignAbility(mean: 5.0 + profile.arm);
    return Player(
      id: _newId(),
      name: _uniqueForeignName(teamSurnames),
      number: number,
      age: _foreignAge(),
      meet: meet,
      power: power,
      speed: speed,
      eye: eye,
      arm: arm,
      bats: _batterHandedness(),
      // 外国人投手は左投げ比率がやや高い（NPB 外国人左腕の人気）
      throws: _r.chance(0.20) ? Handedness.left : Handedness.right,
      fielding: fielding,
      potentials: _buildPotentials(
        meet: meet, power: power, speed: speed, eye: eye, arm: arm,
      ),
      potentialFielding: _buildPotentialFielding(fielding),
      isForeign: true,
    );
  }

  /// 外国人投手を生成する。
  /// 球速 +3 km/h、制球 -1、その他の質はフラット分布（sd 2.5）で当たり外れ大。
  /// 球種抽選は通常投手と同じ枠（最低 2 変化球 + ストレート）。
  Player generateForeignPitcher({
    required int number,
    bool isStarter = true,
    PitcherRole? pitcherRole,
    Set<String> teamSurnames = const <String>{},
  }) {
    // 球速: 平均 +3 km/h で 142〜158 km/h レンジ、sd 4 で当たり外れ
    final avgSpeed =
        (150.0 + _r.nextGaussian() * 4.0).round().clamp(140, 158);

    // 変化球抽選（通常投手と同じロジック）
    const breakingProbs = <String, double>{
      'slider': 0.88,
      'curve': 0.55,
      'splitter': 0.50,
      'changeup': 0.50,
      'shoot': 0.20,
      'cutter': 0.35,
      'sinker': 0.30,
    };
    final chosen = <String>[];
    for (final e in breakingProbs.entries) {
      if (_r.chance(e.value)) chosen.add(e.key);
    }
    while (chosen.length < 2) {
      chosen.add(breakingProbs.keys.firstWhere((k) => !chosen.contains(k)));
    }
    while (chosen.length > 5) {
      chosen.removeAt(_r.random.nextInt(chosen.length));
    }
    int? slider, curve, splitter, changeup, shoot, cutter, sinker;
    for (final t in chosen) {
      // 変化球の質もフラット分布で当たり外れ
      final v = _foreignAbility(mean: 5.0);
      switch (t) {
        case 'slider': slider = v; break;
        case 'curve': curve = v; break;
        case 'splitter': splitter = v; break;
        case 'changeup': changeup = v; break;
        case 'shoot': shoot = v; break;
        case 'cutter': cutter = v; break;
        case 'sinker': sinker = v; break;
      }
    }

    // 外国人投手は左投手の比率がやや高め（30 → 40%）
    final throws = _r.chance(0.40) ? Handedness.left : Handedness.right;

    final fastball = _foreignAbility(mean: 5.0);
    final control = _foreignAbility(mean: 4.0); // 制球 -1
    // 投手の打撃能力は通常通り低め（DH 非採用で打席に立つ）
    final meet = _r.normalInt(mean: 2.0, sd: 0.8);
    final power = _r.normalInt(mean: 2.0, sd: 0.8); // 外国人投手はやや長打あり
    final eye = _r.normalInt(mean: 2.5, sd: 0.8);
    final speed = _r.normalInt(mean: 3.0, sd: 1.2);

    return Player(
      id: _newId(),
      name: _uniqueForeignName(teamSurnames),
      number: number,
      age: _foreignAge(),
      averageSpeed: avgSpeed,
      fastball: fastball,
      control: control,
      slider: slider,
      curve: curve,
      splitter: splitter,
      changeup: changeup,
      shoot: shoot,
      cutter: cutter,
      sinker: sinker,
      throws: throws,
      meet: meet,
      power: power,
      eye: eye,
      speed: speed,
      bats: _batterHandedness(),
      pitcherRole: pitcherRole,
      potentials: _buildPotentials(
        meet: meet, power: power, speed: speed, eye: eye,
        fastball: fastball, control: control,
        slider: slider, curve: curve, splitter: splitter,
        changeup: changeup, shoot: shoot, cutter: cutter, sinker: sinker,
      ),
      potentialAverageSpeed: _potentialAverageSpeed(avgSpeed),
      isForeign: true,
    );
  }

  /// ID生成（簡易: p_1, p_2, ...）
  String _newId() => 'p_${++_idCounter}';

  /// 重複しない苗字＋名前を生成
  String _uniqueName() {
    for (int i = 0; i < 1000; i++) {
      final name = '${_r.pick(NameData.surnames)}${_r.pick(NameData.givenNames)}';
      if (_usedNames.add(name)) return name;
    }
    throw StateError('一意な名前を生成できませんでした（名前データが不足している可能性）');
  }

  /// 外国人選手の名前を生成（苗字単独）。NPB の登録名慣習に倣う（例: ベラスケス）。
  /// 同チームに既に居る苗字は候補から除外して抽選するので、チーム内では衝突しない。
  /// 別チーム同士の同苗字（フェニックスのローズ vs ブリザーズのローズ）は許容。
  ///
  /// [teamSurnames] は同チーム既存外国人の苗字セット（[foreignSurnameOf] で抽出）。
  String _uniqueForeignName(Set<String> teamSurnames) {
    final available = [
      for (final s in NameData.foreignSurnames)
        if (!teamSurnames.contains(s)) s,
    ];
    final pool = available.isEmpty ? NameData.foreignSurnames : available;
    return pool[_r.random.nextInt(pool.length)];
  }
}

/// 外国人選手の名前から苗字部分を抜き出す。
/// 「ベラスケス」「スティーブ・ベラスケス」のいずれでも "ベラスケス" を返す。
/// 同チームに同苗字の外国人が居るかどうかの判定に使う。
String foreignSurnameOf(String name) {
  final i = name.lastIndexOf('・');
  return i < 0 ? name : name.substring(i + 1);
}

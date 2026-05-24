import 'dart:math';
import '../models/models.dart';
import 'ability_profile.dart';
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
  late final AbilitySampler _sampler;
  final Set<String> _usedNames;
  int _idCounter;

  // 全能力のポテンシャル抽選 / 現在値逆算 / 加齢ロジックは [AbilitySampler] に
  // 集約された。能力ごとの違いは [AbilityProfile] の数値テーブルと
  // 呼び出し時の `meanBonus` だけで表現する（[feedback_unified_logic_principle]）。

  /// - [random]: RNG
  /// - [idStart]: id 連番の開始値（ロード時に既存選手の最大 id を渡してデフォ値を超えないようにする）
  /// - [usedNames]: すでに使われている名前。ロード時に渡せばシーズン跨ぎでの重複を回避
  PlayerGenerator({
    Random? random,
    int idStart = 0,
    Set<String>? usedNames,
  })  : _r = RandomUtils(random),
        _idCounter = idStart,
        _usedNames = usedNames ?? <String>{} {
    _sampler = AbilitySampler(_r);
  }

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
    final age = ageOverride ?? _generateAge();

    // 全能力を統一 API で抽選。AbilityProfiles + meanBonus で能力ごとの違いを表現。
    // abilityBoost (エース級+1 等) は全能力 mean に加算する形で反映。
    final speed = _sampleSpeed(age, rookieType, meanBonus: abilityBoost * 2.0);
    final fastball = _sample1to10(age, rookieType, meanBonus: abilityBoost);
    final control = _sample1to10(age, rookieType, meanBonus: abilityBoost);

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
    while (chosen.length < 2) {
      chosen.add(breakingProbs.keys.firstWhere((k) => !chosen.contains(k)));
    }
    while (chosen.length > 5) {
      chosen.removeAt(_r.random.nextInt(chosen.length));
    }
    // 変化球の質は全球種共通で平均 5（abilityBoost で底上げ）。「どれだけ投げるか」は
    // 質ではなく球種別の使用頻度重み（at_bat_simulator の _pitchTypeUsageWeight）で
    // 表現する。質＝被打率・空振り、使用頻度＝投球割合、と役割を分離している。
    final breakingPairs = <String, ({int potential, int current})>{};
    for (final t in chosen) {
      breakingPairs[t] = _sample1to10(age, rookieType, meanBonus: abilityBoost);
    }

    // 投手の利き腕: forcedThrows 指定があればそれ、なければ 右70%・左30%
    final throws = forcedThrows ??
        (_r.chance(0.3) ? Handedness.left : Handedness.right);

    // 投手の打撃能力（DH非採用なので打席に立つ。野手より低め）
    // meanBonus でデフォルト 5.5 から大幅に下げる
    final meet = _sample1to10(age, rookieType, meanBonus: 2.0 - 5.5);
    final power = _sample1to10(age, rookieType, meanBonus: 1.5 - 5.5);
    final eye = _sample1to10(age, rookieType, meanBonus: 2.5 - 5.5);
    final batSpeed = _sample1to10(age, rookieType, meanBonus: 3.5 - 5.5);

    // 未習得変化球に「眠ったポテンシャル」を仕込む（加齢で習得判定）
    final hiddenPotentials = <String, int>{};
    for (final key in _breakingBallKeys) {
      if (breakingPairs.containsKey(key)) continue;
      if (_r.chance(_hiddenPitchPotentialChance)) {
        final dormant =
            _sample1to10(age, rookieType, meanBonus: abilityBoost);
        hiddenPotentials[key] = dormant.potential;
      }
    }

    return Player(
      id: _newId(),
      name: _uniqueName(),
      number: number,
      age: age,
      averageSpeed: speed.current,
      fastball: fastball.current,
      control: control.current,
      slider: breakingPairs['slider']?.current,
      curve: breakingPairs['curve']?.current,
      splitter: breakingPairs['splitter']?.current,
      changeup: breakingPairs['changeup']?.current,
      shoot: breakingPairs['shoot']?.current,
      cutter: breakingPairs['cutter']?.current,
      sinker: breakingPairs['sinker']?.current,
      throws: throws,
      meet: meet.current,
      power: power.current,
      eye: eye.current,
      speed: batSpeed.current,
      bats: _batterHandedness(),
      pitcherRole: pitcherRole,
      potentials: {
        'meet': meet.potential,
        'power': power.potential,
        'speed': batSpeed.potential,
        'eye': eye.potential,
        'fastball': fastball.potential,
        'control': control.potential,
        for (final e in breakingPairs.entries) e.key: e.value.potential,
        ...hiddenPotentials,
      },
      potentialAverageSpeed: speed.potential,
    );
  }

  /// 統一 API のショートハンド: 球速 (km/h) のポテンシャル & 現在値を 1 回で返す。
  ({int potential, int current}) _sampleSpeed(
    int age,
    RookieType? rookieType, {
    double meanBonus = 0.0,
  }) =>
      _sampler.samplePotentialAndCurrent(
        profile: AbilityProfiles.fastballSpeed,
        age: age,
        rookieType: rookieType,
        meanBonus: meanBonus,
      );

  /// 統一 API のショートハンド: 1-10 能力のポテンシャル & 現在値を 1 回で返す。
  ({int potential, int current}) _sample1to10(
    int age,
    RookieType? rookieType, {
    double meanBonus = 0.0,
  }) =>
      _sampler.samplePotentialAndCurrent(
        profile: AbilityProfiles.ability1to10,
        age: age,
        rookieType: rookieType,
        meanBonus: meanBonus,
      );

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

  /// 主ポジションに紐づくサブポジションを抽選し、`fielding` map に低めの守備力で
  /// 追加する。統一 API の `_sample1to10` で「現在値」だけ使う（fielding は
  /// _buildFielding 側でポテンシャルもまとめて構築するので、ここでは current のみ）。
  void _attachSecondaryPositions(
    Map<DefensePosition, int> fielding,
    Map<DefensePosition, int> fieldingPotential,
    DefensePosition primary,
    int age,
    RookieType? rookieType,
  ) {
    final secondaries = _secondaryFielding[primary] ?? const [];
    for (final entry in secondaries) {
      if (fielding.containsKey(entry.pos)) continue;
      if (!_r.chance(entry.chance)) continue;
      // サブポジは「守れるが下手」の幅。mean -2 で平均 3.5 程度。
      final pair = _sample1to10(age, rookieType, meanBonus: -2.0);
      fielding[entry.pos] = pair.current;
      fieldingPotential[entry.pos] = pair.potential;
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
    final age = _generateAge();
    final primaryPosition = positions.first;
    // 主ポジ守備力は平均 6.5 (meanBonus +1.0)、サブは平均 4.5 (meanBonus -1.0)
    final fielding = <DefensePosition, int>{};
    final fieldingPotential = <DefensePosition, int>{};
    final primaryPair = _sample1to10(age, null, meanBonus: 1.0);
    fielding[primaryPosition] = primaryPair.current;
    fieldingPotential[primaryPosition] = primaryPair.potential;
    for (int i = 1; i < positions.length; i++) {
      final pair = _sample1to10(age, null, meanBonus: -1.0);
      fielding[positions[i]] = pair.current;
      fieldingPotential[positions[i]] = pair.potential;
    }
    _attachSecondaryPositions(
        fielding, fieldingPotential, primaryPosition, age, null);
    final profile = _profileForPosition(primaryPosition);
    final meet = _sample1to10(age, null, meanBonus: profile.meet);
    final power = _sample1to10(age, null, meanBonus: profile.power);
    final speed = _sample1to10(age, null, meanBonus: profile.speed);
    // 旧 abilityInt() のデフォルト mean=5.0 は新 potentialMean 5.5 と 0.5 差。
    // 統一原則のため meanBonus -0.5 は付けず、デフォルト 5.5 で行く（measure_growth で確認）。
    final eye = _sample1to10(age, null);
    final arm = _sample1to10(age, null, meanBonus: profile.arm);
    return Player(
      id: _newId(),
      name: _uniqueName(),
      number: number,
      age: age,
      meet: meet.current,
      power: power.current,
      speed: speed.current,
      eye: eye.current,
      arm: arm.current,
      bats: _batterHandedness(),
      throws: _r.chance(0.15) ? Handedness.left : Handedness.right,
      fielding: fielding,
      potentials: {
        'meet': meet.potential,
        'power': power.potential,
        'speed': speed.potential,
        'eye': eye.potential,
        'arm': arm.potential,
      },
      potentialFielding: fieldingPotential,
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
  /// - 年齢: タイプによる（[_ageForRookieType] 参照）
  /// - 能力: ポテンシャル分布は世代を超えて一定 ([feedback_potential_first_design])。
  ///   高卒で入団時に能力が低く見えるのは margin (年齢/タイプ別) で表現済みなので、
  ///   ポテンシャル mean を更に下げない（下げるとリーグの分布が世代交代で減衰する）。
  ///
  /// 守備位置の整合性は LineupPlanner 側で吸収される。
  Player generateRookieFielder({
    required int number,
    RookieType type = RookieType.college,
    List<DefensePosition>? forcedPositions,
  }) {
    final age = _ageForRookieType(type);
    final List<DefensePosition> positions =
        forcedPositions ?? _r.pick(_rookieFieldingPatterns);
    final fielding = <DefensePosition, int>{};
    final fieldingPotential = <DefensePosition, int>{};
    for (int i = 0; i < positions.length; i++) {
      // 1つ目はメイン (旧 mean 5.5 → meanBonus 0)、サブはやや低め (旧 mean 4.5 → -1.0)
      final bonus = (i == 0 ? 0.0 : -1.0);
      final pair = _sample1to10(age, type, meanBonus: bonus);
      fielding[positions[i]] = pair.current;
      fieldingPotential[positions[i]] = pair.potential;
    }
    _attachSecondaryPositions(
        fielding, fieldingPotential, positions.first, age, type);
    final profile = _profileForPosition(positions.first);
    final meet = _sample1to10(age, type, meanBonus: profile.meet);
    final power = _sample1to10(age, type, meanBonus: profile.power);
    final speed = _sample1to10(age, type, meanBonus: profile.speed);
    final eye = _sample1to10(age, type);
    final arm = _sample1to10(age, type, meanBonus: profile.arm);
    return Player(
      id: _newId(),
      name: _uniqueName(),
      number: number,
      age: age,
      meet: meet.current,
      power: power.current,
      speed: speed.current,
      eye: eye.current,
      arm: arm.current,
      bats: _batterHandedness(),
      throws: _r.chance(0.15) ? Handedness.left : Handedness.right,
      fielding: fielding,
      potentials: {
        'meet': meet.potential,
        'power': power.potential,
        'speed': speed.potential,
        'eye': eye.potential,
        'arm': arm.potential,
      },
      potentialFielding: fieldingPotential,
    );
  }

  /// 引退者の代わりに加入する新人投手。
  /// - 役割: 引退者と同じロール（先発 or 救援＋ロール種類）
  /// - 年齢: タイプによる（[_ageForRookieType] 参照）
  /// - 能力: ポテンシャル分布は世代固定。「新人だから低い」は margin (年齢/タイプ別)
  ///   で吸収する ([feedback_potential_first_design])。
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
      ageOverride: _ageForRookieType(type),
      rookieType: type,
    );
  }

  /// 「眠った変化球ポテンシャル」を仕込む確率（未習得の球種ごとに抽選）。
  /// 20% で「将来カーブを覚える可能性のある投手」のような余地を残す。
  /// 加齢処理 (`PlayerAging`) で習得判定の対象。
  static const double _hiddenPitchPotentialChance = 0.20;
  static const Set<String> _breakingBallKeys = {
    'slider', 'curve', 'splitter', 'changeup',
    'shoot', 'cutter', 'sinker',
  };

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
    final age = _foreignAge();
    final primary = _foreignFielderPrimary();
    final profile = _profileForPosition(primary);
    // 守備力は弱め（旧 mean 4.0 → meanBonus -1.5）
    final primaryFielding = _sample1to10(age, null, meanBonus: -1.5);
    final fielding = <DefensePosition, int>{primary: primaryFielding.current};
    final fieldingPotential = <DefensePosition, int>{
      primary: primaryFielding.potential,
    };
    // 国籍別オフセット（日本人 mean 5.5 を基準にした増減を meanBonus で吸収）:
    //   meet -1.0 / power +0.0 / speed -1.0 / eye -0.5 / arm -0.5
    //   ＋ポジションオフセット [_profileForPosition]
    final meet = _sample1to10(age, null, meanBonus: -1.0 + profile.meet);
    final power = _sample1to10(age, null, meanBonus: 0.0 + profile.power);
    final speed = _sample1to10(age, null, meanBonus: -1.0 + profile.speed);
    final eye = _sample1to10(age, null, meanBonus: -0.5);
    final arm = _sample1to10(age, null, meanBonus: -0.5 + profile.arm);
    return Player(
      id: _newId(),
      name: _uniqueForeignName(teamSurnames),
      number: number,
      age: age,
      meet: meet.current,
      power: power.current,
      speed: speed.current,
      eye: eye.current,
      arm: arm.current,
      bats: _batterHandedness(),
      throws: _r.chance(0.20) ? Handedness.left : Handedness.right,
      fielding: fielding,
      potentials: {
        'meet': meet.potential,
        'power': power.potential,
        'speed': speed.potential,
        'eye': eye.potential,
        'arm': arm.potential,
      },
      potentialFielding: fieldingPotential,
      isForeign: true,
    );
  }

  /// 外国人投手を生成する。
  /// 球速 +2 km/h、制球 -1、その他はデフォルト。meanBonus でオフセットを吸収。
  Player generateForeignPitcher({
    required int number,
    bool isStarter = true,
    PitcherRole? pitcherRole,
    Set<String> teamSurnames = const <String>{},
  }) {
    final age = _foreignAge();
    // 球速 mean +2 (外国人は球速で目立つ)
    final speed = _sampleSpeed(age, null, meanBonus: 2.0);
    final fastball = _sample1to10(age, null);
    final control = _sample1to10(age, null, meanBonus: -1.0); // 制球 -1

    // 変化球抽選（通常投手と同じ枠だが保有率は外国人独自）
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
    final breakingPairs = <String, ({int potential, int current})>{};
    for (final t in chosen) {
      breakingPairs[t] = _sample1to10(age, null);
    }

    final throws = _r.chance(0.40) ? Handedness.left : Handedness.right;

    // 投手の打撃: 日本人投手と同じ meanBonus テーブル（power だけやや高め）
    final meet = _sample1to10(age, null, meanBonus: 2.0 - 5.5);
    final power = _sample1to10(age, null, meanBonus: 2.0 - 5.5);
    final eye = _sample1to10(age, null, meanBonus: 2.5 - 5.5);
    final batSpeed = _sample1to10(age, null, meanBonus: 3.0 - 5.5);

    return Player(
      id: _newId(),
      name: _uniqueForeignName(teamSurnames),
      number: number,
      age: age,
      averageSpeed: speed.current,
      fastball: fastball.current,
      control: control.current,
      slider: breakingPairs['slider']?.current,
      curve: breakingPairs['curve']?.current,
      splitter: breakingPairs['splitter']?.current,
      changeup: breakingPairs['changeup']?.current,
      shoot: breakingPairs['shoot']?.current,
      cutter: breakingPairs['cutter']?.current,
      sinker: breakingPairs['sinker']?.current,
      throws: throws,
      meet: meet.current,
      power: power.current,
      eye: eye.current,
      speed: batSpeed.current,
      bats: _batterHandedness(),
      pitcherRole: pitcherRole,
      potentials: {
        'meet': meet.potential,
        'power': power.potential,
        'speed': batSpeed.potential,
        'eye': eye.potential,
        'fastball': fastball.potential,
        'control': control.potential,
        for (final e in breakingPairs.entries) e.key: e.value.potential,
      },
      potentialAverageSpeed: speed.potential,
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

import 'dart:math';
import '../models/models.dart';
import 'name_data.dart';
import 'random_utils.dart';

/// 選手を自動生成する
///
/// - 名前は苗字＋名前のランダム組み合わせで、同一ジェネレーター内では重複しない
/// - 能力値は平均5・標準偏差1.5の正規分布で1〜10にクリップ
/// - ポテンシャル（[Player.potentials] / [Player.potentialFielding] /
///   [Player.potentialAverageSpeed]）は生成時に確定し、加齢成長時の上限となる
class PlayerGenerator {
  final RandomUtils _r;
  final Set<String> _usedNames;
  int _idCounter;

  // ---- ポテンシャル算出パラメータ ----
  // 仮実装: 全能力で同じ値。将来「素質型 / 練習型」に応じて能力ごとに変える想定。
  static const double _potentialBaseMargin = 2.0; // 平均的な伸びしろ
  static const double _potentialSd = 1.0; // 個人差（晩成・期待外れ）
  // 1〜10 能力の上限。10 は基本的に出現しない方針 → 生成時に initial=10 だった
  // 選手のみそのまま 10、それ以外は最大 9 に制限。
  static const int _abilityCeiling = 9;
  // 球速 (km/h) のポテンシャル: 1〜10 の能力換算で +2 ≒ +4 km/h 相当
  static const double _speedBaseMargin = 4.0;
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

  /// 救援投手を生成
  ///
  /// - [reliefRole]: 救援ロール（指定すれば Player.reliefRole にセットされる）
  /// - [abilityBoost]: 能力値の平均オフセット（+1.0 でエース級、-1.0 で控え級）
  /// - [forcedThrows]: 利き腕を強制（例: situational lefty）
  /// - [minStamina]: スタミナの下限（例: ロングリリーフ）
  Player generateReliefPitcher({
    required int number,
    ReliefRole? reliefRole,
    double abilityBoost = 0.0,
    Handedness? forcedThrows,
    int? minStamina,
  }) {
    return _generatePitcher(
      number: number,
      isStarter: false,
      reliefRole: reliefRole,
      abilityBoost: abilityBoost,
      forcedThrows: forcedThrows,
      minStamina: minStamina,
    );
  }

  Player _generatePitcher({
    required int number,
    required bool isStarter,
    ReliefRole? reliefRole,
    double abilityBoost = 0.0,
    Handedness? forcedThrows,
    int? minStamina,
    int? ageOverride,
    RookieType? rookieType,
  }) {
    // 球速: NPB 平均の 147 km/h を中心に正規分布（sd=5）
    // - 147 km/h ≒ 1〜10 能力での 5、160 km/h ≒ 10（数年に一人レベル）
    // - 生成時 clamp 130〜160（編集 UI のみ最大 165 まで設定可、生成では出ない）
    // - abilityBoost 1 ポイントごとに +2 km/h（抑え・エースは速い）
    final speedMean = 147.0 + abilityBoost * 2.0;
    final avgSpeed =
        (speedMean + _r.nextGaussian() * 5.0).round().clamp(130, 160);

    // スタミナ: 先発は高め、救援は低め
    // minStamina が指定された場合は下限として作用
    final staminaMean = isStarter ? 7.0 : 4.0;
    int stamina = _r.normalInt(mean: staminaMean, sd: 1.5);
    if (minStamina != null && stamina < minStamina) {
      stamina = minStamina;
    }

    // 球種: ストレート + 1〜2球種ランダム
    final extraCount = _r.chance(0.5) ? 2 : 1;
    final extraTypes = _r.pickMany(
      const ['slider', 'curve', 'splitter', 'changeup'],
      extraCount,
    );
    int? slider, curve, splitter, changeup;
    for (final t in extraTypes) {
      final v = _r.normalInt(mean: 5.0 + abilityBoost);
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
      }
    }

    // 投手の利き腕: forcedThrows 指定があればそれ、なければ 右70%・左30%
    final throws = forcedThrows ??
        (_r.chance(0.3) ? Handedness.left : Handedness.right);

    final fastball = _r.normalInt(mean: 5.0 + abilityBoost);
    final control = _r.normalInt(mean: 5.0 + abilityBoost);
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
      stamina: stamina,
      slider: slider,
      curve: curve,
      splitter: splitter,
      changeup: changeup,
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
      reliefRole: reliefRole,
      potentials: _buildPotentials(
        meet: meet,
        power: power,
        speed: speed,
        eye: eye,
        fastball: fastball,
        control: control,
        stamina: stamina,
        slider: slider,
        curve: curve,
        splitter: splitter,
        changeup: changeup,
        bonus: potentialBonus,
      ),
      potentialAverageSpeed:
          _potentialAverageSpeed(avgSpeed, bonus: potentialBonus),
    );
  }

  /// スタメン野手（専任ポジション1つだけ守れる、守備力高め）
  Player generateStarterFielder({
    required int number,
    required DefensePosition primaryPosition,
  }) {
    final fielding = {
      primaryPosition: _r.normalInt(mean: 6.5, sd: 1.5),
    };
    final meet = _r.normalInt();
    final power = _r.normalInt();
    final speed = _r.normalInt();
    final eye = _r.normalInt();
    final arm = _r.normalInt();
    final lead =
        primaryPosition == DefensePosition.catcher ? _r.normalInt() : null;
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
      lead: lead,
      bats: _batterHandedness(),
      throws: _r.chance(0.15) ? Handedness.left : Handedness.right,
      fielding: fielding,
      potentials: _buildPotentials(
        meet: meet,
        power: power,
        speed: speed,
        eye: eye,
        arm: arm,
        lead: lead,
      ),
      potentialFielding: _buildPotentialFielding(fielding),
    );
  }

  /// 控え野手（複数ポジション守れる、能力は全体的にやや低め）
  Player generateBenchFielder({
    required int number,
    required List<DefensePosition> positions,
  }) {
    final fielding = <DefensePosition, int>{};
    for (final pos in positions) {
      fielding[pos] = _r.normalInt(mean: 4.5, sd: 1.5);
    }
    final meet = _r.normalInt(mean: 4.5);
    final power = _r.normalInt(mean: 4.5);
    final speed = _r.normalInt();
    final eye = _r.normalInt();
    final arm = _r.normalInt();
    final lead =
        positions.contains(DefensePosition.catcher) ? _r.normalInt() : null;
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
      lead: lead,
      bats: _batterHandedness(),
      throws: _r.chance(0.15) ? Handedness.left : Handedness.right,
      fielding: fielding,
      potentials: _buildPotentials(
        meet: meet,
        power: power,
        speed: speed,
        eye: eye,
        arm: arm,
        lead: lead,
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
  static const _rookieFieldingPatterns = <List<DefensePosition>>[
    // スペシャリスト（1 ポジション）。外野は実数が多いので重複させて確率を上げる
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
    [DefensePosition.catcher, DefensePosition.first],
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
  }) {
    final boost = _abilityBoostForRookieType(type);
    final potentialBonus = _potentialBonusForRookieType(type);
    final positions = _r.pick(_rookieFieldingPatterns);
    final fielding = <DefensePosition, int>{};
    // 1つ目（メイン）は若手平均、サブはやや低めにする
    for (int i = 0; i < positions.length; i++) {
      final mean = (i == 0 ? 5.5 : 4.5) + boost;
      fielding[positions[i]] = _r.normalInt(mean: mean, sd: 1.5);
    }
    final meet = _r.normalInt(mean: 5.0 + boost, sd: 1.8);
    final power = _r.normalInt(mean: 5.0 + boost, sd: 1.8);
    final speed = _r.normalInt(mean: 5.5 + boost, sd: 1.5);
    final eye = _r.normalInt(mean: 4.5 + boost, sd: 1.5);
    final arm = _r.normalInt(mean: 5.0 + boost);
    final lead = positions.contains(DefensePosition.catcher)
        ? _r.normalInt(mean: 5.0 + boost)
        : null;
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
      lead: lead,
      bats: _batterHandedness(),
      throws: _r.chance(0.15) ? Handedness.left : Handedness.right,
      fielding: fielding,
      potentials: _buildPotentials(
        meet: meet,
        power: power,
        speed: speed,
        eye: eye,
        arm: arm,
        lead: lead,
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
    ReliefRole? reliefRole,
    RookieType type = RookieType.college,
  }) {
    return _generatePitcher(
      number: number,
      isStarter: isStarter,
      reliefRole: reliefRole,
      abilityBoost: _abilityBoostForRookieType(type),
      ageOverride: _ageForRookieType(type),
      rookieType: type,
    );
  }

  /// 1〜10 能力のポテンシャル上限を計算する。
  /// initial が 10 のときはそのまま 10、それ以外は 9 をハードキャップとする。
  int _potentialFor(int? initial, {double bonus = 0.0}) {
    if (initial == null) return 0;
    if (initial >= 10) return 10;
    final raw = initial +
        _potentialBaseMargin +
        bonus +
        _r.nextGaussian() * _potentialSd;
    return raw.round().clamp(initial, _abilityCeiling);
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

  /// 1〜10 能力一式（field name → potential）のマップを構築するヘルパー。
  /// initial が null のキーはマップに含めない（その能力を持たない選手の意）。
  Map<String, int> _buildPotentials({
    int? meet,
    int? power,
    int? speed,
    int? eye,
    int? arm,
    int? lead,
    int? fastball,
    int? control,
    int? stamina,
    int? slider,
    int? curve,
    int? splitter,
    int? changeup,
    double bonus = 0.0,
  }) {
    final map = <String, int>{};
    void put(String key, int? v) {
      if (v == null) return;
      map[key] = _potentialFor(v, bonus: bonus);
    }

    put('meet', meet);
    put('power', power);
    put('speed', speed);
    put('eye', eye);
    put('arm', arm);
    put('lead', lead);
    put('fastball', fastball);
    put('control', control);
    put('stamina', stamina);
    put('slider', slider);
    put('curve', curve);
    put('splitter', splitter);
    put('changeup', changeup);
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
        out[e.key] = _potentialFor(e.value, bonus: bonus);
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
}

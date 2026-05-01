import 'dart:math';
import '../models/models.dart';
import 'name_data.dart';
import 'random_utils.dart';

/// 選手を自動生成する
///
/// - 名前は苗字＋名前のランダム組み合わせで、同一ジェネレーター内では重複しない
/// - 能力値は平均5・標準偏差2の正規分布で1〜10にクリップ
class PlayerGenerator {
  final RandomUtils _r;
  final Set<String> _usedNames;
  int _idCounter;

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
  }) {
    // 球速: 先発135〜150km前後、救援140〜155km前後
    // abilityBoost 1ポイントごとに 2km 補正
    final speedMean = (isStarter ? 140.0 : 145.0) + abilityBoost * 2.0;
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

    return Player(
      id: _newId(),
      name: _uniqueName(),
      number: number,
      age: ageOverride ?? _generateAge(),
      averageSpeed: avgSpeed,
      fastball: _r.normalInt(mean: 5.0 + abilityBoost),
      control: _r.normalInt(mean: 5.0 + abilityBoost),
      stamina: stamina,
      slider: slider,
      curve: curve,
      splitter: splitter,
      changeup: changeup,
      throws: throws,
      // 投手の打撃能力（DH非採用なので打席に立つ。野手より低め）
      // 個別に設定されているので、後でバランス調整しやすい
      meet: _r.normalInt(mean: 2.0, sd: 0.8),
      power: _r.normalInt(mean: 1.5, sd: 0.7),
      eye: _r.normalInt(mean: 2.5, sd: 0.8),
      // 投手の走力は低め（平均3.5）
      speed: _r.normalInt(mean: 3.5, sd: 1.5),
      // 打席（投手も打つ）
      bats: _batterHandedness(),
      reliefRole: reliefRole,
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
    return Player(
      id: _newId(),
      name: _uniqueName(),
      number: number,
      age: _generateAge(),
      meet: _r.normalInt(),
      power: _r.normalInt(),
      speed: _r.normalInt(),
      eye: _r.normalInt(),
      arm: _r.normalInt(),
      lead: primaryPosition == DefensePosition.catcher ? _r.normalInt() : null,
      bats: _batterHandedness(),
      throws: _r.chance(0.15) ? Handedness.left : Handedness.right,
      fielding: fielding,
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
    return Player(
      id: _newId(),
      name: _uniqueName(),
      number: number,
      age: _generateAge(),
      meet: _r.normalInt(mean: 4.5, sd: 2.0),
      power: _r.normalInt(mean: 4.5, sd: 2.0),
      speed: _r.normalInt(),
      eye: _r.normalInt(),
      arm: _r.normalInt(),
      lead: positions.contains(DefensePosition.catcher) ? _r.normalInt() : null,
      bats: _batterHandedness(),
      throws: _r.chance(0.15) ? Handedness.left : Handedness.right,
      fielding: fielding,
    );
  }

  /// 開幕時の年齢分布: 平均 26、標準偏差 4、18〜36 にクリップ。
  /// プロ野球の年齢構成（10代後半 〜 30代前半中心）に近い形。
  int _generateAge() {
    return _r.normalInt(mean: 26.0, sd: 4.0, min: 18, max: 36);
  }

  /// 新人選手の年齢分布: 平均 19.5、標準偏差 1、18〜22 にクリップ。
  int _generateRookieAge() {
    return _r.normalInt(mean: 19.5, sd: 1.0, min: 18, max: 22);
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
  /// - 能力: スタメンと控えの中間（mean 5.0 / sd 1.8）
  /// - 年齢: 18-22。新人なので [PlayerAging] で数年かけて伸びる前提
  ///
  /// 守備位置の整合性は LineupPlanner 側で吸収される
  /// （守れない選手はベンチから昇格してきた選手と入れ替わる）。
  Player generateRookieFielder({required int number}) {
    final positions = _r.pick(_rookieFieldingPatterns);
    final fielding = <DefensePosition, int>{};
    // 1つ目（メイン）は若手平均、サブはやや低めにする
    for (int i = 0; i < positions.length; i++) {
      final mean = i == 0 ? 5.5 : 4.5;
      fielding[positions[i]] = _r.normalInt(mean: mean, sd: 1.5);
    }
    return Player(
      id: _newId(),
      name: _uniqueName(),
      number: number,
      age: _generateRookieAge(),
      meet: _r.normalInt(mean: 5.0, sd: 1.8),
      power: _r.normalInt(mean: 5.0, sd: 1.8),
      speed: _r.normalInt(mean: 5.5, sd: 1.5), // 若い分やや走れる
      eye: _r.normalInt(mean: 4.5, sd: 1.5),
      arm: _r.normalInt(),
      lead: positions.contains(DefensePosition.catcher) ? _r.normalInt() : null,
      bats: _batterHandedness(),
      throws: _r.chance(0.15) ? Handedness.left : Handedness.right,
      fielding: fielding,
    );
  }

  /// 引退者の代わりに加入する新人投手。
  /// - 役割: 引退者と同じロール（先発 or 救援＋ロール種類）
  /// - 能力: 普通投手より少し低めだが、若いので伸びる
  /// - 年齢: 18-22
  Player generateRookiePitcher({
    required int number,
    bool isStarter = true,
    ReliefRole? reliefRole,
  }) {
    return _generatePitcher(
      number: number,
      isStarter: isStarter,
      reliefRole: reliefRole,
      abilityBoost: -0.7,
      ageOverride: _generateRookieAge(),
    );
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

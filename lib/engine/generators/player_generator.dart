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
  final Set<String> _usedNames = {};
  int _idCounter = 0;

  PlayerGenerator({Random? random}) : _r = RandomUtils(random);

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

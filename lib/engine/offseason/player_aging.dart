import 'dart:math';

import '../generators/ability_profile.dart';
import '../generators/random_utils.dart';
import '../models/models.dart';

/// オフシーズンの「年齢+1 と能力変動」を適用するヘルパ。
///
/// **設計** ([feedback_unified_logic_principle]): 全能力 (球速 / 1-10 能力 / 守備力)
/// の加齢処理を [AbilitySampler.ageOneStep] に集約する。能力ごとに「衰え係数」や
/// 「年齢別 mean/sd」を別個に持たず、各能力の [AbilityProfile] と統一 margin
/// テーブルだけで成長/衰えを表現する。
///
/// 「眠った変化球ポテンシャル → 加齢で習得」だけは別ロジックで残す
/// （[_newPitchAcquisitionRate]）。これは「未習得→習得」というイベント性が高く、
/// 段階的収束モデルに乗せにくいため。
class PlayerAging {
  final Random _random;
  final AbilitySampler _sampler;

  /// 「眠った変化球ポテンシャル」を持つ未習得球種を、1 シーズンで習得する確率。
  /// 年齢制限なし（ダルビッシュ型のように年取ってからも新球種を覚える）。
  /// キャリア 15 年で約 85%、20 年でほぼ確実に習得する計算。
  /// 習得時の質はポテンシャル値そのままなので、覚醒した瞬間から決め球になる。
  static const double _newPitchAcquisitionRate = 0.12;

  /// 加齢処理の対象となる変化球キー
  static const Set<String> _breakingBallKeys = {
    'slider', 'curve', 'splitter', 'changeup',
    'shoot', 'cutter', 'sinker',
  };

  PlayerAging({Random? random})
      : _random = random ?? Random(),
        _sampler = AbilitySampler(RandomUtils(random));

  /// 選手 1 名を 1 年加齢して返す。
  Player ageOneYear(Player p) {
    final newAge = p.age + 1;

    /// 1〜10 能力の加齢。統一 API [AbilitySampler.ageOneStep] で処理。
    /// 変化球の場合は「未習得 (v == null) でもポテンシャルがあれば習得判定」を行う。
    /// 持っていない変化球に `potentials` 上で値が入っているのは PlayerGenerator が
    /// 「眠った才能」として 20% で仕込んだもの。
    int? adjust1to10(String key, int? v) {
      if (v == null) {
        if (_breakingBallKeys.contains(key)) {
          final pot = p.potentials?[key];
          if (pot != null &&
              _random.nextDouble() < _newPitchAcquisitionRate) {
            return pot; // 急に決め球を覚える
          }
        }
        return null;
      }
      final cap = p.potentialOf(key, v);
      return _sampler.ageOneStep(
        profile: AbilityProfiles.ability1to10,
        currentValue: v,
        potential: cap,
        newAge: newAge,
      );
    }

    int? adjustSpeed(int? v) {
      if (v == null) return null;
      final cap = p.potentialAverageSpeedOf(v);
      return _sampler.ageOneStep(
        profile: AbilityProfiles.fastballSpeed,
        currentValue: v,
        potential: cap,
        newAge: newAge,
      );
    }

    Map<DefensePosition, int>? adjustFielding(
        Map<DefensePosition, int>? f) {
      if (f == null) return null;
      final out = <DefensePosition, int>{};
      for (final entry in f.entries) {
        if (entry.value == 0) {
          // 「守れない」は維持（年齢で守備位置が増えることはない）
          out[entry.key] = 0;
        } else {
          final cap = p.potentialFieldingOf(entry.key, entry.value);
          out[entry.key] = _sampler.ageOneStep(
            profile: AbilityProfiles.ability1to10,
            currentValue: entry.value,
            potential: cap,
            newAge: newAge,
          );
        }
      }
      return out;
    }

    return Player(
      id: p.id,
      name: p.name,
      number: p.number,
      age: newAge,
      averageSpeed: adjustSpeed(p.averageSpeed),
      fastball: adjust1to10('fastball', p.fastball),
      control: adjust1to10('control', p.control),
      slider: adjust1to10('slider', p.slider),
      curve: adjust1to10('curve', p.curve),
      splitter: adjust1to10('splitter', p.splitter),
      changeup: adjust1to10('changeup', p.changeup),
      shoot: adjust1to10('shoot', p.shoot),
      cutter: adjust1to10('cutter', p.cutter),
      sinker: adjust1to10('sinker', p.sinker),
      stamina: adjust1to10('stamina', p.stamina),
      meet: adjust1to10('meet', p.meet),
      power: adjust1to10('power', p.power),
      speed: adjust1to10('speed', p.speed),
      eye: adjust1to10('eye', p.eye),
      arm: adjust1to10('arm', p.arm),
      fielding: adjustFielding(p.fielding),
      throws: p.throws,
      bats: p.bats,
      pitcherRole: p.pitcherRole,
      // potential は加齢で変動しない（生まれもっての素質として固定）
      potentials: p.potentials,
      potentialFielding: p.potentialFielding,
      potentialAverageSpeed: p.potentialAverageSpeed,
      isForeign: p.isForeign,
    );
  }
}

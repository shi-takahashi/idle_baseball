import 'dart:math';

import '../models/models.dart';

/// オフシーズンの「年齢+1 と能力変動」を適用するヘルパ。
///
/// 設計方針:
/// - **年齢曲線**: 18-21 急成長 / 22-24 緩やかに成長 / 25-28 ピーク（横ばい） /
///   29-31 緩やかに低下 / 32-34 はっきり低下 / 35-37 急低下 / 38+ 大幅低下
/// - **ランダム揺らぎ**: 同じ年齢でも個人差が出るよう、各能力に独立な正規ノイズ
/// - **成長タイプ（早熟/普通/晩成）は未実装**: 全員「普通型」として扱う。後のチャンクで導入
/// - **球速 (km/h)**: 1〜10 の能力とは別曲線で、若い時の上昇・高齢の低下を反映
class PlayerAging {
  final Random _random;

  PlayerAging({Random? random}) : _random = random ?? Random();

  /// 選手 1 名を 1 年加齢して返す。
  Player ageOneYear(Player p) {
    final newAge = p.age + 1;
    final mean = _meanDeltaForAge(newAge);
    // 能力ごとの個人差。小さめの sd で「全能力が同じ向きに動きすぎる」のを抑える
    const sd = 0.6;

    /// 1〜10 能力の加齢適用。potential 上限でクランプ。
    /// potential 未設定の選手（旧セーブ等）は現在値を上限とする = 成長停止。
    int? adjust(String key, int? v) {
      if (v == null) return null;
      final delta = mean + _gauss() * sd;
      final cap = p.potentialOf(key, v);
      return (v + delta.round()).clamp(1, cap);
    }

    int? adjustSpeed(int? v) {
      if (v == null) return null;
      // 球速は 1〜10 とスケールが違うので別係数。1 ポイントあたり 1〜2 km の重み感
      final delta = mean * 1.5 + _gauss() * 1.0;
      final cap = p.potentialAverageSpeedOf(v);
      return (v + delta.round()).clamp(110, cap);
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
          final delta = mean + _gauss() * sd;
          final cap = p.potentialFieldingOf(entry.key, entry.value);
          out[entry.key] = (entry.value + delta.round()).clamp(1, cap);
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
      fastball: adjust('fastball', p.fastball),
      control: adjust('control', p.control),
      stamina: adjust('stamina', p.stamina),
      slider: adjust('slider', p.slider),
      curve: adjust('curve', p.curve),
      splitter: adjust('splitter', p.splitter),
      changeup: adjust('changeup', p.changeup),
      meet: adjust('meet', p.meet),
      power: adjust('power', p.power),
      speed: adjust('speed', p.speed),
      eye: adjust('eye', p.eye),
      arm: adjust('arm', p.arm),
      lead: adjust('lead', p.lead),
      fielding: adjustFielding(p.fielding),
      throws: p.throws,
      bats: p.bats,
      reliefRole: p.reliefRole,
      // potential は加齢で変動しない（生まれもっての素質として固定）
      potentials: p.potentials,
      potentialFielding: p.potentialFielding,
      potentialAverageSpeed: p.potentialAverageSpeed,
    );
  }

  /// 加齢後の年齢に対する平均的な能力変化量（1〜10 の能力に直接加算する想定）
  double _meanDeltaForAge(int newAge) {
    if (newAge <= 21) return 1.5;
    if (newAge <= 24) return 0.5;
    if (newAge <= 28) return 0.0;
    if (newAge <= 31) return -0.3;
    if (newAge <= 34) return -0.7;
    if (newAge <= 37) return -1.2;
    return -1.8;
  }

  /// Box-Muller 法による標準正規分布のサンプル
  double _gauss() {
    final u1 = _random.nextDouble().clamp(1e-9, 1.0);
    final u2 = _random.nextDouble();
    return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
  }
}

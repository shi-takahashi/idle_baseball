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

  /// 能力別の「衰えやすさ」係数（delta が負のときに掛ける）。
  /// 衰えは「動体視力 / 反応速度 / 瞬発系」が先に来て、「筋力系」が後から、
  /// という順序を反映する。
  ///
  ///   先に衰える系（0.5）:
  ///     - 走力（瞬発・スタミナ）
  ///     - 選球眼（動体視力）
  ///     - 守備（反応速度の 1 歩目の遅れ。`_fieldingDeclineFactor` で別管理）
  ///   やや早く衰える系（0.4）:
  ///     - ミート（反応速度低下で振り遅れが出る。技術である程度補える）
  ///     - 長打（パワーは維持できるが、バットスピード低下で打球が伸びにくくなる）
  ///   後から衰える系（0.3）:
  ///     - 肩（送球の強さは筋力主体で長持ち）
  ///   投手系:
  ///     - 制球 / 各変化球: 技術で維持 (0.3)
  ///     - 伸び (fastball): 体力依存 (0.5)
  ///   球速 (averageSpeed) は別計算 (`adjustSpeed`) なのでここには含めない。
  ///
  /// 値 1.0 = `_meanDeltaForAge` の負側をそのまま反映、0.5 なら半分の速度で落ちる。
  static const Map<String, double> _abilityDeclineFactor = {
    // 野手能力
    'speed': 0.5,
    'eye': 0.5,
    'meet': 0.4,
    'power': 0.4,
    'arm': 0.3,
    // 投手能力
    'control': 0.3,
    'fastball': 0.5,
    'slider': 0.3,
    'curve': 0.3,
    'splitter': 0.3,
    'changeup': 0.3,
    'shoot': 0.3,
    'cutter': 0.3,
    'sinker': 0.3,
  };

  /// 守備力の衰え係数。反応速度低下が大きく、先に衰える系。
  static const double _fieldingDeclineFactor = 0.5;

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

  PlayerAging({Random? random}) : _random = random ?? Random();

  /// 選手 1 名を 1 年加齢して返す。
  Player ageOneYear(Player p) {
    final newAge = p.age + 1;
    final mean = _meanDeltaForAge(newAge);
    // 能力ごとの個人差。小さめの sd で「全能力が同じ向きに動きすぎる」のを抑える
    const sd = 0.6;

    /// 1〜10 能力の加齢適用。potential 上限でクランプ。
    /// potential 未設定の選手（旧セーブ等）は現在値を上限とする = 成長停止。
    /// 衰え方向（delta < 0）は能力別の係数 [_abilityDeclineFactor] を掛ける:
    /// 「走力は加齢で落ちる」「ミートは技術系で維持」など現実の選手挙動に近づける。
    /// 成長方向は係数を掛けない（成長は potential cap で頭打ちになるので非対称でOK）。
    ///
    /// 変化球の場合は「未習得（v == null）でもポテンシャルがあれば習得判定」を行う。
    /// 持っていない変化球に `potentials` 上で値が入っているのは PlayerGenerator が
    /// 「眠った才能」として 20% で仕込んだもの。`_newPitchAcquisitionRate` の確率で
    /// 覚醒し、その瞬間からポテンシャル値（=決め球レベル）で投げられるようになる。
    int? adjust(String key, int? v) {
      if (v == null) {
        // 変化球の眠ったポテンシャル発動を判定
        if (_breakingBallKeys.contains(key)) {
          final pot = p.potentials?[key];
          if (pot != null &&
              _random.nextDouble() < _newPitchAcquisitionRate) {
            return pot; // 急に決め球を覚える
          }
        }
        return null;
      }
      double delta = mean + _gauss() * sd;
      if (delta < 0) {
        final factor = _abilityDeclineFactor[key] ?? 1.0;
        delta *= factor;
      }
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
          double delta = mean + _gauss() * sd;
          if (delta < 0) {
            // 守備力は反応速度低下があるが、ある程度技術で維持できる
            delta *= _fieldingDeclineFactor;
          }
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
      slider: adjust('slider', p.slider),
      curve: adjust('curve', p.curve),
      splitter: adjust('splitter', p.splitter),
      changeup: adjust('changeup', p.changeup),
      shoot: adjust('shoot', p.shoot),
      cutter: adjust('cutter', p.cutter),
      sinker: adjust('sinker', p.sinker),
      meet: adjust('meet', p.meet),
      power: adjust('power', p.power),
      speed: adjust('speed', p.speed),
      eye: adjust('eye', p.eye),
      arm: adjust('arm', p.arm),
      fielding: adjustFielding(p.fielding),
      throws: p.throws,
      bats: p.bats,
      pitcherRole: p.pitcherRole,
      // potential は加齢で変動しない（生まれもっての素質として固定）
      potentials: p.potentials,
      potentialFielding: p.potentialFielding,
      potentialAverageSpeed: p.potentialAverageSpeed,
    );
  }

  /// 加齢後の年齢に対する平均的な能力変化量（1〜10 の能力に直接加算する想定）。
  /// NPB の打撃・投手のピーク年齢は 27 前後（一般に研究でも 27-29 がピーク帯）
  /// なので、ピーク帯を 26-29 にしている。
  /// 後段（36+）の衰えは、リーグに数名いる「40 歳まで現役を続ける選手」が
  /// 何かしらの能力で平均以上を維持できる程度に抑えている。
  double _meanDeltaForAge(int newAge) {
    if (newAge <= 22) return 1.5; // 急成長
    if (newAge <= 25) return 0.5; // 緩やか成長
    if (newAge <= 29) return 0.0; // ピーク（4 年）
    if (newAge <= 32) return -0.3; // 緩やかに低下
    if (newAge <= 35) return -0.7; // はっきり低下
    if (newAge <= 37) return -0.9; // 急低下
    return -1.3; // 38+ 大幅低下（ただし能力別係数で抑えられる）
  }

  /// Box-Muller 法による標準正規分布のサンプル
  double _gauss() {
    final u1 = _random.nextDouble().clamp(1e-9, 1.0);
    final u2 = _random.nextDouble();
    return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
  }
}

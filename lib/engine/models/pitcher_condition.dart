import 'dart:math';

/// 投手の調子（試合ごとに変動）
/// 各パラメータに±2の補正を適用
class PitcherCondition {
  final int speedModifier;     // 球速補正（-2〜+2 km/h）
  final int fastballModifier;  // ストレートの質補正（-2〜+2）
  final int controlModifier;   // 制球力補正（-2〜+2）
  final int sliderModifier;    // スライダー補正（-2〜+2）
  final int curveModifier;     // カーブ補正（-2〜+2）
  final int splitterModifier;  // スプリット補正（-2〜+2）
  final int changeupModifier;  // チェンジアップ補正（-2〜+2）

  const PitcherCondition({
    this.speedModifier = 0,
    this.fastballModifier = 0,
    this.controlModifier = 0,
    this.sliderModifier = 0,
    this.curveModifier = 0,
    this.splitterModifier = 0,
    this.changeupModifier = 0,
  });

  /// ランダムに調子を生成（各パラメータ独立に-2〜+2）
  factory PitcherCondition.random(Random random) {
    return PitcherCondition(
      speedModifier: random.nextInt(5) - 2,     // -2, -1, 0, +1, +2
      fastballModifier: random.nextInt(5) - 2,
      controlModifier: random.nextInt(5) - 2,
      sliderModifier: random.nextInt(5) - 2,
      curveModifier: random.nextInt(5) - 2,
      splitterModifier: random.nextInt(5) - 2,
      changeupModifier: random.nextInt(5) - 2,
    );
  }

  /// 絶好調（全パラメータ+2）
  static const excellent = PitcherCondition(
    speedModifier: 2,
    fastballModifier: 2,
    controlModifier: 2,
    sliderModifier: 2,
    curveModifier: 2,
    splitterModifier: 2,
    changeupModifier: 2,
  );

  /// 絶不調（全パラメータ-2）
  static const terrible = PitcherCondition(
    speedModifier: -2,
    fastballModifier: -2,
    controlModifier: -2,
    sliderModifier: -2,
    curveModifier: -2,
    splitterModifier: -2,
    changeupModifier: -2,
  );

  /// 普通（全パラメータ±0）
  static const normal = PitcherCondition();

  @override
  String toString() {
    return 'PitcherCondition(速$speedModifier, 直$fastballModifier, 制$controlModifier, '
        'ス$sliderModifier, カ$curveModifier, フ$splitterModifier, チ$changeupModifier)';
  }
}

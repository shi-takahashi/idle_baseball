import 'dart:math';

/// 乱数ユーティリティ（正規分布・リスト選択など）
class RandomUtils {
  final Random random;

  RandomUtils([Random? random]) : random = random ?? Random();

  /// Box-Muller法で標準正規分布（平均0、標準偏差1）から乱数を生成
  double nextGaussian() {
    double u1 = random.nextDouble();
    if (u1 == 0.0) u1 = 1e-10; // log(0)回避
    final u2 = random.nextDouble();
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }

  /// 正規分布ベースの整数（範囲クリップ）
  /// デフォルトは平均5、標準偏差1.2で **1〜8** にクリップ。
  ///
  /// 能力値 9 は「数年に1人の逸材」として極めて稀。自動生成の正規分布の裾で
  /// 出すと毎リーグ複数人になってしまうため、デフォルトでは max=8 でクリップし、
  /// 値 9 への昇格は [abilityInt] のプロモート抽選で別経路として用意する。
  /// 値 10 は自動生成・成長では絶対に出ない（手動編集のみ）。
  ///
  /// 1〜8 の整数値の出現率（mean=5, sd=1.2）:
  ///   1:0.04% 2:1.0% 3:8.6% 4:23.8% 5:30.7% 6:23.8% 7:8.6% 8:3.5%
  /// （8 の値は clamp 効果で本来の片側裾ぶんが乗るため 3.5% に集約される。
  ///  値 9 への昇格は [abilityInt] で別途扱う）
  ///
  /// 年齢など 1〜10 以外のレンジで使う場合は `min` / `max` を明示的に渡す。
  int normalInt({double mean = 5.0, double sd = 1.2, int min = 1, int max = 8}) {
    final value = mean + nextGaussian() * sd;
    return value.round().clamp(min, max);
  }

  /// 能力値 (1〜9) 用の生成。`normalInt` で 1〜8 を出した後、
  /// [promoteNineChance] の確率で 9 にプロモートする。
  ///
  /// 「9 = 数年に1人の逸材」を実現するため、自然分布の裾ではなく独立抽選で出す。
  /// デフォルト 0.05% × リーグ132野手 = 0.066人/リーグ ≈ 15 リーグに 1 人。
  /// 新人加入も含めると、リーグ全体で 10〜15 年に 1 人だけ「初期 9」が現れる頻度。
  ///
  /// 各能力（power, meet, ...）ごとに独立抽選するので、新人選手が複数の能力で
  /// 同時に 9 を持つことは事実上ない。
  int abilityInt({
    double mean = 5.0,
    double sd = 1.2,
    double promoteNineChance = 0.0005,
    int min = 1,
  }) {
    if (chance(promoteNineChance)) return 9;
    return normalInt(mean: mean, sd: sd, min: min, max: 8);
  }

  /// 正規分布ベースのdouble（範囲クリップなし）
  double normalDouble({required double mean, required double sd}) {
    return mean + nextGaussian() * sd;
  }

  /// リストから1要素をランダム選択
  T pick<T>(List<T> list) => list[random.nextInt(list.length)];

  /// 指定数の要素をランダム選択（重複なし）
  List<T> pickMany<T>(List<T> list, int count) {
    final shuffled = [...list]..shuffle(random);
    return shuffled.take(count).toList();
  }

  /// 確率pでtrue
  bool chance(double p) => random.nextDouble() < p;
}

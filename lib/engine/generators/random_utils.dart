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
  /// デフォルトは平均5、標準偏差1.5で **1〜9** にクリップ。
  ///
  /// 能力値 10 は「特別」な扱いで、**自動生成では出現させない**（手動編集
  /// でのみ到達できる）。そのためデフォルトの上限は 10 ではなく 9。
  /// 加齢成長のポテンシャル上限も 9（`PlayerGenerator._abilityCeiling`）
  /// なので、生成後の成長でも 10 には届かない。
  ///
  /// 1〜9 の整数値の出現率（mean=5, sd=1.5）:
  ///   1:1.0% 2:3.8% 3:11.1% 4:21.2% 5:25.9%
  ///   6:21.2% 7:11.1% 8:3.8% 9:1.0%
  /// 中央（5）に集中させ、両端（1 や 9）は希少にしてある。
  ///
  /// 年齢など 1〜10 以外のレンジで使う場合は `min` / `max` を明示的に渡す。
  int normalInt({double mean = 5.0, double sd = 1.5, int min = 1, int max = 9}) {
    final value = mean + nextGaussian() * sd;
    return value.round().clamp(min, max);
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

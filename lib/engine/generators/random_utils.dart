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
  /// デフォルトは平均5、標準偏差2で 1〜10 にクリップ
  int normalInt({double mean = 5.0, double sd = 2.0, int min = 1, int max = 10}) {
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

import '../models/at_bat_result.dart';
import '../models/enums.dart';

/// 1打席の集約情報（OPS 計算用）
class _PA {
  final bool isAB; // 打数にカウントされるか（四球・犠飛は false）
  final bool isHit;
  final bool isWalk;
  final int totalBases; // 塁打数（単打1〜本塁打4、それ以外は0）

  const _PA._({
    required this.isAB,
    required this.isHit,
    required this.isWalk,
    required this.totalBases,
  });

  factory _PA.from(AtBatResult ab) {
    final type = ab.result;
    final isWalk = type == AtBatResultType.walk;
    // 犠飛: 外野フライで打点ありを犠飛扱い（aggregator と同じ簡易判定）
    final isSacFly = type == AtBatResultType.flyOut && ab.rbiCount > 0;
    final isAB = !isWalk && !isSacFly;
    final isHit = type.isHit;
    final int tb;
    switch (type) {
      case AtBatResultType.single:
      case AtBatResultType.infieldHit:
        tb = 1;
        break;
      case AtBatResultType.double_:
        tb = 2;
        break;
      case AtBatResultType.triple:
        tb = 3;
        break;
      case AtBatResultType.homeRun:
        tb = 4;
        break;
      default:
        tb = 0;
    }
    return _PA._(
      isAB: isAB,
      isHit: isHit,
      isWalk: isWalk,
      totalBases: tb,
    );
  }
}

/// 1選手の直近の打席を保持して OPS を計算するクラス。
///
/// 打順決定や代替起用のための「調子」指標として使う。
/// 規定の打席数（[minSampleForOPS]）に満たない場合は判定不能扱いとし、
/// 呼び出し側でデフォルト値（中立=1.0）にフォールバックする。
class RecentForm {
  /// 保持する最大打席数（リングバッファ的に古いものから捨てる）
  static const int maxWindow = 30;

  /// OPS 計算に必要な最小サンプル数
  static const int minSampleForOPS = 10;

  final List<_PA> _window = [];

  void recordAtBat(AtBatResult ab) {
    if (ab.isIncomplete) return;
    // 送りバントは打者が「打ちに行った打席」ではないので調子の指標から除外
    if (ab.result == AtBatResultType.sacrificeBunt) return;
    _window.add(_PA.from(ab));
    if (_window.length > maxWindow) _window.removeAt(0);
  }

  int get sampleSize => _window.length;

  /// 直近の OPS。サンプル数が足りない場合は 0 を返す（呼び出し側で代替）
  double get recentOPS {
    if (_window.length < minSampleForOPS) return 0;
    int ab = 0, hits = 0, walks = 0, totalBases = 0;
    for (final pa in _window) {
      if (pa.isAB) ab++;
      if (pa.isHit) hits++;
      if (pa.isWalk) walks++;
      totalBases += pa.totalBases;
    }
    final pa = _window.length;
    final obp = (hits + walks) / pa;
    final slg = ab == 0 ? 0.0 : totalBases / ab;
    return obp + slg;
  }
}

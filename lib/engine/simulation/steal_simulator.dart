import 'dart:math';
import '../models/models.dart';

/// 盗塁シミュレーター
///
/// 走力 vs 試行確率は非線形。平均（走力5）はほぼ盗塁せず、走力7〜8 から急増する。
/// 「盗塁は走力の高い選手の特権」というデザイン。試みた場合の成功率は基本的に
/// 高めで、走力と捕手の肩の差で上下する。
class StealSimulator {
  final Random _random;

  /// 走力ごとの 1 球あたり盗塁試行確率
  ///
  /// 線形ではなく、俊足層（走力 7〜）に発動が偏る非線形カーブ。盗塁数の大部分は
  /// 走力 7 以上の選手が稼ぐ形にする。
  ///
  /// - 走力 1: 仕掛けない（走力差を明確化するため）
  /// - 走力 2〜4: ごく稀に仕掛ける（投手のクセを読む等のレアケース）
  /// - 走力 5: 平均はめったに走らないが、ゼロではない
  /// - 走力 6 以下: 控えめ
  /// - 走力 7 以上: ここで急増。盗塁の主役
  static const Map<int, double> _attemptRateBySpeed = {
    1: 0.0,
    2: 0.0005,
    3: 0.0012,
    4: 0.0025,
    5: 0.0040,
    6: 0.009,
    7: 0.022,
    8: 0.042,
    9: 0.065,
    10: 0.085,
  };

  // 盗塁成功の基本確率（試行した時点でそれなりに高い）
  static const double _baseStealSuccessRate = 0.75; // 75%

  // 基準走力 / 基準捕手肩
  static const int _baseSpeed = 5;
  static const int _baseArm = 5;

  // 走力による盗塁成功率補正（1あたり）
  static const double _speedSuccessModifier = 0.03;

  // 捕手の肩による盗塁成功率補正（1あたり、肩が強いほど成功率DOWN）
  static const double _catcherArmModifier = 0.025;

  StealSimulator({Random? random}) : _random = random ?? Random();

  /// 走力ごとの試行確率を返す
  static double _attemptRateFor(int speed) {
    if (speed <= 0) return 0.0;
    if (speed >= 10) return _attemptRateBySpeed[10]!;
    return _attemptRateBySpeed[speed] ?? 0.0;
  }

  /// 走力 vs 捕手肩から盗塁成功率を算出する
  static double _successRateFor(int speed, int catcherArm) {
    final speedDiff = speed - _baseSpeed;
    final armDiff = catcherArm - _baseArm;
    final rate = _baseStealSuccessRate +
        speedDiff * _speedSuccessModifier -
        armDiff * _catcherArmModifier;
    return rate.clamp(0.50, 0.95);
  }

  /// 盗塁を試みるか判定し、試みる場合は成功/失敗を判定
  /// catcherArm: 捕手の肩の強さ（1-10、デフォルト5）
  /// 戻り値: 盗塁の試みリスト（空なら盗塁なし）
  List<StealAttempt> simulateSteal(BaseRunners runners, int outs, {int catcherArm = 5}) {
    // 盗塁可能なランナーを取得
    final candidates = runners.getStealCandidates();
    if (candidates.isEmpty) return [];

    // ダブルスチールかどうか判定
    final isDoubleSteal = candidates.length >= 2;

    // 盗塁を試みるかどうか判定
    // ダブルスチールの場合は2塁ランナー（3塁への盗塁）の走力で判定
    //   → 3塁送球が短いので、3塁を取りにいく走者の脚が決め手
    // 単独盗塁の場合はそのランナーの走力で判定
    final keyRunner = isDoubleSteal
        ? candidates.firstWhere((c) => c.$2 == Base.second, orElse: () => candidates.first)
        : candidates.first;
    final runnerSpeed = keyRunner.$1.speed ?? _baseSpeed;

    final attemptRate = _attemptRateFor(runnerSpeed);
    if (attemptRate <= 0.0 || _random.nextDouble() >= attemptRate) {
      return []; // 盗塁を試みない
    }

    // 盗塁を試みる
    if (isDoubleSteal) {
      // ダブルスチールの場合
      // キャッチャーは3塁に送球するので、2塁ランナーの成否のみ判定
      final secondRunner = candidates.firstWhere((c) => c.$2 == Base.second);
      final firstRunner = candidates.firstWhere((c) => c.$2 == Base.first);

      final speed = secondRunner.$1.speed ?? _baseSpeed;
      final successRate = _successRateFor(speed, catcherArm);
      final success = _random.nextDouble() < successRate;

      if (success) {
        // 成功: 両者とも進塁、両者とも盗塁成功
        return [
          StealAttempt(
            runner: secondRunner.$1,
            fromBase: secondRunner.$2,
            toBase: secondRunner.$3,
            success: true,
          ),
          StealAttempt(
            runner: firstRunner.$1,
            fromBase: firstRunner.$2,
            toBase: firstRunner.$3,
            success: true,
          ),
        ];
      } else {
        // 失敗: 2塁ランナーはアウト、1塁ランナーは2塁へ進塁（記録上は盗塁なし）
        return [
          StealAttempt(
            runner: secondRunner.$1,
            fromBase: secondRunner.$2,
            toBase: secondRunner.$3,
            success: false,
            isOut: true, // 2塁ランナーはアウト
          ),
          // 1塁ランナーは進塁するが、盗塁成功としてカウントしない
          StealAttempt(
            runner: firstRunner.$1,
            fromBase: firstRunner.$2,
            toBase: firstRunner.$3,
            success: false, // 記録上は盗塁なし
            isOut: false, // アウトにはならず、2塁へ進塁
          ),
        ];
      }
    } else {
      // 単独盗塁の場合
      final (runner, fromBase, toBase) = candidates.first;
      final speed = runner.speed ?? _baseSpeed;
      final successRate = _successRateFor(speed, catcherArm);
      final success = _random.nextDouble() < successRate;

      return [
        StealAttempt(
          runner: runner,
          fromBase: fromBase,
          toBase: toBase,
          success: success,
          isOut: !success, // 失敗したらアウト
        ),
      ];
    }
  }

  /// 盗塁結果を適用してランナー状況とアウト数を更新
  /// 戻り値: (新しいランナー状況, 新しいアウト数)
  (BaseRunners, int) applyStealResult(
    BaseRunners runners,
    int outs,
    List<StealAttempt> attempts,
  ) {
    if (attempts.isEmpty) return (runners, outs);

    var newRunners = runners;
    var newOuts = outs;

    // ダブルスチールの判定
    final isDoubleSteal = attempts.length >= 2;

    if (isDoubleSteal) {
      // ダブルスチールの場合
      final secondBaseAttempt = attempts.firstWhere((a) => a.fromBase == Base.second);
      final firstBaseAttempt = attempts.firstWhere((a) => a.fromBase == Base.first);

      if (secondBaseAttempt.success) {
        // 成功: 両者とも進塁、盗塁成功
        final steals = attempts.map((a) => (a.runner, a.fromBase, a.toBase)).toList();
        newRunners = newRunners.afterSuccessfulSteal(steals);
      } else {
        // 失敗: 2塁ランナーはアウト、1塁ランナーは2塁へ進塁（盗塁記録なし）
        newRunners = newRunners.afterFailedSteal(secondBaseAttempt.runner, secondBaseAttempt.fromBase);
        newOuts++;

        // 1塁ランナーを2塁へ進塁させる（盗塁記録なし）
        newRunners = BaseRunners(
          first: null,
          second: firstBaseAttempt.runner,
          third: newRunners.third,
        );
      }
    } else {
      // 単独盗塁の場合
      final attempt = attempts.first;
      if (attempt.success) {
        final steals = [(attempt.runner, attempt.fromBase, attempt.toBase)];
        newRunners = newRunners.afterSuccessfulSteal(steals);
      } else {
        newRunners = newRunners.afterFailedSteal(attempt.runner, attempt.fromBase);
        newOuts++;
      }
    }

    return (newRunners, newOuts);
  }
}

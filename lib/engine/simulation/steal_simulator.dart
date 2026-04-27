import 'dart:math';
import '../models/models.dart';

/// 盗塁シミュレーター
class StealSimulator {
  final Random _random;

  // 盗塁を試みる基本確率（盗塁可能な状況で、1球あたり）
  // NPB の 1チーム年間 ~50 盗塁 (143試合) 水準を狙ってチューニング:
  // 30試合シーズンなら 1チーム ~10 盗塁前後を想定
  static const double _baseStealAttemptRate = 0.015; // 1.5%

  // 基準走力
  static const int _baseSpeed = 5;

  // 走力による盗塁試行確率補正（1あたり）
  // 走力1: 約0.5%、走力5: 1.5%、走力10: 約4%
  static const double _speedAttemptModifier = 0.005;

  // 盗塁成功の基本確率
  static const double _baseStealSuccessRate = 0.70; // 70%

  // 走力による盗塁成功率補正（1あたり）
  static const double _speedSuccessModifier = 0.05;

  // 基準捕手の肩
  static const int _baseArm = 5;

  // 捕手の肩による盗塁成功率補正（1あたり、肩が強いほど成功率DOWN）
  static const double _catcherArmModifier = 0.025;

  StealSimulator({Random? random}) : _random = random ?? Random();

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
    // 単独盗塁の場合はそのランナーの走力で判定
    final keyRunner = isDoubleSteal
        ? candidates.firstWhere((c) => c.$2 == Base.second, orElse: () => candidates.first)
        : candidates.first;
    final runnerSpeed = keyRunner.$1.speed ?? _baseSpeed;

    final speedDiff = runnerSpeed - _baseSpeed;
    final attemptRate =
        (_baseStealAttemptRate + speedDiff * _speedAttemptModifier)
            .clamp(0.002, 0.05);

    if (_random.nextDouble() >= attemptRate) {
      return []; // 盗塁を試みない
    }

    // 盗塁を試みる
    if (isDoubleSteal) {
      // ダブルスチールの場合
      // キャッチャーは3塁に送球するので、2塁ランナーの成否のみ判定
      final secondRunner = candidates.firstWhere((c) => c.$2 == Base.second);
      final firstRunner = candidates.firstWhere((c) => c.$2 == Base.first);

      final speed = secondRunner.$1.speed ?? _baseSpeed;
      final speedDiff = speed - _baseSpeed;
      final armDiff = catcherArm - _baseArm;
      final successRate = (_baseStealSuccessRate + speedDiff * _speedSuccessModifier - armDiff * _catcherArmModifier).clamp(0.40, 0.95);
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
      final speedDiff = speed - _baseSpeed;
      final armDiff = catcherArm - _baseArm;
      final successRate = (_baseStealSuccessRate + speedDiff * _speedSuccessModifier - armDiff * _catcherArmModifier).clamp(0.40, 0.95);
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

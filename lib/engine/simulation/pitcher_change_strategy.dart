import 'dart:math';

import '../models/base_runners.dart';
import '../models/player.dart';
import 'team_pitching_state.dart';

/// 投手交代判断に必要な試合状況
///
/// 戦略クラスに渡す「判断材料のまとまり」。後から情報が増えても、
/// このクラスにフィールドを足すだけでストラテジー側の拡張が可能。
class PitcherChangeContext {
  /// 投手側の運用状態（現投手、投球数、連打/失点/ブルペン残り等）
  final TeamPitchingState pitchingState;

  /// 現在のイニング（1〜）
  final int inning;

  /// 現在のハーフイニングが表かどうか（投手は守備側）
  final bool isTop;

  /// 現在のアウトカウント（0〜2）
  final int outs;

  /// 投手側チームの現在得点
  final int myTeamScore;

  /// 相手（攻撃側）チームの現在得点
  final int opponentScore;

  /// 現在のランナー状況
  final BaseRunners runners;

  /// ランダム性が欲しい場合に使用（日ごとの気分、ランダム判定など）
  final Random random;

  const PitcherChangeContext({
    required this.pitchingState,
    required this.inning,
    required this.isTop,
    required this.outs,
    required this.myTeamScore,
    required this.opponentScore,
    required this.runners,
    required this.random,
  });

  /// 得点差（正=投手チームがリード）
  int get scoreDiff => myTeamScore - opponentScore;

  Player get currentPitcher => pitchingState.currentPitcher;
  int get currentPitchCount => pitchingState.pitchCount;
  List<Player> get availableRelievers => pitchingState.bullpen;
}

/// 投手交代の決定
class PitcherChangeDecision {
  /// 交代先の投手
  final Player newPitcher;

  /// 交代理由（表示・デバッグ用）
  final String reason;

  const PitcherChangeDecision({
    required this.newPitcher,
    required this.reason,
  });
}

/// 投手交代の判断を行う戦略
///
/// 拡張イメージ:
/// - 監督の信頼度・性格を加味した戦略
/// - ロングリリーフ/セットアッパー/クローザーの役割別に選ぶ戦略
/// - 学習ベース（過去の相性に基づく）戦略
abstract class PitcherChangeStrategy {
  /// 現時点で投手交代すべきか判定する
  /// 交代しない場合は null を返す
  PitcherChangeDecision? decide(PitcherChangeContext context);
}

/// デフォルトの単純な戦略
///
/// 以下の条件のいずれかを満たすと交代する（上から優先度順にチェック）:
/// - ブルペンがいれば、投球数が100球以上
/// - 現投手が5失点以上
/// - 3連打以上を打たれた
/// - 3連続四球
/// - 7回以降、同点以下、得点圏ランナーありかつ50球以上投げている
class SimplePitcherChangeStrategy implements PitcherChangeStrategy {
  /// 投球数による交代の閾値
  final int pitchCountThreshold;

  /// 失点による交代の閾値
  final int runsAllowedThreshold;

  /// 連打による交代の閾値
  final int hitsStreakThreshold;

  /// 連続四球による交代の閾値
  final int walksStreakThreshold;

  const SimplePitcherChangeStrategy({
    this.pitchCountThreshold = 100,
    this.runsAllowedThreshold = 5,
    this.hitsStreakThreshold = 3,
    this.walksStreakThreshold = 3,
  });

  @override
  PitcherChangeDecision? decide(PitcherChangeContext context) {
    final state = context.pitchingState;
    // ブルペンに残っている投手がいなければ交代不可
    if (state.bullpen.isEmpty) return null;

    String? reason;

    // 1. 球数超過
    if (state.pitchCount >= pitchCountThreshold) {
      reason = '${state.pitchCount}球';
    }
    // 2. 大量失点
    else if (state.runsAllowed >= runsAllowedThreshold) {
      reason = '${state.runsAllowed}失点';
    }
    // 3. 連打
    else if (state.hitsAllowedStreak >= hitsStreakThreshold) {
      reason = '${state.hitsAllowedStreak}連打';
    }
    // 4. 連続四球
    else if (state.walksStreak >= walksStreakThreshold) {
      reason = '${state.walksStreak}連続四球';
    }
    // 5. 終盤のピンチ（7回以降、同点以下、得点圏、50球超）
    else if (context.inning >= 7 &&
        context.scoreDiff <= 0 &&
        (context.runners.second != null || context.runners.third != null) &&
        state.pitchCount >= 50) {
      reason = '終盤のピンチ';
    }

    if (reason == null) return null;

    // 拡張ポイント: ここで役割（セットアッパー/クローザー）を考慮した選択ができる
    final newPitcher = _selectReliever(context);
    return PitcherChangeDecision(newPitcher: newPitcher, reason: reason);
  }

  /// 交代先の投手を選択する
  /// デフォルトはブルペンの先頭投手を起用（登録順 = 起用優先順）
  Player _selectReliever(PitcherChangeContext context) {
    return context.availableRelievers.first;
  }
}

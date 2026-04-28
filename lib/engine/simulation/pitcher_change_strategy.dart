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

  /// 抑え投手（指名されていれば）。試合中まだ未登板で、かつコンディション
  /// 上使用可能な場合のみ非 null。SeasonController がフレッシュさを判断して
  /// 渡す。`pitchingState.bullpen` から外れていないことが前提。
  final Player? closer;

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
    this.closer,
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
/// 先発投手の場合（`usedPitchers.first` がマウンドにいる場合）:
/// - 投球数が `pitchCountThreshold`（100球）以上
/// - `runsAllowedThreshold`（5）失点以上
/// - 3連打、3連続四球
/// - 7回以降、同点以下、得点圏ありかつ50球以上
///
/// リリーフ投手の場合:
/// - イニング境界（outs == 0）かつ既に `relieverPitchCountThreshold`（25球）以上
///   → 1イニング前後で次の投手にスイッチ。NPB の中継ぎ・抑えの一般的な使い方
/// - 上記スターターと同じ「失点しすぎ・連打・連続四球」も適用
class SimplePitcherChangeStrategy implements PitcherChangeStrategy {
  /// 先発の球数による交代の閾値
  final int pitchCountThreshold;

  /// リリーフの球数による交代の閾値（イニング境界で適用）
  final int relieverPitchCountThreshold;

  /// 失点による交代の閾値
  final int runsAllowedThreshold;

  /// 連打による交代の閾値
  final int hitsStreakThreshold;

  /// 連続四球による交代の閾値
  final int walksStreakThreshold;

  const SimplePitcherChangeStrategy({
    this.pitchCountThreshold = 100,
    this.relieverPitchCountThreshold = 25,
    this.runsAllowedThreshold = 5,
    this.hitsStreakThreshold = 3,
    this.walksStreakThreshold = 3,
  });

  @override
  PitcherChangeDecision? decide(PitcherChangeContext context) {
    final state = context.pitchingState;
    // ブルペンに残っている投手がいなければ交代不可
    if (state.bullpen.isEmpty) return null;

    final isStarter = state.currentPitcher.id == state.usedPitchers.first.id;
    final isCurrentCloser = context.closer != null &&
        state.currentPitcher.id == context.closer!.id;

    // ---- 抑え投手の起用判断（セーブ状況） ----
    // 以下のいずれかで、現投手を降ろして抑えに切り替える:
    //   A. 9回以降のセーブ機会
    //   B. 8回途中のピンチ（接戦＋得点圏走者）
    // 適用しない場合:
    //   - 抑えが既にマウンドにいる
    //   - 抑えが未指名 or 当日不在
    //   - 先発が完封ペース（無失点 + 球数 < 100 + 9回頭）→ 続投で完封狙い
    if (!isCurrentCloser &&
        context.closer != null &&
        !_isStarterOnShutoutPace(context, isStarter)) {
      if (_isSaveSituation(context)) {
        return PitcherChangeDecision(
          newPitcher: context.closer!,
          reason: 'セーブ機会',
        );
      }
      if (_isLatePinchInEighth(context)) {
        return PitcherChangeDecision(
          newPitcher: context.closer!,
          reason: '8回ピンチ',
        );
      }
    }

    String? reason;

    // 抑えが既にマウンドにいる場合は、よっぽどの理由がないと降ろさない
    // （25球到達でのイニング境界スイッチや終盤ピンチでの降板を抑止）
    if (isCurrentCloser) {
      // 1イニング限定: 10回以降のイニング境界（outs == 0）で交代
      // 現代野球では抑えは基本 1IP 運用なので、延長戦は別の救援に任せる
      if (context.inning > 9 && context.outs == 0) {
        reason = '抑え1IP終了';
      }
      // 大量失点（同点以下になったケース等で、後続の中継ぎに任せる）
      else if (state.runsAllowed >= runsAllowedThreshold) {
        reason = '${state.runsAllowed}失点';
      } else if (state.hitsAllowedStreak >= hitsStreakThreshold) {
        reason = '${state.hitsAllowedStreak}連打';
      } else if (state.walksStreak >= walksStreakThreshold) {
        reason = '${state.walksStreak}連続四球';
      }
    }
    // リリーフ投手はイニング境界で短い登板で降ろす
    else if (!isStarter &&
        context.outs == 0 &&
        state.pitchCount >= relieverPitchCountThreshold) {
      reason = 'イニング終了';
    }
    // 先発の球数超過
    else if (isStarter && state.pitchCount >= pitchCountThreshold) {
      reason = '${state.pitchCount}球';
    }
    // 大量失点（先発・リリーフ共通）
    else if (state.runsAllowed >= runsAllowedThreshold) {
      reason = '${state.runsAllowed}失点';
    }
    // 連打
    else if (state.hitsAllowedStreak >= hitsStreakThreshold) {
      reason = '${state.hitsAllowedStreak}連打';
    }
    // 連続四球
    else if (state.walksStreak >= walksStreakThreshold) {
      reason = '${state.walksStreak}連続四球';
    }
    // 終盤のピンチ（先発のみ）
    else if (isStarter &&
        context.inning >= 7 &&
        context.scoreDiff <= 0 &&
        (context.runners.second != null || context.runners.third != null) &&
        state.pitchCount >= 50) {
      reason = '終盤のピンチ';
    }

    if (reason == null) return null;

    final newPitcher = _selectReliever(context);
    return PitcherChangeDecision(newPitcher: newPitcher, reason: reason);
  }

  /// セーブ機会かどうか
  /// - 9回以降の守備
  /// - リード（scoreDiff > 0）
  /// - リード ≤ 3 点 OR リード ≤ 走者数 + 2（連続2HRで同点・逆転）
  ///   ※「3イニング以上投げて守る」条件は抑えの運用判断には使わない
  bool _isSaveSituation(PitcherChangeContext context) {
    if (context.inning < 9) return false;
    final lead = context.scoreDiff;
    if (lead <= 0) return false;
    final runnersOnBase = context.runners.count;
    return lead <= 3 || lead <= runnersOnBase + 2;
  }

  /// 8回途中のピンチかどうか（抑えを早めに投入する場面）
  /// - 8回
  /// - アウト ≤ 1（2アウトは打席終わり間近で投入する意味が薄い）
  /// - リード > 0 かつ ≤ 2 点（接戦）
  /// - 得点圏（2塁 or 3塁）に走者がいる
  bool _isLatePinchInEighth(PitcherChangeContext context) {
    if (context.inning != 8) return false;
    if (context.outs >= 2) return false;
    final lead = context.scoreDiff;
    if (lead <= 0 || lead > 2) return false;
    return context.runners.second != null || context.runners.third != null;
  }

  /// 先発が完封ペースかどうか
  /// - 現投手が先発
  /// - 無失点
  /// - 球数 < 100
  /// この場合は抑えに切り替えず、続投させて完封勝ちを狙う。
  bool _isStarterOnShutoutPace(PitcherChangeContext context, bool isStarter) {
    if (!isStarter) return false;
    final state = context.pitchingState;
    return state.runsAllowed == 0 && state.pitchCount < 100;
  }

  /// 交代先の投手を選択する
  /// デフォルトはブルペンの先頭投手を起用（SeasonController が事前に
  /// コンディション順に並び替えて渡している前提）。
  /// ※ セーブ機会での抑え起用は decide() 側で直接 closer を返している。
  /// ※ 抑えはセーブ機会以外では使わないので候補から除外する。
  ///   ただしブルペンが抑えしか残っていない場合は仕方なく抑えを使う。
  Player _selectReliever(PitcherChangeContext context) {
    final closer = context.closer;
    if (closer == null) return context.availableRelievers.first;
    final pool = context.availableRelievers
        .where((p) => p.id != closer.id)
        .toList();
    if (pool.isEmpty) return context.availableRelievers.first;
    return pool.first;
  }
}

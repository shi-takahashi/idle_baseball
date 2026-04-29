import '../models/at_bat_result.dart';
import '../models/enums.dart';
import '../models/pitcher_condition.dart';
import '../models/player.dart';

/// 1チーム分の投手運用状態（可変）
///
/// 試合中、投手の交代判断や成績トラッキングに必要な情報を保持する。
/// GameSimulatorが保持し、打席ごとに更新される。
class TeamPitchingState {
  /// 現在マウンドにいる投手
  Player currentPitcher;

  /// 現投手の調子（交代時に再生成される）
  PitcherCondition condition;

  /// 現投手がこの試合で投げた投球数（交代時にリセット）
  int pitchCount = 0;

  /// この試合で登板済みの投手一覧（先発含む、同じ投手の再登板は不可）
  final List<Player> usedPitchers;

  /// ブルペンに残っている救援投手（使用済みは除外される）
  final List<Player> bullpen;

  // ==== 現投手の交代判断用の指標（交代時にリセット） ====

  /// 現投手の失点（自責/非自責問わず、登板中の総失点）
  int runsAllowed = 0;

  /// 現投手が連続して打たれている本数（連打判定用、アウトでリセット）
  int hitsAllowedStreak = 0;

  /// 現投手が連続して出塁を許した打者数（安打/四球/エラー、アウトでリセット）
  int onBaseStreak = 0;

  /// 現投手が連続して与えた四球の数（四球以外でリセット）
  int walksStreak = 0;

  TeamPitchingState({
    required this.currentPitcher,
    required this.condition,
    required this.bullpen,
  }) : usedPitchers = [currentPitcher];

  /// 投手交代を適用する
  void changePitcher(Player newPitcher, PitcherCondition newCondition) {
    currentPitcher = newPitcher;
    condition = newCondition;
    pitchCount = 0;
    usedPitchers.add(newPitcher);
    bullpen.remove(newPitcher);
    runsAllowed = 0;
    hitsAllowedStreak = 0;
    onBaseStreak = 0;
    walksStreak = 0;
  }

  /// 打席結果を反映して各指標を更新する
  ///
  /// - runsAllowedはatBatによる得点を加算
  /// - ヒット/四球/エラー出塁はストリークを伸ばす
  /// - アウトはonBaseStreakとhitsAllowedStreakをリセット
  void recordAtBat(AtBatResult atBat, {int batteryErrorRuns = 0}) {
    runsAllowed += atBat.rbiCount + batteryErrorRuns;

    if (atBat.result.isHit) {
      hitsAllowedStreak++;
      onBaseStreak++;
      walksStreak = 0;
    } else if (atBat.result == AtBatResultType.walk) {
      hitsAllowedStreak = 0;
      onBaseStreak++;
      walksStreak++;
    } else if (atBat.result == AtBatResultType.reachedOnError) {
      hitsAllowedStreak = 0;
      onBaseStreak++;
      walksStreak = 0;
    } else if (atBat.result.isOut ||
        atBat.result == AtBatResultType.fieldersChoice) {
      // 野選は打者は1塁に出るが、先頭走者をアウトにしているので
      // 投手側の streak はアウトと同じく全てリセット
      hitsAllowedStreak = 0;
      onBaseStreak = 0;
      walksStreak = 0;
    }
  }
}

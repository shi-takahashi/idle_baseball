import '../models/models.dart';
import 'random_utils.dart';

/// 能力ごとの「ポテンシャル分布プロファイル」。
///
/// **設計原則** ([feedback_unified_logic_principle]): 全ての能力（球速 km/h /
/// 1〜10 能力 / 守備力）を 1 つの統一ロジック [AbilitySampler] で処理する。
/// 能力ごとの違いはこのプロファイル（数値テーブル）だけで表現する。
/// 球速だから、制球だから、と専用ロジックを書かない。
///
/// - [potentialMean] / [potentialSd]: ポテンシャル抽選のガウシアン分布
/// - [floor] / [ceiling]: ポテンシャルの下限/上限（生成時 clamp）
/// - [currentFloor]: 現在値の絶対下限（衰え期で [floor] を下回る current を許す場合に
///   floor より低く設定。1-10 能力は floor と同値で OK）
/// - [annualStep]: 1 年の加齢で動かせる最大値（target への収束速度）
///
/// 「投手の打撃能力は低い」のような mean のオフセットは、[AbilitySampler] の
/// 呼び出し時に `meanBonus` 引数で渡す（プロファイルを増やさない）。
class AbilityProfile {
  final double potentialMean;
  final double potentialSd;
  final int floor;
  final int ceiling;
  final int currentFloor;
  final int annualStep;

  const AbilityProfile({
    required this.potentialMean,
    required this.potentialSd,
    required this.floor,
    required this.ceiling,
    required this.currentFloor,
    required this.annualStep,
  });
}

/// 全能力で共有する標準プロファイル定義。
///
/// 数値以外の違い（生成ロジック、加齢ロジック）は持たない。
/// 「能力ごとに違うロジック」を書きたくなったら、まず ここに表で表現できないか
/// 検討する。表で表せない違いは、たいてい設計の偏り（[feedback_unified_logic_principle]）。
class AbilityProfiles {
  /// 球速 (km/h)。
  /// mean 148 / sd 3.5 で 155+ ポテンシャル ≈ 2% × 108 投手 = 2.2 人/リーグ。
  /// 詳細な背景は [PlayerGenerator] の旧 `_potentialSpeedMean` 周辺コメント参照。
  ///
  /// currentFloor=134: 衰え期で潜在 139 から margin 6 引いた現在値 133 を 134 で
  /// 受ける（旧コードの「現在値だけ floor を緩める」挙動を維持）。
  static const fastballSpeed = AbilityProfile(
    potentialMean: 148.0,
    potentialSd: 3.5,
    floor: 139,
    ceiling: 158,
    currentFloor: 134,
    annualStep: 2,
  );

  /// 1〜10 能力（制球 / 伸び / 各変化球 / meet / power / speed / eye / arm / 守備）。
  /// ceiling=9（10 は手動編集のみ、自動生成・成長では出ない）。
  ///
  /// mean 5.5 / sd 1.5 で P(potential >= 9) ≈ 1% × 108 = 1.1 人/能力。
  /// 現在値 9 はピーク年齢層でのみ実現するので、リーグの「能力 9 のスター」は
  /// 1 能力あたり数人。具体的な目標数（9 が 1-2 人、8 が 3-5 人 等）は
  /// [feedback_league_distribution_check] に従い measure_growth で確認・微調整する。
  static const ability1to10 = AbilityProfile(
    potentialMean: 5.5,
    potentialSd: 1.5,
    floor: 1,
    ceiling: 9,
    currentFloor: 1,
    annualStep: 1,
  );
}

/// 統一的なポテンシャル抽選 & 加齢ロジック。
///
/// **使い方:**
/// - 新規生成: [samplePotentialAndCurrent] でポテンシャル & 現在値を 1 回で得る
/// - 加齢: [ageOneStep] で現在値を 1 年ぶん動かす
///
/// [sampleMarginInSd] は内部メソッドだが、年齢/新人タイプ → margin の換算は
/// 全能力で共通（sd 単位なので能力の値域に依存しない）。
/// 球速の現テーブル（mean 5.0/3.0/1.5、ピーク 0.5、36+ 6.0、sd=3.5 km/h）を
/// sd 単位に変換した値をそのまま採用しているので、球速の旧挙動は維持される。
class AbilitySampler {
  final RandomUtils _r;
  AbilitySampler(this._r);

  /// 年齢/新人タイプ → margin（ポテンシャルとの距離、sd 単位、常に >= 0）。
  /// 全能力で共通テーブル。1-10 能力でも球速でも同じ式から margin を引く。
  double sampleMarginInSd(int age, RookieType? rookieType) {
    double mean;
    double sd;
    if (rookieType == RookieType.highSchool) {
      // 高卒 18 歳: 伸び代大・ばらつき大
      mean = 1.43;
      sd = 0.57;
    } else if (rookieType == RookieType.college) {
      // 大卒 22 歳: 中程度
      mean = 0.86;
      sd = 0.43;
    } else if (rookieType == RookieType.corporate) {
      // 社会人 21-25 歳: 即戦力
      mean = 0.43;
      sd = 0.29;
    } else if (age <= 21) {
      mean = 1.43;
      sd = 0.57;
    } else if (age <= 25) {
      mean = 0.71;
      sd = 0.43;
    } else if (age <= 28) {
      // ピーク
      mean = 0.14;
      sd = 0.29;
    } else if (age <= 32) {
      mean = 0.43;
      sd = 0.29;
    } else if (age <= 35) {
      mean = 1.00;
      sd = 0.43;
    } else {
      mean = 1.71;
      sd = 0.57;
    }
    final m = mean + _r.nextGaussian() * sd;
    return m < 0 ? 0 : m;
  }

  /// 新規生成: ポテンシャル直接抽選 → 年齢/タイプから margin を引いて現在値を逆算。
  ///
  /// - [meanBonus]: ポテンシャル mean に加算するオフセット（外国人 / ポジション傾向 /
  ///   投手の打撃能力低下など）。プロファイルを増やさず、ここで吸収する
  /// - 戻り値: (ポテンシャル, 現在値) のタプル
  ({int potential, int current}) samplePotentialAndCurrent({
    required AbilityProfile profile,
    required int age,
    RookieType? rookieType,
    double meanBonus = 0.0,
  }) {
    final potential = (profile.potentialMean +
            meanBonus +
            _r.nextGaussian() * profile.potentialSd)
        .round()
        .clamp(profile.floor, profile.ceiling);
    final marginSd = sampleMarginInSd(age, rookieType);
    final margin = (marginSd * profile.potentialSd).round();
    final current =
        (potential - margin).clamp(profile.currentFloor, profile.ceiling);
    return (potential: potential, current: current);
  }

  /// 加齢 1 年ぶん: ポテンシャルと新しい年齢から target を計算し、現在値を近づける。
  /// 1 年で動かす量は [AbilityProfile.annualStep] で上限を設ける。
  ///
  /// 揺らぎ（noise）は profile.potentialSd × 0.2 程度で、個人差を表現。
  int ageOneStep({
    required AbilityProfile profile,
    required int currentValue,
    required int potential,
    required int newAge,
  }) {
    final marginSd = sampleMarginInSd(newAge, null);
    final margin = (marginSd * profile.potentialSd).round();
    final target =
        (potential - margin).clamp(profile.currentFloor, profile.ceiling);
    final diff = target - currentValue;
    final step = profile.annualStep.toDouble();
    final clamped = diff.toDouble().clamp(-step, step);
    final noise = _r.nextGaussian() * profile.potentialSd * 0.2;
    return (currentValue + (clamped + noise).round())
        .clamp(profile.currentFloor, potential);
  }
}

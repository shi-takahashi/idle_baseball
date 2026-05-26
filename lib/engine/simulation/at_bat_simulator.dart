import 'dart:math';

import '../models/models.dart';
import 'error_simulator.dart';
import 'steal_simulator.dart';

/// インプレー結果（エラー情報を含む）
class InPlayResult {
  final AtBatResultType result;
  final FieldingError? fieldingError;

  /// 外野手の返球・クッション処理ミスで打者が本来の進塁先より +1 塁進む場合 true。
  /// 例: 単打を打ったが返球エラーで打者が二塁まで、二塁打を打ったが中継エラーで
  /// 打者が三塁まで。NPB の公式記録では打席結果はあくまで「単打」「二塁打」で、
  /// 余分な進塁は失策。RBI も自然な打席結果ぶんしか付かない（押し出される
  /// 走者が本塁を踏んだ場合、その得点は失策由来として打点に算入しない）。
  final bool batterTakesExtraBase;

  const InPlayResult({
    required this.result,
    this.fieldingError,
    this.batterTakesExtraBase = false,
  });
}

/// 打席終了チェックの結果
class AtBatEndCheckResult {
  final AtBatResultType? result;
  final FieldingError? fieldingError;
  final bool batterTakesExtraBase;

  const AtBatEndCheckResult({
    this.result,
    this.fieldingError,
    this.batterTakesExtraBase = false,
  });

  /// 打席が終了したかどうか
  bool get isEnded => result != null;
}

/// 打席シミュレーションの結果
class AtBatSimulationResult {
  final AtBatResultType result;
  final List<PitchResult> pitches;
  final List<StealAttempt> stealAttempts; // 打席中の盗塁（記録されるもののみ）
  final BaseRunners updatedRunners; // 盗塁後のランナー状況
  final int additionalOuts; // 盗塁失敗によるアウト数
  final FieldingError? fieldingError; // フィールディングエラー
  final int batteryErrorRuns; // バッテリーエラーによる得点

  /// 外野手のエラーで打者が +1 塁進む場合 true。詳細は [InPlayResult] 参照。
  final bool batterTakesExtraBase;

  /// バッテリーエラー（WP/PB）で生還した走者
  /// 失点の責任投手を特定するために必要（インヘリット走者の場合は前任投手の責任）
  /// type は自責点判定に使用（WP=自責、PB=不自責）
  final List<({Player runner, BatteryErrorType type})> batteryErrorScorers;

  const AtBatSimulationResult({
    required this.result,
    required this.pitches,
    this.stealAttempts = const [],
    required this.updatedRunners,
    this.additionalOuts = 0,
    this.fieldingError,
    this.batteryErrorRuns = 0,
    this.batterTakesExtraBase = false,
    this.batteryErrorScorers = const [],
  });
}

/// インプレー結果の確率データ
class InPlayProbabilities {
  final double probOut;
  final double probSingle;
  final double probDouble;
  final double probTriple;
  final double probHomeRun;

  const InPlayProbabilities({
    required this.probOut,
    required this.probSingle,
    required this.probDouble,
    required this.probTriple,
    required this.probHomeRun,
  });
}

/// 1打席のシミュレーター
class AtBatSimulator {
  final Random _random;

  /// 計測用フラグ。リーグ全体の本塁打 SD を「打席内乱数の各層」「コンディション
  /// 揺らぎ」がどれだけ膨らませているか分解計測するために使う。通常実行では
  /// すべて false（本番動作に影響なし）。bin/measure_variance_breakdown.dart 参照。
  ///
  /// - [disableBatterCondition]: 野手調子 ±1 補正を 0 に固定
  /// - [disablePitcherCondition]: 投手調子 ±2 補正を 0 に固定
  /// - [disableSpeedVariation]: 球速の毎球変動 ±3 を 0 に固定
  /// - [disablePitchSelectionRandomness]: 重み平均で「期待値」相当の球種を毎球選ぶ
  /// - [disableBattedBallTypeRandomness]: 打球タイプを期待値固定（ゴロ）
  /// - [disableFieldPositionRandomness]: 打球方向を期待値固定（センター）
  static bool disableBatterCondition = false;
  static bool disablePitcherCondition = false;
  static bool disableSpeedVariation = false;
  static bool disablePitchSelectionRandomness = false;
  static bool disableBattedBallTypeRandomness = false;
  static bool disableFieldPositionRandomness = false;

  // 基準球速（この球速で基本確率になる）
  static const int _baseSpeed = 145;

  // 球速1kmあたりの線形補正率。球速と伸びは同程度の影響力にしてある
  // （速球の質は球速と伸びの両方で決まる）。
  // 2026-05-23(10): 球速 153km の投手 (NPB トップ級) が ERA 3.31 と普通レベルに
  // なっていた問題を解消するため 0.005 → 0.007 に微増。
  // 2026-05-23(12): 1シーズン (30登板) でパラメータ通りの成績に収束しない
  // （A vs C で逆転発生）問題を解消するため、0.007 → 0.013 に強化。
  // 球速 5km の差が ERA に明確に出るように。
  static const double _speedModifierPerKm = 0.013;

  // ストレートの非線形「球速空振りボーナス」。
  // 実効球速 = 実球速 + (伸び - 5) × _fastballRidePerPoint。実効球速が閾値を
  // 超えると打者の反応時間を奪い、空振りが非線形に急増する（95mph 超の現実傾向）。
  // 伸びが良いほど低い実球速でこの領域に届く＝「球速ガン以上に速く見える」。
  // 奪三振にのみ効き、被打率には乗せない。
  // 2026-05-23(10): 153km/h は NPB エース級（大谷・山本由伸クラス）だが、閾値が
  // 153 だと 153km/h 投手はギリギリ over=0 でメリットを受けない設計になっていた。
  // 閾値を 153 → 150 に下げ、150km/h 以上の速球派が正しくメリットを受けるように。
  static const int _velocityWhiffThreshold = 150;
  static const int _fastballRidePerPoint = 2; // 伸び1ptあたりの実効球速底上げ(km/h)
  // 実効球速が閾値を超えたぶん（over、0〜8 にクランプ）ごとの空振り率ボーナス。
  // 2026-05-25: ユーザー指摘「最多奪三振 236(NPB 145-195)、200K+ が 2.8人/シーズン
  // (NPB ほぼゼロ)、TOP の K/9 11-13.5(NPB 9-10 上限)」を受け、上位帯を約 40% 削減。
  // 上位剛速球(実効158+)の頭打ちボーナス +0.045 はベース 0.055 の +81% で過剰だった。
  // 2026-05-25(3): まだ「200K+ が複数出る・最多213」とのユーザー指摘。NPB エース級
  // (山本由伸/ダルビッシュ K/9 9-10) でも届かない水準。ベース K率 20.3% は維持
  // しつつ上位帯を再削減して TOP K/9 を 9-10 に揃える。over 8+ の頭打ちを -36%。
  static const List<double> _velocityWhiffBonusByOver = [
    0.0,   // over 0（実効150以下）
    0.001, // over 1（実効151）
    0.002, // over 2（実効152）
    0.004, // over 3（実効153）
    0.006, // over 4（実効154）
    0.009, // over 5（実効155）
    0.012, // over 6（実効156）
    0.015, // over 7（実効157）
    0.018, // over 8+（実効158以上、頭打ち）
  ];

  // 基準制球力（この制球力で基本確率になる）
  static const int _baseControl = 5;

  // 制球力1あたりの補正率
  static const double _controlBallModifier = 0.012; // ボール確率補正（0.015→0.012）
  // 被打率補正（アウト率への影響＝甘い球）。2026-05-17: 制球を投手の最重要
  // ファクターにするため 0.01 → 0.025 に強化。
  // 2026-05-23: 「弱点軸ペナルティ」（[pitcherWeaknessPenalty]）を別途導入したため、
  // 二重カウントを避けつつ制球の独立効果は維持する水準（0.025 → 0.035）に。
  // 2026-05-23(9): スイープで制球9 ERA 1.87 / 制球1 ERA 12.65 と影響が突出
  // していたため 0.035 → 0.020 に抑制。制球9 が「球速・変化球の質に関係なく
  // 無双」状態を解消し、他能力の効きとバランスを取る。
  // 2026-05-23(12): 制球の影響を抑えすぎて、1シーズンで制球差が成績に出にくく
  // なっていたため 0.020 → 0.030 に戻す。制球9 ERA 2.92 → 2.0 程度。
  static const double _controlHitModifier = 0.030;

  // 死球（HBP）関連。
  // NPB 目安: 1試合 1チームあたり 0.5 件前後（143 試合で 70〜80 件）。
  // 1 投球あたり 0.35% 程度に当てる。制球が悪いほど発生しやすい。
  static const double _baseProbHitByPitch = 0.0035; // 制球5基準で1球あたり0.35%
  static const double _controlHitByPitchModifier = 0.0006; // 制球-1で+0.06pt

  // 基準ミート力（このミート力で基本確率になる）
  static const int _baseMeet = 5;

  // ミート力1あたりの補正率（インプレーになる確率に影響）
  static const double _meetSwingModifier = 0.015; // 空振り確率補正（高いほど空振り減→インプレー増）

  // ミート力1あたりのインプレー時の打球の質補正
  // 高ミートでアウト率↓（=ヒット率↑）、低ミートでアウト率↑（=ヒット率↓）
  // ※ コンタクトの「質」のモデル化。低ミート打者（投手など）は当てても弱い当たりに。
  // 2026-05-23(4): ミート単独で打率 .341、選球眼単独で .334、長打力単独で .333 と
  // 各々高いだけでなく、組み合わせると打率効果が加算的に重なり、ミ9/長7/眼9 で .426、
  // 5ツール(ミ8/長8/眼8) で .434 と NPB 戦後最高 .367 を大幅に超える値になっていた。
  // 各単独効果を 0.020 → 0.010 に抑え、組み合わせ時の上振れを NPB レンジ内
  // （巧打者 .330-.360、5ツール .340-.370）に収める。
  // 2026-05-23(6): 「コンタクト型 > パワー型」の打率順序を作るため、ミート効果を
  // 0.003 → 0.018 に強化。
  // 2026-05-23(7): シュワーバー型再現（HRテーブル復活）+ NPB 投高打低化（リーグ
  // 平均 .250）のため、ミート効果を 0.018 → 0.017 に調整。ミート低 (1-3) で
  // 打率が大きく落ち、ミート高 (8-9) でやっと3割級になる差別化を実現。
  static const double _meetOutModifier = 0.017;

  // 基準選球眼（この選球眼で基本確率になる）
  static const int _baseEye = 5;

  // 選球眼の影響（2026-05-23 改訂）:
  //   旧実装は「選球眼が高い → ボール率増加」だけで、副作用として「打席が長引く
  //   → 3 ストライク到達確率が上がる → 三振増加」というネット効果ほぼゼロの
  //   パラメータになっていた。実野球では選球眼が良い打者は:
  //   - ボール球を見送る（→ 四球増）
  //   - ストライクゾーンの球はちゃんと振る（→ 見逃し三振減）
  //   - ボールとストライクを見極めるので空振りも減る（→ 空振り三振減・打率↑）
  //   この3経路で「四球+ / 三振- / 打率+」の方向に効くよう再設計。
  static const double _eyeBallModifier = 0.015;            // ボール率増加（既存維持）
  static const double _eyeStrikeLookingModifier = 0.010;   // 見逃しストライク減（強化）
  static const double _eyeSwingMissModifier = 0.010;       // 空振りストライク減（強化）
  static const double _eyeOutModifier = 0.0;               // 選眼の打率寄与は廃止（BB増 + K減 のみで効く）

  // 長打力による四球率補正（ホームラン警戒で勝負を避けられる）
  // 2026-05-23: パワーヒッターが「フルスイングで空振り増 → 三振増」になるよう
  // _powerSwingMissModifier を新規追加。
  static const double _powerWalkModifier = 0.010;          // 0.008 → 0.010（敬遠強化）
  static const double _powerSwingMissModifier = 0.0045;    // 空振り増（フルスイング、新規）

  // 基準長打力（この長打力で基本確率になる）
  static const int _basePower = 5;

  // 長打力1あたりの補正率
  // 2026-05-23(6): 長打力が単打を増やす効果（_powerSingleModifier）は撤廃。
  // 現実では長打力は HR と二塁打を増やす指標で、単打数とはほぼ無相関。さらに
  // 「強打者の打率 > コンタクト型の打率」の逆転が出ていた（HR寄与で打率が
  // 直接押し上がる + 単打も増える二重経路）。HR と二塁打の押し上げに絞り、
  // 単打は廃止する。
  static const double _powerDoubleModifier = 0.002; // 二塁打確率補正（0.005→0.002）
  static const double _powerSingleModifier = 0.0;   // 単打確率補正（廃止）

  // 三塁打は長打力ではなく走力で決まる（俊足の指標。鈍足の長距離砲は三塁打に
  // ならず本塁打/二塁打になる）。走力1あたりの三塁打確率補正。
  static const double _speedTripleModifier = 0.0020;

  // 長打力ごとの本塁打基本確率（インプレー時・正規化前・球種/疲労補正前）
  //
  // 旧実装は長打力1ptあたり一律 +0.015 の線形補正だったが、power7〜10 の差が
  // 体感できない（randomness が parameter を上回って見える）という指摘を受け、
  // 上に凸の非線形カーブへ変更。下位（1〜4）は本塁打をほぼ出さず、
  // 上位（8〜10）を強く引き離す。
  // 2026-05-17 改訂: リーグ全体の SLG/HR が NPB 比で高かったため、長打力9≒40本は
  // 維持したまま中位（power4〜8）を圧縮した。これでリーグ合計が下がり、かつ
  // 上位との差がさらに開いて推測しやすくなる（設計の柱②）。
  // 2026-05-23(5): 打率/HR が組み合わせで過剰上振れし、強打者で HR 65本・5ツール
  // で打率 .413 となっていた。NPB 投高打低（年 50+ HR は数年に1人、3割は数人）の
  // 現実に合わせるべく約 25% ダウン。
  // 2026-05-23(6): HR が打率に直接寄与しすぎて「パワー型 > コンタクト型」の打率
  // 逆転が残っていたため、power 8〜10 を削減（HR が打率を押し上げる経路を弱める）。
  // 2026-05-23(7): シュワーバー型（MLB 2023 .197 / HR 47）を再現するため、ミート
  // 効果でコンタクト型の打率を引き上げ、HR テーブルは「ホームラン王 = 50本級」へ
  // 戻す。ベース probOut も上げて全体打率を NPB 投高打低（.250）に寄せ、
  // 「ミート低 → 打率低、長打力高 → HR 多い」の差別化を強化。
  // (7-rev) HRが直接打率を押し上げるため、オール9で .426 と4割超えになっていた。
  // HR テーブルを「シュワーバー再現に必要な最低限」に再調整:
  //   power7≈18 / power8≈25 / power9≈36 / power10≈45
  // (8) ユーザー共有の実戦データ（長打力9 のスラッガーで HR 21-27 本のみ、NPB
  // 上位 35-45 本に届かない）を受けて、HR テーブルを大幅増。実戦の相手投手は
  // リーグ平均（4-5変化球）で sweep の固定甘い投手より厳しいため、sweep 値より
  // 実戦値が 30-40% 低く出る。実戦で長9 = HR 40本級になるよう sweep ベースで
  // +50% 程度に上げる:
  //   sweep値: power7≈28 / power8≈40 / power9≈55 / power10≈70
  //   実戦値:  power7≈18 / power8≈26 / power9≈38 / power10≈48
  // (9) リーグ多シーズン進行で HR 王 24-30 本の下振れシーズンが頻発・防御率1位
  // 1点台前半が常態化していたユーザー指摘を受け、上位帯を約 1.25倍に再底上げ。
  // power 6 以下は据え置きで「能力差を引き離す」(設計の柱②)。
  // (9-rev) 初回 1.25倍では HR 王 50-60本級が頻発したため、上位帯を ~7% 戻し。
  // power 9 平均 ~37本・HR 王 ~42-45本/上限 ~50本(NPB 王・松井級)に着地させる。
  // (10) 打球タイプ抽選を power 依存に変更(過剰分散主因の解消)したため、強打者
  // のフライ機会が安定し SD が縮む代わりに HR 平均がやや下がった。テーブルを
  // ~10-14% 増やして HR 王 35-40本(NPB近年)に着地させる。
  // (11) 三振抑制(_baseProbStrikeSwinging 0.055→0.045)でインプレー機会が増え
  // HR 王平均が 43→49 本に上振れたため、上位帯を ~10% 減で相殺。
  // 目標 (HR/600PA): power7≈22 / power8≈30 / power9≈38 / power10≈50
  static const Map<int, double> _powerHomeRunBase = {
    1: 0.0011,
    2: 0.0020,
    3: 0.0034,
    4: 0.0060,
    5: 0.0125,
    6: 0.0225,
    7: 0.0445,
    8: 0.0650,
    9: 0.0950,
    10: 0.1220,
  };

  // 基準守備力（この守備力で基本確率になる）
  static const int _baseFielding = 5;

  // 守備力1あたりの補正率（高いほどアウト率が上がる）
  static const double _fieldingModifier = 0.015;

  // 捕手の守備力1あたりのリード（配球）補正。
  // 旧 `lead` パラメータ（独立・推測不能）を廃止し、捕手の守備力に統合した。
  // 守備の良い捕手は配球面でも被打率をわずかに下げる、というおまけ程度の効果。
  static const double _catcherCallModifier = 0.005;

  // 基本確率（球速145km、制球力5、ミート力5、長打力5基準）
  // 2026-05-17 リーグ水準補正: K率が NPB 比で高すぎた（~26% → 目標 ~20%）。
  // 見逃し/空振りストライクを下げてインプレー率を上げ、三振を減らす。
  // ボールも下げて四球が増えすぎないように合わせる。
  static const double _baseProbBall = 0.34;
  static const double _baseProbStrikeLooking = 0.14;
  // 2026-05-18: 変化球の配球比率を上げた（ストレート 50%→45%）ぶん、変化球の
  // 空振り寄与でリーグ K 率が上振れたため、空振りベースを 0.085→0.073 に再センタ。
  // 同日さらにシュート/カット/シンカーを追加し K 率が再び上振れたため 0.073→0.069。
  // 2026-05-23: リーグ K率がやや多い（20.3%）感覚に合わせて 0.069 → 0.063 に微減。
  // 同時に球速空振りボーナスを縮小しているので、実機ではさらに下がる方向。
  // 2026-05-23(2): 平均能力(ミ5/長5/眼5) の K数 が 150試合で 103 と多めだったため
  // ベースを 0.063 → 0.055 へ下げ、平均的選手の三振を NPB 中位水準に寄せる。
  // 2026-05-25: ユーザー指摘「最多奪三振 236(NPB 145-195)、200K+ 2.8人(NPB 0)」を
  // 受け、球速ボーナス削減と合わせて 0.055 → 0.045 へ更に減。リーグ K率 21% → 17-18%
  // へ。インプレー機会増による打率上振れは HR テーブルとセットで吸収。
  // 2026-05-25(3): 球速ボーナス上位帯を再削減しても TOP の K は減らず(変化球の質
  // が支配的)。ベース更に減で全体を抑える。0.045 → 0.038。インプレー機会増に
  // よる打高化は HR テーブルでセット相殺。
  static const double _baseProbStrikeSwinging = 0.038;
  static const double _baseProbFoul = 0.195;
  // インプレー確率は残り（= 1 - 上記4つ = 0.24。旧 0.20 から引き上げ）

  // インプレー時の結果確率（球速145km、制球力5基準）
  // インプレー率を上げたぶん打率が上振れるので probOut を引き上げて
  // リーグ打率を NPB 水準（~.250）へ寄せる。
  // 2026-05-18: シュート/カット/シンカー追加と配球リワークでリーグ水準が動いた
  // ため、リーグ打率を NPB へ戻すべく 0.740→0.718 に再センタ。
  // 2026-05-23(4): 選球眼/ミート/長打力の打率効果を再設計したぶんリーグ打率が
  // .266 に上振れていたため、ベースを 0.718→0.738 に再センタ。
  // 2026-05-23(7): NPB 投高打低（リーグ平均 .240-.250、3割打者は数人レベル）に
  // 寄せるため、ベースを 0.738 → 0.760 に上げる。
  // (8) 実戦データで強打者の打率が .236 (NPB スラッガーは .270 程度) と低く、
  // 全体的に底上げが必要。0.760 → 0.752 に微減。
  // (12) 投手能力差拡大に伴いリーグ打率が .232 へ落ちたため再底上げ 0.752 → 0.725。
  static const double _baseProbOut = 0.725;
  static const double _baseProbSingle = 0.20;
  // 二塁打を引き上げ・三塁打を引き下げ（2026-05-16 微調整）。
  // 旧 0.05 / 0.01 では 143試合換算 二塁打189・三塁打48 で、三塁打が NPB の
  // 約2倍・二塁打:三塁打が 3.9:1（NPB ~10:1）と乖離していた。
  static const double _baseProbDouble = 0.058;
  // 三塁打は走力5基準の基本値。走力で ±_speedTripleModifier される。
  static const double _baseProbTriple = 0.0050;
  // 本塁打確率は残り

  // 基準球種パラメータ（この値で基本効果）
  static const int _basePitchParam = 5;

  // パラメータ1あたりの補正率（球種の効果をスケール）。
  // ストレート（伸び）の質スケーリングに使用（線形）。
  // 2026-05-23(9): 伸び 1→9 で ERA -0.60 と効きが弱かったため 0.01→0.015 に強化。
  // 2026-05-23(12): 1シーズン収束のため更に 0.015 → 0.025 に強化。
  static const double _pitchParamModifier = 0.025;

  // 変化球の質（スライダー/カーブ/スプリット/チェンジアップ）の確率補正テーブル。
  //
  // 旧実装は線形 (param-5)*_pitchParamModifier（±0.04〜0.05）だったが、効果が
  // 小さいうえ各変化球は配球の 15〜20% しか投げられないため、シーズン成績では
  // ノイズに完全に埋もれていた（8シーズン計測で防御率スプレッド ~0.34、ビン値も
  // 非単調）。変化球の質が「観測できる能力」になっていなかった（設計の柱③）。
  //
  // 線形小刻み補正をやめ、長打力→本塁打や走力→盗塁と同じく非線形テーブルで
  // 上下を引き離す（[[feedback_parameter_influence]]）。上に凸で、下位（1〜3）の
  // 「曲がらない変化球」を強く突き放し、上位（8〜10）の決め球を引き上げる。
  // ストレート（伸び）はここを通さず従来どおり線形のまま（既に footprint 健全）。
  // 2026-05-23(12): 1シーズン (30登板) でパラメータ通りに収束させるため、上下を
  // 約 30% 拡大。質1〜3の弱い変化球は更に打たれやすく、質8〜10の決め球は
  // 更に打たれにくく。
  static const Map<int, double> _breakingQualityTable = {
    1: -0.21,
    2: -0.165,
    3: -0.110,
    4: -0.055,
    5: 0.0,
    6: 0.055,
    7: 0.110,
    8: 0.170,
    9: 0.225,
    10: 0.265,
  };

  // 変化球の配球重みテーブル（質パラメータ → 投球選択の重み）。
  //
  // 2026-05-18: ストレートを投げすぎる傾向があったため、ストレートの基本重みを
  // 下げて変化球を増やす。あわせて「得意な球（質の高い変化球）ほど多く投げる」
  // よう、重みを質パラメータに対し非線形（上に凸）でスケールさせる。質9〜10 の
  // 決め球はストレート並み〜それ以上の頻度で投げられる。
  static const Map<int, double> _breakingSelectionWeight = {
    1: 0.30,
    2: 0.36,
    3: 0.43,
    4: 0.51,
    5: 0.60,
    6: 0.71,
    7: 0.84,
    8: 0.99,
    9: 1.15,
    10: 1.30,
  };

  // 球種ごとの使用頻度の重み（配球選択での球種別の倍率）。
  //
  // 2026-05-18: 同じ質でも球種によって「投げやすさ」が違う（スライダーは多投され、
  // カーブは見せ球で少なめ）。質（被打率・空振り）と投球割合を 1 パラメータに
  // 同居させると無理が出るため、投球割合を独立要素として分離した。値は NPB 2016 の
  // 「投球割合 ÷ 投手割合」（その球種を持つ投手が、どれだけその球種を投げるか）の
  // 比に概ね比例。配球重み = _breakingSelectionWeight[質] × この倍率。
  static const Map<PitchType, double> _pitchTypeUsageWeight = {
    PitchType.slider: 1.05,
    PitchType.cutter: 0.92,
    PitchType.sinker: 0.75,
    PitchType.shoot: 0.86,
    PitchType.splitter: 0.71,
    PitchType.changeup: 0.63,
    PitchType.curveball: 0.60, // 2026-05-23(9): 0.47→0.60、カーブの能力差が成績に出るよう配球比率増
  };

  // 持ち球数ボーナス。球種が多い投手は打者が待ち球を絞れず、わずかに有利になる。
  // 基準 4.5 球種。質ほど重要ではない「隠し味」程度の小さな補正に留める
  // （3球種↔6球種で防御率にして ~0.4 程度の差）。
  static const double _baseArsenalSize = 4.5;
  static const double _arsenalSwingBonus = 0.004; // 1球種あたりの空振り率補正
  static const double _arsenalOutBonus = 0.002;   // 1球種あたりのアウト率補正

  // 弱点軸ペナルティの係数。弱点スコアの 2乗 × この係数 = アウト率減少 (=被打率増加)。
  // 弱点 1 軸（例: 制球3 → weakness 2）で 4 × 0.010 = -4%pt
  // 弱点 2 軸（例: 制球3 + 決め球3 → weakness 4）で 16 × 0.010 = -16%pt
  // 弱点 3 軸（例: 全部 3 → weakness 6）で 36 × 0.010 = -36%pt
  // → 「2軸欠点が重なると急激にペナルティが増える」非線形カーブ
  static const double _weaknessPenaltyCoeff = 0.010;

  /// 球種パラメータ（質）の確率補正値。
  /// ストレート（伸び）は線形、変化球は非線形テーブル（footprint 強化）。
  static double _pitchParamScaling(PitchType pitchType, int paramValue) {
    if (pitchType == PitchType.fastball) {
      return (paramValue - _basePitchParam) * _pitchParamModifier;
    }
    return _breakingQualityTable[paramValue.clamp(1, 10)] ?? 0.0;
  }

  /// 投手の持ち球数（ストレート + 投げられる変化球の種類数）。3〜8 の範囲。
  static int _arsenalSize(Player pitcher) {
    var n = 1; // ストレートは必ず投げる
    if (pitcher.slider != null) n++;
    if (pitcher.curve != null) n++;
    if (pitcher.splitter != null) n++;
    if (pitcher.changeup != null) n++;
    if (pitcher.shoot != null) n++;
    if (pitcher.cutter != null) n++;
    if (pitcher.sinker != null) n++;
    return n;
  }

  /// 投手の「弱点軸ペナルティ」。3軸（ストレートの質 / 制球 / 決め球）のうち
  /// 5 未満の軸を「弱点」とみなし、弱点の合計（5未満のぶんの単純和）の **2乗**
  /// にペナルティ係数を掛けて返す。これを被打率（アウト率の逆）に上乗せする。
  ///
  /// 設計意図（2026-05-23）:
  /// - 弱点 1 軸（例: 制球3）なら他軸でカバーできるので weakness=2、ペナルティ
  ///   は 4×0.010 = -4%pt 程度（軽微）
  /// - 弱点 2 軸（例: 制球3 + 決め球3）になると weakness=4、ペナルティは
  ///   16×0.010 = -16%pt と急増。「球速だけ速くて制球も決め球もダメな投手は
  ///   プロで通用しない」を再現する
  /// - 平均的な投手（全軸 ≥ 5）は weakness=0 でペナルティなし。リーグ全体への
  ///   影響はない（ピンポイント補正）
  ///
  /// 軸の定義:
  /// - fb_axis: ストレートの質を 1-10 にマッピング。`(球速 - 140) × 0.5 + 伸び`
  ///   を round して clamp。球速145+伸び5 → 7.5、球速140+伸び5 → 5、
  ///   球速135+伸び3 → 5.5 - これも 5 以下なら弱点
  /// - control_axis: 制球 1-10
  /// - best_breaking_axis: 持っている変化球の最大質。持っていない変化球は
  ///   除外（0扱い）
  static double pitcherWeaknessPenalty(Player pitcher) {
    final speed = pitcher.averageSpeed ?? 145;
    final fastball = pitcher.fastball ?? 5;
    final fbAxisRaw = (speed - 140) * 0.5 + fastball;
    final fbAxis = fbAxisRaw.round().clamp(1, 10);
    final controlAxis = pitcher.control ?? 5;
    // 持っている変化球の中の最大質。持っていなければ 0（「決め球なし」最大ペナルティ）
    final qualities = <int>[
      if (pitcher.slider != null) pitcher.slider!,
      if (pitcher.curve != null) pitcher.curve!,
      if (pitcher.splitter != null) pitcher.splitter!,
      if (pitcher.changeup != null) pitcher.changeup!,
      if (pitcher.shoot != null) pitcher.shoot!,
      if (pitcher.cutter != null) pitcher.cutter!,
      if (pitcher.sinker != null) pitcher.sinker!,
    ];
    final bestBreaking = qualities.isEmpty
        ? 0
        : qualities.reduce((a, b) => a > b ? a : b);

    int weakness = 0;
    if (fbAxis < 5) weakness += (5 - fbAxis);
    if (controlAxis < 5) weakness += (5 - controlAxis);
    if (bestBreaking < 5) weakness += (5 - bestBreaking);

    return weakness * weakness * _weaknessPenaltyCoeff;
  }

  // 球種ごとの特性定義
  // 球速低下量（km/h）
  static const Map<PitchType, int> _speedReductions = {
    PitchType.fastball: 0,
    PitchType.slider: 15,    // -10〜-20の中央
    PitchType.curveball: 25, // -20〜-30の中央
    PitchType.splitter: 10,  // -5〜-15の中央
    PitchType.changeup: 15,  // -10〜-20の中央
    PitchType.shoot: 5,      // ツーシーム系。ストレートとほぼ同球速
    PitchType.cutter: 7,     // ストレートよりやや遅い
    PitchType.sinker: 5,     // 高速シンカー型。ストレートとほぼ同球速（沈むツーシーム）
  };

  // ボール率補正（正=ボール増）
  // ストレート: 低、スライダー: 中、カーブ: やや高、スプリット: 高、チェンジアップ: 中
  static const Map<PitchType, double> _ballModifiers = {
    PitchType.fastball: -0.02,  // 低（制球しやすい）
    PitchType.slider: 0.0,      // 中
    PitchType.curveball: 0.02,  // やや高
    PitchType.splitter: 0.05,   // 高（抜けやすい）
    PitchType.changeup: 0.0,    // 中
    PitchType.shoot: 0.0,       // 中（ツーシームは比較的制球しやすい）
    PitchType.cutter: -0.01,    // やや低（制球の良い球）
    PitchType.sinker: 0.03,     // 高（沈む球で抜けやすい）
  };

  // 三振率補正（正=空振り増）
  // ストレート: 中、スライダー: 高、カーブ: 中、スプリット: 最高、チェンジアップ: 中〜高
  static const Map<PitchType, double> _swingModifiers = {
    PitchType.fastball: 0.0,    // 中（質パラメータで変動）
    PitchType.slider: 0.03,     // 高
    PitchType.curveball: 0.01,  // 中
    PitchType.splitter: 0.05,   // 最高（決め球）
    PitchType.changeup: 0.02,   // 中〜高
    PitchType.shoot: -0.015,    // 最低（空振りは取れない。ゴロで打たせる球）
    PitchType.cutter: 0.02,     // 中〜高
    PitchType.sinker: 0.025,    // 高め
  };

  // アウト率補正（正=アウト増=被打率低）
  // ストレート: やや高（被打率やや高=アウト率低）、スライダー: 低、カーブ: 中、スプリット: 低、チェンジアップ: 低
  static const Map<PitchType, double> _outModifiers = {
    PitchType.fastball: -0.02,  // 被打率やや高
    PitchType.slider: 0.03,     // 被打率低
    PitchType.curveball: 0.0,   // 被打率中
    PitchType.splitter: 0.03,   // 被打率低
    PitchType.changeup: 0.02,   // 被打率低
    PitchType.shoot: -0.02,     // 被打率やや高（コンタクトされやすい）
    PitchType.cutter: 0.0,      // 被打率中
    PitchType.sinker: 0.0,      // 被打率中（ゴロ傾向で打ち取る）
  };

  // 被長打率補正（正=長打増=打者有利）
  // ストレート: 高、スライダー: 低〜中、カーブ: やや高、スプリット: 低、チェンジアップ: 低
  static const Map<PitchType, double> _xbhModifiers = {
    PitchType.fastball: 0.02,   // 被長打率高（力負けしやすい）
    PitchType.slider: -0.01,    // 被長打率低〜中
    PitchType.curveball: 0.01,  // 被長打率やや高
    PitchType.splitter: -0.02,  // 被長打率低
    PitchType.changeup: -0.02,  // 被長打率低（タイミング崩れる）
    PitchType.shoot: -0.02,     // 被長打率低（ゴロ中心で柵越えしにくい）
    PitchType.cutter: -0.01,    // 被長打率低〜中（詰まらせる）
    PitchType.sinker: -0.025,   // 被長打率低（ゴロ中心）
  };

  // === 疲労システム ===

  // 疲労カーブ（全投手共通）。2026-05-17: スタミナを能力パラメータとして廃止し、
  // 投手ごとの差をなくして一律カーブにした。80球から疲労が出始め、140球で完全疲労
  // （ランプ60球）。100球時点の疲労度は (100-80)/60 ≒ 0.33。「プロは皆100球前後を
  // 投げられ、引っ張りすぎると打たれる」をこの一律カーブで表現する。
  static const int _baseFatigueStartPitches = 80;
  static const int _baseFullFatiguePitches = 140;

  // 球種ごとの疲労影響度（0.0〜1.0、高いほど疲労の影響を受けやすい）
  // スプリット: 最大、スライダー: 高、カーブ: 中、チェンジアップ: 低、ストレート: 低
  static const Map<PitchType, double> _fatigueSensitivity = {
    PitchType.fastball: 0.4,    // ★★☆☆☆ 球速低下
    PitchType.slider: 0.8,      // ★★★★☆ 曲がらない
    PitchType.curveball: 0.6,   // ★★★☆☆ 浮く
    PitchType.splitter: 1.0,    // ★★★★★ 落ちない＆被弾
    PitchType.changeup: 0.4,    // ★★☆☆☆ 少しズレる
    PitchType.shoot: 0.4,       // ★★☆☆☆ ストレート系
    PitchType.cutter: 0.5,      // ★★★☆☆ 曲がりが甘くなる
    PitchType.sinker: 0.6,      // ★★★☆☆ 沈まなくなる
  };

  // 疲労ペナルティ（完全疲労 fatigue=1.0 時の最大値）。
  // 引っ張りすぎた投手（球数超過）は球威・制球を失い打たれる。なぜ100球前後で
  // 交代するのかの根拠になる。全投手共通カーブ（80球開始）に乗る。
  // 疲労時の球速低下量（ストレート用）
  static const int _fatigueSpeedReduction = 7;

  // 疲労時のボール率増加
  static const double _fatigueBallModifier = 0.14;

  // 疲労時の空振り率低下
  static const double _fatigueSwingModifier = 0.08;

  // 疲労時のアウト率低下（被打率増加）— 防御率へ効く主ペナルティ
  static const double _fatigueOutModifier = 0.18;

  // 疲労時の被長打率増加
  static const double _fatigueXbhModifier = 0.07;

  // === プラトーン（左vs左=打者不利）補正 ===
  // 左投手 vs 左打者 のみ打者に不利な補正を適用
  // 右vs右は実際の野球でも専門家交代がほぼないため補正なし
  static const double _platoonSwingModifier = 0.02; // 空振り率 +2%
  static const double _platoonOutModifier = 0.02; // インプレー時のアウト率 +2%
  static const double _platoonBallModifier = -0.015; // ボール率 -1.5%（制球しやすい）

  // === 左右の打席による内野安打補正 ===
  // 左打者は一塁に近い位置から走れるため内野安打が増える。
  // 旧実装は左に ×1.15 のみだったが、左打者が1・2塁方向へ引っ張る（その方向は
  // 内野安打になりにくい）効果と相殺して、実測で左右ほぼ同率になっていた。
  // そこで左に強めの加点・右に減点を入れ、ネットで左/右 ≒ 1.35倍（実測）に
  // しつつ、リーグ全体の内野安打数は維持する（左 ×1.40 / 右 ×0.89）。
  // （併殺率の補正は GameSimulator 側で適用）
  static const double _leftBatterInfieldHitFactor = 1.40;
  static const double _rightBatterInfieldHitFactor = 0.89;

  late final ErrorSimulator _errorSimulator;

  AtBatSimulator({Random? random}) : _random = random ?? Random() {
    _errorSimulator = ErrorSimulator(random: _random);
  }

  /// 疲労度を計算（0.0〜1.0）。全投手共通カーブ（80球開始・140球完全疲労）。
  /// pitchCount: 現在の投球数
  double _calculateFatigue(int pitchCount) {
    const fatigueStart = _baseFatigueStartPitches;
    const fullFatigue = _baseFullFatiguePitches;

    if (pitchCount < fatigueStart) {
      return 0.0; // 疲労なし
    }
    if (pitchCount >= fullFatigue) {
      return 1.0; // 完全疲労
    }

    // 疲労開始〜完全疲労の間で線形補間
    return (pitchCount - fatigueStart) / (fullFatigue - fatigueStart);
  }

  /// 球種に応じた疲労効果を計算
  /// fatigue: 基本疲労度（0.0〜1.0）
  /// pitchType: 球種
  /// 戻り値: 球種ごとの実効疲労度（0.0〜1.0）
  double _getEffectiveFatigue(double fatigue, PitchType pitchType) {
    final sensitivity = _fatigueSensitivity[pitchType] ?? 0.5;
    return fatigue * sensitivity;
  }

  /// 投げる球種を選択
  /// ストレートは球速・質で重みが変動、変化球は質パラメータで重みが変動する。
  /// 得意な球（質の高い変化球・速くて質の高いストレート）ほど多く投げる。
  /// 球種選択の確率は調子に影響されない（習慣的なもの）
  ///
  /// 同球種連続ペナルティ:
  /// 打席内で同じ球種を続けると打者が慣れてくるので、配球を散らす。
  /// [prevPitchType] と [prevSameStreak] (= 直前まで何球同球種が続いたか) を
  /// 渡すと、その球種の重みに連続ペナルティを掛ける（連続 1 球後 ×0.5、
  /// 2 球後 ×0.25、3 球以上 ×0.1）。
  PitchType _selectPitchType(
    Player pitcher,
    PitcherCondition condition, {
    PitchType? prevPitchType,
    int prevSameStreak = 0,
  }) {
    // 調子は選択確率には影響しない（効果のみに影響）
    // ignore: unused_local_variable
    final _ = condition;
    final avgSpeed = pitcher.averageSpeed ?? 145;
    final fastballQuality = pitcher.fastball ?? 5;

    // 各球種の重み
    // nullの球種は重み0（投げない）
    final weights = <PitchType, double>{};

    // ストレートは基本重み 1.4 + 球速と質で補正。
    // 2026-05-18: ストレートを投げすぎる傾向があったため基本重みを一度 1.8→1.2 に
    // 下げた。その後シュート/カット/シンカーを追加して持ち球が増えストレートが
    // 40% まで押し出されたため、NPB 水準（~46%）へ戻すべく 1.2→1.4 に再調整。
    // 球の速い・質の高い投手はストレートを多めに投げる。
    final speedBonus = ((avgSpeed - 140) / 30.0).clamp(-0.3, 0.5);  // -0.3〜+0.5
    final qualityBonus = (fastballQuality - 5) * 0.1;               // -0.4〜+0.5
    weights[PitchType.fastball] = (1.35 + speedBonus + qualityBonus).clamp(0.9, 2.1);

    // 変化球の配球重み = 質テーブル（得意な球ほど多投）× 球種別の使用頻度倍率
    // （スライダーは多投・カーブは見せ球、など球種固有の投げやすさ）。
    void setBreaking(PitchType type, int? param) {
      if (param == null) return;
      weights[type] = _breakingSelectionWeight[param.clamp(1, 10)]! *
          (_pitchTypeUsageWeight[type] ?? 1.0);
    }

    setBreaking(PitchType.slider, pitcher.slider);
    setBreaking(PitchType.curveball, pitcher.curve);
    setBreaking(PitchType.splitter, pitcher.splitter);
    setBreaking(PitchType.changeup, pitcher.changeup);
    setBreaking(PitchType.shoot, pitcher.shoot);
    setBreaking(PitchType.cutter, pitcher.cutter);
    setBreaking(PitchType.sinker, pitcher.sinker);

    // 同球種連続ペナルティ: 直前の球種だけ重みを縮小
    if (prevPitchType != null &&
        prevSameStreak > 0 &&
        weights.containsKey(prevPitchType)) {
      weights[prevPitchType] =
          weights[prevPitchType]! * _sameTypeStreakPenalty(prevSameStreak);
    }

    // 全球種が投げられない場合はストレートのみ
    if (weights.isEmpty) {
      return PitchType.fastball;
    }

    // 合計重みを計算
    final totalWeight = weights.values.fold(0.0, (sum, w) => sum + w);
    final roll = _random.nextDouble() * totalWeight;

    // 重み付き選択
    double cumulative = 0;
    for (final entry in weights.entries) {
      cumulative += entry.value;
      if (roll < cumulative) {
        return entry.key;
      }
    }

    // フォールバック
    return PitchType.fastball;
  }

  /// 同球種連続のペナルティ係数。
  /// [prevSameStreak] = 直前まで同じ球種を投げた連続球数。
  /// この球を同球種にすると `prevSameStreak + 1` 球連続になる。
  /// 145km/h 級のストレートを 6 球連続で投げて NPB 打者を抑え続けるのは
  /// 非現実的なので、配球をばらけさせる。
  static double _sameTypeStreakPenalty(int prevSameStreak) {
    switch (prevSameStreak) {
      case 0:
        return 1.0;
      case 1:
        return 0.5; // 連続 2 球目
      case 2:
        return 0.25; // 連続 3 球目
      default:
        return 0.1; // 連続 4 球目以降
    }
  }

  /// 球種に応じた球速を生成
  int _generatePitchSpeed(int avgSpeed, PitchType pitchType) {
    final speedReduction = _speedReductions[pitchType] ?? 0;
    final baseSpeed = avgSpeed - speedReduction;
    return generateSpeed(baseSpeed);
  }

  /// 球速を生成（正規分布的、中央付近が出やすい）
  int generateSpeed(int averageSpeed) {
    if (disableSpeedVariation) return averageSpeed;
    // 2つの一様乱数の平均を使って中央寄りの分布を作る
    // ±3の範囲で中央付近が出やすい（調子±2と合わせて±5の変動）
    final r1 = _random.nextDouble() * 6 - 3; // -3 to +3
    final r2 = _random.nextDouble() * 6 - 3; // -3 to +3
    final offset = ((r1 + r2) / 2).round(); // 平均を取ると中央寄りに
    return averageSpeed + offset;
  }

  /// 1球をシミュレート
  /// pitchType: 球種
  /// pitchParam: その球種のパラメータ値（1-10、nullは基準値5）
  /// eye: 打者の選球眼（1-10、デフォルト5）
  /// power: 打者の長打力（1-10、デフォルト5）- 警戒されて四球増
  /// fatigue: 基本疲労度（0.0〜1.0、デフォルト0）
  /// isPlatoonDisadvantage: 利き手同士マッチアップで打者不利なら true
  /// batterSide: 打者の実効打席（打球方向バイアス用）
  PitchResult simulatePitch(int balls, int strikes, int speed, int control, int meet, PitchType pitchType, int? pitchParam, {int eye = 5, int power = 5, double fatigue = 0.0, bool isPlatoonDisadvantage = false, Handedness batterSide = Handedness.right, int arsenalSize = 4}) {
    // 死球チェック（独立試行、最優先）。
    // 制球が悪い投手ほど発生しやすい。発生率は1球あたり 0.05〜1.0% の範囲に収まる。
    final probHbp = (_baseProbHitByPitch +
            (_baseControl - control) * _controlHitByPitchModifier)
        .clamp(0.0005, 0.01);
    if (_random.nextDouble() < probHbp) {
      return PitchResult(
        type: PitchResultType.hitByPitch,
        pitchType: pitchType,
        speed: speed,
      );
    }

    // 球種に応じた実効疲労度を計算
    final effectiveFatigue = _getEffectiveFatigue(fatigue, pitchType);

    // 球速による補正（ストレートのみ、速いほど空振り増）
    // 疲労時はストレートの球速が低下
    double speedModifier = 0.0;
    int effectiveSpeed = speed;
    if (pitchType == PitchType.fastball) {
      // 疲労による球速低下（最大5km/h）
      final fatigueSpeedDrop = (effectiveFatigue * _fatigueSpeedReduction).round();
      effectiveSpeed = speed - fatigueSpeedDrop;
      final speedDiff = effectiveSpeed - _baseSpeed;
      speedModifier = speedDiff * _speedModifierPerKm;
    }

    // 制球力による補正（高いほどボール減）
    final controlDiff = control - _baseControl;
    final controlBallModifier = controlDiff * _controlBallModifier;

    // ミート力による補正（高いほど空振り減）
    final meetDiff = meet - _baseMeet;
    final swingModifier = meetDiff * _meetSwingModifier;

    // 選球眼による補正（高いほどボール見逃し増→四球増）
    final eyeDiff = eye - _baseEye;
    final eyeBallBonus = eyeDiff * _eyeBallModifier;     // ボール率増加

    // 長打力による補正（高いほど警戒されて四球増）
    final powerDiff = power - _basePower;
    final powerWalkBonus = powerDiff * _powerWalkModifier;  // ボール率増加

    // 球種固有のベース補正
    final pitchBallModifier = _ballModifiers[pitchType] ?? 0.0;
    final pitchSwingModifier = _swingModifiers[pitchType] ?? 0.0;

    // パラメータによるスケーリング。ストレートはfastballパラメータ（伸び）、
    // 変化球はそれぞれの質パラメータ。ストレートは線形・変化球は非線形テーブル。
    final paramValue = pitchParam ?? _basePitchParam;
    final paramScaling = _pitchParamScaling(pitchType, paramValue);

    // ストレートの非線形「球速空振りボーナス」（奪三振にのみ効く）。
    // 実効球速が _velocityWhiffThreshold を超えると非線形に空振りが急増。
    double velocityWhiffBonus = 0.0;
    if (pitchType == PitchType.fastball) {
      final effectiveVelocity =
          effectiveSpeed + (paramValue - _basePitchParam) * _fastballRidePerPoint;
      final over =
          (effectiveVelocity - _velocityWhiffThreshold).clamp(0, 8);
      velocityWhiffBonus = _velocityWhiffBonusByOver[over];
    }

    // 疲労による補正
    // ボール率増加、空振り率低下
    final fatigueBallIncrease = effectiveFatigue * _fatigueBallModifier;
    final fatigueSwingDecrease = effectiveFatigue * _fatigueSwingModifier;

    // プラトーン補正（同じ手=投手有利）
    final platoonBall = isPlatoonDisadvantage ? _platoonBallModifier : 0.0;
    final platoonSwing = isPlatoonDisadvantage ? _platoonSwingModifier : 0.0;

    // 確率を調整
    // ボール率: 球種固有 + 制球力 + パラメータ補正 + 疲労 + 選球眼 + 長打力警戒 + プラトーン
    final probBall = (_baseProbBall + pitchBallModifier - controlBallModifier - paramScaling * 0.5 + fatigueBallIncrease + eyeBallBonus + powerWalkBonus + platoonBall).clamp(0.20, 0.55);
    // 見逃しストライク率: 選球眼が高いほどストライクをちゃんと振るので下がる
    final probStrikeLooking = (_baseProbStrikeLooking - eyeDiff * _eyeStrikeLookingModifier).clamp(0.05, 0.25);
    // 空振り率: 球種固有 + 球速（線形）+ 非線形球速ボーナス + パラメータ補正
    //          - ミート力 - 選球眼 + 長打力 - 疲労 + プラトーン
    //  - 選球眼: 見極めて空振りを減らす
    //  - 長打力: フルスイングで空振りが増える（パワーヒッターの三振多）
    // 持ち球数ボーナス（球種が多いほど打者が待ち球を絞れず空振り増）
    final arsenalSwing = (arsenalSize - _baseArsenalSize) * _arsenalSwingBonus;
    final probStrikeSwinging = (_baseProbStrikeSwinging + pitchSwingModifier + speedModifier + velocityWhiffBonus + paramScaling - swingModifier - eyeDiff * _eyeSwingMissModifier + powerDiff * _powerSwingMissModifier - fatigueSwingDecrease + platoonSwing + arsenalSwing).clamp(0.03, 0.40);
    final probFoul = _baseProbFoul;
    // インプレー確率は残り（他の結果にならなかった場合）

    final roll = _random.nextDouble();
    double cumulative = 0;

    // ボール
    cumulative += probBall;
    if (roll < cumulative) {
      return PitchResult(type: PitchResultType.ball, pitchType: pitchType, speed: speed);
    }

    // 見逃しストライク
    cumulative += probStrikeLooking;
    if (roll < cumulative) {
      return PitchResult(type: PitchResultType.strikeLooking, pitchType: pitchType, speed: speed);
    }

    // 空振りストライク
    cumulative += probStrikeSwinging;
    if (roll < cumulative) {
      return PitchResult(type: PitchResultType.strikeSwinging, pitchType: pitchType, speed: speed);
    }

    // ファウル
    cumulative += probFoul;
    if (roll < cumulative) {
      return PitchResult(type: PitchResultType.foul, pitchType: pitchType, speed: speed);
    }

    // インプレー
    final battedBallType = _randomBattedBallType(pitchType, power);
    final fieldPosition = _randomFieldPosition(battedBallType, batterSide);
    return PitchResult(type: PitchResultType.inPlay, pitchType: pitchType, battedBallType: battedBallType, fieldPosition: fieldPosition, speed: speed);
  }

  /// 球種ごとのゴロ率（インプレー打球のうちゴロになる割合）。
  ///
  /// NPB 2016 実測のゴロ率（ストレート 38% 〜 シンカー 63%）を、シミュレーターの
  /// リーグ平均ゴロ率が従来水準（約 50%）を保つよう一律 +約4.5pt して移植した。
  /// シュート・シンカーは「空振りは取れないがゴロを打たせる」球で、走者ありでは
  /// 併殺を奪いやすい。逆にストレートはフライ・ライナーが出やすく一発を食う。
  static const Map<PitchType, double> _groundBallShare = {
    PitchType.fastball: 0.43,
    PitchType.slider: 0.50,
    PitchType.curveball: 0.555,
    PitchType.splitter: 0.635,
    PitchType.changeup: 0.535,
    PitchType.shoot: 0.65,
    PitchType.cutter: 0.545,
    PitchType.sinker: 0.675,
  };

  /// 打球の種類を球種ごとのゴロ傾向に応じてランダムに決定する。
  ///
  /// ゴロ率は球種依存（[_groundBallShare]）。残り（フライ＋ライナー）は従来の
  /// フライ : ライナー ≒ 76 : 24 の比率で配分する。内野ライナー過多を避けるため
  /// シミュレーターは現実よりゴロ寄り（リーグ平均ゴロ ~50%）に調整している。
  /// 打者長打力 1ptあたりのゴロ率補正(power 5 を基準に、power が高いほどゴロ率
  /// が下がりフライ率が上がる)。
  /// 過剰分散の主因が「打球タイプ抽選の打席ごとぶれ」だった(measure_variance_breakdown)
  /// ことを受け、強打者は安定してフライを多く打つ = HR SD が縮む構造に変更。
  /// power 1 で +0.10 (ゴロ多)、power 9 で -0.10 (フライ多)。
  static const double _groundShiftPerPower = 0.025;

  BattedBallType _randomBattedBallType(PitchType pitchType, int power) {
    if (disableBattedBallTypeRandomness) {
      // 期待値固定: ゴロ率最大のシンカー(0.675)等によらず、リーグ平均ゴロ(0.50)で
      // 「ゴロ」を返す。これで打球タイプ抽選の乱数寄与をゼロにできる。
      return BattedBallType.groundBall;
    }
    final baseGround = _groundBallShare[pitchType] ?? 0.50;
    // 打者長打力でゴロ率を偏らせる(power 1: ゴロ打ち、power 9: アッパースイング)
    final powerShift = (5 - power) * _groundShiftPerPower;
    final ground = (baseGround + powerShift).clamp(0.20, 0.80);
    final roll = _random.nextDouble();
    if (roll < ground) return BattedBallType.groundBall;
    // 非ゴロぶんをフライ 76% / ライナー 24% に配分
    final flyCut = ground + (1.0 - ground) * 0.76;
    if (roll < flyCut) return BattedBallType.flyBall;
    return BattedBallType.lineDrive;
  }

  /// 打球方向をランダムに決定
  /// 打球の種類と打者の打席（利き手）によって確率が変わる
  /// 右打者はレフト方向・三遊間に引っ張りやすい
  /// 左打者はライト方向・一二塁間に引っ張りやすい
  FieldPosition _randomFieldPosition(
      BattedBallType battedBallType, Handedness batterSide) {
    if (disableFieldPositionRandomness) {
      // 期待値固定: ゴロは遊撃、フライ・ライナーは中堅
      if (battedBallType == BattedBallType.groundBall) {
        return FieldPosition.shortstop;
      }
      return FieldPosition.center;
    }
    final weights = _directionWeights(battedBallType, batterSide);
    return _pickWeighted(weights);
  }

  /// 重み付きで FieldPosition を選択
  FieldPosition _pickWeighted(Map<FieldPosition, double> weights) {
    final total = weights.values.fold(0.0, (a, b) => a + b);
    final roll = _random.nextDouble() * total;
    double cumulative = 0;
    for (final entry in weights.entries) {
      cumulative += entry.value;
      if (roll < cumulative) return entry.key;
    }
    return weights.keys.last;
  }

  /// 打球の種類と打者の打席から、各守備位置への打球確率（重み）を返す
  /// 基本分布はbothの値で、右/左に応じて pull/opposite のシフトを適用
  Map<FieldPosition, double> _directionWeights(
      BattedBallType battedBallType, Handedness batterSide) {
    switch (battedBallType) {
      case BattedBallType.groundBall:
        // 基本: 投手5, 一塁25, 二塁25, 三塁20, 遊撃25
        // 右打者はサード/ショートに引っ張る、左打者はファースト/セカンドに引っ張る
        double first = 25, second = 25, third = 20, shortstop = 25;
        if (batterSide == Handedness.right) {
          // 右打者: +左寄り
          third += 5;
          shortstop += 3;
          first -= 5;
          second -= 3;
        } else if (batterSide == Handedness.left) {
          // 左打者: +右寄り
          first += 5;
          second += 3;
          third -= 5;
          shortstop -= 3;
        }
        return {
          FieldPosition.pitcher: 5,
          FieldPosition.first: first,
          FieldPosition.second: second,
          FieldPosition.third: third,
          FieldPosition.shortstop: shortstop,
        };

      case BattedBallType.flyBall:
        // 基本: 捕手5, 一塁5, 二塁5, 三塁5, 遊撃5, 左翼25, 中堅30, 右翼20
        // 右打者はレフト方向、左打者はライト方向
        double left = 25, center = 30, right = 20;
        if (batterSide == Handedness.right) {
          left += 8;
          right -= 8;
        } else if (batterSide == Handedness.left) {
          right += 8;
          left -= 8;
        }
        return {
          FieldPosition.catcher: 5,
          FieldPosition.first: 5,
          FieldPosition.second: 5,
          FieldPosition.third: 5,
          FieldPosition.shortstop: 5,
          FieldPosition.left: left,
          FieldPosition.center: center,
          FieldPosition.right: right,
        };

      case BattedBallType.lineDrive:
        // 基本: 投手10, 一塁10, 二塁15, 三塁10, 遊撃15, 左翼15, 中堅15, 右翼10
        double first = 10, second = 15, third = 10, shortstop = 15;
        double leftOf = 15, rightOf = 10;
        if (batterSide == Handedness.right) {
          third += 3;
          shortstop += 2;
          leftOf += 4;
          first -= 3;
          second -= 2;
          rightOf -= 4;
        } else if (batterSide == Handedness.left) {
          first += 3;
          second += 2;
          rightOf += 4;
          third -= 3;
          shortstop -= 2;
          leftOf -= 4;
        }
        return {
          FieldPosition.pitcher: 10,
          FieldPosition.first: first,
          FieldPosition.second: second,
          FieldPosition.third: third,
          FieldPosition.shortstop: shortstop,
          FieldPosition.left: leftOf,
          FieldPosition.center: 15,
          FieldPosition.right: rightOf,
        };
    }
  }

  // 内野安打の基本確率（走力1あたり）
  static const double _infieldHitBaseRate = 0.012;

  /// 内野安打の確率を計算
  /// batterSpeed: 打者の走力（1〜10）
  /// fieldPosition: 打球方向
  /// fielding: 守備力（1〜10）
  /// isLeftBatter: 左打者なら一塁に近い分だけ有利
  double _calcInfieldHitProbability(int batterSpeed, FieldPosition fieldPosition, int fielding, int arm, {bool isLeftBatter = false}) {
    // 基本確率: 走力 × 1.2%（走力10で12%）
    final baseProbability = batterSpeed * _infieldHitBaseRate;

    // 打球方向による補正
    double directionModifier;
    switch (fieldPosition) {
      case FieldPosition.third:
      case FieldPosition.shortstop:
        // 三遊間: 一塁からの距離が遠いので内野安打になりやすい
        directionModifier = 1.5;
        break;
      case FieldPosition.second:
        // 二塁: 普通
        directionModifier = 1.0;
        break;
      case FieldPosition.first:
        // 一塁: 一塁に近いので内野安打になりにくい
        directionModifier = 0.3;
        break;
      case FieldPosition.pitcher:
      case FieldPosition.catcher:
        // 投手、捕手: 特殊なケース
        directionModifier = 0.5;
        break;
      default:
        // 外野（通常ゴロは来ない）
        directionModifier = 0.0;
    }

    // 守備力による補正（守備力が高いほど内野安打減少）
    // 守備力5で1.0、守備力10で0.75、守備力1で1.2
    final fieldingModifier = 1.0 - (fielding - 5) * 0.05;

    // 肩の強さによる補正（肩が強いほど内野安打減少）
    // 肩5で1.0、肩10で0.85、肩1で1.12
    final armModifier = 1.0 - (arm - 5) * 0.03;

    // 左打者は一塁に近いため内野安打になりやすく、右打者はその逆。
    final handednessFactor = isLeftBatter
        ? _leftBatterInfieldHitFactor
        : _rightBatterInfieldHitFactor;

    return (baseProbability *
            directionModifier *
            fieldingModifier *
            armModifier *
            handednessFactor)
        .clamp(0.0, 0.30);
  }

  /// インプレー結果の確率データ
  /// 確率計算ロジックをsimulateInPlayResultから分離
  InPlayProbabilities _calculateInPlayProbabilities({
    required int speed,
    required int control,
    required int meet,
    required int power,
    required int fielding,
    required int catcherFielding,
    required PitchType pitchType,
    required int pitchParam,
    required double fatigue,
    int eye = 5,
    int batterSpeed = 5,
    bool isPlatoonDisadvantage = false,
    BattedBallType? battedBallType,
    FieldPosition? fieldPosition,
    int arsenalSize = 4,
    double weaknessPenalty = 0.0,
  }) {
    // 球種に応じた実効疲労度を計算
    final effectiveFatigue = _getEffectiveFatigue(fatigue, pitchType);

    // 球速による補正（ストレートのみ、速いほどヒットが減る）
    double speedModifier = 0.0;
    if (pitchType == PitchType.fastball) {
      // 疲労による球速低下を考慮
      final fatigueSpeedDrop = (effectiveFatigue * _fatigueSpeedReduction).round();
      final effectiveSpeed = speed - fatigueSpeedDrop;
      final speedDiff = effectiveSpeed - _baseSpeed;
      speedModifier = speedDiff * _speedModifierPerKm;
    }

    // 制球力による補正（高いほど甘い球が減り、アウトが増える）
    final controlDiff = control - _baseControl;
    final controlModifier = controlDiff * _controlHitModifier;

    // 守備力による補正（高いほどアウトが増える）
    final fieldingDiff = fielding - _baseFielding;
    final fieldingModifierValue = fieldingDiff * _fieldingModifier;

    // 捕手の守備力によるリード（配球）補正（高いほどアウトが増える、おまけ程度）
    final catcherCallDiff = catcherFielding - _baseFielding;
    final leadModifierValue = catcherCallDiff * _catcherCallModifier;

    // 球種固有のベース補正
    final pitchOutModifier = _outModifiers[pitchType] ?? 0.0;
    final pitchXbhModifier = _xbhModifiers[pitchType] ?? 0.0;

    // パラメータによるスケーリング（ストレートは線形・変化球は非線形テーブル）
    final paramScaling = _pitchParamScaling(pitchType, pitchParam);

    // 疲労による補正（アウト率低下、被長打率増加）
    final fatigueOutDecrease = effectiveFatigue * _fatigueOutModifier;
    final fatigueXbhIncrease = effectiveFatigue * _fatigueXbhModifier;

    // 長打力による補正（高いほど長打が増える）
    final powerDiff = power - _basePower;
    final doubleModifier = powerDiff * _powerDoubleModifier;
    final singleModifier = powerDiff * _powerSingleModifier;

    // 三塁打は走力ベース（速い打者ほど三塁を陥れる）。
    final tripleModifier = (batterSpeed - 5) * _speedTripleModifier;

    // 本塁打は長打力ごとの非線形テーブルで基本確率を決める。
    final powerHomeRunBase = _powerHomeRunBase[power.clamp(1, 10)]!;
    // 球種・疲労の被長打率補正は長打力に比例させる（弱打者はストレートでも
    // 柵越えしないので、一律 +0.02 のような加算はしない）。sqrt でゆるく効かせる。
    final xbhPowerFactor =
        sqrt(powerHomeRunBase / _powerHomeRunBase[_basePower]!);

    // ミート力によるアウト率補正
    // 高ミート → アウト率↓（ヒットが増える）、低ミート → アウト率↑（弱い当たり=アウト）
    // 投手のような低ミート打者は、当てても弱い当たりになりアウトになりやすい
    final meetDiff = meet - _baseMeet;
    final meetOutAdjustment = -meetDiff * _meetOutModifier;

    // 選球眼によるアウト率補正（2026-05-23 追加）
    // 選球眼が良いと「ボール球を振らない → スイングは良いコース／質のものに集中
    // → 打球の質が上がる → ヒット率がやや上がる」効果を加える。インプレー時の
    // アウト率を選球眼で下げる方向で補正する。ミートほどは大きく効かない控えめな値。
    final eyeDiff = eye - _baseEye;
    final eyeOutAdjustment = -eyeDiff * _eyeOutModifier;

    // プラトーン補正（同じ手=投手有利）
    final platoonOut = isPlatoonDisadvantage ? _platoonOutModifier : 0.0;

    // 持ち球数ボーナス（球種が多いほど打者が絞れず打ち損じ＝アウト増）
    final arsenalOut = (arsenalSize - _baseArsenalSize) * _arsenalOutBonus;

    // アウト率: 球種固有 + 球速（ストレートのみ）+ パラメータ + 制球力 + 守備力 +
    // リード - 疲労 + ミート + プラトーン + 持ち球数 - 弱点軸ペナルティ
    // 弱点軸ペナルティ（[pitcherWeaknessPenalty]）は「3軸のうち2軸以上に欠点が
    // あるとプロでは通用しない」非線形効果。投手の全打席に一律で乗る。
    final outModifier = pitchOutModifier +
        speedModifier +
        paramScaling +
        controlModifier +
        fieldingModifierValue +
        leadModifierValue -
        fatigueOutDecrease +
        meetOutAdjustment +
        eyeOutAdjustment +
        platoonOut +
        arsenalOut -
        weaknessPenalty;
    var probOut = (_baseProbOut + outModifier).clamp(0.45, 0.85);

    // 打球タイプ × 方向によるアウト率の上書き補正
    // - 外野ライナー: 約7割が安打（NPB 実測 アウト率 27〜30%）→ 大幅に下げる
    // - 内野ライナー: 反応速度で多くがアウト（lineOut to 3B/SS/etc）→ そのまま
    // - 外野フライ: 約7割アウト（基本値そのままで合致）→ そのまま
    // - 内野フライ: ポップフライでほぼ確実にアウト → わずかに上げる
    // - ゴロ: 既存の `_determineGroundOutResult` で内野安打 / エラー処理済み → そのまま
    if (battedBallType != null) {
      final isOutfieldDir = fieldPosition == FieldPosition.left ||
          fieldPosition == FieldPosition.center ||
          fieldPosition == FieldPosition.right;
      final adjust = _battedBallOutAdjustment(battedBallType, isOutfieldDir);
      probOut = (probOut + adjust).clamp(0.05, 0.95);
    }

    // 長打確率（長打力テーブル + 球種効果 + 疲労で変動）
    // 球種・疲労の補正は xbhPowerFactor で長打力に比例させてから加算する。
    final probHomeRun =
        (powerHomeRunBase +
                (pitchXbhModifier + fatigueXbhIncrease) * xbhPowerFactor)
            .clamp(0.0005, 0.24);
    // 三塁打は走力が主役。球種・疲労の影響は弱め（×0.15）にして走力シグナルを残す。
    final probTriple =
        (_baseProbTriple + tripleModifier + pitchXbhModifier * 0.15 + fatigueXbhIncrease * 0.15)
            .clamp(0.0008, 0.025);
    final probDouble =
        (_baseProbDouble + doubleModifier + pitchXbhModifier * 0.5 + fatigueXbhIncrease * 0.5)
            .clamp(0.02, 0.15);
    final probSingle =
        (_baseProbSingle - outModifier * 0.5 + singleModifier).clamp(0.10, 0.35);

    return InPlayProbabilities(
      probOut: probOut,
      probSingle: probSingle,
      probDouble: probDouble,
      probTriple: probTriple,
      probHomeRun: probHomeRun,
    );
  }

  /// 打球タイプ × 外野/内野方向で probOut に加える補正
  ///
  /// NPB 実測値:
  /// - 外野ライナー: アウト率 27〜30%（強い打球が外野手の前後左右に飛ぶため落ちやすい）
  /// - 外野フライ: アウト率 67〜72%
  /// 基本値 0.70 をベースに、外野ライナーだけ大きく引き下げる。
  /// 内野フライ・ポップフライはほぼ確実にアウトなので軽く引き上げる。
  static double _battedBallOutAdjustment(
      BattedBallType type, bool isOutfieldDir) {
    switch (type) {
      case BattedBallType.lineDrive:
        // 外野: 0.70 → 約 0.12（hit prob ~0.29 と合算で out 比率 ≈ 29%）
        // 内野: 反応で多くがアウトのため補正なし
        return isOutfieldDir ? -0.58 : 0.0;
      case BattedBallType.flyBall:
        // 外野: 既存値で 67〜70% アウト → 補正なし
        // 内野: ポップフライはほぼ確実にアウト → わずかに引き上げ
        return isOutfieldDir ? 0.0 : 0.10;
      case BattedBallType.groundBall:
        return 0.0;
    }
  }

  /// ゴロアウト判定（エラーチェック・内野安打チェック含む）
  InPlayResult _determineGroundOutResult({
    required FieldPosition? fieldPosition,
    required int fielding,
    required int? batterSpeed,
    required int? fielderArm,
    bool isLeftBatter = false,
    bool isForcedPlacement = false,
  }) {
    // ゴロの場合、まずエラーチェック（内野のみ）
    if (fieldPosition != null && !fieldPosition.isOutfield) {
      if (_errorSimulator.checkGroundBallError(fielding, fieldPosition,
          isForcedPlacement: isForcedPlacement)) {
        // エラー発生 → 打者出塁。捕球 / 送球の内訳を抽選（進塁ロジックは共通）。
        return InPlayResult(
          result: AtBatResultType.reachedOnError,
          fieldingError: FieldingError(
            type: _errorSimulator.pickGroundBallErrorType(),
            position: fieldPosition,
            runsScored: 0, // 得点はGameSimulatorで計算
          ),
        );
      }
    }
    // エラーなし → 内野安打の可能性をチェック
    if (batterSpeed != null && fieldPosition != null) {
      final armValue = fielderArm ?? 5;
      final infieldHitProb = _calcInfieldHitProbability(
        batterSpeed,
        fieldPosition,
        fielding,
        armValue,
        isLeftBatter: isLeftBatter,
      );
      if (_random.nextDouble() < infieldHitProb) {
        return const InPlayResult(result: AtBatResultType.infieldHit);
      }
    }
    return const InPlayResult(result: AtBatResultType.groundOut);
  }

  /// 二塁打の外野手エラーチェック（クッション処理ミス + 中継返球ミス）。
  /// 外野方向の二塁打で、外野手のミスにより打者が三塁まで進むケース。
  ///
  /// NPB ルール上、エラーで余分に進塁した場合の打席記録は本来の打撃結果
  /// （ここでは二塁打）のまま。エラーぶんの余計な進塁・得点は失策扱いで、
  /// 打点にも算入されない。したがって result は `double_` のままにし、
  /// `batterTakesExtraBase` フラグで「打者が +1 塁進む」ことを伝える。
  /// 走塁本体は `_advanceOnDouble` が処理し、その後 game_simulator 側で
  /// 打者を +1 塁進める後処理（押し出し走者は不自責の得点）が走る。
  InPlayResult _determineDoubleResult({
    required FieldPosition? fieldPosition,
    required int fielding,
    bool isForcedPlacement = false,
  }) {
    if (fieldPosition != null && fieldPosition.isOutfield) {
      if (_errorSimulator.checkDoubleError(fielding, fieldPosition,
          isForcedPlacement: isForcedPlacement)) {
        return InPlayResult(
          result: AtBatResultType.double_,
          fieldingError: FieldingError(
            type: _errorSimulator.pickDoubleErrorType(),
            position: fieldPosition,
            runsScored: 0,
          ),
          batterTakesExtraBase: true,
        );
      }
    }
    return const InPlayResult(result: AtBatResultType.double_);
  }

  /// 単打の外野手エラーチェック（中継・返球ミス）。
  /// 外野方向の単打で、外野手の返球ミスにより打者が二塁まで進むケース。
  /// `_determineDoubleResult` と同じく、result は `single` のまま保ち、
  /// 打者の +1 塁進塁は `batterTakesExtraBase` フラグで伝える。
  /// 内野安打 / 外野手以外の単打にはクッション処理がないので適用しない。
  InPlayResult _determineSingleResult({
    required FieldPosition? fieldPosition,
    required int fielding,
    bool isForcedPlacement = false,
  }) {
    if (fieldPosition != null && fieldPosition.isOutfield) {
      if (_errorSimulator.checkSingleError(fielding, fieldPosition,
          isForcedPlacement: isForcedPlacement)) {
        return InPlayResult(
          result: AtBatResultType.single,
          fieldingError: FieldingError(
            type: FieldingErrorType.throwing,
            position: fieldPosition,
            runsScored: 0,
          ),
          batterTakesExtraBase: true,
        );
      }
    }
    return const InPlayResult(result: AtBatResultType.single);
  }

  /// インプレー時の打席結果を決定（球速・制球力・ミート・長打力・守備力・走力・球種・疲労考慮）
  /// ミート力は (1) インプレーになる確率 (2) インプレー時のアウト率 の両方に影響
  /// fielding: 打球方向を守る野手の守備力（0〜10、nullの場合はデフォルト5）
  /// batterSpeed: 打者の走力（1〜10、内野安打判定に使用）
  /// fieldPosition: 打球方向（内野安打判定に使用）
  /// pitchType: 球種
  /// pitchParam: その球種のパラメータ値（1-10、nullは基準値5）
  /// fatigue: 基本疲労度（0.0〜1.0、デフォルト0）
  /// isPlatoonDisadvantage: 利き手同士マッチアップで打者不利なら true
  /// isLeftBatter: 左打者なら一塁に近い分だけ内野安打確率UP
  InPlayResult simulateInPlayResult(
    BattedBallType battedBallType,
    int speed,
    int control,
    int meet,
    int power,
    int? fielding, {
    int? batterSpeed,
    int? batterEye,
    FieldPosition? fieldPosition,
    int? fielderArm,
    int? catcherFielding,
    PitchType pitchType = PitchType.fastball,
    int? pitchParam,
    double fatigue = 0.0,
    bool isPlatoonDisadvantage = false,
    bool isLeftBatter = false,
    bool isFielderForcedPlacement = false,
    int arsenalSize = 4,
    double weaknessPenalty = 0.0,
  }) {
    final fieldingValue = fielding ?? _baseFielding;
    final catcherFieldingValue = catcherFielding ?? _baseFielding;
    final paramValue = pitchParam ?? _basePitchParam;

    // 確率を計算
    final probs = _calculateInPlayProbabilities(
      speed: speed,
      control: control,
      meet: meet,
      power: power,
      fielding: fieldingValue,
      catcherFielding: catcherFieldingValue,
      pitchType: pitchType,
      pitchParam: paramValue,
      fatigue: fatigue,
      eye: batterEye ?? 5,
      arsenalSize: arsenalSize,
      batterSpeed: batterSpeed ?? 5,
      isPlatoonDisadvantage: isPlatoonDisadvantage,
      battedBallType: battedBallType,
      fieldPosition: fieldPosition,
      weaknessPenalty: weaknessPenalty,
    );

    // 5つの確率を合算して正規化したうえでロール判定する。
    // 旧実装は「残り確率 → HR/Double 二択」を `probHomeRun / (probHomeRun + 0.01)` で
    // 行っていたが、probHomeRun が小さい（=低長打力）場合でも 30% 前後 HR に振られる
    // 不具合があったため、正規化して probHomeRun の比率がそのまま反映されるよう修正。
    final total = probs.probOut +
        probs.probSingle +
        probs.probDouble +
        probs.probTriple +
        probs.probHomeRun;
    final roll = _random.nextDouble() * total;
    double cumulative = 0;

    // アウト判定
    cumulative += probs.probOut;
    if (roll < cumulative) {
      switch (battedBallType) {
        case BattedBallType.groundBall:
          return _determineGroundOutResult(
            fieldPosition: fieldPosition,
            fielding: fieldingValue,
            batterSpeed: batterSpeed,
            fielderArm: fielderArm,
            isLeftBatter: isLeftBatter,
            isForcedPlacement: isFielderForcedPlacement,
          );
        case BattedBallType.flyBall:
          return const InPlayResult(result: AtBatResultType.flyOut);
        case BattedBallType.lineDrive:
          return const InPlayResult(result: AtBatResultType.lineOut);
      }
    }

    // 単打
    cumulative += probs.probSingle;
    if (roll < cumulative) {
      return _determineSingleResult(
        fieldPosition: fieldPosition,
        fielding: fieldingValue,
        isForcedPlacement: isFielderForcedPlacement,
      );
    }

    // 二塁打
    cumulative += probs.probDouble;
    if (roll < cumulative) {
      return _determineDoubleResult(
        fieldPosition: fieldPosition,
        fielding: fieldingValue,
        isForcedPlacement: isFielderForcedPlacement,
      );
    }

    // 三塁打
    cumulative += probs.probTriple;
    if (roll < cumulative) {
      return const InPlayResult(result: AtBatResultType.triple);
    }

    // 残りは本塁打（probHomeRun 分）
    return const InPlayResult(result: AtBatResultType.homeRun);
  }

  /// 1打席をシミュレート（盗塁判定を含む）
  /// pitchingTeam: 守備側チーム（打球方向の守備力を取得するため）
  /// runners: 現在のランナー状況
  /// outs: 現在のアウト数
  /// stealSimulator: 盗塁シミュレーター
  /// 投手から球種に対応するパラメータ値を取得（調子補正を適用）
  int? _getPitchParam(Player pitcher, PitchType pitchType, PitcherCondition condition) {
    int? baseParam;
    int modifier;

    switch (pitchType) {
      case PitchType.fastball:
        baseParam = pitcher.fastball;
        modifier = condition.fastballModifier;
        break;
      case PitchType.slider:
        baseParam = pitcher.slider;
        modifier = condition.sliderModifier;
        break;
      case PitchType.curveball:
        baseParam = pitcher.curve;
        modifier = condition.curveModifier;
        break;
      case PitchType.splitter:
        baseParam = pitcher.splitter;
        modifier = condition.splitterModifier;
        break;
      case PitchType.changeup:
        baseParam = pitcher.changeup;
        modifier = condition.changeupModifier;
        break;
      case PitchType.shoot:
        baseParam = pitcher.shoot;
        modifier = condition.shootModifier;
        break;
      case PitchType.cutter:
        baseParam = pitcher.cutter;
        modifier = condition.cutterModifier;
        break;
      case PitchType.sinker:
        baseParam = pitcher.sinker;
        modifier = condition.sinkerModifier;
        break;
    }

    if (baseParam == null) return null;
    // 調子補正を適用（1〜10の範囲内）
    return (baseParam + modifier).clamp(1, 10);
  }

  AtBatSimulationResult simulateAtBat(
    Player pitcher,
    Player batter,
    Team pitchingTeam, {
    required BaseRunners runners,
    required int outs,
    required StealSimulator stealSimulator,
    int pitchCount = 0, // この打席前までの投球数
    PitcherCondition condition = const PitcherCondition(), // 投手の調子
    int batterConditionModifier = 0, // 野手の調子（-1/0/+1）。攻撃面の能力に一律加算
    // バント途中でヒッティングに切り替わった場合に、現在カウントと既出投球を引き継ぐ
    int initialBalls = 0,
    int initialStrikes = 0,
    List<PitchResult> previousPitches = const [],
  }) {
    // 計測フラグでコンディション補正を 0 化
    final effectivePitcherCondition =
        disablePitcherCondition ? PitcherCondition.normal : condition;
    final effectiveBatterMod = disableBatterCondition ? 0 : batterConditionModifier;
    // 投手の平均球速（設定されていなければ145km）+ 調子補正
    final avgSpeed = (pitcher.averageSpeed ?? 145) + effectivePitcherCondition.speedModifier;
    // 投手の制球力（設定されていなければ5）+ 調子補正（1〜10の範囲内）
    final control = ((pitcher.control ?? 5) + effectivePitcherCondition.controlModifier).clamp(1, 10);
    // 投手の持ち球数（球種が多いほど打者が待ち球を絞れず、わずかに有利）
    final arsenalSize = _arsenalSize(pitcher);
    // 投手の弱点軸ペナルティ（3軸2軸欠点で急増する非線形ペナルティ）
    final weaknessPenalty = pitcherWeaknessPenalty(pitcher);
    // 打者のミート力（設定されていなければ5）+ 調子補正（1〜10の範囲内）
    final meet = ((batter.meet ?? 5) + effectiveBatterMod).clamp(1, 10);
    // 打者の長打力（設定されていなければ5）+ 調子補正
    final power = ((batter.power ?? 5) + effectiveBatterMod).clamp(1, 10);
    // 打者の走力（設定されていなければ5）+ 調子補正
    final batterSpeed = ((batter.speed ?? 5) + effectiveBatterMod).clamp(1, 10);
    // 打者の選球眼（設定されていなければ5）+ 調子補正
    final eye = ((batter.eye ?? 5) + effectiveBatterMod).clamp(1, 10);
    // 捕手の肩の強さ（盗塁阻止に使用）
    final catcher = pitchingTeam.getFielder(FieldPosition.catcher);
    final catcherArm = catcher?.arm ?? 5;

    // 打者の実効打席（両打ちは対投手で決まる）と利き手マッチアップ
    final batterSide = batter.effectiveBatsAgainst(pitcher);
    final isLeftBatter = batterSide == Handedness.left;
    // プラトーン不利は左vs左のみ（右vs右は補正なし）
    final isPlatoonDisadvantage =
        pitcher.effectiveThrows == Handedness.left && isLeftBatter;

    int balls = initialBalls;
    int strikes = initialStrikes;
    final pitches = <PitchResult>[...previousPitches];
    final recordedSteals = <StealAttempt>[]; // 記録される盗塁
    var currentRunners = runners;
    int additionalOuts = 0;
    int currentPitchCount = pitchCount + previousPitches.length; // 打席中の投球数を追跡
    int batteryErrorRuns = 0; // バッテリーエラーによる得点
    final batteryErrorScorers = <({Player runner, BatteryErrorType type})>[];
    // 捕手の守備力（パスボール判定に使用）
    final catcherFielding = catcher?.getFielding(DefensePosition.catcher) ?? 5;
    // 捕手が「捕手を守れない」状態で強引配置されているか（エラー率3倍の対象）
    final isCatcherForced =
        catcher != null && !catcher.canPlay(DefensePosition.catcher);

    while (true) {
      // 盗塁失敗で3アウトになったら打席終了
      if (outs + additionalOuts >= 3) {
        return AtBatSimulationResult(
          result: AtBatResultType.strikeout, // ダミー（使われない）
          pitches: pitches,
          stealAttempts: recordedSteals,
          updatedRunners: currentRunners,
          additionalOuts: additionalOuts,
          batteryErrorRuns: batteryErrorRuns,
          batteryErrorScorers: batteryErrorScorers,
        );
      }

      // 1. 盗塁判定（投球前）
      final stealAttempts = stealSimulator.simulateSteal(currentRunners, outs + additionalOuts, catcherArm: catcherArm);

      // 2. 球種選択と投球
      // 疲労度を計算（投球数に基づく、全投手共通カーブ）
      final fatigue = _calculateFatigue(currentPitchCount);
      // 直前まで同じ球種を投げた連続数を計算（同球種連続ペナルティ用）
      PitchType? prevPitchType;
      int prevSameStreak = 0;
      if (pitches.isNotEmpty) {
        prevPitchType = pitches.last.pitchType;
        for (int i = pitches.length - 1; i >= 0; i--) {
          if (pitches[i].pitchType == prevPitchType) {
            prevSameStreak++;
          } else {
            break;
          }
        }
      }
      final pitchType = _selectPitchType(
        pitcher,
        effectivePitcherCondition,
        prevPitchType: prevPitchType,
        prevSameStreak: prevSameStreak,
      );
      final speed = _generatePitchSpeed(avgSpeed, pitchType);
      final pitchParam =
          _getPitchParam(pitcher, pitchType, effectivePitcherCondition);
      var pitch = simulatePitch(
        balls,
        strikes,
        speed,
        control,
        meet,
        pitchType,
        pitchParam,
        eye: eye,
        power: power,
        fatigue: fatigue,
        isPlatoonDisadvantage: isPlatoonDisadvantage,
        batterSide: batterSide,
        arsenalSize: arsenalSize,
      );
      currentPitchCount++; // 投球数を増加

      // 2.5 ワイルドピッチ/パスボールチェック（ボール時のみ、ランナーがいる場合）
      BatteryError? currentBatteryError;
      if (pitch.type == PitchResultType.ball && currentRunners.hasRunners) {
        // ワイルドピッチチェック（投手の制球力と球種に依存）
        if (_errorSimulator.checkWildPitch(control, pitchType)) {
          final scorer = currentRunners.third; // 3塁ランナーが生還
          final errorResult = _errorSimulator.applyBatteryError(
            ErrorType.wildPitch,
            currentRunners,
          );
          currentRunners = _errorSimulator.applyBatteryErrorToRunners(currentRunners);
          batteryErrorRuns += errorResult.runsScored;
          if (errorResult.runsScored > 0 && scorer != null) {
            batteryErrorScorers.add(
              (runner: scorer, type: BatteryErrorType.wildPitch),
            );
          }
          currentBatteryError = BatteryError(
            type: BatteryErrorType.wildPitch,
            runsScored: errorResult.runsScored,
          );
        }
        // ワイルドピッチでなければパスボールチェック（捕手の守備力と球種に依存）
        else if (_errorSimulator.checkPassedBall(catcherFielding, pitchType,
            isForcedPlacement: isCatcherForced)) {
          final scorer = currentRunners.third;
          final errorResult = _errorSimulator.applyBatteryError(
            ErrorType.passedBall,
            currentRunners,
          );
          currentRunners = _errorSimulator.applyBatteryErrorToRunners(currentRunners);
          batteryErrorRuns += errorResult.runsScored;
          if (errorResult.runsScored > 0 && scorer != null) {
            batteryErrorScorers.add(
              (runner: scorer, type: BatteryErrorType.passedBall),
            );
          }
          currentBatteryError = BatteryError(
            type: BatteryErrorType.passedBall,
            runsScored: errorResult.runsScored,
          );
        }
      }

      // 2.6 捕手送球エラー（盗塁阻止失敗等）。
      // WP/PB と異なりボール球限定でなく、走者あり投球で独立試行。
      // NPB 捕手の PB 除く失策（150試合で 3〜5 個）を再現する経路。
      if (currentBatteryError == null && currentRunners.hasRunners) {
        if (_errorSimulator.checkCatcherThrowingError(catcherFielding,
            isForcedPlacement: isCatcherForced)) {
          final scorer = currentRunners.third;
          final errorResult = _errorSimulator.applyBatteryError(
            ErrorType.throwingError,
            currentRunners,
          );
          currentRunners =
              _errorSimulator.applyBatteryErrorToRunners(currentRunners);
          batteryErrorRuns += errorResult.runsScored;
          if (errorResult.runsScored > 0 && scorer != null) {
            batteryErrorScorers.add(
              (runner: scorer, type: BatteryErrorType.catcherThrowing),
            );
          }
          currentBatteryError = BatteryError(
            type: BatteryErrorType.catcherThrowing,
            runsScored: errorResult.runsScored,
            catcher: catcher,
          );
        }
      }

      // バッテリーエラーがあればPitchResultを更新
      if (currentBatteryError != null) {
        pitch = PitchResult(
          type: pitch.type,
          pitchType: pitch.pitchType,
          battedBallType: pitch.battedBallType,
          fieldPosition: pitch.fieldPosition,
          speed: pitch.speed,
          steals: pitch.steals,
          batteryError: currentBatteryError,
        );
      }

      // 3. 盗塁がある場合の処理
      // 盗塁が成立するのは投球がボール・見逃しストライク・空振りストライクの時のみ。
      // ファール（走者は塁に戻る）・インプレー（打球で進塁が決まる）・死球（押し出し
      // のみ）の球では走者は走らない／戻るため、盗塁は不成立として破棄する。
      final stealResolvable = pitch.type == PitchResultType.ball ||
          pitch.type == PitchResultType.strikeLooking ||
          pitch.type == PitchResultType.strikeSwinging;
      if (stealAttempts.isNotEmpty && stealResolvable) {
        final result = _resolveStealAndPitch(
          stealAttempts: stealAttempts,
          pitch: pitch,
          balls: balls,
          strikes: strikes,
          currentRunners: currentRunners,
          stealSimulator: stealSimulator,
          outs: outs + additionalOuts,
        );

        // 盗塁結果を反映
        currentRunners = result.newRunners;
        additionalOuts += result.additionalOuts;
        recordedSteals.addAll(result.recordedSteals);

        // フォアボール（ball 4）時は盗塁ではなく四球による進塁が優先される。
        // 走者位置は applyStealResult で既に進めた状態のままにするが、
        // pitch.steals に残る成功盗塁は SB として記録されないよう success=false に書き換える
        // （UI 上もフォアボール時の盗塁チップを表示しない）。
        // 盗塁失敗（CS）は実際にアウトが発生しているので、そのまま残す。
        final isBall4 =
            pitch.type == PitchResultType.ball && balls >= 3;
        final pitchSteals = isBall4
            ? stealAttempts
                .map((a) => a.success
                    ? StealAttempt(
                        runner: a.runner,
                        fromBase: a.fromBase,
                        toBase: a.toBase,
                        success: false,
                        isOut: false,
                      )
                    : a)
                .toList()
            : stealAttempts;

        // 盗塁結果を投球に付加して記録（バッテリーエラーも保持）
        pitches.add(
          PitchResult(
            type: pitch.type,
            pitchType: pitch.pitchType,
            battedBallType: pitch.battedBallType,
            fieldPosition: pitch.fieldPosition,
            speed: pitch.speed,
            steals: pitchSteals,
            batteryError: pitch.batteryError,
          ),
        );

        // 盗塁失敗で3アウトになったら打席終了
        if (outs + additionalOuts >= 3) {
          return AtBatSimulationResult(
            result: AtBatResultType.strikeout, // ダミー（使われない）
            pitches: pitches,
            stealAttempts: recordedSteals,
            updatedRunners: currentRunners,
            additionalOuts: additionalOuts,
            batteryErrorRuns: batteryErrorRuns,
            batteryErrorScorers: batteryErrorScorers,
          );
        }
      } else {
        // 盗塁なし、または投球がインプレー/ファール/死球で盗塁不成立
        pitches.add(pitch);
      }

      // 4. 打席終了条件をチェック（共通処理）
      final atBatEndCheck = _checkAtBatEnd(
        pitch: pitch,
        balls: balls,
        strikes: strikes,
        meet: meet,
        power: power,
        eye: eye,
        control: control,
        speed: speed,
        batterSpeed: batterSpeed,
        pitchingTeam: pitchingTeam,
        pitchParam: pitchParam,
        fatigue: fatigue,
        isPlatoonDisadvantage: isPlatoonDisadvantage,
        isLeftBatter: isLeftBatter,
        arsenalSize: arsenalSize,
        weaknessPenalty: weaknessPenalty,
      );

      if (atBatEndCheck.isEnded) {
        return AtBatSimulationResult(
          result: atBatEndCheck.result!,
          pitches: pitches,
          stealAttempts: recordedSteals,
          updatedRunners: currentRunners,
          additionalOuts: additionalOuts,
          fieldingError: atBatEndCheck.fieldingError,
          batterTakesExtraBase: atBatEndCheck.batterTakesExtraBase,
          batteryErrorRuns: batteryErrorRuns,
          batteryErrorScorers: batteryErrorScorers,
        );
      }

      // 5. カウント更新（共通処理）
      _updateCount(pitch, balls, strikes, (b, s) {
        balls = b;
        strikes = s;
      });
    }
  }

  /// バント打席をシミュレートする
  ///
  /// 球ごとにカウントを進めるループ構造:
  /// - 各球: バントの結果を抽選（ボール / 見逃しストライク / ファール / ポップ / インプレー）
  /// - 4ボール → 四球 / 3ストライク（見逃し含む）→ 三振
  /// - 2ストライクからのバントファール → 三振（スリーバント失敗）
  /// - 2ストライク到達時に「バント続行 vs ヒッティング切替」判断（打者の power に依存）
  /// - ヒッティング切替時は [simulateAtBat] にカウントを引き継いで委譲
  ///
  /// インプレー時は方向抽選 + 守備能力 vs 走力で結果を決定。
  AtBatSimulationResult simulateBuntAtBat(
    Player pitcher,
    Player batter, {
    required Team pitchingTeam,
    required BaseRunners runners,
    required int outs,
    required StealSimulator stealSimulator,
    int pitchCount = 0,
    PitcherCondition condition = const PitcherCondition(),
    int batterConditionModifier = 0,
  }) {
    final effectivePitcherCondition =
        disablePitcherCondition ? PitcherCondition.normal : condition;
    final effectiveBatterMod =
        disableBatterCondition ? 0 : batterConditionModifier;
    final meet =
        ((batter.meet ?? 5) + effectiveBatterMod).clamp(1, 10);
    final batterSpeed =
        ((batter.speed ?? 5) + effectiveBatterMod).clamp(1, 10);
    final power = batter.power ?? 5;
    final control =
        ((pitcher.control ?? 5) + effectivePitcherCondition.controlModifier)
            .clamp(1, 10);
    final avgSpeed =
        (pitcher.averageSpeed ?? 145) + effectivePitcherCondition.speedModifier;

    int balls = 0;
    int strikes = 0;
    final pitches = <PitchResult>[];

    while (true) {
      // 2ストライクで「バント続行 vs ヒッティング切替」判断。
      // 続行を選ばなかった場合、残りの打席を通常打席に委譲する。
      if (strikes >= 2 && !_shouldContinueBuntOn2Strikes(power)) {
        return simulateAtBat(
          pitcher,
          batter,
          pitchingTeam,
          runners: runners,
          outs: outs,
          stealSimulator: stealSimulator,
          pitchCount: pitchCount,
          condition: condition,
          batterConditionModifier: batterConditionModifier,
          initialBalls: balls,
          initialStrikes: strikes,
          previousPitches: pitches,
        );
      }

      // バント球を投げる
      final pitchOutcome =
          _rollBuntPitch(meet: meet, control: control, strikes: strikes);

      switch (pitchOutcome) {
        case _BuntPitchOutcome.ball:
          pitches.add(PitchResult(
            type: PitchResultType.ball,
            pitchType: PitchType.fastball,
            speed: avgSpeed,
          ));
          balls++;
          if (balls >= 4) {
            return AtBatSimulationResult(
              result: AtBatResultType.walk,
              pitches: pitches,
              updatedRunners: runners,
            );
          }
          break;

        case _BuntPitchOutcome.calledStrike:
          pitches.add(PitchResult(
            type: PitchResultType.strikeLooking,
            pitchType: PitchType.fastball,
            speed: avgSpeed,
          ));
          strikes++;
          if (strikes >= 3) {
            return AtBatSimulationResult(
              result: AtBatResultType.strikeout,
              pitches: pitches,
              updatedRunners: runners,
            );
          }
          break;

        case _BuntPitchOutcome.foul:
          pitches.add(PitchResult(
            type: PitchResultType.foul,
            pitchType: PitchType.fastball,
            speed: avgSpeed,
          ));
          if (strikes < 2) {
            strikes++;
          } else {
            // 2ストライクからのバントファール = スリーバント失敗（三振）
            return AtBatSimulationResult(
              result: AtBatResultType.strikeout,
              pitches: pitches,
              updatedRunners: runners,
            );
          }
          break;

        case _BuntPitchOutcome.popOut:
          final fieldPosition = _pickBuntPopOutPosition();
          pitches.add(PitchResult(
            type: PitchResultType.inPlay,
            pitchType: PitchType.fastball,
            battedBallType: BattedBallType.flyBall,
            fieldPosition: fieldPosition,
            speed: avgSpeed,
          ));
          return AtBatSimulationResult(
            result: AtBatResultType.flyOut,
            pitches: pitches,
            updatedRunners: runners,
          );

        case _BuntPitchOutcome.inPlay:
          final fieldPosition = _pickBuntDirection();
          pitches.add(PitchResult(
            type: PitchResultType.inPlay,
            pitchType: PitchType.fastball,
            battedBallType: BattedBallType.groundBall,
            fieldPosition: fieldPosition,
            speed: avgSpeed,
          ));
          final outcome = _resolveBuntInPlay(
            fieldPosition: fieldPosition,
            pitchingTeam: pitchingTeam,
            batter: batter,
            batterSpeed: batterSpeed,
            runners: runners,
            outs: outs,
          );
          return AtBatSimulationResult(
            result: outcome,
            pitches: pitches,
            updatedRunners: runners,
          );
      }
    }
  }

  /// バント 1 球の結果を抽選。
  /// meet が高いほどファールやインプレーを成功させやすく、ポップフライが減る。
  /// 制球が悪い投手はボール球が増える。
  /// 2ストライクからは打者がより慎重になり、無理にバットを出さず見送る確率が上がる。
  _BuntPitchOutcome _rollBuntPitch({
    required int meet,
    required int control,
    required int strikes,
  }) {
    // ボール球確率: 投手の制球力に依存
    final pBall = (0.30 - (control - 5) * 0.02).clamp(0.18, 0.45);
    // 見逃しストライク: バット引いてストライク取られる
    // 2ストライクでは「無理に当てに行かず見送る」率が下がるので少なめ
    final pCalled = strikes >= 2 ? 0.03 : 0.05;
    // ポップフライ: meet が低いほど高い
    final pPop = (0.04 - (meet - 5) * 0.005).clamp(0.015, 0.08);
    // ファール: meet が低いほど高い（バットがボールに上手く当たらず擦る）
    final pFoul = (0.20 - (meet - 5) * 0.005).clamp(0.15, 0.25);
    // インプレー（ゴロ）: 残り
    final pInPlay = (1.0 - pBall - pCalled - pPop - pFoul).clamp(0.10, 0.60);

    final r = _random.nextDouble();
    double cum = 0;
    cum += pBall;
    if (r < cum) return _BuntPitchOutcome.ball;
    cum += pCalled;
    if (r < cum) return _BuntPitchOutcome.calledStrike;
    cum += pPop;
    if (r < cum) return _BuntPitchOutcome.popOut;
    cum += pFoul;
    if (r < cum) return _BuntPitchOutcome.foul;
    cum += pInPlay;
    if (r < cum) return _BuntPitchOutcome.inPlay;
    return _BuntPitchOutcome.inPlay; // 余りはインプレー
  }

  /// 2ストライクで「バント続行か」を判定。
  /// 投手レベル（power ≤ 2）はヒッティングしてもダメなのでバント続行が多め。
  /// 強打者（バント自体しないので来ないが念のため）は切替が高い。
  bool _shouldContinueBuntOn2Strikes(int power) {
    final continueProb = power <= 2
        ? 0.80
        : power <= 4
            ? 0.45
            : power <= 6
                ? 0.25
                : 0.10;
    return _random.nextDouble() < continueProb;
  }

  /// バントゴロの打球方向を抽選（投手前 45% / 三塁前 35% / 一塁前 15% / 捕手前 5%）
  FieldPosition _pickBuntDirection() {
    final r = _random.nextDouble();
    if (r < 0.45) return FieldPosition.pitcher;
    if (r < 0.80) return FieldPosition.third;
    if (r < 0.95) return FieldPosition.first;
    return FieldPosition.catcher;
  }

  /// バント小フライの方向（外野には飛ばない、捕手寄り）
  FieldPosition _pickBuntPopOutPosition() {
    final r = _random.nextDouble();
    if (r < 0.40) return FieldPosition.pitcher;
    if (r < 0.70) return FieldPosition.catcher;
    if (r < 0.85) return FieldPosition.third;
    return FieldPosition.first;
  }

  /// Phase 2: ゴロでインプレーした後の解決。
  /// 守備側は「先頭走者を狙うか、安全に 1 塁送球で打者をアウトにするか」を判断し、
  /// 該当走者の走力 vs 守備力（fielding + arm）で結果を決定する。
  AtBatResultType _resolveBuntInPlay({
    required FieldPosition fieldPosition,
    required Team pitchingTeam,
    required Player batter,
    required int batterSpeed,
    required BaseRunners runners,
    required int outs,
  }) {
    final fielder = pitchingTeam.getFielder(fieldPosition);
    // 投手位置は fielding マップに無いので、フォールバック 5。
    final fielderFielding =
        fieldPosition.defensePosition == null
            ? 5
            : (fielder?.getFielding(fieldPosition.defensePosition!) ?? 5);
    final fielderArm = fielder?.arm ?? 5;

    // 先頭走者: 2塁にいれば 2塁走者、それ以外は 1塁走者。bunt strategy 上
    // 必ずどちらかが居る前提だが、防御的に処理する。
    final leadRunner = runners.second ?? runners.first;
    final leadRunnerSpeed = leadRunner?.speed ?? 5;

    // 守備側の判断: 先頭走者を狙うか
    // 三塁手前は 3 塁・2 塁が近い、投手前は 2 塁送球がやや楽、
    // 一塁手前は 1 塁が一番近いので普通に 1 塁、捕手前は 1 塁にタッチ近い
    final goForLead = leadRunner != null &&
        _shouldThrowToLead(
          fielderFielding: fielderFielding,
          fielderArm: fielderArm,
          leadRunnerSpeed: leadRunnerSpeed,
          fieldPosition: fieldPosition,
        );

    if (goForLead) {
      final pLeadOut = _leadRunnerOutProb(
        fielderFielding: fielderFielding,
        fielderArm: fielderArm,
        leadRunnerSpeed: leadRunnerSpeed,
        fieldPosition: fieldPosition,
      );
      if (_random.nextDouble() < pLeadOut) {
        // 先頭走者刺殺。さらに 1塁転送で打者も刺せるか?
        // 1アウト時のみ DP のチャンス（0アウトで DP 完成は稀ではあるが、
        // 実装簡略化のため「打者足遅い + 守備力高い」で確率発火）
        final pDP = _doublePlayProb(
          batterSpeed: batterSpeed,
          fielderArm: fielderArm,
        );
        if (_random.nextDouble() < pDP) {
          return AtBatResultType.doublePlay;
        }
        return AtBatResultType.fieldersChoice;
      }
      // 先頭走者刺殺失敗 → 全員セーフ = バント安打
      return AtBatResultType.infieldHit;
    } else {
      // 1塁送球。打者を刺せれば送りバント成功、間に合わなければバント安打。
      final pFirstOut = _firstBaseOutProb(
        fielderFielding: fielderFielding,
        fielderArm: fielderArm,
        batterSpeed: batterSpeed,
        fieldPosition: fieldPosition,
      );
      if (_random.nextDouble() < pFirstOut) {
        return AtBatResultType.sacrificeBunt;
      }
      return AtBatResultType.infieldHit;
    }
  }

  /// 先頭走者を狙うかどうかの判定。
  /// 守備力と肩が高い + 走者が遅い + 守備位置が有利 で攻めの送球を選ぶ確率が上がる。
  bool _shouldThrowToLead({
    required int fielderFielding,
    required int fielderArm,
    required int leadRunnerSpeed,
    required FieldPosition fieldPosition,
  }) {
    final positionMod = switch (fieldPosition) {
      FieldPosition.third => 0.15, // 三塁手は 3塁/2塁が視野内
      FieldPosition.pitcher => 0.05,
      FieldPosition.catcher => 0.10,
      FieldPosition.first => -0.10, // 1塁手は 1塁タッチが楽
      _ => 0.0,
    };
    final p = (0.10 +
            positionMod +
            (fielderFielding - 5) * 0.04 +
            (fielderArm - 5) * 0.03 -
            (leadRunnerSpeed - 5) * 0.06)
        .clamp(0.02, 0.50);
    return _random.nextDouble() < p;
  }

  /// 先頭走者を刺せる確率
  double _leadRunnerOutProb({
    required int fielderFielding,
    required int fielderArm,
    required int leadRunnerSpeed,
    required FieldPosition fieldPosition,
  }) {
    final positionMod = switch (fieldPosition) {
      FieldPosition.third => 0.10,
      FieldPosition.pitcher => 0.0,
      _ => -0.05,
    };
    return (0.65 +
            positionMod +
            (fielderFielding - 5) * 0.04 +
            (fielderArm - 5) * 0.04 -
            (leadRunnerSpeed - 5) * 0.05)
        .clamp(0.30, 0.90);
  }

  /// 先頭走者を刺した後、1塁転送で打者も刺せる確率（バント DP）。
  double _doublePlayProb({
    required int batterSpeed,
    required int fielderArm,
  }) {
    return (0.10 -
            (batterSpeed - 5) * 0.03 +
            (fielderArm - 5) * 0.02)
        .clamp(0.02, 0.25);
  }

  /// 1塁送球で打者を刺せる確率（送りバント成功）
  double _firstBaseOutProb({
    required int fielderFielding,
    required int fielderArm,
    required int batterSpeed,
    required FieldPosition fieldPosition,
  }) {
    final positionMod = switch (fieldPosition) {
      FieldPosition.pitcher => 0.10, // 投手前は 1塁送球が短い
      FieldPosition.first => 0.05,
      FieldPosition.catcher => 0.05,
      FieldPosition.third => 0.0, // 3塁前は 1塁送球が長い分やや不利
      _ => 0.0,
    };
    return (0.90 +
            positionMod +
            (fielderFielding - 5) * 0.04 +
            (fielderArm - 5) * 0.03 -
            (batterSpeed - 5) * 0.05)
        .clamp(0.55, 0.99);
  }

  /// 盗塁と投球の組み合わせを解決
  _StealPitchResult _resolveStealAndPitch({
    required List<StealAttempt> stealAttempts,
    required PitchResult pitch,
    required int balls,
    required int strikes,
    required BaseRunners currentRunners,
    required StealSimulator stealSimulator,
    required int outs,
  }) {
    var newRunners = currentRunners;
    int additionalOuts = 0;
    final recordedSteals = <StealAttempt>[];

    // 投球結果による打席終了判定（四球時の盗塁記録判定に使用）
    final isBall4 = pitch.type == PitchResultType.ball && balls >= 3;

    // 盗塁結果を適用
    final (runnersAfterSteal, outsAfterSteal) = stealSimulator.applyStealResult(currentRunners, outs, stealAttempts);
    newRunners = runnersAfterSteal;
    additionalOuts = outsAfterSteal - outs;

    // 成功した盗塁を記録するかどうか判定
    for (final attempt in stealAttempts) {
      if (attempt.success) {
        // フォアボール（ball 4）時は盗塁としてカウントしない
        // 押し出されない走者の進塁も「フォアボール優先」で SB クレジットを付けない
        if (isBall4) continue;
        recordedSteals.add(attempt);
      }
      // 失敗した盗塁は記録しない（caught stealingは別途カウント）
    }

    return _StealPitchResult(newRunners: newRunners, additionalOuts: additionalOuts, recordedSteals: recordedSteals);
  }

  /// 打席終了条件をチェック
  AtBatEndCheckResult _checkAtBatEnd({
    required PitchResult pitch,
    required int balls,
    required int strikes,
    required int meet,
    required int power,
    required int eye,
    required int control,
    required int speed,
    required int batterSpeed,
    required Team pitchingTeam,
    required int? pitchParam,
    double fatigue = 0.0,
    bool isPlatoonDisadvantage = false,
    bool isLeftBatter = false,
    int arsenalSize = 4,
    double weaknessPenalty = 0.0,
  }) {
    switch (pitch.type) {
      case PitchResultType.ball:
        if (balls >= 3) {
          return const AtBatEndCheckResult(result: AtBatResultType.walk);
        }
        return const AtBatEndCheckResult();

      case PitchResultType.hitByPitch:
        // 死球は即座に打席終了、打者は1塁へ（カウントは関係ない）
        return const AtBatEndCheckResult(result: AtBatResultType.hitByPitch);

      case PitchResultType.strikeLooking:
      case PitchResultType.strikeSwinging:
        if (strikes >= 2) {
          return const AtBatEndCheckResult(result: AtBatResultType.strikeout);
        }
        return const AtBatEndCheckResult();

      case PitchResultType.foul:
        return const AtBatEndCheckResult();

      case PitchResultType.inPlay:
        final fielding = pitchingTeam.getFieldingAt(pitch.fieldPosition!);
        final fielder = pitchingTeam.getFielder(pitch.fieldPosition!);
        final catcher = pitchingTeam.getFielder(FieldPosition.catcher);
        final defPos = pitch.fieldPosition!.defensePosition;
        final isFielderForced =
            fielder != null && defPos != null && !fielder.canPlay(defPos);
        final inPlayResult = simulateInPlayResult(
          pitch.battedBallType!,
          speed,
          control,
          meet,
          power,
          fielding,
          batterSpeed: batterSpeed,
          batterEye: eye,
          fieldPosition: pitch.fieldPosition,
          fielderArm: fielder?.arm,
          catcherFielding: catcher?.getFielding(DefensePosition.catcher),
          pitchType: pitch.pitchType,
          pitchParam: pitchParam,
          fatigue: fatigue,
          isPlatoonDisadvantage: isPlatoonDisadvantage,
          isLeftBatter: isLeftBatter,
          weaknessPenalty: weaknessPenalty,
          isFielderForcedPlacement: isFielderForced,
          arsenalSize: arsenalSize,
        );
        return AtBatEndCheckResult(
          result: inPlayResult.result,
          fieldingError: inPlayResult.fieldingError,
          batterTakesExtraBase: inPlayResult.batterTakesExtraBase,
        );
    }
  }

  /// カウント更新
  void _updateCount(PitchResult pitch, int balls, int strikes, void Function(int, int) callback) {
    switch (pitch.type) {
      case PitchResultType.ball:
        callback(balls + 1, strikes);
        break;
      case PitchResultType.strikeLooking:
      case PitchResultType.strikeSwinging:
        callback(balls, strikes + 1);
        break;
      case PitchResultType.foul:
        if (strikes < 2) {
          callback(balls, strikes + 1);
        } else {
          callback(balls, strikes);
        }
        break;
      case PitchResultType.inPlay:
      case PitchResultType.hitByPitch:
        // 死球はカウント据え置き（打席は即終了するためここに来た時点で次球は無い）
        callback(balls, strikes);
        break;
    }
  }
}

/// 盗塁と投球の組み合わせ結果
class _StealPitchResult {
  final BaseRunners newRunners;
  final int additionalOuts;
  final List<StealAttempt> recordedSteals;

  const _StealPitchResult({required this.newRunners, required this.additionalOuts, required this.recordedSteals});
}

/// バント 1 球の結果（_rollBuntPitch の戻り値）
enum _BuntPitchOutcome {
  ball,          // ボール（投球が外れた / 見送り）
  calledStrike,  // 見逃しストライク（バントを引いて見送る）
  foul,          // バントしたがファール
  popOut,        // バント小フライ（捕球でアウト）
  inPlay,        // バントゴロでインプレー
}

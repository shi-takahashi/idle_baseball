import 'dart:math';

import '../models/base_runners.dart';
import '../models/enums.dart';
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

  /// 次に打席に立つ打者（ワンポイント判定で使用）
  final Player? batter;

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
    this.batter,
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
    final isCurrentSituational =
        state.currentPitcher.reliefRole == ReliefRole.situational;

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

    // ---- セットアッパー強制起用（8回頭の接戦） ----
    // 8回頭で接戦（リード or 同点 ≤ 3点差）の場合、現投手がセットアッパー以外なら
    // セットアッパーへ強制スイッチ。中継ぎが7回から続投して8回に入るケースで、
    // セットアッパーの本来の出番を確保する。
    // 適用しない場合:
    //   - 既にセットアッパーがマウンド
    //   - 抑えがマウンド（save situation で先に呼ばれているケース）
    //   - 先発が完封ペース → 続投で完封狙い
    if (context.inning == 8 &&
        context.outs == 0 &&
        context.scoreDiff >= 0 &&
        context.scoreDiff <= 3 &&
        !isCurrentCloser &&
        state.currentPitcher.reliefRole != ReliefRole.setup &&
        !_isStarterOnShutoutPace(context, isStarter)) {
      for (final p in state.bullpen) {
        if (p.reliefRole != ReliefRole.setup) continue;
        if (context.closer != null && p.id == context.closer!.id) continue;
        return PitcherChangeDecision(
          newPitcher: p,
          reason: '8回セットアップ',
        );
      }
    }

    // ---- ワンポイント（左 vs 左マッチアップ）の起用判断 ----
    // 終盤の接戦で、現投手が右投手、次打者が左強打者、左の situational reliever が
    // ベンチにいるならスイッチする。
    // 抑え/先発の交代として割り込まないようにリリーフ間の交代に限定（先発が
    // まだマウンドにいる場合は普通の交代条件で先に降ろす方が自然）。
    if (!isCurrentCloser && !isStarter && !isCurrentSituational) {
      final lefty = _findLefty(context, state);
      if (lefty != null) {
        return PitcherChangeDecision(
          newPitcher: lefty,
          reason: '左vs左',
        );
      }
    }

    // ---- ワンポイント役目終了後の交代 ----
    // 現投手がワンポイント（situational）で、左打者をすでに1人以上抑え、
    // 次打者が右打ちなら役目終了。次の中継ぎへスイッチする。
    if (isCurrentSituational && state.pitchCount > 0 && context.batter != null) {
      final batsAgainst =
          context.batter!.effectiveBatsAgainst(state.currentPitcher);
      if (batsAgainst != Handedness.left) {
        // 役目を終えた → 通常選択でリリーフを呼ぶ
        if (state.bullpen.isNotEmpty) {
          final newPitcher = _selectReliever(context);
          return PitcherChangeDecision(
            newPitcher: newPitcher,
            reason: 'ワンポイント終了',
          );
        }
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
  ///
  /// 抑え（closer）とセットアッパー（setup）は役割が明確で、本来の場面以外で
  /// 起用しない。中継ぎ・ワンポイント・ロング・敗戦処理で吸収する方針。
  ///   - 抑え: セーブ機会以外では使わない（decide() 側で直接呼ぶ）
  ///   - セットアッパー: リード時の8回 / 同点8回以降のみ。それ以外では候補から外す。
  ///     どうしても他に投手が残っていない場合のみフォールバックとして起用。
  ///
  /// ロール優先度に合致する投手がいなければフレッシュ順の先頭を選ぶ。
  Player _selectReliever(PitcherChangeContext context) {
    final closer = context.closer;
    var pool = closer == null
        ? List<Player>.of(context.availableRelievers)
        : context.availableRelievers
            .where((p) => p.id != closer.id)
            .toList();
    if (pool.isEmpty) return context.availableRelievers.first;

    // セットアッパーを温存: 本来の場面以外では候補から外す
    if (_shouldReserveSetup(context)) {
      final nonSetup =
          pool.where((p) => p.reliefRole != ReliefRole.setup).toList();
      if (nonSetup.isNotEmpty) pool = nonSetup;
      // 残ったのが抑え+セットアッパーだけ等、本当に枯渇した場合は
      // セットアッパーを最終手段として残しておく（pool そのままで継続）
    }

    final preferred = _preferredRoles(context);
    for (final role in preferred) {
      for (final p in pool) {
        if (p.reliefRole == role) return p;
      }
    }
    return pool.first;
  }

  /// セットアッパーを温存するべき場面かどうか
  /// 起用 OK な場面: リード時の8回 / 同点 8回以降
  /// それ以外（負け・大差・序中盤・延長）では温存する
  bool _shouldReserveSetup(PitcherChangeContext context) {
    final scoreDiff = context.scoreDiff;
    final inning = context.inning;
    // リードしている8回はセットアッパーの本職
    if (scoreDiff > 0 && inning == 8) return false;
    // 同点の8回・9回もセットアッパーで OK（ホールド機会）
    if (scoreDiff == 0 && inning >= 8 && inning < 10) return false;
    // それ以外は温存
    return true;
  }

  /// 試合状況から、リリーフロールの優先順位を決める
  ///
  /// セットアッパーは「リード時の8回」「同点8回以降」だけ priority に入れる。
  /// それ以外で setup が pool に残っていると `_selectReliever` で除外される。
  ///
  /// - 延長戦（10回以降）: ロング優先（中継ぎ・敗戦処理で吸収）
  /// - 先発の早期降板（3回以前 or 球数 < 50）: ロング優先
  /// - 大差（5点差以上）: 敗戦処理優先（主力温存）
  /// - リード中の8回: セットアッパー
  /// - リード中の他のイニング: 中継ぎ
  /// - 同点8回以降: セットアッパー or 中継ぎ
  /// - 同点6〜7回: 中継ぎ
  /// - 接戦で負け: 中継ぎ → 敗戦処理
  /// - 大差で負け: 敗戦処理
  List<ReliefRole> _preferredRoles(PitcherChangeContext context) {
    final inning = context.inning;
    final scoreDiff = context.scoreDiff;
    final state = context.pitchingState;
    final isStarterPull = state.currentPitcher.id == state.usedPitchers.first.id;

    // 延長戦
    if (inning >= 10) {
      return const [
        ReliefRole.long,
        ReliefRole.middle,
        ReliefRole.mopUp,
      ];
    }

    // 先発の早期降板
    if (isStarterPull && (inning <= 3 || state.pitchCount < 50)) {
      return const [
        ReliefRole.long,
        ReliefRole.mopUp,
        ReliefRole.middle,
      ];
    }

    // 大差（5点差以上）→ 主力温存
    if (scoreDiff.abs() >= 5) {
      return const [
        ReliefRole.mopUp,
        ReliefRole.middle,
      ];
    }

    // リード中
    if (scoreDiff > 0) {
      if (inning == 8) {
        return const [
          ReliefRole.setup,
          ReliefRole.middle,
        ];
      }
      // リード時の他のイニングは中継ぎ
      return const [ReliefRole.middle];
    }

    // 同点
    if (scoreDiff == 0) {
      if (inning >= 8) {
        return const [
          ReliefRole.setup,
          ReliefRole.middle,
        ];
      }
      return const [ReliefRole.middle];
    }

    // 接戦で負け（1〜3点差）
    if (scoreDiff >= -3) {
      return const [
        ReliefRole.middle,
        ReliefRole.mopUp,
      ];
    }

    // 4点差以上の負け
    return const [
      ReliefRole.mopUp,
      ReliefRole.middle,
    ];
  }

  /// ワンポイント候補の左投手を見つける
  /// 条件:
  ///   - 終盤（7〜9回）
  ///   - 接戦（リード/ビハインド ≤ 2 点）
  ///   - 走者あり（ピンチでないと出さない）
  ///   - 次打者が左打ち、かつ「強打者」（meet ≥ 7 or power ≥ 7）
  ///   - 現投手が左投手ではない（既に左 vs 左になっていない）
  ///   - 利用可能な situational lefty がベンチにいる
  ///
  /// MLB の3 batter rule 以降の現代運用に合わせ、左強打者へのワンポイント起用に
  /// 限定する。普通の左打者にいちいち変えるとワンポイントが酷使される。
  Player? _findLefty(PitcherChangeContext context, TeamPitchingState state) {
    final batter = context.batter;
    if (batter == null) return null;
    final batsAgainst = batter.effectiveBatsAgainst(state.currentPitcher);
    if (batsAgainst != Handedness.left) return null;
    if (context.inning < 7) return null;
    if (context.scoreDiff.abs() > 2) return null;
    if (state.currentPitcher.effectiveThrows == Handedness.left) return null;
    if (!context.runners.hasRunners) return null;

    // 強打者（ミート力か長打力が7以上）に限定
    final meet = batter.meet ?? 5;
    final power = batter.power ?? 5;
    if (meet < 7 && power < 7) return null;

    // ベンチに situational ロールの左投手がいるか
    for (final p in state.bullpen) {
      if (p.reliefRole != ReliefRole.situational) continue;
      if (p.effectiveThrows != Handedness.left) continue;
      // 抑えと被らないように除外（実際には situational != closer のはずだが念のため）
      if (context.closer != null && p.id == context.closer!.id) continue;
      return p;
    }
    return null;
  }
}

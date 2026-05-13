import '../models/enums.dart';
import '../models/fielder_change.dart';
import '../models/player.dart';
import '../models/team.dart';

/// 1チーム分の野手運用状態（可変）
///
/// 攻撃側の交代（代打・代走）では **ラインナップのみ** 更新する。
/// 守備配置（currentAlignment）の変更は、そのチームが守備につくハーフイニングの開始時に
/// reconcileAlignmentBeforeDefense() で一括確定する。
class TeamFieldingState {
  final Team originalTeam;

  List<Player> currentLineup;
  Map<FieldPosition, Player> currentAlignment;
  final List<Player> bench;
  final List<Player> usedPlayers;

  /// 現投手が打順のどのスロットに居るか（0-indexed、0=1番、8=9番）。
  /// 通常は 9 番（slot 8）だが、大谷型なら他の打順にも置ける。
  /// 投手代打が発生した直後は、PH 選手がこのスロットに居る状態になり、
  /// 続く投手交代でこのスロットの選手を新投手に差し替える。
  int pitcherBattingSlot;

  TeamFieldingState._({
    required this.originalTeam,
    required this.currentLineup,
    required this.currentAlignment,
    required this.bench,
    required this.usedPlayers,
    required this.pitcherBattingSlot,
  });

  factory TeamFieldingState.fromTeam(Team team) {
    final alignment = <FieldPosition, Player>{};
    for (final pos in FieldPosition.values) {
      final fielder = team.getFielder(pos);
      if (fielder != null) alignment[pos] = fielder;
    }
    return TeamFieldingState._(
      originalTeam: team,
      currentLineup: List.of(team.players),
      currentAlignment: alignment,
      bench: List.of(team.bench),
      usedPlayers: List.of(team.players),
      pitcherBattingSlot: team.pitcherBattingIndex,
    );
  }

  Player currentBatter(int battingOrder) =>
      currentLineup[battingOrder % 9];

  Team asTeamSnapshot() {
    return Team(
      id: originalTeam.id,
      name: originalTeam.name,
      shortName: originalTeam.shortName,
      players: List.of(currentLineup),
      startingRotation: originalTeam.startingRotation,
      bullpen: originalTeam.bullpen,
      bench: List.of(bench),
      defenseAlignment: Map.of(currentAlignment),
      primaryColorValue: originalTeam.primaryColorValue,
    );
  }

  FieldPosition? positionOf(Player player) {
    for (final entry in currentAlignment.entries) {
      if (entry.value.id == player.id) return entry.key;
    }
    return null;
  }

  /// 投手が交代した際の処理
  /// - 守備配置の投手位置を新投手で上書き
  /// - DH非採用のため、投手スロットに居る選手（前任投手 or 投手代打の PH）を
  ///   新投手に差し替え（前任 / PH は退場扱い）
  /// - 新投手を出場済みに記録
  void setPitcher(Player pitcher) {
    currentAlignment[FieldPosition.pitcher] = pitcher;

    // 投手スロットを直接 newPitcher に書き換え。
    // - 通常: 旧投手 (currentLineup[pitcherBattingSlot] == oldPitcher) を上書き
    // - 投手代打後: PH 選手が居るスロットを上書き（PH は試合から退場）
    if (pitcherBattingSlot >= 0 &&
        pitcherBattingSlot < currentLineup.length) {
      currentLineup[pitcherBattingSlot] = pitcher;
    }

    // 出場記録を更新
    if (!usedPlayers.any((p) => p.id == pitcher.id)) {
      usedPlayers.add(pitcher);
    }
  }

  /// 代打を適用する（ラインナップのみ更新、守備配置は触らない）
  void applyPinchHit({
    required Player outgoing,
    required Player incoming,
    required int battingOrder,
  }) {
    _applyLineupSubstitution(
      outgoing: outgoing,
      incoming: incoming,
      battingOrder: battingOrder,
    );
  }

  /// 代走を適用する（ラインナップのみ更新、守備配置は触らない）
  void applyPinchRun({
    required Player outgoing,
    required Player incoming,
    required int battingOrder,
  }) {
    _applyLineupSubstitution(
      outgoing: outgoing,
      incoming: incoming,
      battingOrder: battingOrder,
    );
  }

  /// ラインナップの入れ替え
  /// outgoing → incoming に差し替え、ベンチ・出場記録を更新
  /// 守備配置は変更しない
  void _applyLineupSubstitution({
    required Player outgoing,
    required Player incoming,
    required int battingOrder,
  }) {
    currentLineup[battingOrder] = incoming;
    bench.removeWhere((p) => p.id == incoming.id);
    if (!usedPlayers.any((p) => p.id == incoming.id)) {
      usedPlayers.add(incoming);
    }
  }

  /// 守備につく直前に、ラインナップと守備配置の整合を取って変更を確定させる
  ///
  /// 処理内容:
  /// 1. ラインナップから退場した選手（outgoing）が守備位置を空ける
  /// 2. ラインナップに入ったが守備位置の無い選手（incoming）にポジションを割り当てる
  ///    - 空いているポジションを直接守れるならそこへ
  ///    - 守れないなら既存野手とスワップ
  ///    - どうしても無理なら強引に配置
  ///
  /// 戻り値: このハーフイニング開始時点で確定した守備配置変更のリスト
  List<DefensiveChange> reconcileAlignmentBeforeDefense() {
    final changes = <DefensiveChange>[];
    final lineupIds = currentLineup.map((p) => p.id).toSet();

    // outgoing: アライメントにいるがラインナップにいない（= 試合から退いた）
    // ただし投手位置は pitchingState で管理しているので除外
    final vacantPositions = <FieldPosition>[];
    for (final entry in currentAlignment.entries) {
      if (entry.key == FieldPosition.pitcher) continue;
      if (!lineupIds.contains(entry.value.id)) {
        vacantPositions.add(entry.key);
      }
    }

    // outgoing をアライメントから削除
    for (final pos in vacantPositions) {
      currentAlignment.remove(pos);
    }

    // incoming: ラインナップにいるがアライメントにいない（= 守備につく必要あり）
    final alignmentIds = currentAlignment.values.map((p) => p.id).toSet();
    final unplacedPlayers = <Player>[];
    for (final p in currentLineup) {
      if (alignmentIds.contains(p.id)) continue;
      unplacedPlayers.add(p);
    }

    // unplaced をひとりずつ配置していく
    for (final newcomer in unplacedPlayers) {
      final assigned = _assignUnplaced(newcomer, vacantPositions, changes);
      if (assigned != null) {
        vacantPositions.remove(assigned);
      }
    }

    return changes;
  }

  /// 1人の未配置選手 newcomer をどこかに配置する
  /// vacantPositions のうちどこかを埋め、必要に応じて既存野手を移動させる
  /// 戻り値: newcomer が埋めた元の vacant ポジション（そのポジションは埋まった）
  FieldPosition? _assignUnplaced(
    Player newcomer,
    List<FieldPosition> vacantPositions,
    List<DefensiveChange> changes,
  ) {
    // ケース1: vacant のどれかを直接守れる
    for (final pos in vacantPositions) {
      final defPos = pos.defensePosition;
      if (defPos == null) continue;
      if (newcomer.canPlay(defPos)) {
        currentAlignment[pos] = newcomer;
        changes.add(DefensiveChange(
          player: newcomer,
          fromPosition: null,
          toPosition: pos,
        ));
        return pos;
      }
    }

    // ケース2: スワップ
    // 既存野手 F が vacant のどれかを守れる かつ newcomer が F の現在のポジションを守れる
    for (final vacant in vacantPositions) {
      final vacantDefPos = vacant.defensePosition;
      if (vacantDefPos == null) continue;

      for (final entry in currentAlignment.entries.toList()) {
        final fielderPos = entry.key;
        final fielder = entry.value;
        if (fielderPos == FieldPosition.pitcher) continue;

        if (!fielder.canPlay(vacantDefPos)) continue;

        final newcomerDefPos = fielderPos.defensePosition;
        if (newcomerDefPos == null) continue;
        if (!newcomer.canPlay(newcomerDefPos)) continue;

        // スワップ成立: fielder を vacant へ、newcomer を fielderPos へ
        currentAlignment[vacant] = fielder;
        currentAlignment[fielderPos] = newcomer;
        changes.add(DefensiveChange(
          player: fielder,
          fromPosition: fielderPos,
          toPosition: vacant,
        ));
        changes.add(DefensiveChange(
          player: newcomer,
          fromPosition: null,
          toPosition: fielderPos,
        ));
        return vacant;
      }
    }

    // ケース2.5: 2段スワップ（A → B → C のローテーション）
    // 単発スワップが組めない時、既存野手 2 人をローテして newcomer を埋める。
    //   例: SS の打者に代打 N (SS 不可・2B 可) を送った
    //       現 2B (F) は SS 不可、現 1B (G) が SS 可、F は 1B 可 →
    //       SS ← G、 1B ← F、 2B ← N で全員が守れる位置に着く。
    //
    // 条件: F が vacant を守れる、F の元位置を G が守れる、G の元位置を newcomer が守れる。
    for (final vacant in vacantPositions) {
      final vacantDefPos = vacant.defensePosition;
      if (vacantDefPos == null) continue;

      var matched = false;
      for (final fEntry in currentAlignment.entries.toList()) {
        if (matched) break;
        final fPos = fEntry.key;
        final f = fEntry.value;
        if (fPos == FieldPosition.pitcher) continue;
        if (!f.canPlay(vacantDefPos)) continue;

        final fDefPos = fPos.defensePosition;
        if (fDefPos == null) continue;

        for (final gEntry in currentAlignment.entries.toList()) {
          final gPos = gEntry.key;
          final g = gEntry.value;
          if (gPos == FieldPosition.pitcher) continue;
          if (gPos == fPos) continue;
          if (!g.canPlay(fDefPos)) continue;

          final gDefPos = gPos.defensePosition;
          if (gDefPos == null) continue;
          if (!newcomer.canPlay(gDefPos)) continue;

          currentAlignment[vacant] = f;
          currentAlignment[fPos] = g;
          currentAlignment[gPos] = newcomer;
          changes.add(DefensiveChange(
            player: f,
            fromPosition: fPos,
            toPosition: vacant,
          ));
          changes.add(DefensiveChange(
            player: g,
            fromPosition: gPos,
            toPosition: fPos,
          ));
          changes.add(DefensiveChange(
            player: newcomer,
            fromPosition: null,
            toPosition: gPos,
          ));
          matched = true;
          break;
        }
      }
      if (matched) return vacant;
    }

    // ケース3: ベンチから「vacant を直接守れる選手」を呼んで投入し、
    // newcomer は試合から退場させる（守備固めの代替）。
    // newcomer は代打で打席を消費済みなので、退場しても攻撃面の損失は無い。
    for (final vacant in vacantPositions) {
      final defPos = vacant.defensePosition;
      if (defPos == null) continue;
      Player? reliever;
      for (final b in bench) {
        if (b.isPitcher) continue;
        if (b.id == newcomer.id) continue;
        if (b.canPlay(defPos)) {
          reliever = b;
          break;
        }
      }
      if (reliever == null) continue;

      final slot = currentLineup.indexWhere((p) => p.id == newcomer.id);
      if (slot < 0) continue;

      currentLineup[slot] = reliever;
      bench.removeWhere((p) => p.id == reliever!.id);
      if (!usedPlayers.any((p) => p.id == reliever!.id)) {
        usedPlayers.add(reliever);
      }
      currentAlignment[vacant] = reliever;
      changes.add(DefensiveChange(
        player: reliever,
        fromPosition: null,
        toPosition: vacant,
      ));
      return vacant;
    }

    // ケース4: それでも埋まらない → 残った vacant のうち newcomer がまだ守れる
    // 位置を優先的に選んで強引配置（守れる位置が無ければ守備力 1 で強行）。
    if (vacantPositions.isNotEmpty) {
      FieldPosition? chosen;
      for (final pos in vacantPositions) {
        final defPos = pos.defensePosition;
        if (defPos == null) continue;
        if (newcomer.canPlay(defPos)) {
          chosen = pos;
          break;
        }
      }
      chosen ??= vacantPositions.first;
      currentAlignment[chosen] = newcomer;
      changes.add(DefensiveChange(
        player: newcomer,
        fromPosition: null,
        toPosition: chosen,
      ));
      return chosen;
    }

    return null;
  }
}

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

  TeamFieldingState._({
    required this.originalTeam,
    required this.currentLineup,
    required this.currentAlignment,
    required this.bench,
    required this.usedPlayers,
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
      bullpen: originalTeam.bullpen,
      bench: List.of(bench),
      defenseAlignment: Map.of(currentAlignment),
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
  /// - DH非採用のため、打順スロットに居る古い投手も新投手に差し替え（古い投手は退場）
  /// - 新投手を出場済みに記録
  void setPitcher(Player pitcher) {
    final oldPitcher = currentAlignment[FieldPosition.pitcher];
    currentAlignment[FieldPosition.pitcher] = pitcher;

    // ラインナップ上の投手スロットを新投手に更新（古い投手を排除）
    if (oldPitcher != null) {
      for (int i = 0; i < currentLineup.length; i++) {
        if (currentLineup[i].id == oldPitcher.id) {
          currentLineup[i] = pitcher;
          break;
        }
      }
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

    // ケース3: どうしても無理 → 強引に配置
    if (vacantPositions.isNotEmpty) {
      final pos = vacantPositions.first;
      currentAlignment[pos] = newcomer;
      changes.add(DefensiveChange(
        player: newcomer,
        fromPosition: null,
        toPosition: pos,
      ));
      return pos;
    }

    return null;
  }
}

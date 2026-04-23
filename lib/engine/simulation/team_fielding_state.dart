import '../models/enums.dart';
import '../models/fielder_change.dart';
import '../models/player.dart';
import '../models/team.dart';

/// 1チーム分の野手運用状態（可変）
///
/// - 打順（代打・代走で変わる）
/// - 守備配置（代打に伴う再編、守備固めで変わる）
/// - 控え（ベンチ）の残り
/// - 出場済み選手（一度退いたら再登板不可のルール）
///
/// GameSimulatorが試合全体を通して保持し、打席ごとに更新される。
class TeamFieldingState {
  final Team originalTeam; // 試合開始時のチーム情報（不変参照）

  /// 現在の打順（9人、index=打順）
  List<Player> currentLineup;

  /// 現在の守備配置（全9ポジションを網羅）
  Map<FieldPosition, Player> currentAlignment;

  /// ベンチに残っている控え野手
  final List<Player> bench;

  /// 出場済み選手（スタメン含む）
  final List<Player> usedPlayers;

  TeamFieldingState._({
    required this.originalTeam,
    required this.currentLineup,
    required this.currentAlignment,
    required this.bench,
    required this.usedPlayers,
  });

  /// チーム情報から初期状態を構築
  /// defenseAlignment が指定されていればそれを使い、
  /// 欠けている位置は Team.getFielder のデフォルト配置で埋める
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

  /// 現在の打順に対応する打者を取得
  Player currentBatter(int battingOrder) =>
      currentLineup[battingOrder % 9];

  /// 現在の守備配置を Team スナップショットとして取得
  /// AtBatSimulator など既存のTeamを前提にしたコードに渡す用
  Team asTeamSnapshot() {
    return Team(
      id: originalTeam.id,
      name: originalTeam.name,
      players: List.of(currentLineup),
      bullpen: originalTeam.bullpen,
      bench: List.of(bench),
      defenseAlignment: Map.of(currentAlignment),
    );
  }

  /// 指定選手の現在の守備位置を取得
  FieldPosition? positionOf(Player player) {
    for (final entry in currentAlignment.entries) {
      if (entry.value.id == player.id) return entry.key;
    }
    return null;
  }

  /// 投手が交代した際にアライメントの投手位置も同期
  /// （ゴロの打球方向が投手の場合などに肩の値が古くならないように）
  void setPitcher(Player pitcher) {
    currentAlignment[FieldPosition.pitcher] = pitcher;
  }

  /// 代打を適用する
  /// - outgoing はラインナップから外れ、usedPlayersに残る（再出場不可）
  /// - incoming はラインナップに入り、指定されたポジションで次の守備に付く
  /// - otherMoves に従って既存選手のポジションも移動
  void applyPinchHit({
    required Player outgoing,
    required Player incoming,
    required int battingOrder,
    required FieldPosition? incomingNewPosition,
    required List<FielderPositionChange> otherMoves,
  }) {
    // 打順を更新
    currentLineup[battingOrder] = incoming;

    // 守備配置を更新
    // 1. 先に他の移動を処理（fromを空ける → toに配置）
    //    同時に複数処理するためにコピーを更新
    final newAlignment = Map<FieldPosition, Player>.of(currentAlignment);
    for (final move in otherMoves) {
      // from を空ける（ただし別の移動で埋まる可能性もあるので注意）
      if (newAlignment[move.from]?.id == move.player.id) {
        newAlignment.remove(move.from);
      }
    }
    for (final move in otherMoves) {
      newAlignment[move.to] = move.player;
    }

    // 2. outgoing を取り除き、incoming を incomingNewPosition に配置
    newAlignment.removeWhere((_, p) => p.id == outgoing.id);
    if (incomingNewPosition != null) {
      newAlignment[incomingNewPosition] = incoming;
    }

    currentAlignment = newAlignment;

    // ベンチ・出場記録を更新
    bench.removeWhere((p) => p.id == incoming.id);
    if (!usedPlayers.any((p) => p.id == incoming.id)) {
      usedPlayers.add(incoming);
    }
  }
}

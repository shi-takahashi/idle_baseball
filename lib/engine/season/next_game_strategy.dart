import '../models/enums.dart';
import '../models/player.dart';

/// 次の1試合分の作戦（自チームの打順 + 守備配置の上書き）。
///
/// `SeasonController.setMyStrategy(...)` でセットすると、次の `advanceDay()` で
/// 自チームが試合をした瞬間に適用され、消化後に自動でクリアされる（1試合限り）。
///
/// 投手の打順位置は固定しない。野球ルール上、投手は 1〜9 番のどこに置いても
/// よい（大谷選手のような打撃の良い投手は 1 番投手・3 番投手なども成立する）。
/// 通常は 9 番だが、それは「投手は打撃が弱い」という統計的事実から来る慣習。
///
/// 構築時のバリデーション:
/// - `lineup` は 9 人（重複不可）
/// - `alignment` は 9 ポジションすべて埋まっている
/// - `alignment` の 9 人と `lineup` の 9 人が一致
/// - 投手ポジション (`alignment[pitcher]`) の選手は `isPitcher == true`
/// - 投手ポジション以外の 8 人は野手（`isPitcher == false`）
class NextGameStrategy {
  /// 1〜9 番打者。投手はこの中のどこか 1 か所に含まれる。
  final List<Player> lineup;

  /// 9 ポジションすべての守備配置（投手含む）
  final Map<FieldPosition, Player> alignment;

  NextGameStrategy({
    required this.lineup,
    required this.alignment,
  }) {
    if (lineup.length != 9) {
      throw ArgumentError('lineup は 9 人必要 (実際: ${lineup.length})');
    }
    final lineupIds = lineup.map((p) => p.id).toSet();
    if (lineupIds.length != 9) {
      throw ArgumentError('lineup に重複した選手があります');
    }
    for (final pos in FieldPosition.values) {
      if (!alignment.containsKey(pos)) {
        throw ArgumentError(
            '守備配置に ${pos.displayName} が含まれていません');
      }
    }
    final alignmentIds = alignment.values.map((p) => p.id).toSet();
    if (alignmentIds.length != 9) {
      throw ArgumentError('守備配置の 9 人に重複があります');
    }
    if (alignmentIds.difference(lineupIds).isNotEmpty ||
        lineupIds.difference(alignmentIds).isNotEmpty) {
      throw ArgumentError('打順 9 人と守備 9 人の選手集合が一致していません');
    }

    final pitcherInAlignment = alignment[FieldPosition.pitcher]!;
    if (!pitcherInAlignment.isPitcher) {
      throw ArgumentError(
          '投手ポジションに野手が割り当てられています: ${pitcherInAlignment.name}');
    }
    for (final entry in alignment.entries) {
      if (entry.key == FieldPosition.pitcher) continue;
      if (entry.value.isPitcher) {
        throw ArgumentError(
            '${entry.key.displayName} に投手 ${entry.value.name} が割り当てられています'
            '（投手ポジション以外には野手を置いてください）');
      }
    }
  }

  /// 投手ポジションの選手（先発投手）。打順のどこにいても良い。
  Player get startingPitcher => alignment[FieldPosition.pitcher]!;

  /// 1〜9 番の打順（互換用 alias）
  List<Player> get fullLineup => lineup;
}

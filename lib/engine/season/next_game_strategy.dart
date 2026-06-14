import '../models/enums.dart';
import '../models/player.dart';

/// 次の1試合分の作戦（自チームの編成の上書き）。
///
/// `SeasonController.setMyStrategy(...)` でセットすると、次の `advanceDay()` で
/// 自チームが試合をした瞬間に適用され、消化後に自動でクリアされる（1試合限り）。
///
/// 保持する情報は「当日ベンチ入り26人 + 打順 + 守備配置」:
/// - [lineup] / [alignment]: スタメン9人の打順と守備位置
/// - [activeBench]: 当日ベンチ入りの控え野手（通常8人。代打・代走・守備交代要員）
/// - [activeBullpen]: 当日ベンチ入りの救援投手（通常9人）
///
/// [activeBench] / [activeBullpen] が空のときは、エンジンが自動でベンチ入りを
/// 選定する（旧セーブの互換・フォールバック）。
///
/// 投手の打順位置は固定しない。野球ルール上、投手は 1〜9 番のどこに置いても
/// よい（大谷選手のような打撃の良い投手は 1 番投手・3 番投手なども成立する）。
/// 通常は 9 番だが、それは「投手は打撃が弱い」という統計的事実から来る慣習。
///
/// [useDH]（リーグ DH 採用 + そのチームが DH を使う）の有無で打順の意味が変わる:
/// - **useDH = false**（非DH / 大谷型）: [lineup] 9 人の中に投手が 1 人含まれる。
///   [lineup] の集合 == [alignment] の集合。これが従来の挙動。
/// - **useDH = true**（DH採用）: 投手は打席に立たないので [lineup] 9 人は全員野手
///   （8 守備野手 + DH）。投手は [alignment] の投手ポジションにのみ入り、[lineup]
///   には含まれない。DH は「[lineup] に居るが守備に就かない 1 人」。
///
/// 構築時のバリデーション:
/// - [lineup] は 9 人（重複不可）
/// - [alignment] は 9 ポジションすべて埋まっている（重複不可）
/// - 投手ポジション (`alignment[pitcher]`) の選手は `isPitcher == true`
/// - 投手ポジション以外の 8 人は野手（`isPitcher == false`）
/// - useDH=false: [alignment] の 9 人と [lineup] の 9 人が一致
/// - useDH=true: [lineup] は全員野手、[alignment] の守備 8 野手は [lineup] に含まれ、
///   投手は [lineup] に含まれない。差分 1 人（DH）も野手。
/// - [activeBench]（非空時）は野手のみ・重複なし・[lineup] と重複なし
/// - [activeBullpen]（非空時）は投手のみ・重複なし・[lineup] と重複なし
class NextGameStrategy {
  /// 1〜9 番打者。useDH=false なら投手をどこか 1 か所に含む。useDH=true なら全員野手。
  final List<Player> lineup;

  /// 9 ポジションすべての守備配置（投手含む）
  final Map<FieldPosition, Player> alignment;

  /// リーグ DH 採用 + このチームが DH を使うか。
  /// false は「非DH」と「大谷型（投手が打席に立つ）」の両方を表す
  /// （どちらもシミュレーション上は投手が打つ＝同一）。
  final bool useDH;

  /// 当日ベンチ入りの控え野手（代打・代走・守備交代要員、通常9人）。
  /// 空の場合はエンジンが自動選定する。
  final List<Player> activeBench;

  /// 当日ベンチ入りの救援投手（通常8人）。
  /// 空の場合はエンジンが自動選定する。
  final List<Player> activeBullpen;

  NextGameStrategy({
    required this.lineup,
    required this.alignment,
    this.useDH = false,
    this.activeBench = const [],
    this.activeBullpen = const [],
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

    if (useDH) {
      // DH採用: 打順は全員野手、投手は打順に含まれない。
      for (final p in lineup) {
        if (p.isPitcher) {
          throw ArgumentError(
              'DH採用時の打順に投手 ${p.name} が含まれています'
              '（投手は打席に立たないので守備配置のみに置いてください）');
        }
      }
      if (lineupIds.contains(pitcherInAlignment.id)) {
        throw ArgumentError(
            'DH採用時は投手 ${pitcherInAlignment.name} を打順に入れられません');
      }
      // 守備 8 野手はすべて打順に含まれる。残り 1 人が DH。
      final fielderIds = <String>{
        for (final e in alignment.entries)
          if (e.key != FieldPosition.pitcher) e.value.id,
      };
      if (fielderIds.difference(lineupIds).isNotEmpty) {
        throw ArgumentError('守備に就く野手が打順に含まれていません');
      }
      if (lineupIds.difference(fielderIds).length != 1) {
        throw ArgumentError('DH（打順に居て守備に就かない選手）が特定できません');
      }
    } else {
      // 非DH（大谷型含む）: 打順 9 人と守備 9 人が一致。
      if (alignmentIds.difference(lineupIds).isNotEmpty ||
          lineupIds.difference(alignmentIds).isNotEmpty) {
        throw ArgumentError('打順 9 人と守備 9 人の選手集合が一致していません');
      }
    }

    _validateActiveRoster(
        activeBench, lineupIds, isPitcherList: false, label: 'ベンチ入り控え野手');
    _validateActiveRoster(
        activeBullpen, lineupIds, isPitcherList: true, label: 'ベンチ入り救援');
  }

  /// 当日ベンチ入りリスト（控え野手 / 救援）の整合性を検証する。
  /// 空リストはフォールバック（エンジン自動選定）扱いで素通しする。
  static void _validateActiveRoster(
    List<Player> roster,
    Set<String> lineupIds, {
    required bool isPitcherList,
    required String label,
  }) {
    if (roster.isEmpty) return;
    final ids = roster.map((p) => p.id).toSet();
    if (ids.length != roster.length) {
      throw ArgumentError('$label に重複した選手があります');
    }
    if (ids.intersection(lineupIds).isNotEmpty) {
      throw ArgumentError('$label にスタメンと重複した選手があります');
    }
    for (final p in roster) {
      if (p.isPitcher != isPitcherList) {
        throw ArgumentError(
            '$label に${isPitcherList ? '野手' : '投手'} ${p.name} が含まれています');
      }
    }
  }

  /// 投手ポジションの選手（先発投手）。打順のどこにいても良い。
  Player get startingPitcher => alignment[FieldPosition.pitcher]!;

  /// DH（指名打者）。useDH=true のとき「打順に居て守備に就かない 1 人」を返す。
  /// useDH=false のときは null。
  Player? get designatedHitter {
    if (!useDH) return null;
    final fielderIds = <String>{
      for (final e in alignment.entries)
        if (e.key != FieldPosition.pitcher) e.value.id,
    };
    for (final p in lineup) {
      if (!fielderIds.contains(p.id)) return p;
    }
    return null;
  }

  /// 1〜9 番の打順（互換用 alias）
  List<Player> get fullLineup => lineup;

  /// 打順・守備はそのままで [activeBench] / [activeBullpen] だけ差し替えた複製。
  NextGameStrategy copyWith({
    List<Player>? activeBench,
    List<Player>? activeBullpen,
  }) {
    return NextGameStrategy(
      lineup: lineup,
      alignment: alignment,
      useDH: useDH,
      activeBench: activeBench ?? this.activeBench,
      activeBullpen: activeBullpen ?? this.activeBullpen,
    );
  }

  Map<String, dynamic> toJson() => {
        'lineup': [for (final p in lineup) p.id],
        'alignment': {
          for (final e in alignment.entries) e.key.name: e.value.id,
        },
        'useDH': useDH,
        'activeBench': [for (final p in activeBench) p.id],
        'activeBullpen': [for (final p in activeBullpen) p.id],
      };

  factory NextGameStrategy.fromJson(
    Map<String, dynamic> json,
    Map<String, Player> playerById,
  ) {
    final alignment = <FieldPosition, Player>{};
    for (final e in (json['alignment'] as Map).entries) {
      final pos = FieldPosition.values.firstWhere((p) => p.name == e.key);
      alignment[pos] = playerById[e.value]!;
    }
    List<Player> resolveList(Object? raw) => [
          for (final id in (raw as List? ?? const []))
            if (playerById[id] != null) playerById[id]!,
        ];
    return NextGameStrategy(
      lineup: [
        for (final id in (json['lineup'] as List)) playerById[id]!,
      ],
      alignment: alignment,
      useDH: json['useDH'] as bool? ?? false,
      activeBench: resolveList(json['activeBench']),
      activeBullpen: resolveList(json['activeBullpen']),
    );
  }
}

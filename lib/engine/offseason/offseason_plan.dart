import '../models/models.dart';

/// 新人候補のラッパー。Player に加入経路 (`type`) のメタ情報を付ける。
/// type は確定後の Player には載せていない（運用上は必要ないため）。
class RookieCandidate {
  final Player player;
  final RookieType type;
  const RookieCandidate({required this.player, required this.type});

  String get id => player.id;

  Map<String, dynamic> toJson() => {
        'player': player.toJson(),
        'type': type.name,
      };

  factory RookieCandidate.fromJson(Map<String, dynamic> json) =>
      RookieCandidate(
        player: Player.fromJson(json['player'] as Map<String, dynamic>),
        type: RookieType.values
            .firstWhere((t) => t.name == json['type']),
      );
}

/// オフシーズン中、自チーム向けに提示する候補一覧。
///
/// `SeasonController.prepareOffseason()` が生成して UI に渡す。
/// チームの状態自体はこの時点では変更されず、ユーザーが選択を済ませて
/// `SeasonController.commitOffseason(selection)` を呼ぶと初めて反映される。
class OffseasonPlan {
  /// 引退候補の野手（引退スコア降順）
  final List<Player> retireCandidateFielders;

  /// 引退候補の投手（引退スコア降順）
  final List<Player> retireCandidatePitchers;

  /// 入団候補の新人野手（高卒 / 大卒 / 社会人を各複数名含む）
  final List<RookieCandidate> rookieFielderCandidates;

  /// 入団候補の新人投手（高卒 / 大卒 / 社会人を各複数名含む。
  /// 全員 SP 寄りに生成、commit 時に引退者の SP/RP・pitcherRole を継承）
  final List<RookieCandidate> rookiePitcherCandidates;

  /// 自動推奨で引退させる野手 id（CPU と同じ条件: 26 歳以上 + スコア > 0 の上位）
  final List<String> recommendedRetireFielderIds;

  /// 自動推奨で引退させる投手 id
  final List<String> recommendedRetirePitcherIds;

  /// 自動推奨で入団させる野手 id（推奨引退人数に合わせる、能力上位を選ぶ）
  final List<String> recommendedTakeFielderIds;

  /// 自動推奨で入団させる投手 id
  final List<String> recommendedTakePitcherIds;

  const OffseasonPlan({
    required this.retireCandidateFielders,
    required this.retireCandidatePitchers,
    required this.rookieFielderCandidates,
    required this.rookiePitcherCandidates,
    required this.recommendedRetireFielderIds,
    required this.recommendedRetirePitcherIds,
    required this.recommendedTakeFielderIds,
    required this.recommendedTakePitcherIds,
  });

  /// 新人野手 id → タイプ の逆引き
  RookieType? rookieFielderTypeOf(String id) {
    for (final c in rookieFielderCandidates) {
      if (c.id == id) return c.type;
    }
    return null;
  }

  /// 新人投手 id → タイプ の逆引き
  RookieType? rookiePitcherTypeOf(String id) {
    for (final c in rookiePitcherCandidates) {
      if (c.id == id) return c.type;
    }
    return null;
  }

  /// 永続化用。引退候補は id のみ保存（既存選手は controller の playerById で復元）、
  /// 新人候補は Player を丸ごと保存する（commit までは controller に登録されていないため）。
  Map<String, dynamic> toJson() => {
        'retireFielderIds':
            [for (final p in retireCandidateFielders) p.id],
        'retirePitcherIds':
            [for (final p in retireCandidatePitchers) p.id],
        'rookieFielders':
            [for (final c in rookieFielderCandidates) c.toJson()],
        'rookiePitchers':
            [for (final c in rookiePitcherCandidates) c.toJson()],
        'recommendedRetireFielderIds':
            List.of(recommendedRetireFielderIds),
        'recommendedRetirePitcherIds':
            List.of(recommendedRetirePitcherIds),
        'recommendedTakeFielderIds':
            List.of(recommendedTakeFielderIds),
        'recommendedTakePitcherIds':
            List.of(recommendedTakePitcherIds),
      };

  /// JSON からの復元。引退候補の Player は [playerById] で解決する
  /// （既存選手なので controller に登録されている前提）。
  /// 新人候補は JSON 内に Player を丸ごと持っているのでそのまま復元。
  factory OffseasonPlan.fromJson(
    Map<String, dynamic> json,
    Map<String, Player> playerById,
  ) {
    List<Player> resolvePlayers(String key) {
      final ids = (json[key] as List).cast<String>();
      return [
        for (final id in ids)
          if (playerById[id] != null) playerById[id]!,
      ];
    }

    List<RookieCandidate> resolveRookies(String key) => [
          for (final j in (json[key] as List))
            RookieCandidate.fromJson(j as Map<String, dynamic>),
        ];

    return OffseasonPlan(
      retireCandidateFielders: resolvePlayers('retireFielderIds'),
      retireCandidatePitchers: resolvePlayers('retirePitcherIds'),
      rookieFielderCandidates: resolveRookies('rookieFielders'),
      rookiePitcherCandidates: resolveRookies('rookiePitchers'),
      recommendedRetireFielderIds: (json['recommendedRetireFielderIds']
              as List)
          .cast<String>(),
      recommendedRetirePitcherIds: (json['recommendedRetirePitcherIds']
              as List)
          .cast<String>(),
      recommendedTakeFielderIds:
          (json['recommendedTakeFielderIds'] as List).cast<String>(),
      recommendedTakePitcherIds:
          (json['recommendedTakePitcherIds'] as List).cast<String>(),
    );
  }
}

/// オフシーズンの自チーム編成についてのユーザー選択。
///
/// 引退者と新人は順序ペア:
/// `retireFielderIds[i]` を引退させ、`takeFielderIds[i]` を加入させる。
/// それぞれ同じ長さである必要がある（投手も同様）。
class OffseasonSelection {
  final List<String> retireFielderIds;
  final List<String> retirePitcherIds;
  final List<String> takeFielderIds;
  final List<String> takePitcherIds;

  const OffseasonSelection({
    required this.retireFielderIds,
    required this.retirePitcherIds,
    required this.takeFielderIds,
    required this.takePitcherIds,
  });

  /// 何も入れ替えない選択（引退・加入 0 件）
  static const empty = OffseasonSelection(
    retireFielderIds: [],
    retirePitcherIds: [],
    takeFielderIds: [],
    takePitcherIds: [],
  );

  /// プランから推奨選択を作る
  factory OffseasonSelection.recommended(OffseasonPlan plan) {
    return OffseasonSelection(
      retireFielderIds: List.of(plan.recommendedRetireFielderIds),
      retirePitcherIds: List.of(plan.recommendedRetirePitcherIds),
      takeFielderIds: List.of(plan.recommendedTakeFielderIds),
      takePitcherIds: List.of(plan.recommendedTakePitcherIds),
    );
  }

  /// バリデーション: 引退と新人の数が一致しているか。
  /// 一致しないと commitOffseason 内で例外になる。
  bool get isValid =>
      retireFielderIds.length == takeFielderIds.length &&
      retirePitcherIds.length == takePitcherIds.length;
}

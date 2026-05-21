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

  /// 強制離脱が発動した自チーム外国人（UI で `[離脱]` 表示用）。
  /// この id の選手は commit 時に必ずチームから除外される。
  final List<Player> foreignDepartures;

  /// 新外国人候補（投手 2 + 野手 2 が基本）。能力非表示・守備位置 + 年齢 + 苗字のみ
  /// UI に出して「賭け」体験を演出する。commit で `foreignAcquireIds` に含まれた
  /// 候補だけがチームに加わる。
  final List<Player> foreignCandidates;

  const OffseasonPlan({
    required this.retireCandidateFielders,
    required this.retireCandidatePitchers,
    required this.rookieFielderCandidates,
    required this.rookiePitcherCandidates,
    required this.recommendedRetireFielderIds,
    required this.recommendedRetirePitcherIds,
    required this.recommendedTakeFielderIds,
    required this.recommendedTakePitcherIds,
    this.foreignDepartures = const [],
    this.foreignCandidates = const [],
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

  /// 永続化用。引退候補・外国人離脱は id のみ保存（既存選手は controller の
  /// playerById で復元）、新人候補・外国人候補は Player を丸ごと保存する
  /// （commit までは controller に登録されていないため）。
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
        'foreignDepartureIds':
            [for (final p in foreignDepartures) p.id],
        'foreignCandidates':
            [for (final p in foreignCandidates) p.toJson()],
      };

  /// JSON からの復元。引退候補の Player は [playerById] で解決する
  /// （既存選手なので controller に登録されている前提）。
  /// 新人候補は JSON 内に Player を丸ごと持っているのでそのまま復元。
  factory OffseasonPlan.fromJson(
    Map<String, dynamic> json,
    Map<String, Player> playerById,
  ) {
    List<Player> resolvePlayers(String key) {
      // 古いセーブとの後方互換: 新しく追加されたキー（foreignDepartureIds 等）が
      // 存在しない可能性があるので null フォールバックを入れる。
      final ids = (json[key] as List? ?? const []).cast<String>();
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
      foreignDepartures: resolvePlayers('foreignDepartureIds'),
      foreignCandidates: [
        for (final j in (json['foreignCandidates'] as List? ?? const []))
          Player.fromJson(j as Map<String, dynamic>),
      ],
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

  /// ユーザーが任意でカットする外国人選手 id（強制離脱とは別）。
  /// strong commit 時にチームから外れる。投手も野手も同じリストで持つ
  /// （実装側で `Player.isPitcher` で振り分ける）。
  final List<String> foreignReleaseIds;

  /// 候補から獲得する外国人選手 id。strong commit 時にチームに加わる。
  final List<String> foreignAcquireIds;

  const OffseasonSelection({
    required this.retireFielderIds,
    required this.retirePitcherIds,
    required this.takeFielderIds,
    required this.takePitcherIds,
    this.foreignReleaseIds = const [],
    this.foreignAcquireIds = const [],
  });

  /// 何も入れ替えない選択（引退・加入 0 件、外国人も全員継続）
  static const empty = OffseasonSelection(
    retireFielderIds: [],
    retirePitcherIds: [],
    takeFielderIds: [],
    takePitcherIds: [],
  );

  /// プランから推奨選択を作る。
  /// 外国人入替の推奨はシンプル: 強制離脱した枠だけ候補から自動補充（投手枠は
  /// 候補の投手から、野手枠は候補の野手から、それぞれ先頭を採用）。
  factory OffseasonSelection.recommended(OffseasonPlan plan) {
    final acquire = <String>[];
    final hasDepartingPitcher = plan.foreignDepartures.any((p) => p.isPitcher);
    final hasDepartingFielder =
        plan.foreignDepartures.any((p) => !p.isPitcher);
    if (hasDepartingPitcher) {
      final c = plan.foreignCandidates.firstWhere(
        (p) => p.isPitcher,
        orElse: () => plan.foreignCandidates.isEmpty
            ? Player(id: '', name: '', number: 0, age: 0)
            : plan.foreignCandidates.first,
      );
      if (c.id.isNotEmpty) acquire.add(c.id);
    }
    if (hasDepartingFielder) {
      final c = plan.foreignCandidates.firstWhere(
        (p) => !p.isPitcher,
        orElse: () => plan.foreignCandidates.isEmpty
            ? Player(id: '', name: '', number: 0, age: 0)
            : plan.foreignCandidates.first,
      );
      if (c.id.isNotEmpty) acquire.add(c.id);
    }
    return OffseasonSelection(
      retireFielderIds: List.of(plan.recommendedRetireFielderIds),
      retirePitcherIds: List.of(plan.recommendedRetirePitcherIds),
      takeFielderIds: List.of(plan.recommendedTakeFielderIds),
      takePitcherIds: List.of(plan.recommendedTakePitcherIds),
      foreignAcquireIds: acquire,
    );
  }

  /// バリデーション: 引退と新人の数が一致しているか、外国人の解放と獲得の枠数が
  /// タイプ別（投手/野手）で一致するか。一致しないと commitOffseason で例外になる。
  ///
  /// 外国人バリデーションは [validateForeign] で plan と照らし合わせて行う必要が
  /// あるため、ここでは引退・新人の整合だけチェック（基本構造の妥当性のみ）。
  bool get isValid =>
      retireFielderIds.length == takeFielderIds.length &&
      retirePitcherIds.length == takePitcherIds.length;

  /// 外国人入替の事前バリデーション。
  /// 詳細な「枠数が合っているか」は [TeamRebuilder.applyUserSelection] 内で
  /// チームの現状（空席含む）と照らし合わせて検証する。ここでは「候補に存在
  /// しない id を獲得しようとしていないか」など、Plan 範囲内で可能な妥当性
  /// チェックだけ行う。
  String? validateForeign(OffseasonPlan plan) {
    final candidateIds = {for (final c in plan.foreignCandidates) c.id};
    for (final id in foreignAcquireIds) {
      if (!candidateIds.contains(id)) {
        return '外国人候補に存在しない id: $id';
      }
    }
    return null;
  }
}

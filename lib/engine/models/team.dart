import 'player.dart';
import 'enums.dart';

/// チーム
class Team {
  final String id;
  // 名前・略称・チームカラーは TeamEditScreen から編集できるよう非final にしている。
  // SeasonController.updateTeam が in-place で書き換えると、
  // 同じ Team を参照しているスケジュール・統計すべてに反映される。
  String name;
  // スコアボード等の狭い表示領域で使う英字1〜2文字の略称（例: フェニックス → "P"）
  String shortName;
  // 9人。打順順に並ぶ。投手は通常 players[8]（9番）に置くが、
  // 大谷選手のように打撃が強い投手は他の打順にもできる
  // （野球ルール上、投手の打順位置に制約はない）。
  // 投手の特定は `players` を走査して `isPitcher == true` の選手で行うこと。
  final List<Player> players;

  // 先発ローテーション（6人想定）
  // 試合ごとに 1 人がローテから選出されて `players` に組み込まれる。
  // 通常は 9 番（players[8]）に入るが、ユーザーの作戦指定で他の打順にも置ける。
  final List<Player> startingRotation;

  // 救援投手（8人想定: 抑え1 + セットアッパー1 + 中継ぎ2 + ワンポイント1 + ロング1 + 敗戦処理2）
  // 各 Player に reliefRole が割り当てられている。
  // 試合用に SeasonController が疲労した投手を除外して並び替えたリストを渡す。
  final List<Player> bullpen;

  // 控え野手（代打・代走・守備固め要員、8人想定）
  final List<Player> bench;

  // 守備配置（FieldPosition -> Player）
  // 誰がどのポジションを守っているか
  // null の場合はデフォルト配置を使用
  final Map<FieldPosition, Player>? defenseAlignment;

  // チームカラー（ARGB int 値）
  // UI 層で Color に変換して、バナーやアイコンの色付けに使う。
  // engine 層を Flutter 非依存に保つため int で保持。
  int primaryColorValue;

  Team({
    required this.id,
    required this.name,
    this.shortName = '',
    required this.players,
    this.startingRotation = const [],
    this.bullpen = const [],
    this.bench = const [],
    this.defenseAlignment,
    this.primaryColorValue = 0xFF9E9E9E, // デフォルト: グレー
  });

  /// 主に「その日の先発を差し替える」用途で使う複製ヘルパ
  Team copyWith({
    List<Player>? players,
    List<Player>? startingRotation,
    List<Player>? bullpen,
    List<Player>? bench,
    Map<FieldPosition, Player>? defenseAlignment,
    int? primaryColorValue,
  }) {
    return Team(
      id: id,
      name: name,
      shortName: shortName,
      players: players ?? this.players,
      startingRotation: startingRotation ?? this.startingRotation,
      bullpen: bullpen ?? this.bullpen,
      bench: bench ?? this.bench,
      defenseAlignment: defenseAlignment ?? this.defenseAlignment,
      primaryColorValue: primaryColorValue ?? this.primaryColorValue,
    );
  }

  // ---- ブルペン内のロール別 getter ----
  // 試合用 Team の bullpen は SeasonController で疲労していない投手のみ含むため、
  // ここで「fresh で利用可能なロール担当」を引ける。
  Player? _firstWithRole(ReliefRole role) {
    for (final p in bullpen) {
      if (p.reliefRole == role) return p;
    }
    return null;
  }

  /// 抑え投手（fresh で当日使えれば）
  Player? get closer => _firstWithRole(ReliefRole.closer);

  /// セットアッパー
  Player? get setupPitcher => _firstWithRole(ReliefRole.setup);

  /// 中継ぎ（勝ちパ）
  List<Player> get middleRelievers =>
      [for (final p in bullpen) if (p.reliefRole == ReliefRole.middle) p];

  /// ワンポイント（左投手）
  Player? get situationalLefty => _firstWithRole(ReliefRole.situational);

  /// ロングリリーフ
  Player? get longReliever => _firstWithRole(ReliefRole.long);

  /// 敗戦処理
  List<Player> get mopUpRelievers =>
      [for (final p in bullpen) if (p.reliefRole == ReliefRole.mopUp) p];

  /// 打順からプレイヤーを取得（0-indexed）
  Player getBatter(int battingOrder) {
    return players[battingOrder % 9];
  }

  /// 先発投手（`players` 内で `isPitcher == true` の選手）
  ///
  /// 投手は通常 9 番（players[8]）だが、大谷型の選手のように他の打順にも置ける。
  /// そのため index 固定で取らず、`players` を走査して isPitcher で特定する。
  /// players に投手が含まれていない異常系では index 8 にフォールバックする。
  Player get pitcher {
    for (final p in players) {
      if (p.isPitcher) return p;
    }
    return players[8];
  }

  /// 先発投手の打順 index（0-indexed）。投手がいない場合は 8。
  int get pitcherBattingIndex {
    for (int i = 0; i < players.length; i++) {
      if (players[i].isPitcher) return i;
    }
    return 8;
  }

  /// 指定ポジションの守備を担当する選手を取得
  /// defenseAlignment が設定されていない場合はデフォルト配置を使用
  Player? getFielder(FieldPosition position) {
    // 明示的な守備配置がある場合はそれを使用
    if (defenseAlignment != null) {
      return defenseAlignment![position];
    }

    // デフォルト配置（打順1〜8番が野手、9番が投手 を想定）
    // 投手が打順の途中にいる場合（例: 1番投手）は alignment を明示することを推奨。
    // ここのフォールバックは index ベースなので投手位置を変えると齟齬が出る。
    switch (position) {
      case FieldPosition.catcher:
        return players[0];
      case FieldPosition.first:
        return players[1];
      case FieldPosition.second:
        return players[2];
      case FieldPosition.third:
        return players[3];
      case FieldPosition.shortstop:
        return players[4];
      case FieldPosition.left:
        return players[5];
      case FieldPosition.center:
        return players[6];
      case FieldPosition.right:
        return players[7];
      case FieldPosition.pitcher:
        return pitcher;
    }
  }

  /// 指定ポジションの守備力を取得
  /// 守備者がいない場合や投手方向の場合は null
  int? getFieldingAt(FieldPosition fieldPosition) {
    final defensePos = fieldPosition.defensePosition;
    if (defensePos == null) return null; // 投手方向

    final fielder = getFielder(fieldPosition);
    if (fielder == null) return null;

    return fielder.getFielding(defensePos);
  }

  // ---- 永続化 ----
  // Player は id のみ保存。fromJson 時に PlayerRegistry から resolve する。

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'shortName': shortName,
      'primaryColorValue': primaryColorValue,
      'players': [for (final p in players) p.id],
      'startingRotation': [for (final p in startingRotation) p.id],
      'bullpen': [for (final p in bullpen) p.id],
      'bench': [for (final p in bench) p.id],
      if (defenseAlignment != null)
        'defenseAlignment': {
          for (final e in defenseAlignment!.entries) e.key.name: e.value.id,
        },
    };
  }

  factory Team.fromJson(
    Map<String, dynamic> json,
    Map<String, Player> playerById,
  ) {
    Player resolve(Object? v) => playerById[v as String]!;

    Map<FieldPosition, Player>? alignment;
    final a = json['defenseAlignment'];
    if (a is Map) {
      alignment = {};
      for (final e in a.entries) {
        final pos =
            FieldPosition.values.firstWhere((p) => p.name == e.key);
        alignment[pos] = resolve(e.value);
      }
    }

    return Team(
      id: json['id'] as String,
      name: json['name'] as String,
      shortName: (json['shortName'] as String?) ?? '',
      primaryColorValue: (json['primaryColorValue'] as int?) ?? 0xFF9E9E9E,
      players: [for (final id in (json['players'] as List)) resolve(id)],
      startingRotation: [
        for (final id in (json['startingRotation'] as List? ?? []))
          resolve(id),
      ],
      bullpen: [
        for (final id in (json['bullpen'] as List? ?? [])) resolve(id),
      ],
      bench: [for (final id in (json['bench'] as List? ?? [])) resolve(id)],
      defenseAlignment: alignment,
    );
  }

  @override
  String toString() => name;
}

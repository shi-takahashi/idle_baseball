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
  // 各 Player に pitcherRole が割り当てられている。
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

  /// この（試合用）チームが DH 制で編成されているか。
  ///
  /// 試合用 Team でのみ意味を持つ（シーズン保持 Team は常に false）。
  /// true のとき投手は打順 [players] に含まれず、守備の投手は
  /// [defenseAlignment] の投手ポジションにのみ入る。打席に立つ DH は
  /// 「打順に居て守備配置に居ない選手」。
  ///
  /// 大谷型の二刀流選手を「登板しない日に DH で起用」するケースでは、
  /// DH スロットに投手登録の選手が入ることもある。そのため「打順に投手が
  /// 居ない」では DH 判定できず、このフラグで明示する。永続化はしない
  /// （試合用 Team は保存せず、NextGameStrategy.useDH から毎回再構築する）。
  final bool usesDH;

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
    this.usesDH = false,
  });

  /// 主に「その日の先発を差し替える」用途で使う複製ヘルパ
  Team copyWith({
    List<Player>? players,
    List<Player>? startingRotation,
    List<Player>? bullpen,
    List<Player>? bench,
    Map<FieldPosition, Player>? defenseAlignment,
    int? primaryColorValue,
    bool? usesDH,
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
      usesDH: usesDH ?? this.usesDH,
    );
  }

  /// 40人ロスター全体（重複排除）。
  ///
  /// シーズン保持用 Team では構成が
  ///   主力野手8（players[0..7]）+ 先発6 + 救援12 + 控え野手14 = 40
  /// となっている。players[8] は startingRotation のいずれかと同一インスタンス
  /// なので、players からは先頭 8 人（野手）のみ取って重複を避ける。
  ///
  /// 当日 26 人に絞り込んだ試合用 Team で呼ぶ用途は想定していない
  /// （その場合 players は打順 9 人なので take(8) の前提が崩れる）。
  List<Player> get roster => [
        ...players.take(8),
        ...startingRotation,
        ...bullpen,
        ...bench,
      ];

  // ---- ブルペン内のロール別 getter ----
  // 試合用 Team の bullpen は SeasonController で疲労していない投手のみ含むため、
  // ここで「fresh で利用可能なロール担当」を引ける。
  Player? _firstWithRole(PitcherRole role) {
    for (final p in bullpen) {
      if (p.pitcherRole == role) return p;
    }
    return null;
  }

  /// 抑え投手（fresh で当日使えれば）
  Player? get closer => _firstWithRole(PitcherRole.closer);

  /// セットアッパー
  Player? get setupPitcher => _firstWithRole(PitcherRole.setup);

  /// 中継ぎ（勝ちパ）
  List<Player> get middleRelievers =>
      [for (final p in bullpen) if (p.pitcherRole == PitcherRole.middle) p];

  /// ワンポイント（左投手）
  Player? get situationalLefty => _firstWithRole(PitcherRole.situational);

  /// ロングリリーフ
  Player? get longReliever => _firstWithRole(PitcherRole.long);

  /// 敗戦処理
  List<Player> get mopUpRelievers =>
      [for (final p in bullpen) if (p.pitcherRole == PitcherRole.mopUp) p];

  /// 打順からプレイヤーを取得（0-indexed）
  Player getBatter(int battingOrder) {
    return players[battingOrder % 9];
  }

  /// 先発投手。
  ///
  /// 通常（DH非採用）は投手も打順に入るので `players` を走査して
  /// `isPitcher == true` の選手を特定する（大谷型で 9 番以外でも拾える）。
  /// DH採用時は投手が打順（`players`）に含まれないため、まず守備配置
  /// `defenseAlignment[FieldPosition.pitcher]` を見る。試合用 Team は
  /// 必ず守備配置が埋まっているのでここで正しい投手が引ける。
  /// どちらでも引けない異常系では index 8 にフォールバックする。
  Player get pitcher {
    final aligned = defenseAlignment?[FieldPosition.pitcher];
    if (aligned != null) return aligned;
    for (final p in players) {
      if (p.isPitcher) return p;
    }
    return players[8];
  }

  /// 先発投手の打順 index（0-indexed）。
  ///
  /// DH採用時は投手が打順に居ないため -1 を返す（＝「投手は打席に立たない」の合図）。
  /// 非DHでは投手の打順スロットを返す（通常 8 = 9 番）。
  int get pitcherBattingIndex {
    for (int i = 0; i < players.length; i++) {
      if (players[i].isPitcher) return i;
    }
    return -1;
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

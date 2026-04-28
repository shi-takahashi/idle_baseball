import 'player.dart';
import 'enums.dart';

/// チーム
class Team {
  final String id;
  final String name;
  // スコアボード等の狭い表示領域で使う英字1〜2文字の略称（例: フェニックス → "P"）
  final String shortName;
  final List<Player> players; // 9人（players[0]=今日の先発、players[1..8]=スタメン野手）

  // 先発ローテーション（6人想定）
  // players[0] はこのリストの中から日々選出される。
  // 既存テストコード等の互換のため省略可能（空なら従来どおり players[0] が固定の先発）
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
  final int primaryColorValue;

  const Team({
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

  /// 先発投手
  Player get pitcher => players[0];

  /// 指定ポジションの守備を担当する選手を取得
  /// defenseAlignment が設定されていない場合はデフォルト配置を使用
  Player? getFielder(FieldPosition position) {
    // 明示的な守備配置がある場合はそれを使用
    if (defenseAlignment != null) {
      return defenseAlignment![position];
    }

    // デフォルト配置（打順でポジションを割り当て）
    // 0: 投手, 1: 捕手, 2: 一塁, 3: 二塁, 4: 三塁, 5: 遊撃, 6: 左翼, 7: 中堅, 8: 右翼
    switch (position) {
      case FieldPosition.pitcher:
        return players[0];
      case FieldPosition.catcher:
        return players[1];
      case FieldPosition.first:
        return players[2];
      case FieldPosition.second:
        return players[3];
      case FieldPosition.third:
        return players[4];
      case FieldPosition.shortstop:
        return players[5];
      case FieldPosition.left:
        return players[6];
      case FieldPosition.center:
        return players[7];
      case FieldPosition.right:
        return players[8];
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

  @override
  String toString() => name;
}

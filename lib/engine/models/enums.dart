/// 利き手・打席
/// - right: 右利き（投手）、右打ち（打者）
/// - left: 左利き（投手）、左打ち（打者）
/// - both: 両打ち（打者のみ有効）。投手の利き手によって打席が決まる
enum Handedness {
  right,
  left,
  both,
}

/// 救援投手のロール
/// - closer: 抑え。基本9回限定でセーブ機会担当
/// - setup: セットアッパー。8回でリードを守る
/// - middle: 中継ぎ（勝ちパ）。6〜7回のリード/同点で投げる
/// - situational: ワンポイント。左打者へのマッチアップ用（左投手）
/// - long: ロングリリーフ。先発早期降板や延長戦で長いイニングを投げる
/// - mopUp: 敗戦処理。負け試合・大差での消耗を引き受ける
enum ReliefRole {
  closer,
  setup,
  middle,
  situational,
  long,
  mopUp,
}

extension ReliefRoleExtension on ReliefRole {
  String get displayName {
    switch (this) {
      case ReliefRole.closer:
        return '抑え';
      case ReliefRole.setup:
        return 'セットアッパー';
      case ReliefRole.middle:
        return '中継ぎ';
      case ReliefRole.situational:
        return 'ワンポイント';
      case ReliefRole.long:
        return 'ロング';
      case ReliefRole.mopUp:
        return '敗戦処理';
    }
  }
}

extension HandednessExtension on Handedness {
  String get displayName {
    switch (this) {
      case Handedness.right:
        return '右';
      case Handedness.left:
        return '左';
      case Handedness.both:
        return '両';
    }
  }
}

/// 1球の結果タイプ
enum PitchResultType {
  ball, // ボール
  strikeLooking, // 見逃しストライク
  strikeSwinging, // 空振りストライク
  foul, // ファウル
  inPlay, // インプレー（打球が飛んだ）
}

extension PitchResultTypeExtension on PitchResultType {
  /// 表示用の日本語名
  String get displayName {
    switch (this) {
      case PitchResultType.ball:
        return 'ボール';
      case PitchResultType.strikeLooking:
        return '見逃し';
      case PitchResultType.strikeSwinging:
        return '空振り';
      case PitchResultType.foul:
        return 'ファウル';
      case PitchResultType.inPlay:
        return '打球';
    }
  }

  /// 短い表示名（省スペース用）
  String get shortName {
    switch (this) {
      case PitchResultType.ball:
        return 'B';
      case PitchResultType.strikeLooking:
        return 'S見';
      case PitchResultType.strikeSwinging:
        return 'S空';
      case PitchResultType.foul:
        return 'F';
      case PitchResultType.inPlay:
        return '打';
    }
  }
}

/// 打球の種類
enum BattedBallType {
  groundBall, // ゴロ
  flyBall, // フライ
  lineDrive, // ライナー
}

/// 球種
enum PitchType {
  fastball, // ストレート
  slider, // スライダー
  curveball, // カーブ
  splitter, // スプリット（フォーク系）
  changeup, // チェンジアップ
}

extension PitchTypeExtension on PitchType {
  /// 表示用の日本語名
  String get displayName {
    switch (this) {
      case PitchType.fastball:
        return 'ストレート';
      case PitchType.slider:
        return 'スライダー';
      case PitchType.curveball:
        return 'カーブ';
      case PitchType.splitter:
        return 'スプリット';
      case PitchType.changeup:
        return 'チェンジアップ';
    }
  }

  /// 短い表示名（省スペース用）
  String get shortName {
    switch (this) {
      case PitchType.fastball:
        return 'スト';
      case PitchType.slider:
        return 'スラ';
      case PitchType.curveball:
        return 'カー';
      case PitchType.splitter:
        return 'スプ';
      case PitchType.changeup:
        return 'チェ';
    }
  }
}

/// 打席の結果タイプ
enum AtBatResultType {
  strikeout, // 三振
  walk, // 四球
  single, // 単打
  infieldHit, // 内野安打（単打の一種）
  double_, // 二塁打（doubleは予約語なのでアンダースコア）
  triple, // 三塁打
  homeRun, // 本塁打
  groundOut, // ゴロアウト
  doublePlay, // 併殺打（ゴロでダブルプレー）
  flyOut, // フライアウト
  lineOut, // ライナーアウト
  reachedOnError, // エラー出塁
  sacrificeBunt, // 送りバント成功（打者OUT・走者進塁、打数にカウントしない）
  fieldersChoice, // 野選（バント失敗で先頭走者OUT・打者は1塁セーフ）
}

/// 塁
enum Base { first, second, third, home }

/// 守備位置 / 打球方向（9方向）
enum FieldPosition {
  pitcher, // 投手
  catcher, // 捕手
  first, // 一塁手
  second, // 二塁手
  third, // 三塁手
  shortstop, // 遊撃手
  left, // 左翼手
  center, // 中堅手
  right, // 右翼手
}

/// 守備能力の種類（6種類 + 投手向けに飛んだ場合は一律扱い）
/// 外野は左翼・中堅・右翼をまとめて1つ
enum DefensePosition {
  catcher, // 捕手
  first, // 一塁手
  second, // 二塁手
  third, // 三塁手
  shortstop, // 遊撃手
  outfield, // 外野手（左翼・中堅・右翼共通）
}

extension DefensePositionExtension on DefensePosition {
  /// 表示用の日本語名
  String get displayName {
    switch (this) {
      case DefensePosition.catcher:
        return '捕手';
      case DefensePosition.first:
        return '一塁';
      case DefensePosition.second:
        return '二塁';
      case DefensePosition.third:
        return '三塁';
      case DefensePosition.shortstop:
        return '遊撃';
      case DefensePosition.outfield:
        return '外野';
    }
  }

  /// 短い表示名
  String get shortName {
    switch (this) {
      case DefensePosition.catcher:
        return '捕';
      case DefensePosition.first:
        return '一';
      case DefensePosition.second:
        return '二';
      case DefensePosition.third:
        return '三';
      case DefensePosition.shortstop:
        return '遊';
      case DefensePosition.outfield:
        return '外';
    }
  }
}

extension FieldPositionExtension on FieldPosition {
  /// 表示用の日本語名
  String get displayName {
    switch (this) {
      case FieldPosition.pitcher:
        return '投手';
      case FieldPosition.catcher:
        return '捕手';
      case FieldPosition.first:
        return '一塁';
      case FieldPosition.second:
        return '二塁';
      case FieldPosition.third:
        return '三塁';
      case FieldPosition.shortstop:
        return '遊撃';
      case FieldPosition.left:
        return '左翼';
      case FieldPosition.center:
        return '中堅';
      case FieldPosition.right:
        return '右翼';
    }
  }

  /// 短い表示名
  String get shortName {
    switch (this) {
      case FieldPosition.pitcher:
        return '投';
      case FieldPosition.catcher:
        return '捕';
      case FieldPosition.first:
        return '一';
      case FieldPosition.second:
        return '二';
      case FieldPosition.third:
        return '三';
      case FieldPosition.shortstop:
        return '遊';
      case FieldPosition.left:
        return '左';
      case FieldPosition.center:
        return '中';
      case FieldPosition.right:
        return '右';
    }
  }

  /// 内野かどうか
  bool get isInfield {
    return this == FieldPosition.pitcher ||
        this == FieldPosition.catcher ||
        this == FieldPosition.first ||
        this == FieldPosition.second ||
        this == FieldPosition.third ||
        this == FieldPosition.shortstop;
  }

  /// 外野かどうか
  bool get isOutfield {
    return this == FieldPosition.left || this == FieldPosition.center || this == FieldPosition.right;
  }

  /// 対応する守備能力の種類を取得
  /// 投手方向は null（一律扱い）
  DefensePosition? get defensePosition {
    switch (this) {
      case FieldPosition.pitcher:
        return null; // 投手方向は守備力考慮しない
      case FieldPosition.catcher:
        return DefensePosition.catcher;
      case FieldPosition.first:
        return DefensePosition.first;
      case FieldPosition.second:
        return DefensePosition.second;
      case FieldPosition.third:
        return DefensePosition.third;
      case FieldPosition.shortstop:
        return DefensePosition.shortstop;
      case FieldPosition.left:
      case FieldPosition.center:
      case FieldPosition.right:
        return DefensePosition.outfield;
    }
  }
}

extension AtBatResultTypeExtension on AtBatResultType {
  /// ヒットかどうか
  bool get isHit {
    return this == AtBatResultType.single ||
        this == AtBatResultType.infieldHit ||
        this == AtBatResultType.double_ ||
        this == AtBatResultType.triple ||
        this == AtBatResultType.homeRun;
  }

  /// 単打かどうか（内野安打を含む）
  bool get isSingle {
    return this == AtBatResultType.single || this == AtBatResultType.infieldHit;
  }

  /// アウトかどうか
  bool get isOut {
    return this == AtBatResultType.strikeout ||
        this == AtBatResultType.groundOut ||
        this == AtBatResultType.doublePlay ||
        this == AtBatResultType.flyOut ||
        this == AtBatResultType.lineOut ||
        this == AtBatResultType.sacrificeBunt;
  }

  /// 併殺打かどうか
  bool get isDoublePlay {
    return this == AtBatResultType.doublePlay;
  }

  /// エラー出塁かどうか
  bool get isError {
    return this == AtBatResultType.reachedOnError;
  }

  /// 送りバント成功かどうか（打数にカウントせず犠打として記録）
  bool get isSacrificeBunt {
    return this == AtBatResultType.sacrificeBunt;
  }

  /// 野選（FC: 走者OUT・打者SAFE）かどうか
  bool get isFieldersChoice {
    return this == AtBatResultType.fieldersChoice;
  }

  /// 打者が出塁するかどうか（安打・四球・エラー出塁・野選）
  bool get isOnBase {
    return isHit ||
        this == AtBatResultType.walk ||
        this == AtBatResultType.reachedOnError ||
        this == AtBatResultType.fieldersChoice;
  }

  /// 表示用の文字列
  String get displayName {
    switch (this) {
      case AtBatResultType.strikeout:
        return '三振';
      case AtBatResultType.walk:
        return '四球';
      case AtBatResultType.single:
        return '単打';
      case AtBatResultType.infieldHit:
        return '内野安打';
      case AtBatResultType.double_:
        return '二塁打';
      case AtBatResultType.triple:
        return '三塁打';
      case AtBatResultType.homeRun:
        return '本塁打';
      case AtBatResultType.groundOut:
        return 'ゴロ';
      case AtBatResultType.doublePlay:
        return '併殺打';
      case AtBatResultType.flyOut:
        return 'フライ';
      case AtBatResultType.lineOut:
        return 'ライナー';
      case AtBatResultType.reachedOnError:
        return 'エラー出塁';
      case AtBatResultType.sacrificeBunt:
        return '送りバント';
      case AtBatResultType.fieldersChoice:
        return '野選';
    }
  }
}

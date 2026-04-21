/// 1球の結果タイプ
enum PitchResultType {
  ball,           // ボール
  strikeLooking,  // 見逃しストライク
  strikeSwinging, // 空振りストライク
  foul,           // ファウル
  inPlay,         // インプレー（打球が飛んだ）
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
  groundBall,  // ゴロ
  flyBall,     // フライ
  lineDrive,   // ライナー
}

/// 打席の結果タイプ
enum AtBatResultType {
  strikeout,    // 三振
  walk,         // 四球
  single,       // 単打
  double_,      // 二塁打（doubleは予約語なのでアンダースコア）
  triple,       // 三塁打
  homeRun,      // 本塁打
  groundOut,    // ゴロアウト
  flyOut,       // フライアウト
  lineOut,      // ライナーアウト
}

/// 塁
enum Base {
  first,
  second,
  third,
  home,
}

/// 守備位置 / 打球方向
enum FieldPosition {
  pitcher,    // 投手
  catcher,    // 捕手
  first,      // 一塁手
  second,     // 二塁手
  third,      // 三塁手
  shortstop,  // 遊撃手
  left,       // 左翼手
  center,     // 中堅手
  right,      // 右翼手
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
    return this == FieldPosition.left ||
        this == FieldPosition.center ||
        this == FieldPosition.right;
  }
}

extension AtBatResultTypeExtension on AtBatResultType {
  /// ヒットかどうか
  bool get isHit {
    return this == AtBatResultType.single ||
        this == AtBatResultType.double_ ||
        this == AtBatResultType.triple ||
        this == AtBatResultType.homeRun;
  }

  /// アウトかどうか
  bool get isOut {
    return this == AtBatResultType.strikeout ||
        this == AtBatResultType.groundOut ||
        this == AtBatResultType.flyOut ||
        this == AtBatResultType.lineOut;
  }

  /// 打者が出塁するかどうか
  bool get isOnBase {
    return isHit || this == AtBatResultType.walk;
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
      case AtBatResultType.double_:
        return '二塁打';
      case AtBatResultType.triple:
        return '三塁打';
      case AtBatResultType.homeRun:
        return '本塁打';
      case AtBatResultType.groundOut:
        return 'ゴロ';
      case AtBatResultType.flyOut:
        return 'フライ';
      case AtBatResultType.lineOut:
        return 'ライナー';
    }
  }
}

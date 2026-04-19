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

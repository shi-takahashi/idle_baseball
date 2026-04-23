import 'player.dart';

/// 投手交代イベント
/// イニング内の「この打席の前に交代が発生した」という情報を保持する
class PitcherChangeEvent {
  final Player oldPitcher;
  final Player newPitcher;
  final int inning;
  final bool isTop; // 交代が発生したハーフイニングの表/裏
  final int atBatIndex; // このイニング内で、何打席目の前に交代したか（0 = 先頭打者の前）
  final String reason; // 交代理由（表示・デバッグ用）

  const PitcherChangeEvent({
    required this.oldPitcher,
    required this.newPitcher,
    required this.inning,
    required this.isTop,
    required this.atBatIndex,
    required this.reason,
  });

  @override
  String toString() =>
      '$inning回${isTop ? "表" : "裏"} ${oldPitcher.name} → ${newPitcher.name} ($reason)';
}

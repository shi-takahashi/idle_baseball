import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// ユーザー指摘「球速157+伸び8+制球3+変化球2/3 の投手が 11勝3敗 防御率2.21
/// になる、ストレートさえ速ければ抑えられる構造になっている」の検証。
///
/// 各チームの先発エース枠を3パターンの特殊投手に差し替えて、シーズン成績を集計。
///
///   A: ストレート特化型（ユーザー例）
///      球速157 + 伸び8 + 制球3 + スライダー2 + チェンジアップ3
///   B: 制球型
///      球速143 + 伸び5 + 制球8 + スライダー7 + カーブ6
///   C: バランス型（参考）
///      球速147 + 伸び5 + 制球5 + スライダー5 + カーブ5
void main() {
  const numSeasons = 6;
  const gamesPerTeam = 150;

  Player makePitcher(String id, String name, {
    required int speed,
    required int fastball,
    required int control,
    int? slider,
    int? curve,
    int? changeup,
  }) {
    return Player(
      id: id,
      name: name,
      number: 1,
      age: 28,
      averageSpeed: speed,
      fastball: fastball,
      control: control,
      slider: slider,
      curve: curve,
      changeup: changeup,
      meet: 2,
      power: 2,
      eye: 2,
      speed: 3,
      throws: Handedness.right,
      bats: Handedness.right,
      pitcherRole: PitcherRole.starter,
      potentials: {
        'fastball': fastball,
        'control': control,
        if (slider != null) 'slider': slider,
        if (curve != null) 'curve': curve,
        if (changeup != null) 'changeup': changeup,
        'meet': 2, 'power': 2, 'eye': 2, 'speed': 3,
      },
      potentialAverageSpeed: speed,
    );
  }

  Map<String, dynamic> runPattern({
    required String label,
    required int speed,
    required int fastball,
    required int control,
    int? slider,
    int? curve,
    int? changeup,
  }) {
    int totalWins = 0, totalLosses = 0;
    int totalK = 0, totalBB = 0, totalHits = 0, totalHR = 0;
    int totalOuts = 0, totalER = 0;
    int totalStarts = 0;
    int count = 0;

    for (int s = 0; s < numSeasons; s++) {
      final teams = TeamGenerator(random: Random(8000 + s)).generateLeague();
      // 各チームの先発1番手を特殊投手に差し替え
      for (int i = 0; i < teams.length; i++) {
        final t = teams[i];
        final original = t.startingRotation.first;
        final special = makePitcher(
          'sp_${s}_$i',
          '${label}投手_$i',
          speed: speed,
          fastball: fastball,
          control: control,
          slider: slider,
          curve: curve,
          changeup: changeup,
        );
        t.startingRotation[0] = special;
        // bullpen / bench / players からは元の選手を削除しない（先発専用枠なので
        // 元の選手は他の場所には居ない想定）
        final pi = t.players.indexWhere((p) => p.id == original.id);
        if (pi >= 0) t.players[pi] = special;
      }
      final schedule =
          ScheduleGenerator().generateForGamesPerTeam(teams, gamesPerTeam);
      final controller = SeasonController(
        teams: teams,
        schedule: schedule,
        myTeamId: teams.first.id,
        gamesPerTeam: gamesPerTeam,
        random: Random(8000 + s),
      );
      controller.advanceAll();

      for (final t in teams) {
        final special = t.startingRotation.first;
        final st = controller.pitcherStats[special.id];
        if (st == null) continue;
        totalWins += st.wins;
        totalLosses += st.losses;
        totalK += st.strikeoutsRecorded;
        totalBB += st.walksAllowed;
        totalHits += st.hitsAllowed;
        totalHR += st.homeRunsAllowed;
        totalOuts += st.outsRecorded;
        totalER += st.earnedRuns;
        totalStarts += st.starts;
        count++;
      }
    }

    final ip = totalOuts / 3.0;
    final era = totalER / ip * 9;
    final kPer9 = totalK / ip * 9;
    final bbPer9 = totalBB / ip * 9;
    final baa = totalHits / (totalOuts + totalHits);
    final whip = (totalBB + totalHits) / ip;
    final hr9 = totalHR / ip * 9;
    return {
      'label': label,
      'count': count,
      'wins': totalWins / count,
      'losses': totalLosses / count,
      'starts': totalStarts / count,
      'ip': ip / count,
      'era': era,
      'k9': kPer9,
      'bb9': bbPer9,
      'baa': baa,
      'whip': whip,
      'hr9': hr9,
    };
  }

  final results = [
    runPattern(
      label: 'A:剛速球ノーコン',
      speed: 157, fastball: 8, control: 3,
      slider: 2, changeup: 3,
    ),
    runPattern(
      label: 'B:制球技巧派',
      speed: 143, fastball: 5, control: 8,
      slider: 7, curve: 6,
    ),
    runPattern(
      label: 'C:バランス標準',
      speed: 147, fastball: 5, control: 5,
      slider: 5, curve: 5,
    ),
    runPattern(
      label: 'D:全部低い',
      speed: 140, fastball: 3, control: 3,
      slider: 3, curve: 3,
    ),
  ];

  print('===== 特殊投手の先発成績（$numSeasons シーズン × 6 チーム = '
      '${numSeasons * 6} 人サンプル / $gamesPerTeam 試合） =====');
  print('');
  print(' パターン          | 登板 | 勝-負  |  IP  | 防御率| K/9 |BB/9 | 被打率| WHIP |HR/9');
  print('-------------------|------|--------|------|-------|-----|-----|-------|------|-----');
  for (final r in results) {
    print(' ${(r['label'] as String).padRight(17)} '
        '| ${(r['starts'] as double).toStringAsFixed(1).padLeft(4)} '
        '| ${(r['wins'] as double).toStringAsFixed(1)}-'
        '${(r['losses'] as double).toStringAsFixed(1).padLeft(3)} '
        '| ${(r['ip'] as double).toStringAsFixed(0).padLeft(4)} '
        '|  ${(r['era'] as double).toStringAsFixed(2).padLeft(4)} '
        '| ${(r['k9'] as double).toStringAsFixed(1).padLeft(3)} '
        '| ${(r['bb9'] as double).toStringAsFixed(1).padLeft(3)} '
        '| ${(r['baa'] as double).toStringAsFixed(3)} '
        '| ${(r['whip'] as double).toStringAsFixed(2)} '
        '| ${(r['hr9'] as double).toStringAsFixed(2)}');
  }
}

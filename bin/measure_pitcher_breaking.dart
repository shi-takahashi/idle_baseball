import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 変化球（スライダー / カーブ / スプリット / チェンジアップ）パラメータと
/// 先発投手成績の関係を計測。
///
/// 各球種について、その球種を持つ先発投手をパラメータ値ごとにビン分けし、
/// K/9・BB/9・被打率・HR/9・防御率を見る。変化球パラメータが結果に
/// footprint を持つか（設計の柱②③）を確認するのが目的。
///
/// 注意: 各投手は複数球種を投げるため、1 つの変化球パラメータの効果は
/// 配球比率ぶん希釈される。他の能力（球速・制球・伸び・他の変化球）は
/// 独立生成なので、十分なサンプルがあればビン内で平均化される。
void main() {
  const numSeasons = 8;
  const gamesPerTeam = 150;

  // pitchKey -> param(1..10) -> 集計
  final types = <String, int? Function(Player)>{
    'スライダー': (p) => p.slider,
    'カーブ': (p) => p.curve,
    'スプリット': (p) => p.splitter,
    'チェンジ': (p) => p.changeup,
  };

  final bb = <String, List<int>>{};
  final k = <String, List<int>>{};
  final outs = <String, List<int>>{};
  final hits = <String, List<int>>{};
  final hr = <String, List<int>>{};
  final er = <String, List<int>>{};
  final cnt = <String, List<int>>{};
  for (final key in types.keys) {
    bb[key] = List<int>.filled(11, 0);
    k[key] = List<int>.filled(11, 0);
    outs[key] = List<int>.filled(11, 0);
    hits[key] = List<int>.filled(11, 0);
    hr[key] = List<int>.filled(11, 0);
    er[key] = List<int>.filled(11, 0);
    cnt[key] = List<int>.filled(11, 0);
  }

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(7300 + s)).generateLeague();
    final schedule =
        ScheduleGenerator().generateForGamesPerTeam(teams, gamesPerTeam);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      gamesPerTeam: gamesPerTeam,
      random: Random(7300 + s),
    );
    controller.advanceAll();

    for (final team in teams) {
      for (final p in team.startingRotation) {
        final st = controller.pitcherStats[p.id];
        if (st == null || st.outsRecorded < 150) continue;
        for (final entry in types.entries) {
          final raw = entry.value(p);
          if (raw == null) continue; // その球種を投げない
          final v = raw.clamp(1, 10);
          bb[entry.key]![v] += st.walksAllowed;
          k[entry.key]![v] += st.strikeoutsRecorded;
          outs[entry.key]![v] += st.outsRecorded;
          hits[entry.key]![v] += st.hitsAllowed;
          hr[entry.key]![v] += st.homeRunsAllowed;
          er[entry.key]![v] += st.earnedRuns;
          cnt[entry.key]![v]++;
        }
      }
    }
  }

  print('===== 変化球パラメータ × 先発投手成績'
      '（$numSeasons シーズン × $gamesPerTeam 試合） =====');

  for (final key in types.keys) {
    print('');
    print('--- $key ---');
    print(' 値 | 投手数 | K/9  | BB/9 | 被打率 | HR/9 | 防御率');
    print('----|--------|------|------|--------|------|--------');
    double? eraLo, eraHi, kLo, kHi, baaLo, baaHi;
    for (int v = 1; v <= 10; v++) {
      if (cnt[key]![v] == 0) {
        print(' ${v.toString().padLeft(2)} |   0    |  -   |  -   |   -    |  -   |   -');
        continue;
      }
      final ip = outs[key]![v] / 3.0;
      final kPer9 = k[key]![v] / ip * 9;
      final bbPer9 = bb[key]![v] / ip * 9;
      final baa = hits[key]![v] / (outs[key]![v] + hits[key]![v]);
      final hrPer9 = hr[key]![v] / ip * 9;
      final era = er[key]![v] / ip * 9;
      print(' ${v.toString().padLeft(2)} '
          '|  ${cnt[key]![v].toString().padLeft(4)}  '
          '| ${kPer9.toStringAsFixed(1).padLeft(4)} '
          '| ${bbPer9.toStringAsFixed(1).padLeft(4)} '
          '| ${baa.toStringAsFixed(3)} '
          '| ${hrPer9.toStringAsFixed(2).padLeft(4)} '
          '| ${era.toStringAsFixed(2).padLeft(5)}');
      // スプレッド用に典型範囲（3〜7）の上下端を記録
      if (v >= 3 && v <= 7) {
        eraLo = (eraLo == null) ? era : min(eraLo, era);
        eraHi = (eraHi == null) ? era : max(eraHi, era);
        kLo = (kLo == null) ? kPer9 : min(kLo, kPer9);
        kHi = (kHi == null) ? kPer9 : max(kHi, kPer9);
        baaLo = (baaLo == null) ? baa : min(baaLo, baa);
        baaHi = (baaHi == null) ? baa : max(baaHi, baa);
      }
    }
    if (eraLo != null) {
      print('  典型範囲(3〜7) スプレッド: '
          '防御率 ${(eraHi! - eraLo).toStringAsFixed(2)} / '
          'K/9 ${(kHi! - kLo!).toStringAsFixed(2)} / '
          '被打率 ${(baaHi! - baaLo!).toStringAsFixed(3)}');
    }
  }
}

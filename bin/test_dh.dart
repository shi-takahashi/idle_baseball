import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// DH（指名打者）制の Phase 1 検証。
///
/// 確認項目:
///   1. DHあり: 投手はほぼ打席に立たない（PA ≈ 0）。DHなし: 投手が打席に立つ。
///   2. DHあり: 各チーム 9 人の打者が回り、投手以外の野手が DH として打つ。
///   3. DHあり/なし両方でシーズンが完走し例外が出ない。
///   4. enableDH が toJson/fromJson で往復する。
SeasonController _run(int seed, {required bool enableDH, int games = 90}) {
  final teams = TeamGenerator(random: Random(seed)).generateLeague();
  final schedule = const ScheduleGenerator()
      .generateForGamesPerTeam(teams, games, random: Random(seed));
  final controller = SeasonController(
    teams: teams,
    schedule: schedule,
    myTeamId: teams.first.id,
    gamesPerTeam: games,
    enableDH: enableDH,
    random: Random(seed),
  );
  controller.advanceAll();
  return controller;
}

({int pa, int ab, int hits}) _pitcherBatting(SeasonController c) {
  int pa = 0, ab = 0, hits = 0;
  for (final s in c.batterStats.values) {
    if (!s.player.isPitcher) continue;
    pa += s.plateAppearances;
    ab += s.atBats;
    hits += s.hits;
  }
  return (pa: pa, ab: ab, hits: hits);
}

void main() {
  print('=== DH Phase 1 検証 ===\n');

  for (final seed in [1, 7, 42]) {
    final off = _run(seed, enableDH: false);
    final on = _run(seed, enableDH: true);

    final pbOff = _pitcherBatting(off);
    final pbOn = _pitcherBatting(on);

    print('seed=$seed');
    print('  DHなし: 投手の打席 ${pbOff.pa}  打数 ${pbOff.ab}  安打 ${pbOff.hits}');
    print('  DHあり: 投手の打席 ${pbOn.pa}  打数 ${pbOn.ab}  安打 ${pbOn.hits}');

    // 1. DHありで投手の打席が激減していること
    if (pbOn.pa >= pbOff.pa) {
      print('  ❌ DHありでも投手の打席が減っていない');
    } else if (pbOn.pa > 10) {
      print('  ⚠️  DHありでも投手の打席が ${pbOn.pa} と多い（理想は ~0）');
    } else {
      print('  ✅ DHありで投手の打席が ${pbOff.pa} → ${pbOn.pa} に激減');
    }

    // 2. リーグ合計の得点（DHありの方が高いのが正しい挙動）
    double leagueRuns(SeasonController c) {
      int r = 0, g = 0;
      for (final t in c.standings.records) {
        r += t.runsScored;
        g += t.games;
      }
      return g > 0 ? r / g : 0;
    }

    print('  1試合平均得点  DHなし: ${leagueRuns(off).toStringAsFixed(2)}  '
        'DHあり: ${leagueRuns(on).toStringAsFixed(2)}');
  }

  // 3. 永続化往復で enableDH が保たれる
  print('\n=== 永続化往復 ===');
  for (final flag in [true, false]) {
    final c = _run(7, enableDH: flag, games: 30);
    final json = c.toJson();
    final restored = SeasonController.fromJson(json);
    final ok = restored.enableDH == flag;
    print('  enableDH=$flag → 復元後 ${restored.enableDH}  ${ok ? '✅' : '❌'}');
  }

  // 4. 旧セーブ互換（enableDH キー無し → false）
  print('\n=== 旧セーブ互換 ===');
  final c = _run(7, enableDH: true, games: 30);
  final json = c.toJson();
  json.remove('enableDH');
  final restored = SeasonController.fromJson(json);
  print('  enableDH キー削除 → 復元後 ${restored.enableDH}  '
      '${restored.enableDH == false ? '✅ (false 互換)' : '❌'}');

  print('\n完走（例外なし）✅');
}
